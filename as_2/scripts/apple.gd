#apple.gd
extends Area2D

@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D
@onready var collected_sound: AudioStreamPlayer2D = $CollectedSound

@export var apple_id: int = 0

signal apple_collected(player, apple_id)

func is_collected(player_id: int) -> bool:
	var main = get_tree().current_scene
	
	if main == null:
		return false
	
	if not main.player_states.has(player_id):
		return false
	
	var state = main.player_states[player_id]
	
	return state["apples_collected"].has(apple_id)

func _on_body_entered(body: Node2D) -> void:
	if body is CharacterBody2D and body.name.begins_with("Player") and body.alive:
		# commented since apples should not dissapear once ONE player picked it up
		# animated_sprite_2d.animation = "collected"

		if is_collected(body.player_id):
			return

		collected_sound.play()

		emit_signal("apple_collected", body, apple_id)

func reset_apple() -> void:
	animated_sprite_2d.animation = "default"
