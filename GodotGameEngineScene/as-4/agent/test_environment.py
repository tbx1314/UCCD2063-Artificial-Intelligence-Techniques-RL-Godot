import time

import numpy as np
from as4_env import AS4GodotEnv 
from stable_baselines3.common.env_checker import check_env

# Create env before using it.
# Headless mode is appropriate for repeatable automated validation. Change this
# to False temporarily when visually inspecting player and enemy behaviour.
env = AS4GodotEnv(headless=True)

try:
    # 1. Validate the Gymnasium interface.
    check_env(env, warn=True)
    print("PASS: Gymnasium interface is valid")

    # 2. Reset before testing synchronization.
    observation, info = env.reset()
    print("Initial observation:", observation)

    # 3. Check that Godot remains frozen between Python actions.
    before_wait = env.inspect_observation()

    time.sleep(2.0)

    after_wait = env.inspect_observation()

    np.testing.assert_allclose(
        before_wait,
        after_wait,
        atol=1e-7,
        err_msg="Godot state changed while waiting for Python",
    )

    print("PASS: Environment remains frozen between actions")

    # 4. Run one complete random episode.
    cumulative_reward = 0.0
    episode_step = 0
    terminated = False
    truncated = False

    while not (terminated or truncated):
        action = env.action_space.sample()

        observation, reward, terminated, truncated, info = env.step(action)

        episode_step += 1
        cumulative_reward += reward

        # Keep routine output readable while still showing early transitions,
        # regular progress, and the terminal transition needed for diagnosis.
        if episode_step <= 5 or episode_step % 25 == 0 or terminated or truncated:
            print(
                f"step={episode_step}, "
                f"action={action}, "
                f"reward={reward:.3f}, "
                f"reason={info.get('reason', '')}"
            )

        # Observation must remain inside the declared observation space.
        assert env.observation_space.contains(observation), (
            f"Invalid observation at step {episode_step}: {observation}"
        )

        # Python and Godot must agree about the step number.
        assert info["steps"] == episode_step, (
            f"Step mismatch: Python={episode_step}, Godot={info['steps']}"
        )

        # Python and Godot must agree about cumulative reward.
        np.testing.assert_allclose(
            cumulative_reward,
            info["total_reward"],
            atol=1e-5,
            err_msg="Python reward total differs from Godot total",
        )

        # An episode cannot be terminated and truncated simultaneously.
        assert not (terminated and truncated)

    # 5. Save terminal information before reset overwrites info.
    reason = info["reason"]
    terminal_info = info.copy()
    terminal_reward = reward

    print("Episode finished:", terminal_info)
    print("Cumulative reward:", cumulative_reward)

    # 6. Validate the terminal reason.
    if reason == "enemy":
        assert terminated and not truncated

        # Enemy penalty is -30. One apple may contribute +15 in the same step;
        # the terminal transition must therefore still be approximately -15
        # or lower. A small tolerance allows the bounded progress component.
        assert terminal_reward <= -14.8, (
            f"Enemy termination did not include the expected penalty: {terminal_reward}"
        )

    elif reason == "fall":
        assert terminated and not truncated

        # A fall uses the same -30 penalty and may coincide with one +15 apple.
        assert terminal_reward <= -14.8, (
            f"Fall termination did not include the expected penalty: {terminal_reward}"
        )

    elif reason == "timeout":
        assert truncated and not terminated

    elif reason == "success":
        assert terminated and not truncated
        assert terminal_info["apples_collected"] == terminal_info["total_apples"]

    else:
        raise AssertionError(f"Unknown terminal reason: {reason}")

    print(f"PASS: Terminal reason '{reason}' is valid")

    # 7. Reset only after checking the terminal information.
    observation, reset_info = env.reset()

    assert reset_info["reason"] == ""
    assert reset_info["steps"] == 0
    assert reset_info["apples_collected"] == 0

    print("PASS: Environment reset is valid")
    print("ALL ENVIRONMENT TESTS PASSED")

finally:
    env.close()
