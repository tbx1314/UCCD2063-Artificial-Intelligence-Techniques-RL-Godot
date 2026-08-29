#player.gd
extends CharacterBody2D

@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D
@onready var jump_sound: AudioStreamPlayer2D = $jumpSound
@onready var death_sound: AudioStreamPlayer2D = $DeathSound

# Raycast
@onready var ray_left: RayCast2D = $RayLeft
@onready var ray_right: RayCast2D = $RayRight
@onready var ray_top: RayCast2D = $RayTop
@onready var ray_bottom: RayCast2D = $RayBottom
@onready var ray_diagonal_left: RayCast2D = $RayDiagonalLeft
@onready var ray_diagonal_right: RayCast2D = $RayDiagonalRight

@export var player_id: int = 0

# Previously made for 16 agents
static var available_shirt_colors: Array[Color] = [
	Color("#E6194B"), Color("#3CB44B"), Color("#4363D8"), Color("#FFE119"),
	Color("#F58231"), Color("#911EB4"), Color("#42D4F4"), Color("#F032E6"),
	Color("#800000"), Color("#469990"), Color("#9A6324"), Color("#808000"),
	Color("#000075"), Color("#AAFFC3"), Color("#DCBEFF"), Color("#FABED4")
]

# Parameters
const SPEED: float = 300.0
const JUMP_VELOCITY: float = -850.0
const WORLD_WIDTH: float = 1280.0
const WORLD_HEIGHT: float = 720.0
const MAX_FALL_SPEED: float = 1200.0

var current_action: int = 0
var rl_mode: bool = false
var rl_step_frames: int = 0

var alive: bool = true
var previous_position: Vector2
var nearby_snails: Dictionary = {}
var avoided_snails: Dictionary = {}

var reset_protected: bool = true

signal rl_step_finished

func _ready() -> void:
	previous_position = global_position

	if animated_sprite_2d.material:
		animated_sprite_2d.material = animated_sprite_2d.material.duplicate()

	var my_shirt_color: Color = available_shirt_colors[
		posmod(player_id, available_shirt_colors.size())
	]

	if animated_sprite_2d.material is ShaderMaterial:
		animated_sprite_2d.material.set_shader_parameter("shirt_color", my_shirt_color)

func _physics_process(delta: float) -> void:
	if not alive or not rl_mode:
		return

	if not is_on_floor():
		velocity += get_gravity() * delta

	var direction: float = apply_action()

	if not is_on_floor():
		animated_sprite_2d.animation = "jumping"
	elif abs(velocity.x) > 1.0:
		animated_sprite_2d.animation = "running"
	else:
		animated_sprite_2d.animation = "idle"

	if direction == 1.0:
		animated_sprite_2d.flip_h = false
	elif direction == -1.0:
		animated_sprite_2d.flip_h = true

	move_and_slide()

	var distance_moved: float = global_position.distance_to(previous_position)

	if distance_moved > 0.0:
		var main = get_tree().current_scene

		if main != null and main.player_states.has(player_id):
			main.player_states[player_id]["distance_travelled"] += distance_moved

	previous_position = global_position

	rl_step_frames += 1

	if rl_step_frames >= 5:
		rl_step_frames = 0
		rl_step_finished.emit()

func get_nearest_apple() -> Node2D:
	var nearest_apple: Node2D = null
	var nearest_distance: float = INF

	for apple_node in get_tree().get_nodes_in_group("apples"):
		if not is_instance_valid(apple_node):
			continue

		var apple: Node2D = apple_node as Node2D

		if apple == null or apple.is_collected(player_id):
			continue

		var distance: float = global_position.distance_to(apple.global_position)

		if distance < nearest_distance:
			nearest_distance = distance
			nearest_apple = apple

	return nearest_apple

func get_apple_state() -> Array:
	var apple = get_nearest_apple()

	if apple == null:
		return [1.0, 1.0]

	return [
		clampf(
			(apple.global_position.x - global_position.x) / WORLD_WIDTH,
			-1.0,
			1.0
		),
		clampf(
			(apple.global_position.y - global_position.y) / WORLD_HEIGHT,
			-1.0,
			1.0
		)
	]

func get_apple_0_collected() -> float:
	var main = get_tree().current_scene

	if main == null or not main.player_states.has(player_id):
		return 0.0

	return 1.0 if main.player_states[player_id]["apples_collected"].has(0) else 0.0

func get_nearest_enemy() -> Node2D:
	var nearest_enemy: Node2D = null
	var nearest_distance: float = INF

	for enemy_node in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy_node):
			continue

		var enemy: Node2D = enemy_node as Node2D

		if enemy == null:
			continue

		var distance: float = global_position.distance_to(enemy.global_position)

		if distance < nearest_distance:
			nearest_distance = distance
			nearest_enemy = enemy

	return nearest_enemy

func get_enemy_state() -> Array:
	var enemy: Node2D = get_nearest_enemy()

	if enemy == null:
		return [1.0, 1.0, 0.0, 1.0]

	var dx_snail: float = clampf(
		(enemy.global_position.x - global_position.x) / WORLD_WIDTH,
		-1.0,
		1.0
	)

	var dy_snail: float = clampf(
		(enemy.global_position.y - global_position.y) / WORLD_HEIGHT,
		-1.0,
		1.0
	)

	var snail_velocity: float = 0.0

	if enemy.has_method("get_velocity_direction"):
		snail_velocity = enemy.get_velocity_direction()

	var snail_euclidean_distance: float = clampf(
		sqrt(dx_snail * dx_snail + dy_snail * dy_snail),
		0.0,
		1.0
	)

	return [
		dx_snail,
		dy_snail,
		snail_velocity,
		snail_euclidean_distance
	]

func get_ray_distance(ray: RayCast2D) -> float:
	if not ray.is_colliding():
		return 1.0

	return clampf(
		global_position.distance_to(ray.get_collision_point())
		/ ray.target_position.length(),
		0.0,
		1.0
	)


func get_state() -> Array:
	var apple_state = get_apple_state()
	var enemy_state = get_enemy_state()

	return [
		clampf(velocity.x / SPEED, -1.0, 1.0),              # Velocity X
		clampf(velocity.y / MAX_FALL_SPEED, -1.0, 1.0),     # Velocity Y
		1.0 if is_on_floor() else 0.0,                      # On Floor

		apple_state[0],    # Apple dx
		apple_state[1],    # Apple dy

		enemy_state[0],    # Snail dx
		enemy_state[1],    # Snail dy
		enemy_state[2],    # Snail velocity
		enemy_state[3],    # Snail euclidean distance

		get_ray_distance(ray_left),            # Left Ray
		get_ray_distance(ray_right),           # Right Ray
		get_ray_distance(ray_top),             # Top Ray
		get_ray_distance(ray_bottom),          # Bottom Ray
		get_ray_distance(ray_diagonal_left),   # Diagonal Left Ray
		get_ray_distance(ray_diagonal_right),  # Diagonal Right Ray

		get_apple_0_collected()                # Phase flag: 0=phase1, 1=phase2
	]

func set_action(action: int) -> void:
	current_action = action

func apply_action() -> float:
	var direction: float = 0.0
	var jump: bool = false

	match current_action:
		1: direction = -1.0
		2: direction = 1.0
		3: jump = true
		4: direction = -1.0; jump = true
		5: direction = 1.0; jump = true

	if direction != 0.0:
		velocity.x = direction * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0.0, SPEED)

	if jump and is_on_floor():
		velocity.y = JUMP_VELOCITY
		jump_sound.play()

	return direction

func die() -> void:
	death_sound.play()
	animated_sprite_2d.animation = "dying"
	alive = false
