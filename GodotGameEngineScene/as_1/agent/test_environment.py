from stable_baselines3.common.env_checker import check_env

from as1_env import AS1GodotEnv


env = AS1GodotEnv(headless=False)

try:
    # Validate the Gymnasium interface.
    check_env(env, warn=True)

    observation, info = env.reset()
    print("Initial observation:", observation)

    # Run random actions before introducing PPO.
    for step_number in range(1_000):
        action = env.action_space.sample()

        observation, reward, terminated, truncated, info = env.step(action)

        print(
            f"step={step_number}, "
            f"action={action}, "
            f"reward={reward:.3f}, "
            f"reason={info.get('reason', '')}"
        )

        if terminated or truncated:
            print("Episode finished:", info)
            observation, info = env.reset()

finally:
    env.close()
