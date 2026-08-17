class_name EcosystemSimulator

## Offline "catch-up" ecosystem simulation using Lotka-Volterra population dynamics.
##
## Called once when a chunk loads to approximate what happened to its animals
## while the player was away, without running any 3D physics.
##
## Time scale: DayNightCycle.game_time is in real seconds.
##             1 in-game day = 300 real seconds.
## All rates below are expressed per IN-GAME DAY for readability.

# ─── Tuning ───────────────────────────────────────────────────────────────────

## Max rabbits that can live in one chunk (based on available food tiles)
const MAX_RABBITS := 8
## Max wolves that can live in one chunk
const MAX_WOLVES  := 2

## Rabbit base birth rate per day (fraction of population that reproduces)
const RABBIT_BIRTH_RATE := 0.5      # +50% per day if food is plentiful
## Rabbit death rate per day from wolf predation (per wolf * per rabbit)
const PREDATION_RATE := 0.25        # Each wolf kills 0.25 rabbits per day per rabbit
## Rabbit starvation threshold: if berry/apple availability is low, births slow
const LOW_FOOD_THRESHOLD := 2       # Fewer than 2 food sources → no reproduction

## Wolf birth rate per day (fraction of population that reproduces from eating rabbits)
const WOLF_BIRTH_RATE := 0.08       # Wolves reproduce slowly
## Wolf starvation rate per day (die without prey)
const WOLF_STARVATION_RATE := 0.15  # Wolves die at 15% per day with no rabbits

## Migration: once a population hits 0, this is the chance per day of a single
## animal migrating in from an off-screen region. Keeps the ecosystem from going
## permanently extinct while still feeling natural.
const MIGRATION_CHANCE_PER_DAY := 0.05   # 5% chance per day

## Real seconds per in-game day
const SECONDS_PER_DAY := 300.0

# ─── Main Entry Point ─────────────────────────────────────────────────────────

## Runs catch-up simulation on a ChunkData.
## Call this when a chunk is about to be loaded/rendered.
static func catch_up(data: ChunkData) -> void:
	var now := DayNightCycle.game_time
	
	# Fresh chunk: just stamp the time, don't alter spawns
	if data.last_sim_time < 0.0:
		data.last_sim_time = now
		return
	
	var elapsed_seconds := now - data.last_sim_time
	if elapsed_seconds < 5.0:  # Loaded very recently, skip
		data.last_sim_time = now
		return
	
	var days_elapsed := elapsed_seconds / SECONDS_PER_DAY
	data.last_sim_time = now
	
	# Count current populations
	var rabbits := _count(data.animals, "blocky_rabbit")
	var wolves  := _count(data.animals, "wolf")
	var food    := _count_food(data)
	
	# Run discrete Lotka-Volterra for each day elapsed (capped to avoid huge loops)
	var steps := mini(int(days_elapsed), 30)  # Max 30 steps per load
	var frac  := days_elapsed / float(steps) if steps > 0 else 0.0
	
	for _i in range(steps):
		# ── Rabbit dynamics ──
		var food_factor := clampf(float(food) / float(LOW_FOOD_THRESHOLD + 1), 0.0, 1.0)
		var rabbit_births := float(rabbits) * RABBIT_BIRTH_RATE * food_factor * frac
		var rabbit_deaths := float(rabbits) * float(wolves) * PREDATION_RATE * frac
		rabbits = roundi(float(rabbits) + rabbit_births - rabbit_deaths)
		rabbits = clampi(rabbits, 0, MAX_RABBITS)
		
		# ── Wolf dynamics ──
		var wolf_births := float(wolves) * WOLF_BIRTH_RATE * float(rabbits) * frac
		var wolf_deaths := float(wolves) * WOLF_STARVATION_RATE * frac * (1.0 if rabbits <= 0 else 0.2)
		wolves = roundi(float(wolves) + wolf_births - wolf_deaths)
		wolves = clampi(wolves, 0, MAX_WOLVES)
		
		# ── Food depletion (rabbits eat) ──
		food = max(0, food - rabbits)
		
	# ── Migration: prevent permanent extinction ──
	if rabbits == 0:
		var migrate_chance := 1.0 - pow(1.0 - MIGRATION_CHANCE_PER_DAY, days_elapsed)
		if randf() < migrate_chance:
			rabbits = 1
			
	if wolves == 0 and rabbits >= 4:
		var migrate_chance := 1.0 - pow(1.0 - MIGRATION_CHANCE_PER_DAY * 0.5, days_elapsed)
		if randf() < migrate_chance:
			wolves = 1
	
	# ── Apply new populations back to ChunkData ──
	_rebuild_animals(data, rabbits, wolves)

# ─── Save Living Animals Before Unload ────────────────────────────────────────

## Call this BEFORE returning a ChunkNode to the pool.
## Extracts the live positions/hunger of each animal and saves them to ChunkData.
static func snapshot(data: ChunkData, node: ChunkNode) -> void:
	if not is_instance_valid(node.animals_container):
		return
	
	var saved: Array[Dictionary] = []
	for child in node.animals_container.get_children():
		if child is Animal:
			var local_pos := child.global_position - node.global_position
			saved.append({
				"type": child.animal_type,
				"x": local_pos.x / ChunkData.TILE_SIZE,
				"y": child.global_position.y,
				"z": local_pos.z / ChunkData.TILE_SIZE,
				"is_water": child.is_water_animal,
				"hunger": child.hunger,
			})
	
	# Only overwrite if there were actual animals (don't wipe freshly-generated ones)
	if node.animals_container.get_child_count() > 0:
		data.animals = saved
	
	data.last_sim_time = DayNightCycle.game_time

# ─── Helpers ──────────────────────────────────────────────────────────────────

static func _count(animals: Array[Dictionary], type: String) -> int:
	var n := 0
	for a in animals:
		if a.get("type", "") == type:
			n += 1
	return n

static func _count_food(data: ChunkData) -> int:
	# Berry bushes + apple trees are both food sources for rabbits
	var berries := data.vegetation.berry_bush_count()
	var apples  := data.vegetation.count_of(VegetationData.APPLE_TREE)
	return berries + apples

static func _rebuild_animals(data: ChunkData, rabbits: int, wolves: int) -> void:
	# Keep exact entries where we can, then add/remove to match counts
	var existing_rabbits: Array[Dictionary] = []
	var existing_wolves:  Array[Dictionary] = []
	for a in data.animals:
		if a.get("type", "") == "blocky_rabbit":
			existing_rabbits.append(a)
		elif a.get("type", "") == "wolf":
			existing_wolves.append(a)
	
	# Trim or grow rabbit list
	while existing_rabbits.size() > rabbits:
		existing_rabbits.pop_back()
	while existing_rabbits.size() < rabbits:
		existing_rabbits.append(_random_animal_dict("blocky_rabbit", false, data))
		
	# Trim or grow wolf list
	while existing_wolves.size() > wolves:
		existing_wolves.pop_back()
	while existing_wolves.size() < wolves:
		existing_wolves.append(_random_animal_dict("wolf", false, data))
	
	data.animals = existing_rabbits + existing_wolves

static func _random_animal_dict(type: String, is_water: bool, data: ChunkData) -> Dictionary:
	return {
		"type": type,
		"x": randf_range(1.0, ChunkData.CHUNK_SIZE - 2.0),
		"y": 3.0,  # Will land on terrain via gravity
		"z": randf_range(1.0, ChunkData.CHUNK_SIZE - 2.0),
		"is_water": is_water,
		"hunger": 80.0,
	}
