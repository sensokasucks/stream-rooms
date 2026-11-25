extends Node3D
## Shared weather for rooms built in code (first used by the Log Cabin, rooms/log_cabin/; the
## plan is for the cabin's scene rooms, and maybe the campfire and the Drive-In, to use it too).
## One node does all of it, so a room only has to make it, call setup() once and run() every frame:
##   - rain (thin streaks) or snow (soft flakes) falling round whichever camera is on, kept off
##     the room's indoors by the room's "shelters" (boxes the falling drops vanish in),
##   - water dripping off the eaves while things are wet,
##   - the room's window glass getting wet, running with drops and frosting up
##     (weather_glass.gdshader), and its outdoor surfaces getting wet or snowy (the room's surface
##     shader needs `wet` and `snow` uniforms, see rooms/log_cabin/cabin_surface.gdshader),
##   - the trees' wind (camp_foliage / camp_prop `wind`), and frost on their leaves in the snow,
##   - lightning in a storm (photosensitive-safe: one soft slow glow, capped, scaled by
##     flash_strength), and the room's lamps dipping now and then in a storm (not in safe mode),
##   - the sky, the fog and the daylight for the weather (apply_env, called by the room when it
##     redraws its sky),
##   - a generated soundscape on the Ambience bus: rain on the roof, wind, thunder, and the
##     crackle of the room's fire (no sound files needed).
## The settings are the room's own, named <prefix> + (Room tab):
##   weather     "clear" | "cloudy" | "rain" | "storm" | "snow"
##   fog         "off" | "light" | "heavy"
##   wind        0..2 (0 = still, 1 = a breeze, 2 = a gale; a storm blows at least STORM_WIND)
##   snow        0..1, snow lying on the ground (more builds up while it snows, and melts after)
##   weather_fx  0..1, how many drops and flakes this PC draws (each PC's own)
## The room shares the first four in a co-stream. Wetness, frost and the snow that builds up
## ease in and out over a minute or so on each PC, so they can drift apart a little between PCs.

## The least wind in a storm (the Wind slider can still make it stronger).
const STORM_WIND: float = 1.4
## Lightning in photosensitive-safe mode never gets brighter than this share of a full flash.
const SAFE_FLASH_CAP: float = 0.3
const MIX_RATE: float = 22050.0
const TEX := "res://rooms/weather/textures/"
const GLASS_SHADER := preload("res://rooms/weather/weather_glass.gdshader")
## What each weather does: the least cloud on the sky (camp_sky cloud_amount), how much of the
## sun or moon gets through, how dark the sky turns (exposure), how hard it rains on the glass and
## out of the sky (0..1), whether it snows, and how far you can see through the rain (metres;
## 0 = no rain haze).
const LOOKS: Dictionary = {
	"clear": {"clouds": 0.0, "sun": 1.0, "sky": 1.0, "rain": 0.0, "snow": false, "see": 0.0},
	"cloudy": {"clouds": 1.25, "sun": 0.55, "sky": 0.85, "rain": 0.0, "snow": false, "see": 0.0},
	"rain": {"clouds": 1.7, "sun": 0.32, "sky": 0.7, "rain": 0.6, "snow": false, "see": 260.0},
	"storm": {"clouds": 2.0, "sun": 0.18, "sky": 0.5, "rain": 1.0, "snow": false, "see": 170.0},
	"snow": {"clouds": 1.6, "sun": 0.45, "sky": 0.8, "rain": 0.0, "snow": true, "see": 210.0},
}

## Setting names: prefix + "weather", "fog", "wind", "snow", "weather_fx".
var prefix: String = ""
## How much the room's fire burns (0..2), set by the room every frame: the crackle follows it.
var fire: float = 0.0

var _room: Node3D
var _sky_shader: Shader
var _surface_mats: Array = []     # the room's surface materials (they get wet and snow)
var _glass: ShaderMaterial        # the window glass (weather_glass.gdshader)
var _foliage: Array = []          # tree materials (wind, frost); [material, its own tint]
var _rng := RandomNumberGenerator.new()
var _rain: GPUParticles3D
var _snow: GPUParticles3D
var _drips: Array[CPUParticles3D] = []
var _bolt: DirectionalLight3D     # the lightning flash
var _amb: AudioStreamGeneratorPlayback

# eased state (see the header)
var _wet: float = 0.0
var _rain_now: float = 0.0
var _frost: float = 0.0
## The least snow there always is on the ground, 0..1, whatever the setting says (a snowy scene
## sets it before setup(): Cabin: Frozen North, cabin_north.gd SNOW_FLOOR). 0 = none.
var snow_floor: float = 0.0
## How much of the lying snow heaps up on the detailed trees' boughs (camp_foliage.gdshader
## `snow_load` = snow on the ground times this), 0..1. 0 = none, only the frost tint (set before
## setup(); Cabin: Frozen North sets 0.7).
var tree_snow: float = 0.0
var _built_snow: float = 0.0      # snow that has piled up while it snowed, on top of the setting
var _pushed: Vector4 = Vector4(-1, -1, -1, -1)   # wet, snow, frost, wind last given to the materials
# lightning
var _flash: float = 0.0
var _flash_twice: float = -1.0
var _flash_wait: float = 3.0
var _thunder_in: float = -1.0
var _rumble: float = 0.0
var _sky_flash_drawn: float = 0.0
# a storm's lamp dip: 0..1, eases in and out over a few tenths of a second (never a strobe)
var _dip: float = 0.0
var _dip_target: float = 0.0
var _dip_wait: float = 12.0
# sound
var _lp_rain: float = 0.0
var _lp_roof: float = 0.0
var _lp_wind: float = 0.0
var _lp_wind2: float = 0.0
var _lp_rumble: float = 0.0
var _lp_crackle: float = 0.0
var _pop: float = 0.0
var _drip_click: float = 0.0


## Called once by the room after the set is built.
##   room          the room (sounds and lights go under this node; the camera is its viewport's)
##   setting_prefix  e.g. "cabin_"
##   sky_shader    the room's sky shader (camp_sky.gdshader): the sky is only touched when the
##                 Environment in use has it, never another room's
##   shelters      Array[AABB], world space: the indoors, where rain and snow must not fall
##   eaves         Array of [Vector3, Vector3]: roof edges water drips off
##   surface_mats  the room's surface ShaderMaterials (`wet`, `snow` uniforms)
##   glass         the window glass material, made by glass_material()
##   foliage       the trees' ShaderMaterials (`wind`, and `tint` for frost on the leaves)
func setup(room: Node3D, setting_prefix: String, sky_shader: Shader, shelters: Array, eaves: Array,
		surface_mats: Array, glass: ShaderMaterial, foliage: Array) -> void:
	_room = room
	prefix = setting_prefix
	_sky_shader = sky_shader
	_surface_mats = surface_mats
	_glass = glass
	for m: ShaderMaterial in foliage:
		var tint: Variant = m.get_shader_parameter("tint")
		_foliage.append([m, tint if tint is Color else Color.WHITE])
	_rng.seed = 4242
	_build_rain(shelters)
	_build_snow(shelters)
	for e: Array in eaves:
		_build_drips(e[0], e[1])
	_bolt = DirectionalLight3D.new()
	_bolt.name = "Lightning"
	_bolt.light_color = Color(0.78, 0.84, 1.0)
	_bolt.shadow_enabled = false
	_bolt.visible = false
	add_child(_bolt)
	_amb = (room as Room)._start_generated_ambience(MIX_RATE, 0.25) if room is Room else null
	settle()


## Jumps the slow parts (wet glass, frost, piled-up snow) straight to what the weather says, so a
## room that loads in the rain is already wet. Also used by tests.
func settle() -> void:
	var look := _look()
	_rain_now = float(look["rain"])
	_wet = _rain_now
	_frost = 1.0 if bool(look["snow"]) else (0.45 if snow_cover() > 0.3 else 0.0)
	_pushed = Vector4(-1, -1, -1, -1)


## Sets off a lightning stroke now (in a storm; for tests).
func strike() -> void:
	_flash_wait = 0.0


## A window glass material for the room's panes (weather_glass.gdshader with our drop, runner
## and frost pictures). tint = the dry glass's colour and alpha.
static func glass_material(tint: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = GLASS_SHADER
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("drops", load(TEX + "drops.png"))
	m.set_shader_parameter("runners", load(TEX + "runners.png"))
	m.set_shader_parameter("frost_tex", load(TEX + "frost.png"))
	return m


# ── What the settings say ────────────────────────────────────
func kind() -> String:
	var k := String(AppState.get_setting(prefix + "weather"))
	return k if LOOKS.has(k) else "clear"


func _look() -> Dictionary:
	return LOOKS[kind()]


## The wind now: the slider, at least STORM_WIND in a storm (0..2).
func wind() -> float:
	var w := clampf(float(AppState.get_setting(prefix + "wind")), 0.0, 2.0)
	return maxf(w, STORM_WIND) if kind() == "storm" else w


## The least cloud the sky shows in this weather (the room takes the larger of this and its
## Clouds slider).
func cloud_floor() -> float:
	return float(_look()["clouds"])


## How much of the sun or moon gets through the cloud (multiplies the room's sun / moon lamp).
func sun_share() -> float:
	return float(_look()["sun"])


## The snow shown on the ground and roofs now, 0..1: the room's snow_floor or the setting,
## whichever is more, plus what has piled up while it snowed.
func snow_cover() -> float:
	return clampf(maxf(float(AppState.get_setting(prefix + "snow")), snow_floor) + _built_snow, 0.0, 1.0)


## How wet things are now, 0..1 (for tests).
func wetness() -> float:
	return _wet


## The frost on the glass now, 0..1 (for tests).
func frost() -> float:
	return _frost


## The lightning as shown now, 0..1 (flash_strength and the safe-mode cap applied; for tests).
func flash() -> float:
	var f := _flash * clampf(float(AppState.get_setting("flash_strength")), 0.0, 1.0)
	if bool(AppState.get_setting("photosensitive_safe")):
		f = minf(f, SAFE_FLASH_CAP)
	return f


## The room's lamps multiply their level by this: 1, dipping a little now and then in a storm.
func lamp_factor() -> float:
	return 1.0 - 0.35 * _dip


## The rain and snow particle systems (for tests).
func get_rain() -> GPUParticles3D:
	return _rain


func get_snow() -> GPUParticles3D:
	return _snow


# ── Every frame ──────────────────────────────────────────────
## Called by the room every frame: eases the wetness, frost and snow, keeps the rain and snow
## round the camera, runs the lightning and the lamp dips, feeds the materials and the sound.
func run(delta: float) -> void:
	var look := _look()
	var snowing := bool(look["snow"])
	var rain_target := float(look["rain"])
	var fx := clampf(float(AppState.get_setting(prefix + "weather_fx")), 0.0, 1.0)
	# rain on the glass comes on over a few seconds; the glass dries over a minute and a half
	_rain_now = move_toward(_rain_now, rain_target, delta / 4.0)
	_wet = move_toward(_wet, rain_target, delta / (20.0 if rain_target > _wet else 90.0))
	_frost = move_toward(_frost, 1.0 if snowing else (0.45 if snow_cover() > 0.3 else 0.0), delta / 60.0)
	_built_snow = move_toward(_built_snow, 0.6 if snowing else 0.0, delta / (300.0 if snowing else 600.0))
	# the falling rain and snow
	if _rain:
		_rain.emitting = rain_target > 0.0 and fx > 0.01
		_rain.amount_ratio = clampf(rain_target * fx, 0.0, 1.0)
		_rain.visible = _rain.emitting or _rain_now > 0.05
	if _snow:
		_snow.emitting = snowing and fx > 0.01
		_snow.amount_ratio = fx
		_snow.visible = _snow.emitting
	var w := wind()
	_aim_particles(w)
	for d in _drips:
		d.emitting = _wet > 0.3 and snow_cover() < 0.5 and fx > 0.01
	_run_lightning(delta)
	_run_dips(delta)
	_push_materials(w)
	_fill_sound(w, snowing)


## Moves the rain and snow boxes above and a little ahead of the camera, and leans them with the
## wind.
func _aim_particles(w: float) -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return
	var fwd := -cam.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	if _rain and _rain.visible:
		_rain.global_position = cam.global_position + fwd * 10.0 + Vector3(0.0, 16.0, 0.0)
		var pm := _rain.process_material as ParticleProcessMaterial
		pm.direction = Vector3(0.12 + 0.3 * w, -1.0, 0.05 + 0.1 * w).normalized()
	if _snow and _snow.visible:
		_snow.global_position = cam.global_position + fwd * 8.0 + Vector3(0.0, 11.0, 0.0)
		var sm := _snow.process_material as ParticleProcessMaterial
		sm.gravity = Vector3(0.5 + 1.6 * w, -0.9, 0.2 + 0.5 * w)


## Gives the materials the weather when it has changed enough to show.
func _push_materials(w: float) -> void:
	var now := Vector4(_wet, snow_cover(), _frost, w)
	if now.distance_to(_pushed) < 0.004:
		return
	_pushed = now
	for m: ShaderMaterial in _surface_mats:
		m.set_shader_parameter("wet", _wet)
		m.set_shader_parameter("snow", now.y)
	if _glass:
		_glass.set_shader_parameter("rain", _rain_now)
		_glass.set_shader_parameter("wet", maxf(_wet, _rain_now * 0.8))
		_glass.set_shader_parameter("frost", _frost)
		_glass.set_shader_parameter("wind", w)
		_glass.set_shader_parameter("refract", 0.0 if String(AppState.get_setting("graphics_quality")) == "low" else 1.0)
	for f: Array in _foliage:
		var m := f[0] as ShaderMaterial
		m.set_shader_parameter("wind", 0.4 + w)
		# frost on the leaves and needles: paler, a little blue, as the snow lies
		m.set_shader_parameter("tint", (f[1] as Color).lerp(Color(1.25, 1.3, 1.4), now.y * 0.55))
		if tree_snow > 0.0:
			m.set_shader_parameter("snow_load", now.y * tree_snow)


## The sky, fog and light for the weather. Called by the room each time it redraws its sky
## (after setting its own values, which this adjusts). env / sky may be null (another room's).
## haze = the colour the room gave its fog.
func apply_env(env: Environment, sky: ShaderMaterial, haze: Color) -> void:
	var look := _look()
	if sky:
		sky.set_shader_parameter("cloud_amount", maxf(float(sky.get_shader_parameter("cloud_amount")), float(look["clouds"])))
		sky.set_shader_parameter("exposure", float(look["sky"]))
		_sky_flash_drawn = 0.0
	if env == null:
		return
	var fog := String(AppState.get_setting(prefix + "fog"))
	var see := float(look["see"])
	var grey := haze.lerp(Color(0.55, 0.58, 0.62) * maxf(haze.v, 0.08) * 1.6, 0.5)
	if fog == "heavy":
		_depth_fog(env, 5.0, 34.0, 1.0, 1.0, grey)
	elif fog == "light":
		_depth_fog(env, 10.0, minf(see, 110.0) if see > 0.0 else 110.0, 0.85, 0.6, grey)
	elif see > 0.0:
		_depth_fog(env, 14.0, see, 0.6, 0.35, grey)
	else:
		# the room's own thin haze (it set fog_density just before this call). Setting fog_mode
		# puts fog_density back to 1.0 in this engine, so the density is set again after it,
		# or the whole view drowns in fog.
		var density := env.fog_density
		env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
		env.fog_density = density
		env.fog_sky_affect = 0.0
	# a dull day: the ambient light greys over
	var dull := 1.0 - float(look["sun"])
	env.ambient_light_color = env.ambient_light_color.lerp(Color(0.5, 0.53, 0.58) * env.ambient_light_color.v * 1.2, dull * 0.6)


## Fog by distance from the camera: none nearer than `begin` metres, so the inside of the room
## stays clear while the view outside fades out by `end`.
func _depth_fog(env: Environment, begin: float, end: float, density: float, sky_affect: float, col: Color) -> void:
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_depth_begin = begin
	env.fog_depth_end = end
	env.fog_depth_curve = 1.6
	env.fog_density = density
	env.fog_sky_affect = sky_affect
	env.fog_light_color = col


# ── Lightning and lamp dips ──────────────────────────────────
## A stroke every 6 to 18 seconds in a storm: a flash that dies in a quarter second with a second
## flicker, and its thunder a moment later. Safe mode: one soft slow glow, capped, no flicker.
func _run_lightning(delta: float) -> void:
	var safe := bool(AppState.get_setting("photosensitive_safe"))
	_flash = move_toward(_flash, 0.0, delta * (0.8 if safe else 4.0))
	if _flash_twice > 0.0:
		_flash_twice -= delta
		if _flash_twice <= 0.0 and not safe:
			_flash = maxf(_flash, 0.75)
	if _thunder_in > 0.0:
		_thunder_in -= delta
		if _thunder_in <= 0.0:
			_rumble = 1.0
	if kind() == "storm":
		_flash_wait -= delta
		if _flash_wait <= 0.0:
			_flash_wait = _rng.randf_range(6.0, 18.0)
			var az := _rng.randf_range(-PI, PI)
			_bolt.global_basis = Basis.looking_at(-Vector3(cos(az) * 0.7, 0.7, sin(az) * 0.7 - 0.3).normalized(), Vector3.UP)
			_flash = SAFE_FLASH_CAP if safe else 1.0
			_flash_twice = -1.0 if safe else _rng.randf_range(0.12, 0.3)
			_thunder_in = _rng.randf_range(0.8, 3.5)
	var f := flash()
	_bolt.visible = f > 0.005
	_bolt.light_energy = f * 3.5
	# the sky lights up with the flash (only this room's sky)
	if absf(f - _sky_flash_drawn) > 0.01:
		var sky := _own_sky()
		if sky:
			sky.set_shader_parameter("exposure", float(_look()["sky"]) + f * 1.6)
			_sky_flash_drawn = f


## In a storm the lamps dip a little every 15 to 40 seconds, easing down and back up over about
## half a second (never in photosensitive-safe mode).
func _run_dips(delta: float) -> void:
	if kind() == "storm" and not bool(AppState.get_setting("photosensitive_safe")):
		_dip_wait -= delta
		if _dip_wait <= 0.0:
			_dip_wait = _rng.randf_range(15.0, 40.0)
			_dip_target = 1.0
	if _dip >= 0.99:
		_dip_target = 0.0
	_dip = move_toward(_dip, _dip_target, delta * 4.0)


func _own_sky() -> ShaderMaterial:
	var env := get_world_3d().environment if is_inside_tree() else null
	if env and env.sky and env.sky.sky_material is ShaderMaterial and (env.sky.sky_material as ShaderMaterial).shader == _sky_shader:
		return env.sky.sky_material as ShaderMaterial
	return null


# ── Building the rain, snow and drips ───────────────────────
## Rain: thin streaks falling from a box above the camera (_aim_particles moves it). Built for
## the heaviest rain; amount_ratio sets how many fall. They vanish inside the shelters.
func _build_rain(shelters: Array) -> void:
	_rain = GPUParticles3D.new()
	_rain.name = "Rain"
	_rain.amount = 9000
	_rain.lifetime = 1.5
	_rain.preprocess = 1.5
	_rain.local_coords = false
	_rain.emitting = false
	_rain.visible = false
	_rain.visibility_aabb = AABB(Vector3(-35, -40, -35), Vector3(70, 60, 70))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(22.0, 1.0, 22.0)
	pm.direction = Vector3(0.12, -1.0, 0.05)
	pm.spread = 2.0
	pm.initial_velocity_min = 13.0
	pm.initial_velocity_max = 16.0
	pm.gravity = Vector3(0.0, -9.8, 0.0)
	pm.particle_flag_align_y = true
	pm.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	_rain.process_material = pm
	_rain.collision_base_size = 0.02
	var drop := BoxMesh.new()
	drop.size = Vector3(0.008, 0.45, 0.008)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.72, 0.78, 0.88, 0.26)
	drop.material = m
	_rain.draw_pass_1 = drop
	_rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_rain)
	_add_shelters(shelters)


## Snow: soft flakes drifting down slowly and sideways with the wind.
func _build_snow(_shelters: Array) -> void:
	_snow = GPUParticles3D.new()
	_snow.name = "Snow"
	_snow.amount = 5000
	_snow.lifetime = 11.0
	_snow.preprocess = 11.0
	_snow.local_coords = false
	_snow.emitting = false
	_snow.visible = false
	_snow.visibility_aabb = AABB(Vector3(-35, -30, -35), Vector3(70, 50, 70))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(22.0, 1.0, 22.0)
	pm.direction = Vector3(0.0, -1.0, 0.0)
	pm.spread = 25.0
	pm.initial_velocity_min = 0.3
	pm.initial_velocity_max = 0.8
	pm.gravity = Vector3(0.6, -0.9, 0.2)
	pm.damping_min = 0.6
	pm.damping_max = 1.0
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.turbulence_noise_scale = 4.0
	pm.turbulence_noise_speed_random = 0.3
	pm.scale_min = 0.6
	pm.scale_max = 1.3
	pm.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	_snow.process_material = pm
	_snow.collision_base_size = 0.03
	var flake := QuadMesh.new()
	flake.size = Vector2(0.06, 0.06)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.95, 0.97, 1.0, 0.9)
	m.albedo_texture = _soft_dot()
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	flake.material = m
	_snow.draw_pass_1 = flake
	_snow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_snow)


## The indoors: falling rain and snow vanish when they touch these boxes.
func _add_shelters(shelters: Array) -> void:
	for box: AABB in shelters:
		var c := GPUParticlesCollisionBox3D.new()
		c.name = "Shelter"
		c.size = box.size
		add_child(c)
		c.global_position = box.get_center()


## Water dripping off one roof edge (from a to b) while things are wet: a few slow drops.
func _build_drips(a: Vector3, b: Vector3) -> void:
	var d := CPUParticles3D.new()
	d.name = "EaveDrips"
	d.amount = int(clampf(a.distance_to(b) * 3.0, 6.0, 60.0))
	d.lifetime = 0.9
	d.emitting = false
	d.local_coords = false
	d.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	var half := (b - a) * 0.5
	d.emission_box_extents = Vector3(absf(half.x), 0.01, absf(half.z))
	d.direction = Vector3.DOWN
	d.spread = 0.0
	d.initial_velocity_min = 0.0
	d.initial_velocity_max = 0.3
	d.gravity = Vector3(0.0, -9.8, 0.0)
	d.particle_flag_align_y = true
	var drop := BoxMesh.new()
	drop.size = Vector3(0.012, 0.09, 0.012)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.75, 0.82, 0.9, 0.45)
	drop.material = m
	d.mesh = drop
	d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(d)
	d.global_position = (a + b) * 0.5
	_drips.append(d)


static func _soft_dot() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	g.add_point(0.5, Color(1.0, 1.0, 1.0, 0.7))
	g.set_color(g.get_point_count() - 1, Color(1.0, 1.0, 1.0, 0.0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 32
	t.height = 32
	return t


# ── Sound ────────────────────────────────────────────────────
## Called every frame: tops the generator up. Rain drumming on the roof (muffled noise, louder in
## a storm, with drips ticking off the eaves while wet), the wind (two bands of filtered noise,
## swelling slowly), thunder after each stroke, a hush for falling snow, and the fire's crackle
## (soft hiss plus little pops, from `fire`).
func _fill_sound(w: float, snowing: bool) -> void:
	if _amb == null:
		return
	var n := _amb.get_frames_available()
	if n <= 0:
		return
	var ms := float(Time.get_ticks_msec())
	var gust := 0.75 + 0.17 * sin(ms * 0.00025) + 0.08 * sin(ms * 0.000105 + 1.0)
	var wind_lv := (0.004 + 0.022 * w * w * 0.6 + 0.012 * w) * gust
	var rain_lv := 0.05 * _rain_now
	var drip_rate := 4.0 * _wet if snow_cover() < 0.5 else 0.0
	var snow_lv := 0.006 if snowing else 0.0
	var fire_lv := clampf(fire, 0.0, 2.0)
	var buf := PackedVector2Array()
	buf.resize(n)
	for i in n:
		var r := _rng.randf() * 2.0 - 1.0
		_lp_rain += (r - _lp_rain) * 0.25
		_lp_roof += (r - _lp_roof) * 0.05
		_lp_wind += (r - _lp_wind) * 0.02
		_lp_wind2 += (r - _lp_wind2) * 0.1
		_lp_rumble += (r - _lp_rumble) * 0.006
		_lp_crackle += (r - _lp_crackle) * 0.4
		_rumble *= 0.99996
		_pop *= 0.996
		_drip_click *= 0.98
		var s := _lp_roof * rain_lv * 1.6 + _lp_rain * rain_lv * 0.35
		s += _lp_wind * wind_lv * 1.6 + _lp_wind2 * wind_lv * 0.9
		s += _lp_wind2 * snow_lv
		s += _lp_rumble * _rumble * 1.6
		if drip_rate > 0.0 and _rng.randf() < drip_rate / MIX_RATE:
			_drip_click = 0.05
		s += _lp_crackle * _drip_click
		if fire_lv > 0.01:
			# crackle: a few pops a second, more for a bigger fire, over a quiet hiss
			if _rng.randf() < fire_lv * 5.0 / MIX_RATE:
				_pop = _rng.randf_range(0.03, 0.09) * minf(fire_lv, 1.3)
			s += _lp_crackle * _pop + _lp_rain * 0.004 * fire_lv
		buf[i] = Vector2(s, s * 0.95)
	_amb.push_buffer(buf)
