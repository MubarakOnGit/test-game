class_name ChunkMetadata

# ─── Chunk State Machine ───────────────────────────────────────────────────────
# UNLOADED → QUEUED → GENERATING → UPLOADING → VISIBLE → SLEEPING → UNLOADING
enum State {
	UNLOADED,
	QUEUED,
	GENERATING,
	MESHING,
	UPLOADING,
	VISIBLE,
	SLEEPING,
	UNLOADING,
}

var state: State = State.UNLOADED

# ─── Per-System Version Numbers ───────────────────────────────────────────────
# Only the affected system increments its version — no unnecessary rebuilds.
var terrain_version:    int = 0
var vegetation_version: int = 0
var objects_version:    int = 0
var nav_version:        int = 0
var water_version:      int = 0

# ─── Dirty Flags ──────────────────────────────────────────────────────────────
var dirty_terrain:    bool = false
var dirty_vegetation: bool = false
var dirty_nav:        bool = false
var dirty_water:      bool = false

# ─── Observability ────────────────────────────────────────────────────────────
var is_generated:         bool = false
var is_modified:          bool = false  # player changed something
var last_access_usec:     int  = 0
var last_simulation_tick: int  = 0
var lod_level:            int  = 0
var streaming_priority:   int  = 0     # lower = higher priority

# ─── Mutation Helpers ─────────────────────────────────────────────────────────

func mark_terrain_dirty() -> void:
	dirty_terrain = true
	terrain_version += 1
	is_modified = true
	_touch()

func mark_vegetation_dirty() -> void:
	dirty_vegetation = true
	vegetation_version += 1
	_touch()

func mark_water_dirty() -> void:
	dirty_water = true
	water_version += 1
	_touch()

func mark_nav_dirty() -> void:
	dirty_nav = true
	nav_version += 1
	_touch()

func _touch() -> void:
	last_access_usec = Time.get_ticks_usec()
