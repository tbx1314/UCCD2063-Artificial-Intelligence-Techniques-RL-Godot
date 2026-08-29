extends Area2D

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collected_sound: AudioStreamPlayer2D = $CollectedSound
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

var is_collected: bool = false

func _ready() -> void:
	add_to_group("rewards")
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	reset_item()

func _on_body_entered(body: Node2D) -> void:
	if not (body is Player) or is_collected:
		return

	is_collected = true
	visible = false
	collected_sound.play()
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	if collision_shape:
		collision_shape.set_deferred("disabled", true)

	var controllers = get_tree().get_nodes_in_group("ai_controller")
	if controllers.size() > 0:
		controllers[0].on_apple_collected_by_node(self)


func reset_item() -> void:
	# 1. Turn the visuals back on immediately
	visible = true
	
	# 2. THE FIX: Wait for one physics frame so the player can safely teleport away
	await get_tree().physics_frame
	
	# 3. Now it is safe to turn the physics collisions back on
	is_collected = false
	set_deferred("monitoring", true)
	set_deferred("monitorable", true)
	if collision_shape:
		collision_shape.set_deferred("disabled", false)
