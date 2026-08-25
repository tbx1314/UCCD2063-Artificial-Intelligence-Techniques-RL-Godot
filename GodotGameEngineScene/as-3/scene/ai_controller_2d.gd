extends AIController2D

var player: Player = null
var prev_dist_to_reward: float = INF
var apples_collected: int = 0
var last_pickup_time: float = -1.0
var max_x_reached: float = 0.0
var reached_upper_platform: bool = false
var reached_right_platform: bool = false
var phase2_zone0_steps: int = 0
const MAX_APPLES: int = 2

# --- NEW: Step Tracker Variable ---
var episode_steps: int = 0 

func _ready() -> void:
	add_to_group("ai_controller")
	_find_player()
	reset_after = 100000
	super._ready()

func _find_player() -> void:
	if get_parent() is Player:
		player = get_parent()
	else:
		var players = get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			player = players[0] as Player
		else:
			player = get_node_or_null("../Player") as Player

func get_action_space() -> Dictionary:
	return {
		"actions": {
			"size": 2,
			"action_type": "continuous"
		}
	}

func get_obs() -> Dictionary:
	if not is_instance_valid(player):
		_find_player()

	if needs_reset:
		reset()

	if is_instance_valid(player):
		if not player.alive or player.global_position.y > 750.0:
			done = true

	var target_enemy = _get_stage_enemy()
	var enemy_pos = target_enemy.global_position if target_enemy else Vector2.ZERO
	var enemy_vx = 0.0
	if target_enemy:
		if "velocity" in target_enemy:
			enemy_vx = sign(target_enemy.velocity.x)
		elif "direction" in target_enemy:
			enemy_vx = float(target_enemy.direction)

	var target_apple_pos = _get_target_apple_pos()

	var p_pos = player.global_position if is_instance_valid(player) else Vector2(100.0, 150.0)
	var p_vx = player.velocity.x if is_instance_valid(player) else 0.0
	var p_vy = player.velocity.y if is_instance_valid(player) else 0.0
	var p_speed = player.SPEED if is_instance_valid(player) else 300.0
	var p_jump = abs(player.JUMP_VELOCITY) if is_instance_valid(player) else 950.0
	var p_on_floor = 1.0 if (is_instance_valid(player) and player.is_on_floor()) else 0.0

	var enemy_rel = (enemy_pos - p_pos) / 1000.0 if enemy_pos != Vector2.ZERO else Vector2.ZERO
	var reward_rel = (target_apple_pos - p_pos) / 1000.0 if target_apple_pos != Vector2.ZERO else Vector2.ZERO

	var norm_x = clampf((p_pos.x / 1280.0) * 2.0 - 1.0, -1.0, 1.0)
	var norm_y = clampf((p_pos.y / 720.0) * 2.0 - 1.0, -1.0, 1.0)

	var obs: Array[float] = [
		norm_x,
		norm_y,
		p_vx / p_speed,
		p_vy / p_jump,
		p_on_floor,
		enemy_rel.x,
		enemy_rel.y,
		reward_rel.x,
		reward_rel.y,
		float(apples_collected),
		enemy_vx
	]
	
	if is_instance_valid(player) and player.rays.size() > 0:
		for ray in player.rays:
			ray.force_raycast_update()
			
			var dist = 1.0 
			var is_wall = 0.0
			var is_apple = 0.0
			var is_enemy = 0.0
			
			if ray.is_colliding():
				var hit_point = ray.get_collision_point()
				dist = player.global_position.distance_to(hit_point) / player.view_distance
				
				var collider = ray.get_collider()
				if collider:
					if collider.is_in_group("rewards"):
						is_apple = 1.0
					elif collider.is_in_group("enemies"):
						is_enemy = 1.0
					else:
						is_wall = 1.0
						
			obs.append(dist)
			obs.append(is_wall)
			obs.append(is_apple)
			obs.append(is_enemy)
	else:
		for i in range(16 * 4):
			obs.append(0.0)

	return {"obs": obs}

func get_reward() -> float:
	# --- NEW: Increment steps every time Godot asks for a reward update ---
	episode_steps += 1
	
	if is_instance_valid(player) and (not player.alive or player.global_position.y > 750.0):
		return -50.0

	var target_apple = _get_target_apple_pos()
	
	var step_rew = reward - 0.2

	if is_instance_valid(player):
		if apples_collected >= 1:
			if player.global_position.x <= max_x_reached + 2.0:
				phase2_zone0_steps += 1
			else:
				phase2_zone0_steps = 0

		if player.global_position.x > max_x_reached:
			var diff = player.global_position.x - max_x_reached
			var multiplier = 0.08 if apples_collected >= 1 else 0.03
			step_rew += clampf(diff * multiplier, 0.0, 0.3)
			max_x_reached = player.global_position.x

		if apples_collected >= 1:
			if not reached_upper_platform and player.is_on_floor() and player.global_position.x > 500.0 and player.global_position.y < 600.0:
				reached_upper_platform = true
				step_rew += 30.0

			if not reached_right_platform and player.global_position.x > 580.0:
				reached_right_platform = true
				step_rew += 50.0

		if target_apple != Vector2.ZERO:
			var current_dist = player.global_position.distance_to(target_apple)
			if prev_dist_to_reward != INF:
				var delta_dist = prev_dist_to_reward - current_dist
				var mult = 0.12 if apples_collected >= 1 else 0.06
				step_rew += clampf(delta_dist * mult, -1.0, 0.2)
			prev_dist_to_reward = current_dist

	reward = 0.0
	return step_rew

func on_apple_collected_by_node(apple_node: Node) -> void:
	var current_time = Time.get_ticks_msec() / 1000.0
	if last_pickup_time > 0.0 and (current_time - last_pickup_time) < 0.3:
		return

	last_pickup_time = current_time
	apples_collected += 1
	prev_dist_to_reward = INF
	phase2_zone0_steps = 0

	# --- NEW: Speedrun Bonus Implementation ---
	if apples_collected == 1:
		reward += 50.0 
	else:
		# Base 100 reward + 1 bonus point for every step saved under 150
		var speed_bonus: float = maxf(0.0, 150.0 - float(episode_steps))
		reward += (100.0 + speed_bonus)
		print("[WIN] Finished in ", episode_steps, " steps! Awarded: +", 100.0 + speed_bonus)

	if apples_collected >= MAX_APPLES:
		done = true

func set_action(action) -> void:
	if not is_instance_valid(player) or not player.alive:
		return

	var move_val: float = 0.0
	var jump_val: float = 0.0

	var data = action
	if typeof(data) == TYPE_DICTIONARY:
		data = data.get("actions", data.values()[0])
	if typeof(data) == TYPE_ARRAY and data.size() > 0:
		if typeof(data[0]) in [TYPE_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY]:
			data = data[0]

	if typeof(data) in [TYPE_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY]:
		if data.size() > 0:
			move_val = float(data[0])
		if data.size() > 1:
			jump_val = float(data[1])

	player.move_input = clampf(move_val, -1.0, 1.0)
	player.jump_requested = (jump_val > 0.5)

func reset() -> void:
	if not is_instance_valid(player):
		_find_player()

	if is_instance_valid(player):
		player.reset_player()

	# --- NEW: Reset Step Tracker to 0 at the start of a new episode ---
	episode_steps = 0
	
	apples_collected = 0
	last_pickup_time = -1.0
	prev_dist_to_reward = INF
	reached_upper_platform = false
	reached_right_platform = false
	phase2_zone0_steps = 0
	
	max_x_reached = player.global_position.x if is_instance_valid(player) else 100.0
	get_tree().call_group("rewards", "reset_item")
	get_tree().call_group("enemies", "reset_item")

	super.reset()
	reward = 0.0
	done = false
	needs_reset = false

func _get_target_apple_pos() -> Vector2:
	var nodes = get_tree().get_nodes_in_group("rewards")
	if nodes.is_empty():
		return Vector2.ZERO

	for n in nodes:
		if is_instance_valid(n) and n is Node2D and n.is_inside_tree() and n.visible:
			if apples_collected == 0 and n.global_position.x < 600.0:
				return n.global_position
			elif apples_collected >= 1 and n.global_position.x >= 600.0:
				return n.global_position
			return n.global_position

	return Vector2.ZERO

func _get_stage_enemy() -> Node2D:
	var nodes = get_tree().get_nodes_in_group("enemies")
	if nodes.is_empty():
		return null

	var selected: Node2D = null
	for n in nodes:
		if is_instance_valid(n) and n is Node2D and n.is_inside_tree() and n.visible:
			if apples_collected == 0:
				if n.global_position.x < 500.0:
					return n
			else:
				if n.global_position.x >= 500.0:
					return n
			selected = n
	return selected

func _nearest_in_group(group_name: String) -> Vector2:
	var nodes = get_tree().get_nodes_in_group(group_name)
	if nodes.is_empty() or not is_instance_valid(player):
		return Vector2.ZERO
	var nearest: Node2D = null
	var min_dist: float = INF
	for n in nodes:
		if is_instance_valid(n) and n is Node2D and n.is_inside_tree() and n.visible:
			var d = player.global_position.distance_squared_to(n.global_position)
			if d < min_dist:
				min_dist = d
				nearest = n
	return nearest.global_position if nearest else Vector2.ZERO
