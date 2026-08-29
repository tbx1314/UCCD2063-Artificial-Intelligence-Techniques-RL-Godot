extends Node

const PORT: int = 8765
const MAX_BATCH_DURATION_MS: int = 2_000
const STATE_SIZE: int = 16

@onready var game = get_parent()

var tcp_server := TCPServer.new()
var peers: Dictionary = {}
var next_peer_id := 1
var players: Dictionary = {}

var batch_peer: WebSocketPeer = null
var queued_actions: Dictionary = {}
var pending_players: Dictionary = {}
var completed_results: Dictionary = {}
var batch_running: bool = false
var batch_started_msec: int = 0


func _ready() -> void:
	if tcp_server.listen(PORT) != OK:
		push_error("Failed to start WebSocket server")
		return

	var players_node = game.get_node_or_null("LevelRoot/Players")

	if players_node == null:
		push_error("LevelRoot/Players is required")
		return

	for player in players_node.get_children():
		var player_id: int = int(player.player_id)
		players[player_id] = player
		player.rl_step_finished.connect(
			_on_player_step_finished.bind(player_id)
		)

	if not game.HEADLESS_MODE:
		print(
			"Synchronized multi-player RL server started on port ",
			PORT
		)


func _handle_message(peer: WebSocketPeer, message: String) -> void:
	var json = JSON.parse_string(message)

	if not json is Dictionary:
		_send_error(peer, "Malformed JSON object")
		return

	match json.get("type", ""):
		"reset":
			_handle_reset(peer, json)
		"step":
			_queue_action(peer, json)
		"quit":
			_handle_quit(peer)
		_:
			_send_error(peer, "Unknown message type")


func _handle_quit(peer: WebSocketPeer) -> void:
	peer.send_text(
		JSON.stringify({"type": "quit_response"})
	)

	get_tree().quit()


func _handle_reset(peer: WebSocketPeer, json: Dictionary) -> void:
	seed(int(json.get("seed", 42)))

	_cancel_batch()

	game.rl_batch_active = false
	game.reset_episode()

	var states := {}

	for player_id in players:
		var player = players[player_id]

		player.rl_mode = false
		player.rl_step_frames = 0

		states[str(player_id)] = _get_rl_state(player)

	peer.send_text(
		JSON.stringify({
			"type": "reset_response",
			"states": states
		})
	)


func _active_player_ids() -> Array:
	var active: Array = []

	for player_id in players:
		if not game.get_player_state(player_id).get(
			"episode_done",
			true
		):
			active.append(player_id)

	active.sort()

	return active


func _queue_action(peer: WebSocketPeer, json: Dictionary) -> void:
	if not json.has("player_id") or not json.has("action"):
		_send_error(
			peer,
			"Step requires player_id and action"
		)
		return

	var player_id := int(json["player_id"])
	var action := int(json["action"])

	if not players.has(player_id) or action < 0 or action > 5:
		_send_error(
			peer,
			"Unknown player_id or invalid action"
		)
		return

	if game.get_player_state(player_id).get(
		"episode_done",
		false
	):
		peer.send_text(
			JSON.stringify(
				_terminal_result(player_id)
			)
		)
		return

	if batch_running:
		_send_error(
			peer,
			"Environment step is already running"
		)
		return

	if batch_peer != null and batch_peer != peer:
		_send_error(
			peer,
			"Another client owns the current action batch"
		)
		return

	if queued_actions.has(player_id):
		_send_error(
			peer,
			"Duplicate action for player %s" % player_id
		)
		return

	batch_peer = peer
	queued_actions[player_id] = action

	var active := _active_player_ids()

	if _has_actions_for(active):
		_start_batch(active)
	elif active.is_empty():
		_send_batch_responses()


func _has_actions_for(player_ids: Array) -> bool:
	for player_id in player_ids:
		if not queued_actions.has(player_id):
			return false

	return true


func _start_batch(active: Array) -> void:
	batch_running = true
	game.rl_batch_active = true
	pending_players.clear()

	for player_id in active:
		var player = players[player_id]

		game.begin_step(player_id)

		player.set_action(queued_actions[player_id])
		player.rl_step_frames = 0
		player.rl_mode = true

		pending_players[player_id] = true

	batch_started_msec = Time.get_ticks_msec()


func _on_player_step_finished(player_id: int) -> void:
	if pending_players.has(player_id):
		_finish_player_step(player_id)


func _finish_player_step(player_id: int) -> void:
	if not pending_players.has(player_id):
		return

	pending_players.erase(player_id)

	var player = players[player_id]

	player.rl_mode = false
	player.rl_step_frames = 0
	player.reset_protected = false

	game.apply_apple_progress_reward(
		player_id,
		player
	)

	game.apply_step_penalty(player_id)

	var step_reward: float = game.get_step_reward(
		player_id
	)

	if (
		game.DEBUG_REWARDS
		and player_id == game.DEBUG_PLAYER_ID
	):
		print(
			"[STEP] P", player_id,
			" action=", player.current_action,
			" pos=", player.global_position,
			" on_floor=", player.is_on_floor(),
			" vel=", player.velocity,
			" step_reward=%.4f" % step_reward
		)

	completed_results[player_id] = {
		"type": "step_response",
		"player_id": player_id,
		"state": _get_rl_state(player),
		"reward": step_reward,
		"done": bool(
			game.get_player_state(player_id).get(
				"episode_done",
				false
			)
		),
		"statistics": game.get_statistics(player_id)
	}

	if pending_players.is_empty():
		_send_batch_responses()


func _terminal_result(player_id: int) -> Dictionary:
	var player = players[player_id]

	return {
		"type": "step_response",
		"player_id": player_id,
		"state": _get_rl_state(player),
		"reward": game.get_step_reward(player_id),
		"done": true,
		"statistics": game.get_statistics(player_id)
	}


func _get_rl_state(player: CharacterBody2D) -> Array:
	var state: Array = player.get_state()

	if state.size() != STATE_SIZE:
		push_error(
			"Player %s returned state size %s; expected %s"
			% [
				player.player_id,
				state.size(),
				STATE_SIZE
			]
		)

		return state

	return state


func _send_batch_responses() -> void:
	if batch_peer == null:
		_cancel_batch()
		return

	for player_id in queued_actions.keys():
		if not completed_results.has(player_id):
			completed_results[player_id] = _terminal_result(
				player_id
			)

		batch_peer.send_text(
			JSON.stringify(
				completed_results[player_id]
			)
		)

	_cancel_batch()


func _cancel_batch() -> void:
	for player_id in pending_players:
		var player = players[player_id]

		player.rl_mode = false
		player.rl_step_frames = 0

	queued_actions.clear()
	pending_players.clear()
	completed_results.clear()

	batch_peer = null
	batch_running = false
	batch_started_msec = 0

	game.rl_batch_active = false


func _send_error(
	peer: WebSocketPeer,
	message: String
) -> void:
	peer.send_text(
		JSON.stringify({
			"type": "error",
			"message": message
		})
	)


func _process(_delta: float) -> void:
	# Required:
	# - Poll WebSocket peers
	# - Receive Python actions
	# - Detect interrupted player batches
	# - Prevent Python from waiting indefinitely

	if batch_running:
		for player_id in pending_players.keys():
			if game.get_player_state(player_id).get(
				"episode_done",
				false
			):
				_finish_player_step(player_id)

		if (
			batch_running
			and Time.get_ticks_msec() - batch_started_msec
				> MAX_BATCH_DURATION_MS
		):
			push_warning(
				"RL batch watchdog finished stalled players."
			)

			for player_id in pending_players.keys():
				_finish_player_step(player_id)

	while tcp_server.is_connection_available():
		var tcp_connection: StreamPeerTCP = (
			tcp_server.take_connection()
		)

		var peer := WebSocketPeer.new()

		if peer.accept_stream(tcp_connection) == OK:
			peers[next_peer_id] = peer
			next_peer_id += 1

	for peer_id in peers.keys():
		var peer: WebSocketPeer = peers[peer_id]

		peer.poll()

		if peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
			while peer.get_available_packet_count() > 0:
				var packet := peer.get_packet()

				if peer.was_string_packet():
					_handle_message(
						peer,
						packet.get_string_from_utf8()
					)

		elif peer.get_ready_state() == WebSocketPeer.STATE_CLOSED:
			if peer == batch_peer:
				_cancel_batch()

			peers.erase(peer_id)
