extends CharacterBody2D
class_name Player

@export var SPEED: float = 300.0
@export var JUMP_VELOCITY: float = -950.0

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var jump_sound: AudioStreamPlayer2D = $jumpSound
@onready var death_sound: AudioStreamPlayer2D = $DeathSound

# NEW: Easily adjust how low the eyes are in the Godot Inspector
@export var ray_y_offset: float = 15.0 

var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")
var move_input: float = 0.0
var jump_requested: bool = false
var alive: bool = true
var spawn_position: Vector2 = Vector2.ZERO

# --- Vision Variables ---
var num_rays: int = 16          # 16 rays in a circle
var view_distance: float = 400.0
var rays: Array[RayCast2D] = []

@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D

func _ready() -> void:
	add_to_group("player")
	spawn_position = global_position
	_setup_vision()

func _setup_vision() -> void:
	var angle_step = (PI * 2.0) / num_rays # 360 degree vision
	
	for i in range(num_rays):
		var ray = RayCast2D.new()
		# UPDATED: Shift the raycast origin down
		ray.position.y = ray_y_offset 
		ray.target_position = Vector2.RIGHT.rotated(i * angle_step) * view_distance
		ray.collide_with_areas = true  # MUST BE TRUE TO HIT APPLES/SNAILS
		ray.collide_with_bodies = true # Hit walls/floors
		add_child(ray)
		rays.append(ray)

func _physics_process(delta: float) -> void:
	if not alive:
		return

	queue_redraw() # Tells Godot to redraw the rays every frame

	# 1. Gravity & Horizontal Movement
	if not is_on_floor():
		velocity.y += gravity * delta
		if move_input != 0.0:
			velocity.x = move_input * SPEED
	else:
		velocity.x = move_input * SPEED

	# 2. Jump Execution
	if jump_requested:
		jump_sound.play()
		if is_on_floor():
			velocity.y = JUMP_VELOCITY
		jump_requested = false

	move_and_slide()

	# 3. Animation Handling
	if animated_sprite_2d:
		if move_input != 0.0:
			animated_sprite_2d.flip_h = (move_input < 0.0)

		if not is_on_floor():
			animated_sprite.play("jumping")
		elif abs(velocity.x) > 5.0:
			animated_sprite.play("running")
		else:
			animated_sprite.play("idle")

func _draw() -> void:
	for ray in rays:
		# UPDATED: Draw from the new offset position
		var start_pos = ray.position 
		var end_pos = start_pos + ray.target_position
		var color = Color(0, 1, 0, 0.2) # Faint green for empty space
		
		if ray.is_colliding():
			end_pos = to_local(ray.get_collision_point())
			var collider = ray.get_collider()
			
			if collider:
				if collider.is_in_group("enemies"):
					color = Color(1, 0, 0, 0.8) # Red for Snail
				elif collider.is_in_group("rewards"):
					color = Color(1, 1, 0, 0.8) # Yellow for Apple
				else:
					color = Color(1, 1, 1, 0.5) # White for Walls/Floor
					
		draw_line(start_pos, end_pos, color, 2.0)

func _play_if_exists(anim_name: String) -> void:
	if animated_sprite_2d and animated_sprite_2d.sprite_frames:
		if animated_sprite_2d.sprite_frames.has_animation(anim_name):
			animated_sprite_2d.play(anim_name)
		elif animated_sprite_2d.sprite_frames.has_animation("default"):
			animated_sprite_2d.play("default")

func die() -> void:
	if not alive:
		return
	alive = false
	velocity = Vector2.ZERO
	death_sound.play()
	animated_sprite.play("dying")

func reset_player() -> void:
	alive = true
	velocity = Vector2.ZERO
	move_input = 0.0
	jump_requested = false
	global_position = spawn_position
	
	# Force physics state sync
	if is_inside_tree():
		set_physics_process(true)
	
	animated_sprite.play("idle")
