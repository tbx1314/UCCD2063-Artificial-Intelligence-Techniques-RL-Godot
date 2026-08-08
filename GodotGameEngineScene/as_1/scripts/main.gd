extends Node2D

## Acts as the reinforcement-learning environment controller. It coordinates
## the Player, apples and enemies, then returns observation, reward, termination
## status and evaluation information after every PPO action.

# A Python communication bridge can listen for this signal to receive a result.
signal step_finished(result: Dictionary)

# Reward values. Keeping them together makes experiment changes reproducible.
const STEP_PENALTY := -0.01
const APPLE_REWARD := 10.0
const GOAL_REWARD := 100.0
const ENEMY_PENALTY := -20.0
const FALL_PENALTY := -20.0
const TIMEOUT_PENALTY := -5.0
const PROGRESS_SCALE := 0.001

# Episode controls. One decision is held for several Godot physics frames so
# the agent has enough time to produce visible movement.
const MAX_STEPS := 1000
const ACTION_REPEAT := 4
const FALL_Y := 760.0

# Approximate level dimensions used to normalize positions and distances.
const LEVEL_WIDTH := 1280.0
const LEVEL_HEIGHT := 720.0
const PLAYER_SPEED := 300.0
const PLAYER_JUMP_SPEED := 850.0

# Obtain the important objects from the LevelRoot scene hierarchy.
@onready var player = $LevelRoot/Player
@onready var enemies_node: Node2D = $LevelRoot/Enemies
@onready var apples_node: Node2D = $LevelRoot/Apple

var player_start_position := Vector2.ZERO
var enemies: Array = []
var apples: Array = []

# Episode statistics and terminal-state information.
var episode_done := false
var terminal_reason := ""
var step_count := 0
var apples_collected := 0
var total_reward := 0.0

# Temporary values used while processing the current action.
var current_step_reward := 0.0
var previous_target_distance := 0.0
var collected_during_step := false


## Initializes object references, connects gameplay signals to the environment,
## and starts the first episode when the Main scene becomes ready.
func _ready() -> void:
	player_start_position = player.global_position
	enemies = enemies_node.get_children()
	apples = apples_node.get_children()

	# Enemy collisions and apple collections are converted into reward events.
	for enemy in enemies:
		enemy.player_hit.connect(_on_player_hit)

	for apple in apples:
		apple.collected.connect(_on_apple_collected)

	reset_episode()


## Restores the complete environment and returns the first observation of a new
## episode. Python should call this after done becomes true.
func reset_episode() -> Array:
	episode_done = false
	terminal_reason = ""
	step_count = 0
	apples_collected = 0
	total_reward = 0.0
	current_step_reward = 0.0
	collected_during_step = false

	# Every dynamic object must return to a known initial state.
	player.reset_player(player_start_position)

	for enemy in enemies:
		enemy.reset_enemy()

	for apple in apples:
		apple.reset_apple()

	# Store the starting distance for distance-based progress reward.
	previous_target_distance = _distance_to_nearest_apple()
	return get_observation()


## Executes one discrete PPO action, advances the game for ACTION_REPEAT physics
## frames, calculates reward, and returns a Gym-like transition dictionary.
## Because this function uses await, its caller must also await its result.
func agent_step(action: int) -> Dictionary:
	# If Python calls step after termination, return the terminal observation
	# without changing the game or awarding extra reward.
	if episode_done:
		return _create_step_result(0.0)

	current_step_reward = STEP_PENALTY
	collected_during_step = false
	player.set_agent_action(action)

	# Hold the selected action for a short period. Signals may add apple or enemy
	# reward while these physics frames are being processed.
	for frame in range(ACTION_REPEAT):
		await get_tree().physics_frame

		if episode_done:
			break

		# Crossing below the safe map boundary counts as an unsafe fall.
		if player.global_position.y > FALL_Y:
			current_step_reward += FALL_PENALTY
			_end_episode("fall")
			break

	player.clear_agent_action()
	step_count += 1

	# Do not calculate distance progress during an apple collection because the
	# target changes to another apple and would create a misleading distance jump.
	if not episode_done and not collected_during_step:
		_add_progress_reward()

	# A time limit prevents an unproductive policy from creating endless episodes.
	if not episode_done and step_count >= MAX_STEPS:
		current_step_reward += TIMEOUT_PENALTY
		_end_episode("timeout")

	total_reward += current_step_reward

	var result := _create_step_result(current_step_reward)
	step_finished.emit(result)
	return result


## Builds the ten-number observation vector supplied to PPO. Normalization keeps
## values within similar ranges, which generally makes neural-network training
## more stable than using raw pixel coordinates.
func get_observation() -> Array:
	var nearest_apple_offset := _nearest_apple_offset()
	var nearest_enemy_offset := _nearest_enemy_offset()

	return [
		# Player position.
		clampf(player.global_position.x / LEVEL_WIDTH, 0.0, 1.5),
		clampf(player.global_position.y / LEVEL_HEIGHT, -0.5, 1.5),

		# Player horizontal and vertical velocity.
		clampf(player.velocity.x / PLAYER_SPEED, -1.0, 1.0),
		clampf(player.velocity.y / PLAYER_JUMP_SPEED, -2.0, 2.0),

		# Ground status is encoded numerically because PPO expects numbers.
		1.0 if player.is_on_floor() else 0.0,

		# Relative location of the closest uncollected apple.
		clampf(nearest_apple_offset.x / LEVEL_WIDTH, -1.0, 1.0),
		clampf(nearest_apple_offset.y / LEVEL_HEIGHT, -1.0, 1.0),

		# Relative location of the closest active snail.
		clampf(nearest_enemy_offset.x / LEVEL_WIDTH, -1.0, 1.0),
		clampf(nearest_enemy_offset.y / LEVEL_HEIGHT, -1.0, 1.0),

		# Fraction of apples that remain in the episode.
		float(apples.size() - apples_collected) / maxf(float(apples.size()), 1.0)
	]


## Converts an Apple's collected signal into reward and score. Collecting every
## apple also awards the completion bonus and ends the episode successfully.
func _on_apple_collected(_apple: Area2D) -> void:
	if episode_done:
		return

	apples_collected += 1
	collected_during_step = true
	current_step_reward += APPLE_REWARD

	if apples_collected >= apples.size():
		current_step_reward += GOAL_REWARD
		_end_episode("success")
	else:
		# The next uncollected apple becomes the new progress target.
		previous_target_distance = _distance_to_nearest_apple()


## Converts a snail collision into a penalty, plays the player's death state,
## and terminates the current episode.
func _on_player_hit(hit_player) -> void:
	if episode_done:
		return

	current_step_reward += ENEMY_PENALTY
	hit_player.die()
	_end_episode("enemy")


## Rewards movement toward the nearest apple and slightly penalizes movement
## away from it. Clamping prevents this shaping reward from dominating the task.
func _add_progress_reward() -> void:
	var current_distance := _distance_to_nearest_apple()

	if is_inf(current_distance) or is_inf(previous_target_distance):
		return

	var distance_improvement := previous_target_distance - current_distance
	var progress_reward := clampf(
		distance_improvement * PROGRESS_SCALE,
		-0.1,
		0.1
	)

	current_step_reward += progress_reward
	previous_target_distance = current_distance


## Records why the episode ended, clears movement, and freezes every enemy.
## The guard prevents two terminal events from being processed in the same step.
func _end_episode(reason: String) -> void:
	if episode_done:
		return

	episode_done = true
	terminal_reason = reason
	player.clear_agent_action()

	if reason == "fall":
		player.die()

	for enemy in enemies:
		enemy.stop_enemy()


## Finds the scalar distance to the nearest uncollected apple. INF is returned
## when no valid target remains, allowing the caller to detect that situation.
func _distance_to_nearest_apple() -> float:
	var nearest_distance := INF

	for apple in apples:
		if not apple.is_collected:
			var distance: float = player.global_position.distance_to(apple.global_position)
			nearest_distance = minf(nearest_distance, distance)

	return nearest_distance


## Finds the x/y displacement from the player to the nearest available apple.
## The displacement supplies both direction and distance information to PPO.
func _nearest_apple_offset() -> Vector2:
	var nearest_offset := Vector2.ZERO
	var nearest_distance := INF

	for apple in apples:
		if not apple.is_collected:
			var offset: Vector2 = apple.global_position - player.global_position
			var distance: float = offset.length()

			if distance < nearest_distance:
				nearest_distance = distance
				nearest_offset = offset

	return nearest_offset


## Finds the displacement to the closest active snail so PPO can learn when to
## avoid it or jump. Inactive enemies are ignored after episode termination.
func _nearest_enemy_offset() -> Vector2:
	var nearest_offset := Vector2.ZERO
	var nearest_distance := INF

	for enemy in enemies:
		if enemy.active:
			var offset: Vector2 = enemy.global_position - player.global_position
			var distance: float = offset.length()

			if distance < nearest_distance:
				nearest_distance = distance
				nearest_offset = offset

	return nearest_offset


## Packages one transition in a structure similar to a Python Gym environment:
## next observation, immediate reward, terminal status, and diagnostic metrics.
func _create_step_result(reward: float) -> Dictionary:
	return {
		"observation": get_observation(),
		"reward": reward,
		"done": episode_done,
		"info": {
			"reason": terminal_reason,
			"steps": step_count,
			"apples_collected": apples_collected,
			"total_apples": apples.size(),
			"total_reward": total_reward
		}
	}
