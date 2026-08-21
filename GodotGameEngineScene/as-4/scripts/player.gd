extends CharacterBody2D

## Controls the player using either human keyboard input or an action selected
## by the PPO agent. The PPO action is stored as an integer from 0 to 5.

# Give every PPO action a readable name instead of using unexplained numbers.
enum AgentAction {
	NOTHING,
	LEFT,
	RIGHT,
	JUMP,
	LEFT_JUMP,
	RIGHT_JUMP
}

# Movement constants used by both human and agent control.
const SPEED := 300.0
const JUMP_VELOCITY := -850.0

# Child-node references become available when the Player enters the scene tree.
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var jump_sound: AudioStreamPlayer2D = $jumpSound
@onready var death_sound: AudioStreamPlayer2D = $DeathSound

# Runtime state used to stop movement after death and store the latest PPO action.
var alive := true
var agent_controlled := false
var current_action: int = AgentAction.NOTHING
var jump_requested := false


## Runs once per physics frame. It converts the selected input into velocity,
## applies gravity and collision movement, and updates the player's animation.
func _physics_process(delta: float) -> void:
	# A dead player must not continue moving or accepting new actions.
	if not alive:
		return

	var direction := 0.0

	# During training, obtain horizontal movement from the latest PPO action.
	# Otherwise, retain keyboard control so the level can be tested manually.
	if agent_controlled:
		direction = _get_agent_direction()
	else:
		direction = Input.get_axis("left", "right")

		if Input.is_action_just_pressed("jump"):
			jump_requested = true

	# Godot does not apply 2D character gravity automatically, so add it while
	# the player is airborne. Multiplying by delta keeps it frame-rate independent.
	if not is_on_floor():
		velocity += get_gravity() * delta

	# A jump is valid only when standing on a platform. The request is consumed
	# after one physics frame to prevent one PPO action from causing repeated jumps.
	if jump_requested and is_on_floor():
		velocity.y = JUMP_VELOCITY
		jump_sound.play()

	jump_requested = false

	# Apply horizontal movement. When there is no direction, gradually reduce
	# horizontal velocity instead of stopping the character instantly.
	if direction != 0.0:
		velocity.x = direction * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0.0, SPEED)

	# Move the CharacterBody2D and let Godot resolve platform collisions.
	move_and_slide()
	_update_animation(direction)


## Receives an integer action from the RL environment. clampi prevents an
## invalid action value from producing undefined player behaviour.
func set_agent_action(action: int) -> void:
	agent_controlled = true
	current_action = clampi(
		action,
		AgentAction.NOTHING,
		AgentAction.RIGHT_JUMP
	)

	# Jump actions include either a vertical jump alone or a jump combined
	# with horizontal movement.
	if current_action in [
		AgentAction.JUMP,
		AgentAction.LEFT_JUMP,
		AgentAction.RIGHT_JUMP
	]:
		jump_requested = true


## Clears the previous PPO action at the end of an environment step so the
## character does not continue moving while Python is selecting its next action.
func clear_agent_action() -> void:
	current_action = AgentAction.NOTHING
	jump_requested = false


## Converts the discrete PPO action into the horizontal direction required by
## the movement code: -1 for left, 1 for right, and 0 for no horizontal movement.
func _get_agent_direction() -> float:
	match current_action:
		AgentAction.LEFT, AgentAction.LEFT_JUMP:
			return -1.0
		AgentAction.RIGHT, AgentAction.RIGHT_JUMP:
			return 1.0
		_:
			return 0.0


## Selects the animation that matches the physical state and turns the sprite
## toward its movement direction.
func _update_animation(direction: float) -> void:
	if not is_on_floor():
		animated_sprite.play("jumping")
	elif absf(velocity.x) > 1.0:
		animated_sprite.play("running")
	else:
		animated_sprite.play("idle")

	if direction > 0.0:
		animated_sprite.flip_h = false
	elif direction < 0.0:
		animated_sprite.flip_h = true


## Changes the player to its terminal death state after an enemy collision or
## unsafe fall. The guard prevents the sound and animation from playing twice.
func die() -> void:
	if not alive:
		return

	alive = false
	velocity = Vector2.ZERO
	death_sound.play()
	animated_sprite.play("dying")


## Restores all temporary player state at the beginning of a new RL episode.
func reset_player(start_position: Vector2) -> void:
	global_position = start_position
	velocity = Vector2.ZERO
	alive = true
	current_action = AgentAction.NOTHING
	jump_requested = false
	animated_sprite.flip_h = false
	animated_sprite.play("idle")
