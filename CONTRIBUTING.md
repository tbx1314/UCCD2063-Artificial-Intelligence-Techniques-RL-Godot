# Contributing Guide

This guide coordinates the four-person UCCD2063 assignment. Contributions should remain reproducible, easy to review, and clearly attributable to a group member.

## Branch and commit workflow

1. Pull the latest agreed group version before beginning work.
2. Create a focused branch such as `feature/as-2-sarsa` or `docs/report-results`.
3. Keep unrelated changes out of the same commit.
4. Use short, meaningful commit messages, for example:

   ```text
   feat(as-2): add SARSA action selection
   experiment(as-2): compare epsilon decay schedules
   fix(godot): reset apples between episodes
   docs: add DQN evaluation discussion
   ```

5. Ask at least one teammate to review a change before it is merged into the group submission version.
6. Do not commit generated Godot cache folders, Python virtual environments, notebook checkpoints, or temporary files.

No remote push is required for the initial documentation files.

## Scene requirements

Each scene must have a meaningfully different platform layout, route design, apple placement, or enemy placement. Renaming an identical project is not sufficient.

Before training, confirm that the environment can:

- accept one action from the agent at each step;
- return the next state, scalar reward, terminal status, and score/metrics;
- reset the player, apples, enemies, timers, and score consistently;
- detect goal completion, enemy collision, and unsafe falls;
- run repeatedly without requiring manual keyboard input; and
- support deterministic evaluation where practical through recorded random seeds.

Keep game logic separate from the Python agent logic. Avoid embedding algorithm-specific behaviour inside the scene if a general environment interface can be used.

## Python and notebook standards

- Use Python 3.6 or later and document the exact tested version.
- Put reusable logic in clearly named functions or classes.
- Use meaningful names such as `learning_rate`, `discount_factor`, and `episode_reward`.
- Add comments for non-obvious reasoning, state encodings, reward calculations, and protocol messages.
- Keep training, testing, and visualization code clearly separated.
- Set and record random seeds when supported.
- Save raw numerical results before creating graphs.
- Restart the notebook kernel and run all cells from top to bottom before review.
- Remove broken cells, hidden dependencies, debug output, and unexplained constants.
- Add/update `requirements.txt` whenever a dependency changes.

## Experiment record

Every reported run should include enough information to reproduce it. Save at least:

- member, scene, algorithm, date, and run identifier;
- code revision or commit identifier;
- Python, Godot, and package versions;
- random seed(s);
- state representation and action mapping;
- complete reward function;
- episode count and maximum steps per episode;
- learning rate, discount factor, exploration settings, and algorithm-specific parameters;
- hardware used and training duration;
- raw per-episode metrics; and
- evaluation protocol and final metrics.

Change one main factor at a time where possible. Compare multiple settings rather than showing only the best run. Keep unsuccessful runs when they help explain failure modes or parameter sensitivity.

Suggested result filenames follow this pattern:

```text
results/<scene>/<algorithm>/<run-id>_config.json
results/<scene>/<algorithm>/<run-id>_episodes.csv
results/<scene>/<algorithm>/<run-id>_learning-curve.png
```

## Result quality checks

Before using a result in the report, verify that:

- training and evaluation episodes are clearly distinguished;
- evaluation uses a fixed policy or a documented exploration setting;
- averages state the number of runs or episodes used;
- graph axes, units, legends, and captions are present;
- smoothing, if used, is disclosed and does not replace the raw data;
- screenshots correspond to the stated scene and agent; and
- claims in the discussion are supported by a table, graph, log, or observed failure case.

## LLM usage log

The rubric awards marks for responsible LLM prompt documentation. For every material use, retain:

1. the original prompt and relevant follow-up prompts;
2. the useful generated output or a clear reference to it;
3. what the group changed or rejected;
4. how the result was tested, checked, or verified; and
5. where it was applied in the code, experiment, or report.

Never submit generated code or writing that no group member can explain. Check technical claims against credible references and cite sources using IEEE style in the report.

## Documentation and report standards

- Keep setup and execution instructions synchronized with the working code.
- Use consistent terminology for states, actions, rewards, and metrics across all four sections.
- Give every table and figure a number, caption, and discussion in the text.
- Explain the RL concept, update process, policy, exploration/exploitation strategy, and suitability for the assigned scene.
- Report the training setup and all important parameter values, not only final results.
- Discuss improvement, limitations, strengths, weaknesses, and failure cases.
- Format the final report in Times New Roman, 10-point font, 1.0 line spacing, with IEEE citations.
- Keep the main report within 20 pages, excluding the cover, references, and appendices.

## Review checklist

Before accepting a contribution:

- [ ] The assigned Godot scene opens and runs.
- [ ] The environment resets correctly across repeated episodes.
- [ ] Training and testing run from a clean environment using documented commands.
- [ ] The notebook runs from its first cell to its last cell without manual repair.
- [ ] State, actions, rewards, and terminal conditions are documented.
- [ ] Hyperparameters and seeds are recorded.
- [ ] Raw results and readable visualizations are included.
- [ ] New code uses clear names, formatting, and comments.
- [ ] External sources and reused assets are credited.
- [ ] LLM-assisted work has a prompt and verification record.
- [ ] No personal credentials, machine-specific secrets, caches, or large temporary files are included.

## Final integration

One nominated integrator should assemble a clean copy of the project and reproduce each member's instructions. The group should then check the ZIP contents, open the final PDF, run the notebooks and Godot scenes where feasible, and confirm that no required asset is referenced only from a member's local machine.

The submission deadline stated in the assignment brief is **30 August 2026 (Sunday), 5:00 PM**. Allow time before the deadline for final reproduction, report formatting, presentation preparation, and ZIP validation.
