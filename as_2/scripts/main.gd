extends Node2D

var player_start_positions: Dictionary = {}
var rl_batch_active: bool = false
var player_states: Dictionary = {}

# DEBUG
const DEBUG_PLAYER_ID: int = 0
const DEBUG_REWARDS: bool = false
const HEADLESS_MODE: bool = true

const TOTAL_APPLES: int = 2

# Parameters
const APPLE_REWARD: float = 15.0
const LEVEL_COMPLETE_REWARD: float = 50.0
const DEATH_REWARD: float = -8.0
const STEP_PENALTY: float = -0.02
const APPLE_PROGRESS_REWARD_PER_UNIT: float = 0.001
const MAX_APPLE_PROGRESS_REWARD: float = 0.05

const RL_SPAWN_X_FIRST: float = 1070.0
const RL_SPAWN_X_SPACING: float = 10.0


func _ready() -> void:
	_setup_level()

	var players = $LevelRoot.get_node_or_null("Players")

	if players:
		for player in players.get_children():
			player_start_positions[player.player_id] = Vector2(
				RL_SPAWN_X_FIRST + RL_SPAWN_X_SPACING * player.player_id,
				player.global_position.y
			)

			player_states[player.player_id] = {
				"apples_collected": {},
				"current_reward": 0.0,
				"step_reward": 0.0,
				"episode_done": false,
				"episode_steps": 0,
				"score": 0,
				"distance_travelled": 0.0,
				"snails_avoided": 0,
				"completed": false,
				"death_cause": "",
				"progress_apple_id": -1,
				"progress_apple_prev_distance": INF
			}


func _setup_level() -> void:
	var enemies = $LevelRoot.get_node_or_null("Enemies")

	if enemies:
		for enemy in enemies.get_children():
			enemy.player_died.connect(_on_player_died)

	var apples = $LevelRoot.get_node_or_null("Apple")

	if apples:
		for apple in apples.get_children():
			apple.apple_collected.connect(_on_apple_collected)


func _on_apple_collected(player, apple_id: int) -> void:
	var player_id: int = player.player_id

	if not player_states.has(player_id):
		print("ERROR: Unknown Player ID: ", player_id)
		return

	var state = player_states[player_id]

	if state["apples_collected"].has(apple_id):
		return

	state["apples_collected"][apple_id] = true
	state["score"] += 1

	if DEBUG_REWARDS and player_id == DEBUG_PLAYER_ID:
		print(
			"[APPLE] P", player_id,
			" collected apple ", apple_id,
			" -> +", APPLE_REWARD
		)

	add_reward(player_id, APPLE_REWARD)

	if not HEADLESS_MODE:
		print(
			"P", player_id,
			" Apple ", apple_id,
			" (",
			state["apples_collected"].size(),
			"/",
			TOTAL_APPLES,
			")"
		)

	if state["apples_collected"].size() >= TOTAL_APPLES:
		_on_level_completed(player_id)


func _on_level_completed(player_id: int) -> void:
	if not player_states.has(player_id):
		return

	var state = player_states[player_id]

	if state["episode_done"]:
		return

	state["episode_done"] = true
	state["completed"] = true
	state["death_cause"] = "completed"

	add_reward(player_id, LEVEL_COMPLETE_REWARD)

	if not HEADLESS_MODE:
		print(
			"P", player_id,
			" completed level. Reward: ",
			state["current_reward"]
		)


func _on_player_died(player) -> void:
	var player_id: int = player.player_id

	if not player_states.has(player_id):
		print("ERROR: Unknown Player ID: ", player_id)
		return

	var state = player_states[player_id]

	if state["episode_done"]:
		return

	state["death_cause"] = "snail"

	if DEBUG_REWARDS and player_id == DEBUG_PLAYER_ID:
		print(
			"[DEATH] P", player_id,
			" died to snail -> ",
			DEATH_REWARD
		)

	add_reward(player_id, DEATH_REWARD)

	state["episode_done"] = true
	player.die()

	if not HEADLESS_MODE:
		print(
			"P", player_id,
			" died. Reward: ",
			state["current_reward"]
		)


func _begin_apple_progress(player_id: int) -> void:
	var player = $LevelRoot/Players.get_node_or_null(
		"Player%s" % player_id
	)

	if player == null:
		return

	var target = _nearest_uncollected_apple(player_id, player)
	var state = player_states[player_id]

	if target == null:
		state["progress_apple_id"] = -1
		state["progress_apple_prev_distance"] = INF
		return

	state["progress_apple_id"] = int(target.get("apple_id"))
	state["progress_apple_prev_distance"] = (
		player.global_position.distance_to(target.global_position)
	)


func _nearest_uncollected_apple(
	player_id: int,
	player: Node2D
) -> Node2D:
	var apples = $LevelRoot.get_node_or_null("Apple")

	if apples == null:
		return null

	var nearest: Node2D = null
	var nearest_distance := INF

	for apple in apples.get_children():
		if player_states[player_id]["apples_collected"].has(
			int(apple.get("apple_id"))
		):
			continue

		var distance := player.global_position.distance_to(
			apple.global_position
		)

		if distance < nearest_distance:
			nearest_distance = distance
			nearest = apple

	return nearest


func add_reward(player_id: int, amount: float) -> void:
	if not player_states.has(player_id):
		print("ERROR: Unknown Player ID: ", player_id)
		return

	var state = player_states[player_id]

	state["current_reward"] += amount
	state["step_reward"] += amount

	if DEBUG_REWARDS and player_id == DEBUG_PLAYER_ID:
		print(
			"[R] P", player_id,
			" +%.4f" % amount,
			" | step_total=%.4f" % state["step_reward"],
			" | episode_total=%.4f" % state["current_reward"]
		)


func apply_apple_progress_reward(
	player_id: int,
	player: Node2D
) -> void:
	if not player_states.has(player_id):
		return

	var state = player_states[player_id]

	if state["episode_done"]:
		return

	var target_id: int = state["progress_apple_id"]

	if target_id < 0 or state["apples_collected"].has(target_id):
		return

	var apples = $LevelRoot.get_node_or_null("Apple")

	if apples == null:
		return

	var target: Node2D = null

	for apple in apples.get_children():
		if int(apple.get("apple_id")) == target_id:
			target = apple
			break

	if target == null:
		return

	var current_distance: float = (
		player.global_position.distance_to(target.global_position)
	)

	var prev_distance: float = state["progress_apple_prev_distance"]

	if prev_distance == INF:
		prev_distance = current_distance

	var scale: float = 0.015

	var reward_amount: float = scale * (
		prev_distance - 0.99 * current_distance
	)

	reward_amount = clampf(reward_amount, -1.0, 1.0)

	if DEBUG_REWARDS and player_id == DEBUG_PLAYER_ID:
		print(
			"[POTENTIAL_SHAPING] P", player_id,
			" prev_dist=%.2f" % prev_distance,
			" curr_dist=%.2f" % current_distance,
			" reward=%.4f" % reward_amount
		)

	add_reward(player_id, reward_amount)


func apply_step_penalty(player_id: int) -> void:
	if not player_states.has(player_id):
		return

	var state = player_states[player_id]

	if state["episode_done"]:
		return

	state["episode_steps"] += 1
	add_reward(player_id, STEP_PENALTY)

	var player = $LevelRoot/Players.get_node_or_null(
		"Player%s" % player_id
	)

	if player != null:
		var nearest_enemy = player.get_nearest_enemy()

		if nearest_enemy != null:
			var snail_dist = player.global_position.distance_to(
				nearest_enemy.global_position
			)

			var dy = abs(
				nearest_enemy.global_position.y - player.global_position.y
			)

			if snail_dist < 120.0 and dy < 50.0:
				var proximity_penalty = -0.2 * (
					1.0 - (snail_dist / 120.0)
				)

				add_reward(player_id, proximity_penalty)

				if DEBUG_REWARDS and player_id == DEBUG_PLAYER_ID:
					print(
						"[SNAIL_PROXIMITY] P", player_id,
						" dist=%.2f" % snail_dist,
						" dy=%.2f" % dy,
						" penalty=%.4f" % proximity_penalty
					)


func get_step_reward(player_id: int) -> float:
	if not player_states.has(player_id):
		return 0.0

	var state = player_states[player_id]
	var reward: float = state["step_reward"]
	state["step_reward"] = 0.0

	return reward


func get_player_state(player_id: int) -> Dictionary:
	if not player_states.has(player_id):
		return {}

	return player_states[player_id]


func get_collection_progress(player_id: int) -> float:
	if not player_states.has(player_id):
		return 0.0

	var state = player_states[player_id]

	return float(state["apples_collected"].size()) / float(TOTAL_APPLES)


func get_episode_statistics(player_id: int) -> Dictionary:
	if not player_states.has(player_id):
		return {
			"apples_collected": 0,
			"snails_avoided": 0,
			"distance_travelled": 0.0,
			"episode_length": 0
		}

	var state = player_states[player_id]

	return {
		"apples_collected": state["apples_collected"].size(),
		"snails_avoided": state["snails_avoided"],
		"distance_travelled": state["distance_travelled"],
		"episode_length": state["episode_steps"]
	}


func begin_step(player_id: int) -> void:
	if not player_states.has(player_id):
		return

	var state = player_states[player_id]

	if state["episode_done"]:
		return

	state["step_reward"] = 0.0
	_begin_apple_progress(player_id)


func get_statistics(player_id: int) -> Dictionary:
	if not player_states.has(player_id):
		return {}

	var state = player_states[player_id]
	var apples_collected: int = state["apples_collected"].size()

	return {
		"score": state["score"],
		"apples_collected": apples_collected,
		"apple_collection_rate": (
			float(apples_collected) / float(TOTAL_APPLES)
		),
		"snails_avoided": state["snails_avoided"],
		"distance_travelled": state["distance_travelled"],
		"steps": state["episode_steps"],
		"episode_length": state["episode_steps"],
		"completed": state["completed"],
		"death_cause": state["death_cause"]
	}


func reset_players() -> void:
	var players = $LevelRoot.get_node_or_null("Players")

	if players == null:
		return

	for player in players.get_children():
		player.global_position = player_start_positions[player.player_id]
		player.previous_position = player.global_position
		player.velocity = Vector2.ZERO
		player.alive = true
		player.reset_protected = true
		player.rl_mode = false
		player.rl_step_frames = 0
		player.current_action = 0
		player.nearby_snails.clear()
		player.avoided_snails.clear()


func reset_player_states() -> void:
	for player_id in player_states.keys():
		player_states[player_id]["apples_collected"] = {}
		player_states[player_id]["current_reward"] = 0.0
		player_states[player_id]["step_reward"] = 0.0
		player_states[player_id]["episode_done"] = false
		player_states[player_id]["episode_steps"] = 0
		player_states[player_id]["score"] = 0
		player_states[player_id]["distance_travelled"] = 0.0
		player_states[player_id]["snails_avoided"] = 0
		player_states[player_id]["completed"] = false
		player_states[player_id]["death_cause"] = ""
		player_states[player_id]["progress_apple_id"] = -1
		player_states[player_id]["progress_apple_prev_distance"] = INF


func reset_apples() -> void:
	var apples = $LevelRoot.get_node_or_null("Apple")

	if apples == null:
		return

	for apple in apples.get_children():
		if apple.has_method("reset_apple"):
			apple.reset_apple()


func reset_enemies() -> void:
	var enemies = $LevelRoot.get_node_or_null("Enemies")

	if enemies == null:
		return

	for enemy in enemies.get_children():
		if enemy.has_method("reset_enemy"):
			enemy.reset_enemy()


func reset_episode() -> void:
	reset_player_states()
	reset_players()
	reset_apples()
	reset_enemies()
