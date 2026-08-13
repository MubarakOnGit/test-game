class_name SlopeGenerator

## Fills data.slopes[] — max height delta to any cardinal neighbor.
## Requires data.heights[] to be populated first.
## Can run in parallel with ClimateGenerator (no shared dependency).
static func generate(data: ChunkData) -> void:
	var cs := ChunkData.CHUNK_SIZE

	for lz in range(cs):
		for lx in range(cs):
			var h   := data.heights[ChunkData.hi(lx,     lz    )]
			var h_n := data.heights[ChunkData.hi(lx,     lz - 1)]
			var h_s := data.heights[ChunkData.hi(lx,     lz + 1)]
			var h_e := data.heights[ChunkData.hi(lx + 1, lz    )]
			var h_w := data.heights[ChunkData.hi(lx - 1, lz    )]

			var slope := maxf(
				maxf(abs(h - h_n), abs(h - h_s)),
				maxf(abs(h - h_e), abs(h - h_w))
			)
			# Write into the bordered array at the core tile position
			data.slopes[ChunkData.hi(lx, lz)] = slope
