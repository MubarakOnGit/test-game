class_name RegionManager
extends Node

const SAVES_DIR := "user://saves/"

var database: WorldDatabase
var _regions: Dictionary = {} # Vector2i -> Region

func _init(db: WorldDatabase) -> void:
	name = "RegionManager"
	database = db
	
	var dir = DirAccess.open("user://")
	if not dir.dir_exists(SAVES_DIR):
		dir.make_dir_recursive(SAVES_DIR)
		
	# Listen to chunk modifications to mark regions dirty
	WorldEventBus.chunk_modified.connect(_on_chunk_modified)

func get_region(rx: int, rz: int) -> Region:
	var key := Vector2i(rx, rz)
	if _regions.has(key):
		return _regions[key]
	var r = Region.new(rx, rz)
	_regions[key] = r
	return r

func _on_chunk_modified(chunk_key: Vector2i) -> void:
	var rkey = Region.chunk_to_region(chunk_key)
	var r = get_region(rkey.x, rkey.y)
	r.dirty = true
	r.chunks[chunk_key] = database.get_chunk(chunk_key)

func save_all_dirty_regions() -> void:
	for rkey in _regions:
		var r: Region = _regions[rkey]
		if r.dirty:
			_save_region(r)
			r.dirty = false

func _save_region(r: Region) -> void:
	var path := SAVES_DIR + "region_%d_%d.bin" % [r.rx, r.rz]
	var file = FileAccess.open_compressed(path, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if file:
		# Build a dictionary of serialized chunks
		var serialized_chunks := {}
		for ckey in r.chunks:
			var bytes = serialize_chunk(r.chunks[ckey])
			serialized_chunks[ckey] = bytes
			
		file.store_var(serialized_chunks)
		file.close()

func load_region(rx: int, rz: int) -> void:
	var path := SAVES_DIR + "region_%d_%d.bin" % [rx, rz]
	if not FileAccess.file_exists(path):
		return
		
	var file = FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if file:
		var serialized_chunks = file.get_var()
		file.close()
		
		if serialized_chunks is Dictionary:
			var r = get_region(rx, rz)
			for ckey in serialized_chunks:
				var bytes: PackedByteArray = serialized_chunks[ckey]
				var data = deserialize_chunk(bytes)
				if data:
					r.chunks[ckey] = data
					database.store_chunk(data)

# ─── Serialization ──────────────────────────────────────────────────────────────

func serialize_chunk(data: ChunkData) -> PackedByteArray:
	if data == null:
		return PackedByteArray()
	
	# Only save what can't be deterministically regenerated or is modified
	var dict := {
		"cx": data.cx,
		"cz": data.cz,
		"seed": data.world_seed,
		"terrain_version": data.metadata.terrain_version,
		"vegetation_version": data.metadata.vegetation_version,
		"is_modified": data.metadata.is_modified,
	}
	
	if data.metadata.is_modified:
		dict["heights"] = data.heights
		# Optionally save other modified arrays if gameplay allows modifying them (like biomes, etc.)
		
	return var_to_bytes(dict)

func deserialize_chunk(bytes: PackedByteArray) -> ChunkData:
	if bytes.size() == 0:
		return null
		
	var dict = bytes_to_var(bytes)
	if dict == null:
		return null
		
	var data := ChunkData.create(dict["cx"], dict["cz"], dict["seed"])
	data.metadata.terrain_version = dict.get("terrain_version", 0)
	data.metadata.vegetation_version = dict.get("vegetation_version", 0)
	data.metadata.is_modified = dict.get("is_modified", false)
	
	if data.metadata.is_modified and dict.has("heights"):
		data.heights = dict["heights"]
	
	return data
