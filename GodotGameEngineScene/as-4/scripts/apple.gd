extends Area2D

## Represents one collectible apple. It emits an event to the environment when
## collected and can be restored when a new training episode begins.

# main.gd listens to this signal to add reward and update the episode score.
signal collected(apple: Area2D)

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collected_sound: AudioStreamPlayer2D = $CollectedSound
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

# Prevent the same apple from giving reward more than once in one episode.
var is_collected := false

# This counter invalidates an old animation callback if the episode is reset
# before the collection animation has finished.
var collection_version := 0


## Called by the Area2D body_entered signal. Only the Player is allowed to
## collect the apple; enemies or other physics bodies are ignored.
func _on_body_entered(body: Node2D) -> void:
	if body.name != "Player":
		return

	if is_collected:
		return

	collect()


## Marks the apple as collected, disables further collision, plays audiovisual
## feedback, and informs main.gd that reward should be assigned.
func collect() -> void:
	is_collected = true
	collection_version += 1
	var current_version := collection_version

	# Collision properties are changed with set_deferred because this function
	# may be running while Godot is processing a physics collision callback.
	set_deferred("monitoring", false)
	collision_shape.set_deferred("disabled", true)

	animated_sprite.play("collected")
	collected_sound.play()
	collected.emit(self)

	# Wait for the non-looping collection animation before hiding the apple.
	await animated_sprite.animation_finished

	# If reset_apple ran during the await, the version will differ and the newly
	# restored apple must remain visible.
	if is_collected and current_version == collection_version:
		visible = false


## Restores the apple's visibility, collision, and default animation for the
## beginning of the next training or evaluation episode.
func reset_apple() -> void:
	collection_version += 1
	is_collected = false
	visible = true

	set_deferred("monitoring", true)
	collision_shape.set_deferred("disabled", false)
	animated_sprite.play("default")
