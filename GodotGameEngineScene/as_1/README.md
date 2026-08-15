# AS1 PPO Platform-Collector Agent

This directory contains the AS1 Godot level, its synchronized Gymnasium
interface, PPO experiment notebook, configurations, models, and report evidence.

## Environment design

Python and Godot communicate locally through WebSocket port `8765`. During an
agent session, Godot is paused between Python requests. One `env.step(action)`
temporarily advances exactly four physics ticks, ensuring that player movement,
enemy movement, collisions, rewards, and terminal status belong to the same
transition.

The policy chooses one of six discrete actions:

| Value | Action |
|---:|---|
| 0 | Do nothing |
| 1 | Move left |
| 2 | Move right |
| 3 | Jump |
| 4 | Move left and jump |
| 5 | Move right and jump |

Each observation contains 12 normalized values in this exact order:

1. player x and y position;
2. horizontal and vertical velocity;
3. floor contact;
4. wall contact and horizontal wall normal;
5. relative x and y offset to the active navigation target;
6. relative x and y offset to the closest active snail; and
7. fraction of apples remaining.

The navigation target is normally the nearest uncollected apple. After the
lower apple is collected, an approach waypoint on the central platform becomes
the temporary target. This represents the reachable detour around the wall that
blocks a direct jump to the upper apple.

## Reward and termination design

| Event | Reward |
|---|---:|
| Each decision step | -0.01 |
| Collect an apple | +15 |
| Collect all apples | +100 |
| Hit an enemy | -30 |
| Unsafe fall | -30 |
| Reach 1,000 decisions | -25 |
| Target-distance improvement | Clipped to [-0.1, +0.1] |

`success`, `enemy`, and `fall` are task terminal states. `timeout` is represented
as Gymnasium truncation. Terminal bonuses and penalties are centralized in
`main.gd::_end_episode()` so each is applied exactly once.

## Tested software

- Godot 4.6.3
- Python 3.11.15
- Package versions in [`agent/requirements.txt`](agent/requirements.txt)

Create an isolated Python environment and install the recorded dependencies:

```bash
python -m pip install -r agent/requirements.txt
```

The official macOS Godot location is detected automatically. On another system,
set `GODOT_EXECUTABLE` to the full Godot executable path before running Python.
The project directory itself is resolved relative to `as1_env.py` and therefore
does not contain a user-specific repository path.

## Validate before training

From the repository root, run:

```bash
python GodotGameEngineScene/as_1/agent/test_environment.py
```

The test checks:

- Gymnasium API compatibility;
- observation shape and bounds;
- frozen state between Python actions;
- matching Python/Godot step counts;
- matching cumulative rewards;
- terminal versus truncated semantics; and
- reset counters.

Change `headless=True` to `headless=False` temporarily when visually inspecting
the validation episode.

## Train and evaluate

Open and run
[`agent/AS1_PPO_Training_and_Evaluation.ipynb`](agent/AS1_PPO_Training_and_Evaluation.ipynb)
from top to bottom. The notebook:

1. records software and hardware versions;
2. validates the environment;
3. evaluates a random policy;
4. loads the numbered one-factor PPO configurations;
5. trains and saves each configuration sequentially;
6. evaluates all completed policies with the same protocol; and
7. saves raw CSV evidence and report-quality figures.

Corrected synchronized results are written directly under `results`. Corrected
models remain under `models/v2_synchronized_waypoint` so they cannot be confused
with pilot models from the earlier 10-observation environment.

## Reproducibility notes

- All configurations currently use seed 42 and a common 200,000-timestep target.
- PPO may finish slightly above the target because it completes full rollouts.
- The fixed scene is deterministic, so repeated deterministic evaluations may
  duplicate behaviour. Final robustness claims should use documented evaluation
  variations or additional training seeds.
- If the observation definition, reward function, or scene layout changes,
  create a new experiment version and retrain models from scratch.
