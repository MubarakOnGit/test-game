extends Node

# ─── Chunk Lifecycle (cross-system notifications) ─────────────────────────────
signal chunk_loaded(key: Vector2i)
signal chunk_unloaded(key: Vector2i)
signal chunk_modified(key: Vector2i)   # triggers mesh + nav rebuild

# ─── Gameplay Events ──────────────────────────────────────────────────────────
# These are the ONLY events here — rendering talks directly to ChunkRenderer,
# not through the bus. Events are for independent multi-subscriber situations.
signal tree_burned(world_x: int, world_z: int)
signal terrain_modified(world_x: int, world_z: int, new_height: float)
signal rain_started(region_x: int, region_z: int)
signal rain_stopped(region_x: int, region_z: int)
signal animal_spawned(species_id: int, world_pos: Vector3)
signal villager_died(villager_id: int)
signal water_ripple_spawned(pos: Vector3, max_age: float, normal_strength: float, foam_strength: float, speed: float)
