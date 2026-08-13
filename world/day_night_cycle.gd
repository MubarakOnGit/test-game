class_name DayNightCycle
extends Node

# ─── Time ─────────────────────────────────────────────────────────────────────
## Current time: 0.0–24.0 hours. 6.0 = sunrise, 12.0 = noon, 18.0 = sunset.
var time_of_day: float = 10.0
## Multiplier: 1.0 = real-time, 10.0 = 10× faster, 0.0 = paused.
var time_speed: float = 1.0

# ─── References (assigned by WorldManager) ────────────────────────────────────
var sun:     DirectionalLight3D
var moon:    DirectionalLight3D
var sky_mat: ProceduralSkyMaterial
var env:     Environment

# ─── Sky colour keyframes (hour → colors) ─────────────────────────────────────
# [hour, sky_top, sky_horizon, ground_bottom, sun_light_color]
const SKY_KEYS := [
	[0.0,  "#07101f", "#0d1b2a", "#050910", "#8bb6f2"],  # Midnight – deep navy
	[5.5,  "#0f1a30", "#5a2a10", "#090810", "#ff7030"],  # Pre-dawn orange glow
	[6.0,  "#1a4080", "#ff9050", "#1a2a40", "#ffb060"],  # Sunrise
	[8.0,  "#2e6db5", "#87ceeb", "#2a3a50", "#fff0d0"],  # Morning
	[12.0, "#1a5dab", "#7ab8e0", "#1e2c3a", "#fff8f0"],  # Noon – bright white
	[16.0, "#2e6db5", "#87ceeb", "#2a3a50", "#fff0d0"],  # Afternoon
	[18.0, "#1a1030", "#ff5520", "#1a0808", "#ff6020"],  # Sunset
	[19.0, "#080f1a", "#201020", "#040810", "#8bb6f2"],  # Dusk
	[24.0, "#07101f", "#0d1b2a", "#050910", "#8bb6f2"],  # Midnight (wrap)
]

# ─── Process ───────────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	# Advance time: time_speed=1 → 0.1 real seconds per in-game second
	time_of_day += time_speed * delta * 0.1
	if time_of_day >= 24.0:
		time_of_day -= 24.0
	_apply()

# ─── Core update ──────────────────────────────────────────────────────────────
func _apply() -> void:
	var t := time_of_day

	# ── 1. Sun & Moon angle ────────────────────────────────────────────────────
	# Map t to radians: 6h = horizon (0), 12h = zenith (PI/2), 18h = horizon again
	var sun_angle := ((t - 6.0) / 24.0) * TAU
	if sun:
		# Y-axis -45° matches original — casts diagonal shadows across the screen
		sun.rotation = Vector3(-sun_angle, deg_to_rad(-45.0), 0.0)
	if moon:
		moon.rotation = Vector3(-sun_angle + PI, deg_to_rad(-45.0), 0.0)

	# ── 2. Light energy via sin (smooth bell curve) ────────────────────────────
	var sun_height  := sin(sun_angle)
	var moon_height := sin(sun_angle + PI)

	if sun:
		sun.light_energy  = clampf(sun_height  * 2.0, 0.0, 1.5)
		sun.shadow_enabled = sun.light_energy > 0.05
	if moon:
		moon.light_energy  = clampf(moon_height * 2.0, 0.0, 0.4)
		moon.shadow_enabled = moon.light_energy > 0.02

	# ── 3. Sky colour interpolation ────────────────────────────────────────────
	if sky_mat:
		var prev_k : Array = SKY_KEYS[0]
		var next_k : Array = SKY_KEYS[SKY_KEYS.size() - 1]
		for i in range(SKY_KEYS.size() - 1):
			if t >= float(SKY_KEYS[i][0]) and t < float(SKY_KEYS[i + 1][0]):
				prev_k = SKY_KEYS[i]
				next_k = SKY_KEYS[i + 1]
				break

		var span    : float = float(next_k[0]) - float(prev_k[0])
		var local_t : float = smoothstep(0.0, 1.0, (t - float(prev_k[0])) / max(span, 0.001))

		sky_mat.sky_top_color        = Color(prev_k[1]).lerp(Color(next_k[1]), local_t)
		sky_mat.sky_horizon_color    = Color(prev_k[2]).lerp(Color(next_k[2]), local_t)
		sky_mat.ground_bottom_color  = Color(prev_k[3]).lerp(Color(next_k[3]), local_t)
		sky_mat.ground_horizon_color = sky_mat.sky_horizon_color.darkened(0.35)

	# ── 4. Ambient energy ──────────────────────────────────────────────────────
	if env:
		var day_factor := clampf(sun_height, 0.0, 1.0)
		env.ambient_light_energy = lerp(0.06, 0.65, day_factor)
