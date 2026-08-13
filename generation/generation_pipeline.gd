class_name GenerationPipeline

## Master orchestrator for generating chunk data.
## Runs on a background thread.
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

	# 5. Pipeline Stage 4: Water Seeding
	# Fill water_levels for every tile at or below sea level BEFORE vegetation
	# runs. This ensures VegetationGenerator can check water_levels > 0 and
	# never place trees on tiles the water plane will visually cover.
	_seed_water(data)

	# 6. Pipeline Stage 5: Vegetation (Requires biomes, heights, water_levels)
	VegetationGenerator.generate(data, world_seed)

	# 7. Pipeline Stage 6: Animals
	AnimalGenerator.generate(data, world_seed)

	# Note: ChunkData is now populated. We mark it as generated.
	data.metadata.is_generated = true
	data.metadata.mark_terrain_dirty()
	data.metadata.mark_vegetation_dirty()
	data.metadata.mark_water_dirty()

	return data

## Seeds initial water into every tile that sits at or below the water plane.
## The water plane renders at SEA_LEVEL + 0.45, so any terrain height <= 0
## will be visually submerged. We add enough water to bring the surface up
## to sea level so WaterSimulation can take over from there.
static func _seed_water(data: ChunkData) -> void:
	var bw := ChunkData.BSIZE
	for bz in range(bw):
		for bx in range(bw):
			var idx := bz * bw + bx
			var h := data.heights[idx]
			if h <= ChunkData.SEA_LEVEL:
				# Fill water up to sea level so the tile is visually correct
				# and VegetationGenerator's water_levels check works at gen time.
				data.water_levels[idx] = ChunkData.SEA_LEVEL - h + 0.5
