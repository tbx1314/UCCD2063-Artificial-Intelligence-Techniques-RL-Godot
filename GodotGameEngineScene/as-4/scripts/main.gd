extends Node2D

## Acts as the reinforcement-learning environment controller. It coordinates
## the Player, apples and enemies, then returns observation, reward, termination
## status and evaluation information after every PPO action.

# A Python communication bridge can listen for this signal to receive a result.
signal step_finished(result: Dictionary)

# Reward values. Keeping them together makes experiment changes reproducible.
const STEP_PENALTY := -0.01
const APPLE_REWARD := 5.0
const GOAL_REWARD := 20.0
const ENEMY_PENALTY := -10.0
const FALL_PENALTY := -10.0
const TIMEOUT_PENALTY := -8.0
const PROGRESS_SCALE := 0.001

# Episode controls. One decision is held for several Godot physics frames so
# the agent has enough time to produce visible movement.
const MAX_STEPS := 1000
const ACTION_REPEAT := 4
const FALL_Y := 760.0

# Route shaping for the upper apple. The two apples are almost vertically
# aligned, but the upper apple cannot be reached by jumping straight upward
# from the lower apple. After Apple2 (the lower apple) is collected, this
# waypoint guides the policy left toward the central platform before the upper
# apple becomes the navigation target again.
const LOWER_APPLE_NODE_NAME := &"Apple2"
const UPPER_APPLE_APPROACH_POINT := Vector2(900.0, 480.0)
const WAYPOINT_RADIUS := 70.0
const WAYPOINT_REWARD := 4.0

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
var navigation_target_changed_during_step := false
var use_upper_apple_waypoint := false

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

	# Establish a complete and reproducible initial episode. Python performs
	# another reset when it connects, while this reset also supports manual play.
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
	navigation_target_changed_during_step = false
	use_upper_apple_waypoint = false

	# Every dynamic object must return to a known initial state.
	player.reset_player(player_start_position)

	for enemy in enemies:
		enemy.reset_enemy()

	for apple in apples:
		apple.reset_apple()

	# Initialize the potential used by progress shaping from the same navigation
	# target that is exposed in the observation vector.
	previous_target_distance = _distance_to_navigation_target()
	return get_observation()


## Executes one discrete PPO action, advances the game for ACTION_REPEAT physics
## frames, calculates reward, and returns a Gym-like transition dictionary.
## Because this function uses await, its caller must also await its result.
func agent_step(action: int) -> Dictionary:
	if episode_done:
		return _create_step_result(0.0)

	current_step_reward = STEP_PENALTY
	navigation_target_changed_during_step = false
	player.set_agent_action(action)

	# The WebSocket bridge unpauses the SceneTree only for this method. Holding
	# one decision for a fixed number of physics ticks gives deterministic action
	# duration and prevents gameplay from advancing while Python is choosing.
	for _frame in range(ACTION_REPEAT):
		await get_tree().physics_frame

		# Ensure collisions and physics signals from this tick finish.
		await get_tree().process_frame

		if episode_done:
			break

		if player.global_position.y > FALL_Y:
			# FALL_PENALTY is added inside _end_episode().
			_end_episode("fall")
			break

	player.clear_agent_action()
	step_count += 1

	# Reaching the approach waypoint changes the target from the waypoint to the
	# remaining apple. Skip progress shaping on that transition so the target
	# switch cannot create a false distance reward or penalty.
	if not episode_done:
		_update_navigation_target()

	if not episode_done and not navigation_target_changed_during_step:
		_add_progress_reward()

	if not episode_done and step_count >= MAX_STEPS:
		# TIMEOUT_PENALTY is added inside _end_episode().
		_end_episode("timeout")

	total_reward += current_step_reward

	var result := _create_step_result(current_step_reward)
	step_finished.emit(result)
	return result


## Builds the twelve-number observation vector supplied to PPO. Normalization keeps
## values within similar ranges, which generally makes neural-network training
## more stable than using raw pixel coordinates.
func get_observation() -> Array:
	var navigation_target_offset: Vector2 = (
		_navigation_target_position() - player.global_position
	)
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

		# Wall information.
		1.0 if player.is_on_wall() else 0.0,
		player.get_wall_normal().x if player.is_on_wall() else 0.0,

		# Relative location of the active navigation target. Normally this is the
		# nearest apple; after collecting the lower apple it temporarily becomes
		# the central-platform approach waypoint.
		clampf(navigation_target_offset.x / LEVEL_WIDTH, -1.0, 1.0),
		clampf(navigation_target_offset.y / LEVEL_HEIGHT, -1.0, 1.0),

		# Relative location of the closest active snail.
		clampf(nearest_enemy_offset.x / LEVEL_WIDTH, -1.0, 1.0),
		clampf(nearest_enemy_offset.y / LEVEL_HEIGHT, -1.0, 1.0),

		# Fraction of apples that remain in the episode.
		float(apples.size() - apples_collected) / maxf(float(apples.size()), 1.0)
	]


## Converts an Apple's collected signal into reward and score. Collecting every
## apple also awards the completion bonus and ends the episode successfully.
func _on_apple_collected(apple: Area2D) -> void:
	if episode_done:
		return

	apples_collected += 1
	navigation_target_changed_during_step = true
	current_step_reward += APPLE_REWARD

	if apples_collected >= apples.size():
		_end_episode("success")
	elif apple.name == LOWER_APPLE_NODE_NAME:
		# A straight-line vector to the upper apple points into a wall. Switching
		# to the approach waypoint makes both the observation and shaping reward
		# represent the reachable detour through the central platform.
		use_upper_apple_waypoint = true
		previous_target_distance = (
			player.global_position.distance_to(UPPER_APPLE_APPROACH_POINT)
		)
	else:
		previous_target_distance = _distance_to_nearest_apple()

## Converts a snail collision into a penalty, plays the player's death state,
## and terminates the current episode.
func _on_player_hit(hit_player) -> void:
	if episode_done:
		return

	hit_player.die()

	# ENEMY_PENALTY is added inside _end_episode().
	_end_episode("enemy")


## Rewards movement toward the active navigation target and slightly penalizes
## movement away from it. Clamping prevents dense shaping from dominating the
## sparse apple and terminal rewards.
func _add_progress_reward() -> void:
	var current_distance := _distance_to_navigation_target()
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

	# Apply exactly one terminal reward or penalty.
	match reason:
		"success":
			current_step_reward += GOAL_REWARD

		"enemy":
			current_step_reward += ENEMY_PENALTY

		"fall":
			current_step_reward += FALL_PENALTY

		"timeout":
			current_step_reward += TIMEOUT_PENALTY

		_:
			push_error("Unknown terminal reason: %s" % reason)
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


## Finds the displacement to the closest active snail so PPO can learn when to
## avoid it or jump. Inactive enemies are ignored after episode termination.
func _nearest_enemy_offset() -> Vector2:
	var nearest_offset := Vector2(LEVEL_WIDTH * 2.0, LEVEL_HEIGHT * 2.0)
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
			"total_reward": total_reward,
			"player_x": player.global_position.x,
			"player_y": player.global_position.y,
		}
	}
	
## Advances from the approach waypoint to the remaining apple. This state
## mutation happens only during agent_step(); get_observation() and the Python
## inspect command remain read-only and therefore cannot advance the task.
func _update_navigation_target() -> void:
	if not use_upper_apple_waypoint:
		return
	if (player.global_position.distance_to(UPPER_APPLE_APPROACH_POINT) > WAYPOINT_RADIUS):
		return
	use_upper_apple_waypoint = false
	navigation_target_changed_during_step = true
	current_step_reward += WAYPOINT_REWARD
	previous_target_distance = _distance_to_nearest_apple()


## Returns the position currently exposed to PPO as its navigation objective.
## This function deliberately has no side effects so repeated observations are
## identical while the synchronized environment is paused.
func _navigation_target_position() -> Vector2:
	if use_upper_apple_waypoint:
		return UPPER_APPLE_APPROACH_POINT

	var nearest_position: Vector2 = player.global_position
	var nearest_distance := INF

	for apple in apples:
		if not apple.is_collected:
			var distance: float = player.global_position.distance_to(
				apple.global_position
			)

			if distance < nearest_distance:
				nearest_distance = distance
				nearest_position = apple.global_position

	return nearest_position


## Returns the straight-line distance to the current route-aware target. The
## target itself may be an apple or the intermediate approach waypoint.
func _distance_to_navigation_target() -> float:
	return player.global_position.distance_to(
		_navigation_target_position()
	)
