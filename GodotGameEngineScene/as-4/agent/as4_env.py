"""Gymnasium environment connecting Stable-Baselines3 to Godot AS4.

AS4 reuses the same player/snail/apple building blocks and the same
Python<->Godot WebSocket protocol as AS1 (see AS1GodotEnv in as1_env.py);
the only difference visible from level_root.tscn is a harder level layout
with two Snail instances and two Apple instances instead of one of each.
Because AS1's twelve-value observation already reports the *nearest*
active apple/waypoint and the *nearest* active snail rather than hardcoding
exactly one of each, that observation and action design should generalize
to AS4's extra enemies and apples without any change on the Python side.

This file assumes the AS4 Godot project exposes the same
reset/step/inspect JSON WebSocket protocol that AS1's websocket_bridge.gd
implements, and that its main.gd reports the same twelve normalized
observation values (see the table below) and the same six discrete
actions. If AS4's main.gd instead reports per-enemy or per-apple
observations (e.g. separate dx/dy for each of the two snails/apples
rather than only the nearest of each), the observation_space and
_convert_observation below will need to be widened accordingly - this
file cannot detect that mismatch on its own since only level_root.tscn
(not the AS4 GDScript) was available when this was written.

AS4GodotEnv now accepts a `port` argument (default 8765) which is passed
both to its local WebSocket server and to Godot as a "--port=<n>" user
argument. This lets multiple AS4GodotEnv instances - each on its own
port - run simultaneously for parallel training, as long as the paired
websocket_bridge.gd on the Godot side also reads that "--port=" argument
(via OS.get_cmdline_user_args()) instead of using a hardcoded port.
"""

from __future__ import annotations

import json
import os
import queue
import shutil
import subprocess
import threading
from pathlib import Path
from typing import Any

import gymnasium as gym
import numpy as np
from websockets.exceptions import ConnectionClosed
from websockets.sync.server import ServerConnection, serve


def _resolve_godot_executable() -> Path:
    """Locate Godot while allowing an explicit machine-specific override."""

    override = os.environ.get("GODOT_EXECUTABLE")
    if override:
        return Path(override).expanduser()

    # Command-line installations normally expose one of these executable names.
    command = shutil.which("godot") or shutil.which("godot4")
    if command:
        return Path(command)

    # Default location used by the official macOS application bundle.
    return Path(r"D:\Downloads\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64\Godot_v4.7.1-stable_mono_win64.exe")


GODOT_EXECUTABLE = _resolve_godot_executable()

# Resolve the Godot project relative to this module so the repository can be
# moved or opened on another group member's machine without editing source code.
PROJECT_DIRECTORY = Path(r"D:\GitHub\UCCD2063-Artificial-Intelligence-Techniques-RL-Godot\GodotGameEngineScene\as-4")


class GodotWebSocketServer:
    """Runs a local WebSocket server and exchanges JSON messages with Godot."""

    def __init__(
        self,
        host: str = "127.0.0.1",
        port: int = 8765,
        timeout: float = 30.0,
    ) -> None:
        self.host = host
        self.port = port
        self.timeout = timeout

        self._connection: ServerConnection | None = None
        self._server = None

        # Events allow the main thread to wait until the server and Godot are ready.
        self._server_ready = threading.Event()
        self._godot_connected = threading.Event()

        # Godot responses are placed here by the connection-handling thread.
        self._response_queue: queue.Queue[dict[str, Any]] = queue.Queue()

        # Only one reset or step request may be active at one time.
        self._request_lock = threading.Lock()

        self._thread = threading.Thread(
            target=self._run_server,
            name=f"godot-websocket-server-{port}",
            daemon=True,
        )

    def start(self) -> None:
        """Start the WebSocket server in a background thread."""

        self._thread.start()

        if not self._server_ready.wait(self.timeout):
            raise TimeoutError("WebSocket server did not start")

    def wait_for_godot(self) -> None:
        """Wait until the Godot WebSocket client connects."""

        if not self._godot_connected.wait(self.timeout):
            raise TimeoutError("Godot did not connect to the WebSocket server")

    def request(self, payload: dict[str, Any]) -> dict[str, Any]:
        """Send one request and block until its matching response arrives."""

        with self._request_lock:
            if self._connection is None:
                raise ConnectionError("Godot WebSocket is not connected")

            # Remove an unexpected stale response before sending a new request.
            while not self._response_queue.empty():
                self._response_queue.get_nowait()

            self._connection.send(json.dumps(payload))

            try:
                response = self._response_queue.get(timeout=self.timeout)
            except queue.Empty as error:
                raise TimeoutError(
                    f"Godot did not answer request: {payload}"
                ) from error

            if response.get("type") == "error":
                raise RuntimeError(
                    f"Godot error: {response.get('message', 'unknown error')}"
                )

            return response

    def close(self) -> None:
        """Stop accepting connections and close the WebSocket server."""

        if self._server is not None:
            self._server.shutdown()

    def _run_server(self) -> None:
        """Create the server and keep it running until close() is called."""

        with serve(
            self._handle_connection,
            self.host,
            self.port,
            ping_interval=20,
            ping_timeout=20,
        ) as server:
            self._server = server
            self._server_ready.set()
            server.serve_forever()

    def _handle_connection(
        self,
        websocket: ServerConnection,
    ) -> None:
        """Receive every JSON response sent by the connected Godot process."""

        self._connection = websocket
        self._godot_connected.set()

        try:
            for message in websocket:
                response = json.loads(message)
                self._response_queue.put(response)
        except ConnectionClosed:
            # A disconnect is expected when close() shuts down Godot and the
            # local WebSocket server at the end of a test or training run.
            pass
        finally:
            if self._connection is websocket:
                self._connection = None
                self._godot_connected.clear()


class AS4GodotEnv(gym.Env[np.ndarray, int]):
    """Gymnasium wrapper for the AS4 Godot platform environment.

    AS4's level_root.tscn places two Snail enemies (Enemies/Snail,
    Enemies/Snail2) and two Apple pickups (Apple/Apple, Apple/Apple2)
    instead of AS1's one of each. The observation and action definitions
    below are otherwise identical to AS1GodotEnv, since main.gd is assumed
    to already report only the nearest active apple/waypoint and the
    nearest active snail rather than one slot per entity.
    """

    metadata = {"render_modes": ["human"]}

    def __init__(
        self,
        headless: bool = False,
        request_timeout: float = 30.0,
        port: int = 8765,
    ) -> None:
        super().__init__()

        if not GODOT_EXECUTABLE.exists():
            raise FileNotFoundError(f"Godot executable not found: {GODOT_EXECUTABLE}")

        if not (PROJECT_DIRECTORY / "project.godot").exists():
            raise FileNotFoundError(f"Godot project not found: {PROJECT_DIRECTORY}")

        # The agent can select one of six integer actions.
        self.action_space = gym.spaces.Discrete(6)

        # Exact boundaries corresponding, in order, to main.gd's twelve
        # normalized observations. Keeping both definitions synchronized lets
        # Gymnasium reject malformed or out-of-range states before the agent
        # sees them.
        self.observation_space = gym.spaces.Box(
            low=np.array(
                [
                    0.0,  # player x
                    -0.5,  # player y
                    -1.0,  # horizontal velocity
                    -2.0,  # vertical velocity
                    0.0,  # is_on_floor
                    0.0,  # is touching wall
                    -1.0,  # wall-normal x
                    -1.0,  # nearest active apple/waypoint dx
                    -1.0,  # nearest active apple/waypoint dy
                    -1.0,  # nearest active snail dx
                    -1.0,  # nearest active snail dy
                    0.0,  # apples remaining
                ],
                dtype=np.float32,
            ),
            high=np.array(
                [
                    1.5,  # player x
                    1.5,  # player y
                    1.0,  # horizontal velocity
                    2.0,  # vertical velocity
                    1.0,  # is_on_floor
                    1.0,  # is touching wall
                    1.0,  # wall-normal x
                    1.0,  # nearest active apple/waypoint dx
                    1.0,  # nearest active apple/waypoint dy
                    1.0,  # nearest active snail dx
                    1.0,  # nearest active snail dy
                    1.0,  # apples remaining
                ],
                dtype=np.float32,
            ),
            dtype=np.float32,
        )

        self.port = port
        self.bridge = GodotWebSocketServer(port=port, timeout=request_timeout)
        self.bridge.start()

        # Start Godot only after Python is ready to accept its connection.
        command = [
            str(GODOT_EXECUTABLE),
            "--path",
            str(PROJECT_DIRECTORY),
        ]

        if headless:
            command.append("--headless")

        # simulate 4x faster than real-time
        command.extend(["--fixed-fps", "480"])

        # Everything after "--" is passed through to Godot's user args
        # (OS.get_cmdline_user_args() on the GDScript side), rather than
        # being interpreted as an engine flag. websocket_bridge.gd reads
        # "--port=<n>" from there to decide which port to connect to, so
        # each concurrently-running Godot instance can bind to a different
        # local Python WebSocket server.
        command.extend(["--", f"--port={port}"])

        self.godot_process = subprocess.Popen(command)
        self.bridge.wait_for_godot()

    def reset(
        self,
        *,
        seed: int | None = None,
        options: dict[str, Any] | None = None,
    ) -> tuple[np.ndarray, dict[str, Any]]:
        """Start a new Godot episode and return its first observation."""

        super().reset(seed=seed)

        # Gymnasium's environment RNG and the Discrete action-space RNG are
        # independent. Seeding both makes the random-agent baseline repeatable.
        if seed is not None:
            self.action_space.seed(seed)

        response = self.bridge.request({"command": "reset"})

        observation = self._convert_observation(response["observation"])
        info = dict(response.get("info", {}))

        return observation, info

    def step(
        self,
        action: int,
    ) -> tuple[np.ndarray, float, bool, bool, dict[str, Any]]:
        """Send one action to Godot and return the resulting transition."""

        if not self.action_space.contains(action):
            raise ValueError(f"Invalid action: {action}")

        response = self.bridge.request(
            {
                "command": "step",
                "action": int(action),
            }
        )

        observation = self._convert_observation(response["observation"])
        reward = float(response["reward"])
        info = dict(response.get("info", {}))

        reason = str(info.get("reason", ""))

        # These events are natural terminal states of the AS4 task.
        terminated = reason in {
            "success",
            "enemy",
            "fall",
        }

        # Timeout is an external time limit rather than a task terminal state.
        truncated = reason == "timeout"

        return observation, reward, terminated, truncated, info

    def inspect_observation(self) -> np.ndarray:
        """Read synchronized state without executing an action or physics tick."""

        response = self.bridge.request({"command": "inspect"})
        return self._convert_observation(response["observation"])

    def close(self) -> None:
        """Close Godot and the local WebSocket server."""

        # Close the WebSocket first so it can send a normal close frame while
        # Godot is still alive and polling the connection.
        if hasattr(self, "bridge"):
            self.bridge.close()

        if hasattr(self, "godot_process"):
            if self.godot_process.poll() is None:
                self.godot_process.terminate()

                try:
                    self.godot_process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    self.godot_process.kill()

        super().close()

    def _convert_observation(
        self,
        values: list[float],
    ) -> np.ndarray:
        """Convert and validate a Godot observation."""

        observation = np.asarray(values, dtype=np.float32)

        if observation.shape != self.observation_space.shape:
            raise ValueError(
                "Incorrect observation shape: "
                f"expected {self.observation_space.shape}, "
                f"received {observation.shape}"
            )

        if not np.all(np.isfinite(observation)):
            raise ValueError(f"Observation contains NaN or infinity: {observation}")

        if not self.observation_space.contains(observation):
            raise ValueError(
                f"Observation is outside its declared space: {observation}"
            )

        return observation