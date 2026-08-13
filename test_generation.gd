extends SceneTree

func _init():
	var db = WorldDatabase.new()
	# generate some chunks
	var chunks = []
	for cx in range(-2, 3):
		for cz in range(-2, 3):
			var data = GenerationPipeline.generate(cx, cz, 12345)
			chunks.append(data)
	
	print("Checking chunks for trees in water...")
	var errors = 0
	for data in chunks:
		var veg = data.vegetation
		for i in range(veg.count()):
			var lx = veg.local_xs[i]
			var lz = veg.local_zs[i]
			var hidx = ChunkData.hi(int(lx), int(lz))
			var h = data.heights[hidx]
			var w = data.water_levels[hidx]
			var biome = data.biomes[ChunkData.bi(int(lx), int(lz))]
			if h <= ChunkData.SEA_LEVEL or w > 0 or biome != BiomeGenerator.GRASS:
				print("ERROR: Tree at chunk ", data.cx, ",", data.cz, " local ", lx, ",", lz, " has h=", h, " water=", w, " biome=", biome)
				errors += 1
	print("Done. Errors: ", errors)
	quit()
