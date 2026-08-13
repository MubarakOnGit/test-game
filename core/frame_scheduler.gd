class_name FrameScheduler
extends Node

var profiler: Profiler
var chunk_manager: ChunkManager
var simulation_manager: SimulationManager
var world_manager: WorldManager

const BUDGETS_MS := {
	"streaming":   0.5,
	"upload":      1.5,
	"simulation":  1.5,
	"cleanup":     0.3,
}

func setup(p: Profiler, cm: ChunkManager, sm: SimulationManager, wm: WorldManager) -> void:
	profiler = p
	chunk_manager = cm
	simulation_manager = sm
	world_manager = wm

func _process(delta: float) -> void:
	if not world_manager or not chunk_manager or not simulation_manager: return
	
	var center_chunk = world_manager._get_camera_chunk()

	profiler.begin("Streaming")
	chunk_manager.tick(center_chunk)
	profiler.end("Streaming")

	profiler.begin("Upload")
	chunk_manager.tick_uploads()
	profiler.end("Upload")

	profiler.begin("Simulation")
	simulation_manager.tick(center_chunk)
	profiler.end("Simulation")

	profiler.begin("Cleanup")
	chunk_manager.tick_cleanup(center_chunk)
	profiler.end("Cleanup")
