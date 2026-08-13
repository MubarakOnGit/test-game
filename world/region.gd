class_name Region

const REGION_SIZE := 16   # 16×16 chunks per region

var rx: int
var rz: int
var chunks: Dictionary   # Vector2i → ChunkData
var dirty: bool = false

func _init(x: int, z: int) -> void:
	rx = x
	rz = z
	chunks = {}

static func chunk_to_region(key: Vector2i) -> Vector2i:
	return Vector2i(floori(float(key.x) / REGION_SIZE),
					floori(float(key.y) / REGION_SIZE))
