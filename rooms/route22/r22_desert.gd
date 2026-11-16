extends Node3D
## Route 22's desert: the hour, the sky, the weather and the sound, shared by both Route 22 rooms
## (route22_room.gd = the Drive-In, route22_cruise_room.gd = the Cruise). The room makes one of
## these, calls setup() once and tick() every frame.
##
## Settings it follows (all "r22_", the Room tab's Time of day / Weather / Sky sections; shared in
## a co-stream with the host's "room" group, see NetSession.SHARED_BASE):
##   r22_time, r22_day_minutes   the hour (6 sunrise, 18 sunset) and a running clock
##   r22_weather   "clear" | "clouddeck" (the reference photo's orange ceiling) | "dust" (dust
##                 storm) | "storm" (thunderstorm: rain, lightning) | "afterrain" (wet road,
##                 puddles, a rainbow)
##   r22_clouds, r22_stars   how much cloud and how bright the stars
##   r22_heat      heat shimmer and the road mirage on hot afternoons
##   r22_wind      how hard the wind blows (brush sway, blowing sand, cloud shadows, the sound)
##   r22_detail    each PC's own Set detail (photo grain, volumetric haze, the car's reflections)
## plus photosensitive_safe and flash_strength (the lightning).
##
## What it drives:
##   - the sky (r22_sky.gdshader uniforms), the sun / moon lamp, a lightning lamp, the ambient
##     light, the fog (and the volumetric fog's density on Detailed: dust storm haze, sunbeams),
##   - the shared uniforms of every Route 22 material (kit["mats"], r22_common.gdshaderinc):
##     travel, bend, hill, wet, cloud shadows, detail; and the night glow of lights and neon,
##   - rain and blowing sand round `centre`, and heat-shimmer sheets the room asks for,
##   - a generated soundscape: wind, rain, thunder, crickets at night, and the road (tyres and
##     engine, from road_noise; passing traffic, from whoosh()).
## Weather changes ease over a few seconds; the road dries slowly after rain.

const Geo := preload("res://rooms/route22/r22_geo.gd")
const SKY_SHADER := preload("res://rooms/route22/r22_sky.gdshader")
const HEAT_SHADER := preload("res://rooms/route22/r22_heat.gdshader")
const MIX_RATE: float = 22050.0
## Travel (metres) is handed to the shaders wrapped at this, so float precision never runs out;
## every texture that scrolls with it must repeat evenly into it (see r22_common.gdshaderinc).
const TRAVEL_WRAP: float = 2048.0
## In photosensitive-safe mode light never jumps by more than this share of full brightness.
const SAFE_FLASH_CAP: float = 0.3

## Each weather's targets: cloud cover (times the Clouds slider), how stormy (dark cloud, rain,
## lightning), dust, how wet the ground ends up, the rainbow, the low haze, the fog density, and
## how much sunlight gets through.
const WEATHER: Dictionary = {
	"clear": {"clouds": 0.15, "storm": 0.0, "dust": 0.0, "wet": 0.0, "rainbow": 0.0, "haze": 0.3, "fog": 0.0012, "sun": 1.0},
	"clouddeck": {"clouds": 1.25, "storm": 0.0, "dust": 0.0, "wet": 0.0, "rainbow": 0.0, "haze": 0.4, "fog": 0.0016, "sun": 0.85},
	"dust": {"clouds": 0.55, "storm": 0.0, "dust": 0.75, "wet": 0.0, "rainbow": 0.0, "haze": 1.0, "fog": 0.018, "sun": 0.45},
	"storm": {"clouds": 2.0, "storm": 1.0, "dust": 0.0, "wet": 1.0, "rainbow": 0.0, "haze": 0.5, "fog": 0.006, "sun": 0.3},
	"afterrain": {"clouds": 0.9, "storm": 0.15, "dust": 0.0, "wet": 0.75, "rainbow": 1.0, "haze": 0.25, "fog": 0.0022, "sun": 0.95},
}

@export var sun_energy: float = 1.5
@export var moon_energy: float = 0.22
@export var moon_color: Color = Color(0.55, 0.66, 1.0)
@export var day_ambient: Color = Color(0.72, 0.62, 0.55)
@export var day_ambient_energy: float = 0.55
@export var night_ambient: Color = Color(0.2, 0.23, 0.42)
@export var night_ambient_energy: float = 0.3
## How far the clock must move (hours) before the sky and the lamps are redrawn.
@export var time_step: float = 0.02

## The road sound's level 0..1 (the Cruise sets it from its speed; 0 in the Drive-In).
## The Drive-In's house light level 0..1 (route22_room.gd): scales the glow of the props' lamps and
## lit windows, so the Lot lights tick box and the dimming for a film reach the bulbs. 1 on the Cruise.
var lamp_scale: float = 1.0
var road_noise: float = 0.0
## 0 = night, 1 = full day (from the hour; read by the rooms for their lamps and headlights).
var day: float = 1.0
## 1 at night, 0 by day: how much lights (headlights, neon, lit windows) show.
var night: float = 0.0
## Where the sun is now (a unit vector pointing at it, world space).
var sun_now: Vector3 = Vector3.UP
## The weather as it is right now (eased towards the setting's targets).
var wet: float = 0.0
var dust: float = 0.0
var storm: float = 0.0

var _room: Node3D
var _kit: Dictionary
var _sun: DirectionalLight3D
var _bolt: DirectionalLight3D     # the lightning flash
var _rain: CPUParticles3D
var _sand: CPUParticles3D
var _heat_sheets: Array[MeshInstance3D] = []
var _heat_mat: ShaderMaterial
var _hour: float = 18.2
var _hour_drawn: float = -99.0
var _env_drawn: int = 0
var _retired: bool = false
var _clouds: float = 1.0          # cloud cover now (eased)
var _rainbow: float = 0.0
var _haze: float = 0.35
var _fog: float = 0.0015
var _sun_through: float = 1.0
var _cloud_drift: Vector2 = Vector2.ZERO
var _flash: float = 0.0           # the lightning right now, 0..1
var _flash_wait: float = 6.0      # seconds to the next stroke
var _flash_twice: float = -1.0    # seconds to a stroke's second flicker (-1 = none)
var _bolt_az: float = 0.6
var _thunder_in: float = -1.0     # seconds until this stroke's thunder is heard
var _rng := RandomNumberGenerator.new()
# the generated sound
var _amb: AudioStreamGeneratorPlayback
var _lp_wind: float = 0.0
var _lp_wind2: float = 0.0
var _lp_road: float = 0.0
var _lp_rumble: float = 0.0
var _rumble: float = 0.0          # thunder, dying away
var _whoosh: float = 0.0          # a vehicle passing, dying away
var _sample: int = 0


## Called once by the room, after it has built its set. kit: r22_geo.gd new_kit() (its materials
## get the shared uniforms). centre: where the rain and blowing sand fall round (room space).
## heat: transforms (room space) of the heat-shimmer sheets, each 1 x 1 before `heat_size`.
## sound: start the generated soundscape on the Ambience bus.
func setup(room: Node3D, kit: Dictionary, centre: Vector3, heat: Array[Transform3D], heat_size: Vector2, sound: bool) -> void:
	_room = room
	_kit = kit
	name = "SunShafts"       # (so Room.get_static_meshes skips the rain and the shimmer)
	_rng.seed = 2222
	_sun = DirectionalLight3D.new()
	_sun.name = "SunMoon"
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 90.0
	_sun.light_angular_distance = 0.8
	add_child(_sun)
	_bolt = DirectionalLight3D.new()
	_bolt.name = "Lightning"
	_bolt.light_color = Color(0.75, 0.8, 1.0)
	_bolt.shadow_enabled = false
	_bolt.visible = false
	add_child(_bolt)
	_build_rain(centre)
	_build_sand(centre)
	_heat_mat = ShaderMaterial.new()
	_heat_mat.shader = HEAT_SHADER
	_heat_mat.set_shader_parameter("rock_noise", Geo.ROCK_NOISE)
	for xf in heat:
		var q := QuadMesh.new()
		q.size = heat_size
		var mi := MeshInstance3D.new()
		mi.name = "HeatShimmer"
		mi.mesh = q
		mi.material_override = _heat_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		mi.transform = xf
		mi.visible = false
		_heat_sheets.append(mi)
	_hour = fposmod(float(AppState.get_setting("r22_time")), 24.0)
	var w: Dictionary = WEATHER.get(String(AppState.get_setting("r22_weather")), WEATHER["clouddeck"])
	_snap_weather(w)
	if sound and room.has_method("_start_generated_ambience"):
		_amb = room.call("_start_generated_ambience", MIX_RATE, 0.3)
	EventBus.setting_changed.connect(_on_setting_changed)


## The room is being replaced (RoomHost calls the room's retire(), which calls this): stop
## touching the sky, which belongs to the next room now.
func retire() -> void:
	_retired = true
	_exit_tree()


func _exit_tree() -> void:
	if EventBus.setting_changed.is_connected(_on_setting_changed):
		EventBus.setting_changed.disconnect(_on_setting_changed)


func _on_setting_changed(key: String, _value: Variant) -> void:
	match key:
		"r22_time":
			_hour = fposmod(float(AppState.get_setting("r22_time")), 24.0)
		"r22_clouds", "r22_stars", "r22_weather", "r22_heat", "photosensitive_safe", "r22_detail", "graphics_quality":
			_hour_drawn = -100.0


## The hour the clock shows now, 0..24.
func get_hour() -> float:
	return _hour


## The look this PC draws the set in: "low" (flat colours) or "full" (photo grain, haze, the
## car's reflections). From "r22_detail" (Room tab > Set detail, each PC's own); "auto" follows
## "graphics_quality" (low = "low", else "full").
static func detail_level() -> String:
	var choice := String(AppState.get_setting("r22_detail"))
	if choice in ["low", "full"]:
		return choice
	return "low" if String(AppState.get_setting("graphics_quality")) == "low" else "full"


## Where the sun is at an hour: a unit vector pointing AT it. It rises behind (+Z, east), is
## high and a little to the left (south) at noon and sets ahead (-Z, west): straight down the
## Cruise's road, and behind the Drive-In's screen.
static func sun_at(hour: float) -> Vector3:
	var a := (hour - 6.0) / 12.0 * PI
	return Vector3(-0.35 * sin(a), sin(a), cos(a)).normalized()


## The moon: up while the sun is down, crossing the southern sky the other way round.
static func moon_at(hour: float) -> Vector3:
	var b := (hour - 18.0) / 12.0 * PI
	return Vector3(-0.5 * sin(b) - 0.2, sin(b) * 0.8 + 0.1, cos(b) * 0.9).normalized()


## A vehicle went by: a rush of air and tyres in the sound (0..1, louder for big ones).
func whoosh(amount: float) -> void:
	_whoosh = maxf(_whoosh, clampf(amount, 0.0, 1.0))


## Called every frame by the room. travel = metres driven (the Cruise; 0 in the Drive-In),
## bend / hill = the road's curve now (r22_common.gdshaderinc), speed = metres a second the
## scenery moves (the rain and sand lean with it).
func tick(delta: float, travel: float, bend: float, hill: float, speed: float) -> void:
	if _retired:
		return
	var day_minutes := float(AppState.get_setting("r22_day_minutes"))
	if day_minutes > 0.0:
		_hour = fposmod(_hour + delta * 24.0 / (day_minutes * 60.0), 24.0)
	_ease_weather(delta)
	_run_lightning(delta)
	var wind := clampf(float(AppState.get_setting("r22_wind")), 0.0, 1.0)
	_cloud_drift += Vector2(1.0, 0.35) * (2.0 + 8.0 * wind) * delta
	_cloud_drift = Vector2(fposmod(_cloud_drift.x, TRAVEL_WRAP), fposmod(_cloud_drift.y, TRAVEL_WRAP))
	var env := get_world_3d().environment if is_inside_tree() else null
	var env_id := env.get_instance_id() if env else 0
	if absf(_hour - _hour_drawn) >= time_step or env_id != _env_drawn or _flash > 0.0 or _changing:
		_hour_drawn = _hour
		_env_drawn = env_id
		_apply_sky(env)
	_apply_shared(travel, bend, hill, wind)
	_rain.emitting = storm > 0.35
	_rain.visible = storm > 0.05
	_rain.gravity = Vector3(wind * 4.0, -30.0, speed * 0.8)
	_sand.emitting = dust > 0.2 or wind > 0.75
	_sand.visible = _sand.emitting or _sand.visible and dust > 0.05
	_sand.gravity = Vector3(6.0 + 14.0 * wind, 0.2, speed)
	_fill_ambience(wind)


var _changing: bool = false       # the weather is still easing (redraw the sky every frame)


## The weather's numbers move towards the setting's targets: a few seconds for cloud and dust;
## rain soaks the ground in about 20 s and it dries in about two minutes.
func _ease_weather(delta: float) -> void:
	var w: Dictionary = WEATHER.get(String(AppState.get_setting("r22_weather")), WEATHER["clouddeck"])
	var clouds_to := float(w["clouds"]) * clampf(float(AppState.get_setting("r22_clouds")), 0.0, 2.0)
	var before := _clouds + dust + storm + _haze + _rainbow + _fog * 100.0 + _sun_through
	_clouds = move_toward(_clouds, clouds_to, delta * 0.3)
	dust = move_toward(dust, float(w["dust"]), delta * 0.15)
	storm = move_toward(storm, float(w["storm"]), delta * 0.2)
	_haze = move_toward(_haze, float(w["haze"]), delta * 0.2)
	_rainbow = move_toward(_rainbow, float(w["rainbow"]), delta * 0.1)
	_fog = move_toward(_fog, float(w["fog"]), delta * 0.004)
	_sun_through = move_toward(_sun_through, float(w["sun"]), delta * 0.2)
	var wet_to := float(w["wet"])
	wet = move_toward(wet, wet_to, delta * (0.05 if wet_to > wet else 0.008))
	_changing = absf(before - (_clouds + dust + storm + _haze + _rainbow + _fog * 100.0 + _sun_through)) > 0.00001


## Jumps straight to a weather (when the room loads).
func _snap_weather(w: Dictionary) -> void:
	_clouds = float(w["clouds"]) * clampf(float(AppState.get_setting("r22_clouds")), 0.0, 2.0)
	dust = float(w["dust"])
	storm = float(w["storm"])
	_haze = float(w["haze"])
	_rainbow = float(w["rainbow"])
	_fog = float(w["fog"])
	_sun_through = float(w["sun"])
	wet = float(w["wet"])


## Lightning in a thunderstorm: a stroke every 5 to 16 seconds, a bright flash that dies in a
## quarter second with a second flicker, the bolt in the sky, and its thunder a moment later.
## Photosensitive-safe mode: one soft, slow glow capped at SAFE_FLASH_CAP, no flicker.
## flash_strength scales it all.
func _run_lightning(delta: float) -> void:
	var safe := bool(AppState.get_setting("photosensitive_safe"))
	_flash = move_toward(_flash, 0.0, delta * (0.8 if safe else 4.0))
	if _flash_twice > 0.0:
		_flash_twice -= delta
		if _flash_twice <= 0.0 and not safe:
			_flash = maxf(_flash, 0.8)
	if _thunder_in > 0.0:
		_thunder_in -= delta
		if _thunder_in <= 0.0:
			_rumble = 1.0
	if storm < 0.6:
		return
	_flash_wait -= delta
	if _flash_wait <= 0.0:
		_flash_wait = _rng.randf_range(5.0, 16.0)
		_bolt_az = _rng.randf_range(-PI, PI)
		_flash = SAFE_FLASH_CAP if safe else 1.0
		_flash_twice = -1.0 if safe else _rng.randf_range(0.12, 0.3)
		_thunder_in = _rng.randf_range(0.8, 4.0)


## The lightning's brightness as shown (flash_strength, safe-mode cap).
func _flash_shown() -> float:
	var f := _flash * clampf(float(AppState.get_setting("flash_strength")), 0.0, 1.0)
	if bool(AppState.get_setting("photosensitive_safe")):
		f = minf(f, SAFE_FLASH_CAP)
	return f


## Everything that follows the hour and the weather: the sky shader, the sun / moon lamp, the
## lightning lamp, ambient light and fog. env = the Environment in use; only touched when its sky
## is this room's (r22_sky.gdshader), never another room's.
func _apply_sky(env: Environment) -> void:
	var sun := sun_at(_hour)
	var moon := moon_at(_hour)
	sun_now = sun
	day = smoothstep(-0.12, 0.22, sun.y)
	night = 1.0 - smoothstep(0.05, 0.45, day)
	var dusk := (1.0 - smoothstep(0.0, 0.4, absf(sun.y))) * smoothstep(-0.3, -0.05, sun.y)
	var turn := _room.global_basis.orthonormalized() if _room else Basis.IDENTITY
	var flash := _flash_shown()
	var hor := Color(0.015, 0.02, 0.05).lerp(Color(0.62, 0.66, 0.78), day).lerp(Color(0.95, 0.55, 0.35), dusk * 0.6)
	if env and env.sky and env.sky.sky_material is ShaderMaterial and (env.sky.sky_material as ShaderMaterial).shader == SKY_SHADER:
		var sky := env.sky.sky_material as ShaderMaterial
		sky.set_shader_parameter("cloud_noise", Geo.SKY_NOISE)
		sky.set_shader_parameter("sun_dir", turn * sun)
		sky.set_shader_parameter("moon_dir", turn * moon)
		sky.set_shader_parameter("day", day)
		sky.set_shader_parameter("dusk", dusk)
		sky.set_shader_parameter("twinkle", 0.0 if bool(AppState.get_setting("photosensitive_safe")) else 1.0)
		sky.set_shader_parameter("cloud_amount", _clouds)
		sky.set_shader_parameter("star_amount", float(AppState.get_setting("r22_stars")) * (1.0 - storm) * (1.0 - dust))
		sky.set_shader_parameter("storm", storm)
		sky.set_shader_parameter("flash", flash)
		sky.set_shader_parameter("bolt_az", _bolt_az)
		sky.set_shader_parameter("rainbow", _rainbow * smoothstep(0.02, 0.15, sun.y) * smoothstep(0.75, 0.45, sun.y))
		sky.set_shader_parameter("dust", dust)
		sky.set_shader_parameter("haze", clampf(_haze, 0.0, 1.0))
		var amb := night_ambient.lerp(day_ambient, day).lerp(Color(0.75, 0.48, 0.42), dusk * 0.35)
		amb = amb.lerp(Color(0.6, 0.42, 0.3), dust * 0.6).lerp(Color(0.45, 0.48, 0.55), storm * 0.5)
		env.ambient_light_color = amb
		env.ambient_light_energy = lerpf(night_ambient_energy, day_ambient_energy, day) * (1.0 - 0.3 * storm) + flash * 0.6
		var fog_col := hor.lerp(Color(0.62, 0.4, 0.25) * (0.06 + 0.94 * day), dust)
		env.fog_light_color = fog_col.lerp(Color(0.5, 0.52, 0.6) * (0.05 + 0.95 * day), storm * 0.5)
		env.fog_density = _fog
		# the volumetric haze (when the graphics settings have it on): sunbeams through the rock
		# gaps on Detailed, thick in a dust storm
		if env.volumetric_fog_enabled:
			var vol := 0.0 if detail_level() == "low" else 0.004 + 0.03 * dust + 0.008 * storm + 0.004 * dusk
			env.volumetric_fog_density = vol
			env.volumetric_fog_albedo = Color(0.9, 0.7, 0.55).lerp(Color(0.85, 0.6, 0.4), dust)
	# the sun by day, the moon by night
	var light_dir := sun
	var light_col := Color(1.0, 0.52, 0.25).lerp(Color(1.0, 0.95, 0.86), smoothstep(0.05, 0.45, sun.y))
	var energy := sun_energy * smoothstep(0.0, 0.2, sun.y) * _sun_through
	if sun.y <= 0.02:
		light_dir = moon
		light_col = moon_color
		energy = moon_energy * smoothstep(0.05, 0.25, moon.y) * (1.0 - storm)
	light_col = light_col.lerp(Color(1.0, 0.7, 0.45), dust * 0.6)
	_sun.light_color = light_col
	_sun.light_energy = energy
	_sun.visible = energy > 0.002
	var world_dir := turn * light_dir
	_sun.global_basis = Basis.looking_at(-world_dir, Vector3.UP if absf(world_dir.y) < 0.99 else Vector3.FORWARD)
	_bolt.visible = flash > 0.01
	_bolt.light_energy = flash * 2.5
	var bolt_dir := Vector3(sin(_bolt_az), 0.6, -cos(_bolt_az)).normalized()
	_bolt.global_basis = Basis.looking_at(-(turn * bolt_dir), Vector3.UP)
	# the shimmer: hot, dry, clear afternoons only
	var heat := clampf(float(AppState.get_setting("r22_heat")), 0.0, 1.0) * smoothstep(0.2, 0.6, sun.y) * (1.0 - wet) * (1.0 - dust) * (1.0 - storm)
	_heat_mat.set_shader_parameter("amount", heat)
	for mi in _heat_sheets:
		mi.visible = heat > 0.02
	for m: ShaderMaterial in _kit["roads"]:
		m.set_shader_parameter("sky_horizon", Vector3(hor.r, hor.g, hor.b) * (0.6 + 0.4 * day))
		m.set_shader_parameter("heat", heat)
		m.set_shader_parameter("night", night)


## Writes the shared uniforms to every Route 22 material (r22_common.gdshaderinc) and the night
## glow to the lights. Called every frame.
func _apply_shared(travel: float, bend: float, hill: float, wind: float) -> void:
	var t := fposmod(travel, TRAVEL_WRAP)
	var shade := clampf(_clouds * 0.45, 0.0, 0.8) * day * smoothstep(0.05, 0.2, sun_now.y) * (1.0 - dust * 0.7)
	var detailed := 1.0 if detail_level() == "full" else 0.0
	var neon_on := bool(AppState.get_setting("r22_neon"))
	var safe := bool(AppState.get_setting("photosensitive_safe"))
	var lamp := (night * 2.6 + 0.15) * lamp_scale
	for m: ShaderMaterial in _kit["mats"]:
		m.set_shader_parameter("travel", t)
		m.set_shader_parameter("bend", bend)
		m.set_shader_parameter("hill", hill)
		m.set_shader_parameter("wet", wet)
		m.set_shader_parameter("cloud_shadow", shade)
		m.set_shader_parameter("cloud_drift", _cloud_drift)
		m.set_shader_parameter("detail", detailed)
	for key: String in ["prop", "brush"]:
		var pm := _kit[key] as ShaderMaterial
		pm.set_shader_parameter("glow", lamp)
		pm.set_shader_parameter("wind", 0.4 + 2.2 * wind)
	var nm := _kit["neon"] as ShaderMaterial
	nm.set_shader_parameter("glow", (night * 4.0 + 0.6) if neon_on else 0.0)
	nm.set_shader_parameter("flicker", 0.0 if safe else 1.0)
	for g: ShaderMaterial in _kit["glows"]:
		g.set_shader_parameter("strength", night)
	for g: ShaderMaterial in _kit["neon_glows"]:
		g.set_shader_parameter("strength", night * 0.8 if neon_on else 0.0)


# ── Rain and blowing sand ────────────────────────────────────
## Rain: thin streaks falling round `centre` (a 40 m square), leaning with the wind and the drive.
func _build_rain(centre: Vector3) -> void:
	_rain = CPUParticles3D.new()
	_rain.name = "Rain"
	_rain.amount = 900
	_rain.lifetime = 0.9
	_rain.preprocess = 0.9
	_rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_rain.emission_box_extents = Vector3(20.0, 1.0, 20.0)
	_rain.direction = Vector3.DOWN
	_rain.spread = 3.0
	_rain.initial_velocity_min = 4.0
	_rain.initial_velocity_max = 6.0
	_rain.gravity = Vector3(0.0, -30.0, 0.0)
	var drop := QuadMesh.new()
	drop.size = Vector2(0.012, 0.5)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.75, 0.8, 0.88, 0.35)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	m.billboard_keep_scale = true
	drop.material = m
	_rain.mesh = drop
	_rain.local_coords = false
	_rain.emitting = false
	_rain.visible = false
	_rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_rain)
	_rain.position = centre + Vector3(0.0, 14.0, 0.0)


## Blowing sand: fast, low specks streaming across in the wind (a dust storm, or a gale).
func _build_sand(centre: Vector3) -> void:
	_sand = CPUParticles3D.new()
	_sand.name = "BlowingSand"
	_sand.amount = 420
	_sand.lifetime = 2.0
	_sand.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_sand.emission_box_extents = Vector3(4.0, 1.2, 30.0)
	_sand.direction = Vector3(1.0, 0.05, 0.0)
	_sand.spread = 8.0
	_sand.initial_velocity_min = 8.0
	_sand.initial_velocity_max = 16.0
	_sand.gravity = Vector3(10.0, 0.0, 0.0)
	_sand.scale_amount_min = 0.5
	_sand.scale_amount_max = 1.6
	var fade := Gradient.new()
	fade.set_color(0, Color(0.85, 0.6, 0.4, 0.0))
	fade.add_point(0.2, Color(0.8, 0.55, 0.35, 0.5))
	fade.set_color(fade.get_point_count() - 1, Color(0.75, 0.5, 0.3, 0.0))
	_sand.color_ramp = fade
	var speck := QuadMesh.new()
	speck.size = Vector2(0.25, 0.06)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	speck.material = m
	_sand.mesh = speck
	_sand.local_coords = false
	_sand.emitting = false
	_sand.visible = false
	_sand.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_sand)
	_sand.position = centre + Vector3(-22.0, 0.8, 0.0)


# ── Sound ────────────────────────────────────────────────────
## Called every frame: tops the generator up with the desert's sound. Wind (two bands of
## filtered noise, gusting), rain hiss, thunder (a low rumble after each stroke), crickets on dry
## nights, the road (tyre roar and a low engine hum, from road_noise) and passing traffic.
func _fill_ambience(wind: float) -> void:
	if _amb == null:
		return
	var n := _amb.get_frames_available()
	if n <= 0:
		return
	var gust := 0.6 + 0.4 * sin(float(Time.get_ticks_msec()) * 0.0007) * sin(float(Time.get_ticks_msec()) * 0.00023)
	var wind_lv := (0.006 + 0.03 * wind * gust + 0.04 * dust) * (0.6 + 0.4 * gust)
	var rain_lv := 0.03 * storm
	var cricket_lv := 0.01 * night * (1.0 - storm) * (1.0 - dust)
	var road_lv := 0.045 * road_noise
	var buf := PackedVector2Array()
	buf.resize(n)
	for i in n:
		var w := _rng.randf() * 2.0 - 1.0
		_lp_wind += (w - _lp_wind) * 0.02
		_lp_wind2 += (w - _lp_wind2) * 0.12
		_lp_road += (w - _lp_road) * 0.06
		_lp_rumble += (w - _lp_rumble) * 0.008
		_rumble *= 0.99997
		_whoosh *= 0.99992
		_sample += 1
		var t := float(_sample) / MIX_RATE
		var s := _lp_wind * wind_lv * 3.0 + _lp_wind2 * wind_lv * 0.6
		s += w * rain_lv * 0.5 + _lp_wind2 * rain_lv
		s += _lp_rumble * _rumble * 0.9
		if road_lv > 0.0:
			s += _lp_road * road_lv * 2.0 + sin(t * TAU * 46.0) * road_lv * 0.25 + sin(t * TAU * 92.0) * road_lv * 0.1
		s += _lp_road * _whoosh * 0.35
		if cricket_lv > 0.0005 and fmod(t, 1.1) < 0.4 and sin(t * 180.0) > 0.0:
			s += sin(t * 26000.0) * cricket_lv
		buf[i] = Vector2(s, s * 0.94)
	_amb.push_buffer(buf)
