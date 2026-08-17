"""
Offline Lotka-Volterra ecosystem stability test.
Simulates 100 in-game days to ensure populations don't explode or crash to zero.
"""
import random
import math

RABBIT_BIRTH_RATE = 0.5
PREDATION_RATE    = 0.25
LOW_FOOD_THRESHOLD = 2
WOLF_BIRTH_RATE   = 0.08
WOLF_STARVATION_RATE = 0.15
MAX_RABBITS = 8
MAX_WOLVES  = 2
MIGRATION_CHANCE_PER_DAY = 0.05

def simulate(days, init_rabbits, init_wolves, init_food):
    r, w, f = float(init_rabbits), float(init_wolves), float(init_food)
    history = [(0, r, w)]
    for day in range(1, days + 1):
        food_factor = min(f / (LOW_FOOD_THRESHOLD + 1), 1.0)
        rabbit_births = r * RABBIT_BIRTH_RATE * food_factor
        rabbit_deaths = r * w * PREDATION_RATE
        r = round(min(max(r + rabbit_births - rabbit_deaths, 0), MAX_RABBITS))

        wolf_births = w * WOLF_BIRTH_RATE * r
        starvation_mult = 1.0 if r <= 0 else 0.2
        wolf_deaths = w * WOLF_STARVATION_RATE * starvation_mult
        w = round(min(max(w + wolf_births - wolf_deaths, 0), MAX_WOLVES))

        f = max(0, f - r)  # rabbits eat food

        # Migration
        if r == 0 and random.random() < MIGRATION_CHANCE_PER_DAY:
            r = 1
        if w == 0 and r >= 4 and random.random() < MIGRATION_CHANCE_PER_DAY * 0.5:
            w = 1

        history.append((day, r, w))
    return history

scenarios = [
    ("Normal start",       4, 1, 6),
    ("No wolves",          5, 0, 6),
    ("Rabbit crash",       1, 2, 1),
    ("Too many wolves",    2, 2, 4),
    ("Lots of food",       3, 1, 15),
]

for name, init_r, init_w, init_f in scenarios:
    hist = simulate(100, init_r, init_w, init_f)
    rabbit_vals = [h[1] for h in hist]
    wolf_vals   = [h[2] for h in hist]
    print(f"\n--- {name} (R={init_r}, W={init_w}, F={init_f}) ---")
    print(f"  Rabbits: min={int(min(rabbit_vals))}, max={int(max(rabbit_vals))}, final={int(rabbit_vals[-1])}")
    print(f"  Wolves:  min={int(min(wolf_vals))}, max={int(max(wolf_vals))}, final={int(wolf_vals[-1])}")
    # Check stability
    never_extinct_r = any(v > 0 for v in rabbit_vals[10:])
    never_explode_r = max(rabbit_vals) <= MAX_RABBITS
    ok = "STABLE" if never_extinct_r and never_explode_r else "UNSTABLE"
    print(f"  Result: {ok}")
