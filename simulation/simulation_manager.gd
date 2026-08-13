class_name SimulationManager
extends Node

var database: WorldDatabase
var chunk_manager: ChunkManager
var _sim_index: int = 0
const SIM_DISTANCE = 2 # Process chunks within this radius

func setup(db: WorldDatabase, cm: ChunkManager) -> void:
	database = db
	chunk_manager = cm

func tick(center_chunk: Vector2i) -> void:
	if chunk_manager == null or database == null:
		return
		
	# Find all active chunks within SIM_DISTANCE
	var active_keys = []
	for key in chunk_manager._active_nodes.keys():
		var dist_x = absi(key.x - center_chunk.x)
		var dist_z = absi(key.y - center_chunk.y)
		if dist_x <= SIM_DISTANCE and dist_z <= SIM_DISTANCE:
			active_keys.append(key)
			
	if active_keys.size() == 0:
		return
		
	# Process a few chunks per frame to avoid lag spikes
	var chunks_per_frame = 4
	for i in range(chunks_per_frame):
		_sim_index = (_sim_index + 1) % active_keys.size()
		var key = active_keys[_sim_index]
		var data = database.get_chunk(key)
		if data != null:
			WaterSimulation.step(data, database)
