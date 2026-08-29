extends Area2D

signal player_died(body)

@export var move_speed: float = 100.0
@export var patrol_distance: float = 100.0

var start_position: Vector2
var direction: float = 1.0 

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var movement_timer: Timer = $Timer

func _ready() -> void:
	start_position = global_position
	if not is_in_group("enemies"):
		add_to_group("enemies")

func _physics_process(delta: float) -> void:
	if not visible:
		return

	global_position.x += direction * move_speed * delta
	
	if abs(global_position.x - start_position.x) > patrol_distance:
		direction *= -1.0
		# Visually flip the snail (logic inverted so it matches your sprite's default artwork)
		if animated_sprite:
			animated_sprite.flip_h = (direction > 0.0)

func _on_body_entered(body: Node2D) -> void:
	if not visible or not monitoring:
		return

	if body.name == "Player" and body.alive: 
		if global_position.distance_to(body.global_position) > 150.0:
			return

		print("[DEATH] Player killed by Snail at pos: ", global_position, " | Player pos: ", body.global_position)
		player_died.emit(body)
		body.die()
		set_deferred("monitoring", false)

func reset_item() -> void:
	global_position = start_position
	direction = 1.0
	visible = true
	set_deferred("monitoring", true)
	if animated_sprite:
		# Reset visual orientation using the same inverted logic
		animated_sprite.flip_h = (direction > 0.0)
