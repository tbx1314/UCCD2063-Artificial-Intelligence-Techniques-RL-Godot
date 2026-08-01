# UCCD2063 Artificial Intelligence Techniques Practical Assignment

Group project for the June-September 2026 semester. The project develops four variants of a 2D platform collector game in Godot and trains a reinforcement learning (RL) agent for each variant.

> **Current status:** the repository currently contains the assignment brief and four Godot scene directories. The Python RL agents, training notebooks, experiment results, report, presentation materials, and LLM prompt log still need to be added.

## Assignment objective

Create RL agents that learn through repeated interaction with a Godot platform game. An agent must move and jump across platforms, collect apples, avoid snail enemies and unsafe falls, and complete its assigned level while maximizing cumulative reward.

1. One distinct Godot scene design.
2. One suitable RL technique, such as Q-Learning, SARSA, Expected SARSA, DQN, Double DQN, or PPO.
3. The state, action, and reward design for that scene.
4. Training and testing the selected agent under multiple parameter settings.
5. Recording results and contributing approximately five pages to the group report.

## Required system design

After every action, the Godot environment should provide the Python agent with:

- the next state;
- the reward received;
- whether the episode has ended; and
- the current score or relevant performance metrics.

A state may include the player's position, whether the player is grounded, distances or directions to apples and enemies, nearby platforms or gaps, and distance to the goal. The action space may include no action, left, right, jump, left-jump, and right-jump.

The reward function should encourage useful progress and efficient completion. Examples include positive rewards for collecting an apple, approaching the next objective, and completing the level; and penalties for enemy contact, falling, remaining idle, or consuming unnecessary time steps.

Every design decision must be explained and linked to the selected RL method and scene layout.

## Experiments and evaluation

Do not report only one run with default settings. Each member must compare different training settings and record suitable metrics, such as:

- total reward per episode and a learning curve;
- average evaluation score;
- apples collected;
- enemies avoided;
- completion rate or distance travelled;
- survival time; and
- training time.

The discussion should explain whether learning improved, compare strengths and weaknesses, analyze failure cases, and relate observed behaviour to the algorithm and level design.

## Repository structure

```text
.
├── FullTime-2026-June_Sept_UCCD2063_-_Question.pdf
├── GodotGameEngineScene/
│   ├── as_1/
│   ├── as-2/
│   ├── as-3/
│   └── as-4/
├── README.md
└── CONTRIBUTING.md
```

Each Godot directory currently contains a project with a player, collectible apples, snail enemies, audio, scenes, and GDScript files. Before experimentation, the four scenes must be changed into genuinely different layouts as required by the brief.

Recommended additions as the project develops:

```text
agents/       # RL implementations or reusable Python modules
notebooks/    # Training and testing .ipynb files
results/      # CSV data, plots, evaluation tables, and screenshots
prompts/      # LLM prompts, outputs, verification, and modifications
report/       # Report source and final PDF
slides/       # Presentation materials
```

## Requirements

- Godot 4.6 (the current projects declare Godot 4.6 features)
- Python 3.6 or later
- Jupyter Notebook
- Packages appropriate to the chosen method, for example NumPy, Matplotlib, PyTorch, or TensorFlow

Record exact Python package versions in a `requirements.txt` or environment file before final submission.

## Run the current Godot prototype

1. Install Godot 4.6.
2. Open Godot and import the `project.godot` file from the assigned scene directory.
3. Run the main scene with **F6**, or run the project with **F5**.
4. Use **A/Left Arrow** and **D/Right Arrow** to move.
5. Use **W** or **Space** to jump.

These steps run the current human-controlled prototype. RL training instructions must be added after the Godot-Python interface and agent notebooks are implemented.

## Submission checklist

Submit one ZIP file to WBLE by **30 August 2026 (Sunday), 5:00 PM**. The ZIP must contain:

- [ ] final report in PDF format;
- [ ] runnable and well-commented Python notebook(s) (`.ipynb`);
- [ ] all Godot projects, scenes, scripts, and required assets;
- [ ] LLM prompts, relevant follow-up prompts, generated outputs, and notes explaining how outputs were checked, changed, and used;
- [ ] training and testing data, graphs, tables, and screenshots required to reproduce the reported results;
- [ ] clear setup and reproduction instructions; and
- [ ] any other supporting material used in the assignment.

The report is limited to 20 pages, excluding the cover page, references, and appendices. Use Times New Roman, 10-point font, single-line spacing, and IEEE in-text citations and references.

## Mark allocation

| Criterion | Weight |
|---|---:|
| Explanation of RL techniques | 15% |
| Training setup and parameter settings | 15% |
| Training and testing results | 20% |
| Discussion of agent performance | 20% |
| Presentation | 10% |
| LLM prompt generation | 5% |
| Report documentation | 5% |
| Effort and in-depth/self-directed analysis | 5% |
| Coding style | 5% |

See [CONTRIBUTING.md](CONTRIBUTING.md) for the group workflow, coding standards, experiment records, and review checklist.

## Academic integrity

All submitted work must be understood, verified, and attributable to the group. Cite external ideas, code, media, and references appropriately. Retain the LLM prompt history required by the rubric and explain how generated material was validated or modified. Plagiarism can result in zero marks and further action under university regulations.

