#snail.gd
extends Area2D

@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D
@onready var timer: Timer = $Timer
@onready var danger_area: Area2D = $DangerArea

# Snail Parameters
const SPEED: float = 100.0
var direction: float = -1.0
var start_position: Vector2

# Events
signal player_died

func _ready() -> void:
	start_position = global_position

	timer.process_callback = Timer.TIMER_PROCESS_PHYSICS
	timer.paused = true

	danger_area.body_entered.connect(_on_danger_area_body_entered)
	danger_area.body_exited.connect(_on_danger_area_body_exited)

func _physics_process(delta: float) -> void:
	var main = get_tree().current_scene

	if main == null:
		return

	var active: bool = main.rl_batch_active

	timer.paused = not active

	if active:
		position.x += direction * SPEED * delta

func _on_timer_timeout() -> void:
	direction *= -1.0
	animated_sprite_2d.flip_h = !animated_sprite_2d.flip_h


func _on_body_entered(body: Node2D) -> void:
	if body is CharacterBody2D \
	and body.name.begins_with("Player") \
	and body.alive \
	and not body.reset_protected:
		emit_signal("player_died", body)

func _on_danger_area_body_entered(body: Node2D) -> void:
	if not (body is CharacterBody2D and body.name.begins_with("Player")):
		return

	if not body.alive:
		return

	body.nearby_snails[self] = true

func _on_danger_area_body_exited(body: Node2D) -> void:
	if not (body is CharacterBody2D and body.name.begins_with("Player")):
		return

	if not body.nearby_snails.has(self):
		return

	if body.alive:
		if not body.avoided_snails.has(self):
			body.avoided_snails[self] = true

			var main = get_tree().current_scene

			if main != null and main.player_states.has(body.player_id):
				main.player_states[body.player_id]["snails_avoided"] += 1

	body.nearby_snails.erase(self)


func get_velocity_direction() -> float:
	if is_zero_approx(direction):
		return 0.0

	return signf(direction)
	

func reset_enemy() -> void:
	global_position = start_position
	direction = -1.0
	animated_sprite_2d.flip_h = false

	if timer:
		timer.stop()
		timer.start()
