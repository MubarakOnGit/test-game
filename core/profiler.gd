class_name Profiler

# ─── In-Game Millisecond Profiler ─────────────────────────────────────────────
# Rolling-average timers for every named system.
# Visible in ProfilerHUD. Independent of Godot's built-in profiler.

const SMOOTH := 0.08   # lerp factor — lower = smoother, higher = more reactive

var _starts: Dictionary = {}   # name:String → start_usec:int
var samples: Dictionary = {}   # name:String → smoothed ms:float

# ─── API ──────────────────────────────────────────────────────────────────────

func begin(name: String) -> void:
	_starts[name] = Time.get_ticks_usec()

func end(name: String) -> void:
	var start: int = _starts.get(name, 0)
	if start == 0:
		return
	var elapsed_ms := float(Time.get_ticks_usec() - start) / 1000.0
	if samples.has(name):
		samples[name] = lerpf(samples[name], elapsed_ms, SMOOTH)
	else:
		samples[name] = elapsed_ms

func get_ms(name: String) -> float:
	return samples.get(name, 0.0)

func format_all() -> String:
	var lines := PackedStringArray()
	for k: String in samples.keys():
		lines.append("%s: %.2fms" % [k, samples[k]])
	return "\n".join(lines)
