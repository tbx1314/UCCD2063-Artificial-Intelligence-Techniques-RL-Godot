extends Area2D

## Controls one patrolling snail enemy. It reports player contact to main.gd and
## supports stopping and resetting between reinforcement-learning episodes.

# main.gd receives the colliding Player through this signal.
signal player_hit(player)

const SPEED := 100.0

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var movement_timer: Timer = $Timer

# The snail starts by moving left and reverses whenever its Timer expires.
var direction := -1.0
var active := true

# These values remember the original scene state so every episode starts from
# exactly the same enemy position and direction.
var starting_position := Vector2.ZERO
var starting_direction := -1.0


## Stores the position and direction configured in the scene after the snail
## enters the scene tree for the first time.
func _ready() -> void:
	starting_position = global_position
	starting_direction = direction


## Moves the snail horizontally every rendered frame. delta makes the distance
## travelled per second independent of the computer's frame rate.
func _process(delta: float) -> void:
	if not active:
		return

	position.x += direction * SPEED * delta


## Reverses the patrol direction when the Timer expires and flips the sprite so
## the snail continues facing the direction in which it moves.
func _on_timer_timeout() -> void:
	if not active:
		return

	direction *= -1.0
	animated_sprite.flip_h = not animated_sprite.flip_h


## Handles Area2D contact. A living Player causes an enemy terminal event;
## contact with platforms or other objects is ignored.
func _on_body_entered(body: Node2D) -> void:
	if not active:
		return

	if body.name == "Player" and body.alive:
		player_hit.emit(body)


## Freezes the snail after an episode has reached a terminal state.
func stop_enemy() -> void:
	active = false
	movement_timer.stop()


## Restores the enemy's original state so training episodes are comparable.
func reset_enemy() -> void:
	global_position = starting_position
	direction = starting_direction
	active = true

	animated_sprite.flip_h = direction > 0.0
	animated_sprite.play("running")
	movement_timer.start()
