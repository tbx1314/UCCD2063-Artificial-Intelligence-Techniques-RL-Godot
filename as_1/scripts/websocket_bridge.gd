extends Node

## Connects the Godot RL environment to the Python WebSocket server.

const SERVER_URL := "ws://127.0.0.1:8765"

@onready var environment = get_parent()

# True after Python connects. During an agent session, the SceneTree stays
# paused between requests so no collision or reward can occur outside step().
var agent_session_active := false
var socket := WebSocketPeer.new()
var step_in_progress := false


## Starts the WebSocket connection after the complete Main scene is ready.
func _ready() -> void:
	# The bridge must continue polling while gameplay is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_connect_to_python")

## Creates a non-blocking connection to the Python WebSocket server.
func _connect_to_python() -> void:
	var error := socket.connect_to_url(SERVER_URL)

	if error != OK:
		push_error("Unable to start WebSocket connection: %s" % error)


## Polling is required so WebSocketPeer can update its connection state and
## receive messages from the Python server.
func _process(_delta: float) -> void:
	socket.poll()

	var state := socket.get_ready_state()

	if state == WebSocketPeer.STATE_OPEN:
		if not agent_session_active:
			agent_session_active = true
			get_tree().paused = true

		while socket.get_available_packet_count() > 0:
			var packet := socket.get_packet()

			if socket.was_string_packet():
				var message := packet.get_string_from_utf8()
				_handle_message(message)

	elif agent_session_active:
		# Restore normal Godot behaviour if Python disconnects.
		agent_session_active = false
		get_tree().paused = false

## Converts incoming JSON into either an environment reset or one agent step.
func _handle_message(message: String) -> void:
	var request = JSON.parse_string(message)

	if typeof(request) != TYPE_DICTIONARY:
		_send_error("Invalid JSON request")
		return

	var command: String = request.get("command", "")

	match command:
		"reset":
			_handle_reset()

		"step":
			if step_in_progress:
				_send_error("A step is already being processed")
				return

			var action: int = int(request.get("action", 0))
			_process_agent_step(action)

		"inspect":
			# Diagnostic command used by test_environment.py. It must remain
			# read-only so repeated calls can prove that paused state is stable.
			_send_json({
				"type": "inspect_result",
				"observation": environment.get_observation()
			})

		_:
			_send_error("Unknown command: %s" % command)


## Resets all gameplay objects and sends the initial observation to Python.
func _handle_reset() -> void:
	if step_in_progress:
		_send_error("Cannot reset while a step is being processed")
		return

	get_tree().paused = true
	var observation: Array = environment.reset_episode()

	_send_json({
		"type": "reset_result",
		"observation": observation,
		"info": {
    	"reason": "",
    	"steps": 0,
    	"apples_collected": 0,
    	"player_x": environment.player.global_position.x,
    	"player_y": environment.player.global_position.y,
		}
	})


## Executes the asynchronous Godot environment step. Python remains blocked
## until agent_step finishes its repeated physics frames.
func _process_agent_step(action: int) -> void:
	step_in_progress = true

	# Allow gameplay to advance only during this action.
	get_tree().paused = false
	var result: Dictionary = await environment.agent_step(action)
	get_tree().paused = true

	result["type"] = "step_result"
	_send_json(result)
	step_in_progress = false


## Serializes a Dictionary as JSON and sends it as a WebSocket text frame.
func _send_json(data: Dictionary) -> void:
	if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return

	socket.send_text(JSON.stringify(data))


## Returns structured error information so Python does not wait indefinitely.
func _send_error(message: String) -> void:
	_send_json({
		"type": "error",
		"message": message
	})
