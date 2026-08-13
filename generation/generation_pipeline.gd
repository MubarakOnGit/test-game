class_name GenerationPipeline

## Master orchestrator for generating chunk data.
## Runs on a background thread (Milestone 4).
## Only receives seed and chunk coordinates, returns a fully populated ChunkData.

static func generate(cx: int, cz: int, world_seed: int) -> ChunkData:
	# 1. Instantiate the empty data container
	var data := ChunkData.create(cx, cz, world_seed)

	# 2. Pipeline Stage 1: Heights (Noise -> Heights)
	HeightGenerator.generate(data, world_seed)

	# 3. Pipeline Stage 2: Climate & Slopes (Parallelizable)
	# These only depend on heights.
	ClimateGenerator.generate(data, world_seed)
	SlopeGenerator.generate(data)
	
	# 4. Pipeline Stage 3: Biomes (Requires heights, climate, slopes)
	BiomeGenerator.generate(data)
	
	# 5. Pipeline Stage 4: Vegetation (Requires biomes, heights)
	VegetationGenerator.generate(data, world_seed)
	
	# Note: ChunkData is now populated. We mark it as generated.
	data.metadata.is_generated = true
	data.metadata.mark_terrain_dirty()
	data.metadata.mark_vegetation_dirty()
	data.metadata.mark_water_dirty()
	
	return data
