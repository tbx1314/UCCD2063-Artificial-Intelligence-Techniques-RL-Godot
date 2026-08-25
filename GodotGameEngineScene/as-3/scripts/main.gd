extends Node2D

func _ready() -> void:
	_setup_level()

func _setup_level() -> void:
	var level_root = get_node_or_null("LevelRoot")
	if not level_root:
		return

	var enemies = level_root.get_node_or_null("Enemies")
	if enemies:
		for enemy in enemies.get_children():
			if enemy.has_signal("player_died"):
				if not enemy.player_died.is_connected(_on_player_died):
					enemy.player_died.connect(_on_player_died)

# Signal handler kept lightweight so AIController2D handles the RL death/reset flow
func _on_player_died(_body) -> void:
	pass
