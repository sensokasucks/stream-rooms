extends Room
## Lakeside Campfire: an outdoor room. A campfire in a forest clearing, the presenters on camp
## chairs on its far side, chat on log benches on the near side, the big screen hung between two
## posts with a lake and mountains behind it, three tents, a stream, and a sky for every hour
## and weather.
##   - The set is built in code by campfire_builder.gd when the room loads (there is no Blender
##     model): the ground, the water, the forest, the furniture and every marker the app looks
##     for. This script keeps the materials and nodes it hands back and animates them.
##   - Time of day ("camp_time", hours; "camp_day_minutes" lets the clock run): _apply_time()
##     moves the sun and the moon, sets the sky shader (camp_sky.gdshader: stars, Milky Way,
##     aurora, two cloud layers, mountain ridges, the far shore), the one sunlight / moonlight
##     lamp, the ambient light, the mist and what the lake mirrors (camp_water.gdshader).
##   - Weather: "camp_rain" (0..1) and "camp_storm" (a thunderstorm) roll in over a few seconds
##     (_gloom): the clouds close up and darken, the wind rises in the trees, rain falls round the
##     camera, the ground and props go dark and shiny, rings spread on the lake and the fire
##     shrinks and hisses. In a thunderstorm lightning lights the clouds and the camp at random
##     moments (strike()), with thunder a little later. Flashes follow the Flash strength slider;
##     in photosensitive-safe mode a strike is a slow, dim glow instead of a flash.
##   - The fire ("camp_fire", 0..2): flames (the Forge Hall's fire.gdshader), a flickering
##     light, sparks, smoke, glowing coals and a crackle. flare() makes it leap up for a few
##     seconds: the fire games call it when a stick lands, and so does any chat reaction thrown
##     at the "campfire" target.
##   - The big screen ("camp_screen"): switching it off hides the sheet and everything the app
##     hangs on it (its lights, the curtain, the side chat windows), which opens the view over
##     the lake. The posts stay: the string lights hang from them. The sound keeps playing.
##   - The close woods ("camp_close_woods"): a thick belt of trees right round the clearing and
##     behind the screen that hides the lake, for a camp deep in the forest. Off by default.
##   - String lights and tent lanterns ("camp_string_lights") are the room's house lights; they
##     glow weakly by day and fully at night, and dim for a video like any room's lamps.
##   - Fire games (campfire_games.gd, "camp_games"): hold M to roast a marshmallow on a stick
##     that pokes out of your avatar, press T to toss a stick on the fire.
##   - A generated soundscape on the Ambience bus: the fire, rain, thunder, and crickets at night.
## The weather, time and fire settings are shared in a co-stream (NetSession.SHARED_BASE, with the
## host's "room" group), so everyone sits in the same storm.

const Builder := preload("res://rooms/campfire/campfire_builder.gd")
const Games := preload("res://rooms/campfire/campfire_games.gd")
const SKY_SHADER := preload("res://rooms/campfire/camp_sky.gdshader")
const FIRE_SHADER := preload("res://rooms/forge_hall/fire.gdshader")
const MIX_RATE: float = 22050.0
## The flames: [metres east, metres south, size as a share of flame_size].
const FIRE_FLAMES: Array = [[0.0, 0.0, 1.0], [-0.26, 0.08, 0.7], [0.25, 0.06, 0.76], [-0.1, -0.2, 0.82], [0.12, 0.2, 0.62], [-0.38, -0.08, 0.45], [0.4, -0.05, 0.5]]
## Raindrops in the air at Rain 100% (the slider scales how many are shown).
const RAIN_DROPS: int = 2600
## The things the app hangs on the big screen, hidden with it (see _apply_screen).
const SCREEN_PARTS: PackedStringArray = ["ScreenLights", "StageCurtain", "StandbyCard", "SideChats"]
## Seconds between lightning strikes in a thunderstorm (picked at random between the two).
const STRIKE_GAP: Vector2 = Vector2(7.0, 22.0)
## The longest a normal strike's flicker lasts, and a safe-mode strike's slow glow (seconds).
const STRIKE_SECONDS: float = 0.7
const SAFE_STRIKE_SECONDS: float = 2.4
## In photosensitive-safe mode light never jumps by more than this share of full brightness.
const SAFE_FLASH_CAP: float = 0.3

@export_group("Fire")
## The tallest flame: width and height in metres at Fire 100%.
@export var flame_size: Vector2 = Vector2(0.95, 1.5)
@export var spark_count: int = 28
## The light the fire throws: energy at Fire 100%, range in metres.
@export var fire_light_energy: float = 7.0
@export var fire_light_range: float = 17.0
@export var fire_light_color: Color = Color(1.0, 0.5, 0.18)
## How much the fire's light wavers (share of its energy). 0 = steady.
@export_range(0.0, 0.3) var fire_flicker: float = 0.12
## The fire's light drops to this share while the lights are dimmed for a video.
@export_range(0.0, 1.0) var fire_dimmed: float = 0.45
## How much rain at 100% takes off the fire (0.45 = it burns at 55%).
@export_range(0.0, 1.0) var rain_on_fire: float = 0.45
## Seconds a flare (a stick landing) takes to die back down.
@export var flare_seconds: float = 5.0

@export_group("Time of day")
@export var sun_energy: float = 1.35
@export var moon_energy: float = 0.24
@export var moon_color: Color = Color(0.55, 0.68, 1.0)
## Ambient light (colour, energy) by day and at night; _apply_time() mixes them.
@export var day_ambient: Color = Color(0.55, 0.63, 0.78)
@export var day_ambient_energy: float = 0.6
@export var night_ambient: Color = Color(0.2, 0.27, 0.52)
@export var night_ambient_energy: float = 0.32
## How far the clock must move (hours) before the sky and lights are redrawn.
@export var time_step: float = 0.02
## The lamps (string lights, lanterns) burn at this share of full in broad daylight.
@export_range(0.0, 1.0) var lamps_by_day: float = 0.2

@export_group("Weather")
## Seconds the weather takes to roll in or clear.
@export var weather_seconds: float = 6.0
## Lightning: the pale light it throws over the camp at Flash strength 100%.
@export var strike_energy: float = 2.6

@export_group("Sound")
@export var ambience_enabled: bool = true
@export_range(0.0, 1.0) var fire_loudness: float = 0.06
@export_range(0.0, 1.0) var rain_loudness: float = 0.07
@export_range(0.0, 1.0) var thunder_loudness: float = 0.5
@export_range(0.0, 1.0) var cricket_loudness: float = 0.012

var _parts: Dictionary = {}       # what campfire_builder.gd built (see Builder.build)
## Holds what this script draws (flames, rain, fireflies). Named "SunShafts" so the app doesn't
## count them as the room's own meshes (Room.get_static_meshes).
var _fx: Node3D
var _games: Node3D                # campfire_games.gd
var _sun: DirectionalLight3D      # the sun by day, the moon by night
var _bolt: DirectionalLight3D     # lightning's light
var _fire_mats: Array[ShaderMaterial] = []
var _fire_meshes: Array[MeshInstance3D] = []
var _fire_light: OmniLight3D
var _sparks: CPUParticles3D
var _burst: CPUParticles3D        # the shower of sparks when the fire flares
var _smoke: CPUParticles3D
var _rain: GPUParticles3D
var _fireflies: CPUParticles3D
var _hour: float = 18.6           # the room's clock, hours 0..24 (starts at "camp_time")
var _hour_drawn: float = -99.0    # the hour the sky was last drawn for
var _env_drawn: int = 0           # instance id of the Environment it was drawn on
var _day: float = 0.0             # 0 = night, 1 = full day (from _apply_time)
var _gloom: float = 0.0           # 0 = fair, 1 = full storm cloud; eases toward the weather settings
var _rain_now: float = 0.0        # the rain falling right now, 0..1; eases toward "camp_rain"
var _gloom_drawn: float = -1.0
var _flare: float = 0.0           # extra fire from a stick, 0..1.2, dying away
var _flare_shown: float = 0.0     # what the flames and light show of it (eased; slower in safe mode)
var _strike_t: float = -1.0       # seconds since the last strike began (below 0 = none)
var _strike_wait: float = 8.0     # seconds until the next strike in a storm
var _strike_dir: Vector3 = Vector3(0.0, 0.4, -0.9)
var _flash: float = 0.0           # the strike's light right now, 0..1
var _thunder_wait: float = -1.0   # seconds until the last strike's thunder starts (below 0 = none)
var _retired: bool = false        # another room has taken over (retire()): leave the sky alone
var _time: float = 0.0
var _last_level: float = -1.0     # the house light level the glows were last set for
var _screen_nodes: Array[Node3D] = []     # the screen's parts, found once the app has added them
# the generated sound
var _amb_playback: AudioStreamGeneratorPlayback
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _lp_fire: float = 0.0         # low-pass states: the fire's roar,
var _lp_rain: float = 0.0         # the part taken out of the rain's hiss,
var _lp_thunder: float = 0.0      # and thunder's rumble
var _pop: float = 0.0             # the current crackle, dying away
var _thunder: float = 0.0         # thunder's loudness right now, dying away
var _crack: float = 0.0           # the sharp start of a thunderclap, dying away fast
var _sample: int = 0              # samples made so far (the crickets' clock)


func _ready() -> void:
	# first of all: Room._ready() and RoomHost read the set's markers straight away
	_parts = Builder.build(self)
	super._ready()
	_fx = Node3D.new()
	_fx.name = "SunShafts"
	add_child(_fx)
	_build_sun()
	_build_fire()
	_build_rain()
	_build_fireflies()
	_coal_look()
	_games = Games.new()
	_games.name = "FireGames"
	_fx.add_child(_games)
	_games.setup(self)
	_hour = fposmod(float(AppState.get_setting("camp_time")), 24.0)
	# start in the weather that is set, instead of watching it roll in on every room load
	_rain_now = _rain_target()
	_gloom = _gloom_target()
	_rng.randomize()
	if ambience_enabled:
		_amb_playback = _start_generated_ambience(MIX_RATE, 0.3)
	EventBus.setting_changed.connect(_on_camp_setting_changed)
	EventBus.room_changed.connect(_on_camp_room_changed)
	EventBus.reaction_play.connect(_on_reaction_play)
	_apply_woods()
	_apply_fire()
	_apply_wet()


## The room is freed on a room swap: drop the EventBus connections with it.
func _exit_tree() -> void:
	if EventBus.setting_changed.is_connected(_on_camp_setting_changed):
		EventBus.setting_changed.disconnect(_on_camp_setting_changed)
		EventBus.room_changed.disconnect(_on_camp_room_changed)
		EventBus.reaction_play.disconnect(_on_reaction_play)


## RoomHost calls this (through propagate_call) when another room replaces this one, three
## seconds before it is freed: stop touching the sky, which is the new room's now.
func retire() -> void:
	_retired = true
	_exit_tree()


## Room tab: the fire, the screen, the hour, the sky and the weather.
func get_controls() -> Array[Dictionary]:
	return [
		{"heading": "Lakeside Campfire"},
		{"key": "camp_fire", "label": "Fire", "min": 0.0, "max": 2.0, "step": 0.01, "format": "%d%%", "scale": 100.0,
			"tooltip": "How big the campfire is: its flames, the light it throws, its sparks and its crackle. 0% = out. Rain makes it smaller."},
		{"key": "camp_screen", "label": "Big screen", "type": "check",
			"tooltip": "On: the big screen hangs between the two posts. Off: the screen is taken down, which opens the view over the lake. The sound of whatever is playing carries on."},
		{"key": "camp_close_woods", "label": "Woods close around the camp", "type": "check",
			"tooltip": "On: thick trees stand right round the clearing and behind the screen, so the lake is hidden and the camp sits deep in the forest. Off: the open view over the lake."},
		{"key": "camp_string_lights", "label": "String lights and lanterns", "type": "check",
			"tooltip": "The string lights between the posts and the lanterns in the tents. They glow softly by day and fully at night, and follow the House lights slider."},
		{"key": "camp_fireflies", "label": "Fireflies at night", "type": "check",
			"tooltip": "Small drifting lights round the edge of the clearing on dry nights."},
		{"key": "camp_games", "label": "Fire games (M and T keys)", "type": "check",
			"tooltip": "On: hold M in the room window to roast a marshmallow on a stick that pokes out of your avatar, and press T to toss a stick on the fire. In a co-stream everyone sees everyone's. Chat can feed the fire too, by throwing a reaction at the target \"campfire\"."},
		{"heading": "Time of day"},
		{"key": "camp_time", "label": "Time of day", "min": 0.0, "max": 24.0, "step": 0.1, "format": "%.1f h",
			"tooltip": "The hour at the camp, 0 to 24. 6 = sunrise, 12 = noon, 18 = sunset. The sun sets over the lake's left side; at night the moon crosses above the lake."},
		{"key": "camp_day_minutes", "label": "Day length", "min": 0.0, "max": 120.0, "step": 1.0, "format": "%d min", "zero": "Clock stopped",
			"tooltip": "Lets the clock run: how many minutes a full day and night takes, starting from the Time of day. 0 = the clock stands still."},
		{"heading": "Sky"},
		{"key": "camp_clouds", "label": "Clouds", "min": 0.0, "max": 2.0, "step": 0.01, "format": "%d%%", "scale": 100.0,
			"tooltip": "How much cloud drifts across the sky in fair weather. 0% = a clear sky (and the lightest on a slow graphics card), 200% = overcast. Rain brings its own clouds."},
		{"key": "camp_stars", "label": "Stars", "min": 0.0, "max": 2.0, "step": 0.01, "format": "%d%%", "scale": 100.0,
			"tooltip": "How bright the stars and the Milky Way are at night. 0% = none."},
		{"key": "camp_aurora", "label": "Aurora", "min": 0.0, "max": 2.0, "step": 0.01, "format": "%d%%", "scale": 100.0,
			"tooltip": "Green and violet northern lights over the lake at night. 0% = none (and lighter on a slow graphics card)."},
		{"key": "camp_mist", "label": "Mist", "min": 0.0, "max": 1.0, "step": 0.01, "format": "%d%%", "scale": 100.0,
			"tooltip": "The haze over the lake and between the mountain ridges."},
		{"heading": "Weather"},
		{"key": "camp_rain", "label": "Rain", "min": 0.0, "max": 1.0, "step": 0.01, "format": "%d%%", "scale": 100.0, "zero": "Dry",
			"tooltip": "How hard it rains. The clouds close in, the ground goes dark and shiny, rings spread on the lake and the fire burns lower. It rolls in over a few seconds."},
		{"key": "camp_storm", "label": "Thunderstorm", "type": "check",
			"tooltip": "On: heavy rain, wind in the trees, and lightning with thunder every so often. The flashes follow the Flash strength slider (Sound tab > Accessibility); in photosensitive-safe mode a strike is a slow, dim glow instead."},
	]


func _on_camp_setting_changed(key: String, _value: Variant) -> void:
	match key:
		"camp_fire":
			_apply_fire()
		"camp_time":
			_hour = fposmod(float(AppState.get_setting("camp_time")), 24.0)
		"camp_clouds", "camp_stars", "camp_aurora", "camp_mist", "camp_string_lights", "photosensitive_safe":
			_hour_drawn = -100.0        # _run_clock redraws the sky and lights next frame
		"camp_screen":
			_apply_screen()
		"camp_close_woods":
			_apply_woods()
		"camp_storm":
			_strike_wait = _rng.randf_range(2.0, 5.0)      # the first strike comes soon


## RoomHost emits room_changed when it has finished setting the room up (the screen's lights,
## the curtain and the side chats exist now): find them and hide them if the screen is off.
func _on_camp_room_changed(_room_id: String) -> void:
	if _retired or not is_inside_tree():
		return
	_screen_nodes.clear()
	for part in SCREEN_PARTS:
		var n := get_node_or_null(part) as Node3D
		if n:
			_screen_nodes.append(n)
	_apply_screen()


func _process(delta: float) -> void:
	super._process(delta)
	_time += delta
	_run_weather(delta)
	_run_lightning(delta)        # before the clock, which draws the sky with this frame's flash
	_run_clock(delta)
	_run_fire(delta)
	if not is_equal_approx(_level, _last_level):
		_last_level = _level
		_apply_glows()
	_keep_screen_hidden()
	_follow_camera()
	_fill_ambience()


# ── The big screen ───────────────────────────────────────────
## "camp_screen": shows or hides the sheet, its dark back and everything the app hung on it.
func _apply_screen() -> void:
	var on := bool(AppState.get_setting("camp_screen"))
	for key: String in ["screen", "screen_back"]:
		(_parts[key] as Node3D).visible = on
	for n in _screen_nodes:
		if is_instance_valid(n):
			n.visible = on


## "camp_close_woods": shows or hides the thick trees round the clearing and behind the screen
## (built hidden by campfire_builder.gd's _build_close_woods). Called once when the room loads
## and on every change of the setting.
func _apply_woods() -> void:
	var on := bool(AppState.get_setting("camp_close_woods"))
	for n: Node3D in _parts["close_woods"]:
		n.visible = on


## Called every frame. The app's own code may show a screen part again (the curtain opening,
## a chat window switching on); while the screen is off they are hidden again at once.
func _keep_screen_hidden() -> void:
	if bool(AppState.get_setting("camp_screen")):
		return
	for n in _screen_nodes:
		if is_instance_valid(n) and n.visible:
			n.visible = false


# ── The lamps ────────────────────────────────────────────────
## The house lights (string lights, lanterns) are off with their tick box and weak by day, on
## top of what every room does (the House lights slider, dimming for a video).
func _target_level() -> float:
	if not bool(AppState.get_setting("camp_string_lights")):
		return 0.0
	return super._target_level() * lerpf(1.0, lamps_by_day, _day)


## The bulbs' and the tents' glow follow the house light level (_level, 0..1).
func _apply_glows() -> void:
	(_parts["bulb_mat"] as StandardMaterial3D).emission_energy_multiplier = 3.2 * _level
	(_parts["tent_mat"] as ShaderMaterial).set_shader_parameter("glow", 0.5 * _level * (1.0 - _day))


# ── The fire ─────────────────────────────────────────────────
## Flames, the light, sparks, the burst for a flare, and smoke, all at the FIRE_Camp marker.
func _build_fire() -> void:
	var marker := _parts["fire"] as Node3D
	for k in FIRE_FLAMES.size():
		var f: Array = FIRE_FLAMES[k]
		var size := flame_size * float(f[2])
		var quad := QuadMesh.new()
		quad.size = size
		var mat := ShaderMaterial.new()
		mat.shader = FIRE_SHADER
		mat.set_shader_parameter("seed", float(k) * 1.37)
		var mi := MeshInstance3D.new()
		mi.name = "FireFlame"
		mi.mesh = quad
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_fx.add_child(mi, true)
		# (the shader turns the rectangle to face the camera and counts height from its bottom)
		mi.global_position = marker.global_position + Vector3(float(f[0]), size.y * 0.5 - 0.06, float(f[1]))
		mi.extra_cull_margin = maxf(size.x, size.y) * 2.0
		_fire_mats.append(mat)
		_fire_meshes.append(mi)
	_fire_light = OmniLight3D.new()
	_fire_light.name = "FireLight"
	_fire_light.light_color = fire_light_color
	_fire_light.omni_range = fire_light_range
	_fire_light.omni_attenuation = 0.9
	_fire_light.shadow_enabled = false
	add_child(_fire_light)
	_fire_light.global_position = marker.global_position + Vector3(0.0, 1.4, 0.0)      # above the flames, so it reaches the ground and the benches
	_sparks = _make_sparks("FireSparks", spark_count, 2.4, false)
	_burst = _make_sparks("FireBurst", 70, 1.8, true)
	# smoke: a few soft grey puffs that rise, spread and fade
	_smoke = CPUParticles3D.new()
	_smoke.name = "FireSmoke"
	_smoke.amount = 14
	_smoke.lifetime = 6.0
	_smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_smoke.emission_sphere_radius = 0.2
	_smoke.direction = Vector3.UP
	_smoke.spread = 12.0
	_smoke.gravity = Vector3(0.25, 0.3, 0.08)
	_smoke.initial_velocity_min = 0.7
	_smoke.initial_velocity_max = 1.1
	_smoke.scale_amount_min = 0.6
	_smoke.scale_amount_max = 1.0
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.3))
	grow.add_point(Vector2(1.0, 1.0))
	_smoke.scale_amount_curve = grow
	var fade := Gradient.new()
	fade.set_color(0, Color(0.5, 0.48, 0.46, 0.0))
	fade.add_point(0.15, Color(0.45, 0.44, 0.43, 0.2))
	fade.set_color(fade.get_point_count() - 1, Color(0.4, 0.4, 0.42, 0.0))
	_smoke.color_ramp = fade
	var puff := QuadMesh.new()
	puff.size = Vector2(1.6, 1.6)
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.vertex_color_use_as_albedo = true
	pm.albedo_texture = _soft_dot(false)
	pm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	pm.billboard_keep_scale = true
	pm.disable_fog = true
	puff.material = pm
	_smoke.mesh = puff
	_smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fx.add_child(_smoke)
	_smoke.global_position = marker.global_position + Vector3(0.0, 1.3, 0.0)


## A soft round dot texture for particles. additive = true: white fading to black (for glowing
## specks added onto the picture); false: white fading to see-through (for smoke).
func _soft_dot(additive: bool) -> GradientTexture2D:
	var dot := GradientTexture2D.new()
	dot.width = 32
	dot.height = 32
	dot.fill = GradientTexture2D.FILL_RADIAL
	dot.fill_from = Vector2(0.5, 0.5)
	dot.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.set_color(0, Color.WHITE)
	g.set_color(1, Color.BLACK if additive else Color(1.0, 1.0, 1.0, 0.0))
	dot.gradient = g
	return dot


## Glowing specks rising from the fire. one_shot = the burst a flare throws up all at once.
func _make_sparks(node_name: String, count: int, life: float, one_shot: bool) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = node_name
	p.amount = count
	p.lifetime = life
	p.randomness = 0.6
	p.one_shot = one_shot
	p.explosiveness = 0.92 if one_shot else 0.0
	p.emitting = not one_shot
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.3
	p.direction = Vector3.UP
	p.spread = 35.0 if one_shot else 20.0
	p.gravity = Vector3(0.15, 0.45, 0.0)
	p.initial_velocity_min = 1.4 if one_shot else 0.6
	p.initial_velocity_max = 3.4 if one_shot else 1.5
	p.damping_min = 0.3
	p.damping_max = 0.7
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	var fade := Gradient.new()
	fade.set_color(0, Color(1.0, 0.8, 0.4, 1.0))
	fade.add_point(0.5, Color(1.0, 0.4, 0.08, 0.9))
	fade.set_color(fade.get_point_count() - 1, Color(0.6, 0.1, 0.0, 0.0))
	p.color_ramp = fade
	var speck := QuadMesh.new()
	speck.size = Vector2(0.035, 0.035)
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.vertex_color_use_as_albedo = true
	sm.albedo_color = Color(3.0, 3.0, 3.0)              # above 1: the specks bloom
	sm.albedo_texture = _soft_dot(true)
	sm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	sm.billboard_keep_scale = true
	sm.disable_fog = true           # (fog on a glow that is added to the picture shows as a pale square)
	speck.material = sm
	p.mesh = speck
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fx.add_child(p)
	p.global_position = (_parts["fire"] as Node3D).global_position + Vector3(0.0, 0.3, 0.0)
	return p


## The bed of coals (the builder's "Embers" disc): a blotchy noise picture on its glow breaks it
## into bright coals with dark gaps. _run_fire sets how strongly it glows.
func _coal_look() -> void:
	var m := _parts["ember_mat"] as StandardMaterial3D
	var cells := FastNoiseLite.new()
	cells.noise_type = FastNoiseLite.TYPE_CELLULAR
	cells.frequency = 0.09
	cells.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
	var pic := NoiseTexture2D.new()
	pic.width = 128
	pic.height = 128
	pic.seamless = true
	pic.noise = cells
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.0, 0.0, 0.0))
	ramp.add_point(0.35, Color(0.35, 0.03, 0.0))
	ramp.add_point(0.7, Color(1.0, 0.3, 0.03))
	ramp.set_color(ramp.get_point_count() - 1, Color(1.0, 0.8, 0.4))
	pic.color_ramp = ramp
	m.emission_texture = pic
	m.emission = Color.WHITE
	m.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
	m.albedo_color = Color(0.03, 0.02, 0.02)
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(1.6, 1.6, 1.6)


## How big the fire burns right now, 0..2.4: the Fire slider, less what the rain takes, plus a
## flare. The fire games read it too (a bigger fire toasts faster).
func get_fire_amount() -> float:
	var set_to := clampf(float(AppState.get_setting("camp_fire")), 0.0, 2.0)
	if set_to <= 0.005:
		return 0.0
	return set_to * (1.0 - rain_on_fire * _rain_now) + _flare_shown * 0.9


## Makes the fire leap up for a few seconds (a stick landed on it): taller flames, more light and
## a shower of sparks. strength 0..1; several add up to 1.2 at most. Does nothing if the fire is out.
func flare(strength: float) -> void:
	if float(AppState.get_setting("camp_fire")) <= 0.005:
		return
	_flare = minf(_flare + clampf(strength, 0.0, 1.0), 1.2)
	_burst.amount = maxi(int(70.0 * clampf(strength, 0.2, 1.0)), 8)
	_burst.restart()
	_pop = 1.0                       # a loud crackle


## How much flare is left, 0..1.2 (for tests).
func get_flare() -> float:
	return _flare


## "camp_fire" changed: show or hide the flames and sparks (their size follows in _run_fire).
func _apply_fire() -> void:
	var lit := float(AppState.get_setting("camp_fire")) > 0.005
	for mi in _fire_meshes:
		mi.visible = lit
	for p: CPUParticles3D in [_sparks, _smoke]:
		p.emitting = lit
		p.visible = lit
	var want := maxi(int(round(float(spark_count) * clampf(float(AppState.get_setting("camp_fire")), 0.1, 2.0))), 1)
	if _sparks.amount != want:      # (changing the count restarts the sparks, so only when it changes)
		_sparks.amount = want


## Called every frame: the flare dies back, and the flames, coals and light follow the fire's
## size. The light wavers a little (two slow sine waves, never a strobe; steady in safe mode).
func _run_fire(delta: float) -> void:
	_flare = move_toward(_flare, 0.0, delta * 1.2 / maxf(flare_seconds, 0.1))
	# what is shown eases toward it: fast normally, slowly in safe mode so the light never jumps
	var safe := bool(AppState.get_setting("photosensitive_safe"))
	var target := minf(_flare, SAFE_FLASH_CAP) if safe else _flare
	_flare_shown = move_toward(_flare_shown, target, delta * (0.5 if safe else 6.0))
	var amount := get_fire_amount()
	for m in _fire_mats:
		m.set_shader_parameter("amount", minf(amount, 2.0))
	(_parts["ember_mat"] as StandardMaterial3D).emission_energy_multiplier = 2.2 * minf(amount, 2.0)
	_fire_light.visible = amount > 0.005
	if _fire_light.visible:
		var waver := 1.0
		if fire_flicker > 0.0 and not safe:
			waver += fire_flicker * (0.6 * sin(_time * 5.3) + 0.4 * sin(_time * 8.9 + 1.7))
		var show_dim := lerpf(fire_dimmed, 1.0, clampf(super._target_level(), 0.0, 1.0)) if AppState.is_playback_active() else 1.0
		_fire_light.light_energy = fire_light_energy * amount * show_dim * waver


# ── Time of day and the sky ──────────────────────────────────
## One lamp for the sun and the moon (only one of them lights the camp at a time), and one for
## lightning.
func _build_sun() -> void:
	_sun = DirectionalLight3D.new()
	_sun.name = "SunMoon"
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 70.0
	_sun.light_angular_distance = 1.0
	add_child(_sun)
	_bolt = DirectionalLight3D.new()
	_bolt.name = "Lightning"
	_bolt.light_color = Color(0.75, 0.82, 1.0)
	_bolt.shadow_enabled = false
	_bolt.visible = false
	add_child(_bolt)


## Called every frame. Moves the clock on while "camp_day_minutes" is above 0, and redraws the
## sky and lights when the hour has moved by time_step, the weather has changed enough to
## show, or the app swapped the Environment (a graphics setting changed).
func _run_clock(delta: float) -> void:
	if _retired:
		return
	var day_minutes := float(AppState.get_setting("camp_day_minutes"))
	if day_minutes > 0.0:
		_hour = fposmod(_hour + delta * 24.0 / (day_minutes * 60.0), 24.0)
	var env := get_world_3d().environment if is_inside_tree() else null
	var env_id := env.get_instance_id() if env else 0
	if absf(_hour - _hour_drawn) >= time_step or env_id != _env_drawn or absf(_gloom - _gloom_drawn) > 0.01 or _strike_t >= 0.0:
		_hour_drawn = _hour
		_env_drawn = env_id
		_gloom_drawn = _gloom
		_apply_time(env)


## The hour the room's clock shows now, 0..24 (for tests; "camp_time" only says where it started).
func get_hour() -> float:
	return _hour


## Where the sun is at an hour: a unit vector pointing AT it. It rises in the east (+X), is
## highest at noon and sets in the west, swinging from the south-east to the north-west so the
## sunset is over the lake's left side.
static func sun_at(hour: float) -> Vector3:
	var a := (hour - 6.0) / 12.0 * PI
	return Vector3(cos(a), sin(a), 0.5 * cos(a) - 0.05).normalized()


## Where the moon is: it crosses the northern sky, over the lake, while the sun is down.
static func moon_at(hour: float) -> Vector3:
	var b := (hour - 18.0) / 12.0 * PI
	return Vector3(cos(b) * 0.8, sin(b) * 0.75 + 0.12, -0.62).normalized()


## Everything that follows the hour and the weather (_hour, _gloom, _flash): the sky shader's
## uniforms, the sun / moon lamp, the ambient light and mist, and what the water mirrors.
## env = the Environment in use; it is only touched when it is this room's own (its sky uses
## camp_sky.gdshader), never another room's.
func _apply_time(env: Environment) -> void:
	var sun := sun_at(_hour)
	var moon := moon_at(_hour)
	_day = smoothstep(-0.12, 0.22, sun.y)
	var dusk := (1.0 - smoothstep(0.0, 0.4, absf(sun.y))) * smoothstep(-0.3, -0.05, sun.y)
	var clouds := lerpf(clampf(float(AppState.get_setting("camp_clouds")), 0.0, 2.0), 2.0, _gloom)
	var mist := clampf(float(AppState.get_setting("camp_mist")), 0.0, 1.0)
	var turn := global_basis.orthonormalized()                   # the shaders work in world space
	# the same sky colours camp_sky.gdshader mixes, for the water's mirror and the mist
	var top := Color(0.004, 0.006, 0.02).lerp(Color(0.08, 0.27, 0.72), _day).lerp(Color(0.2, 0.14, 0.4), dusk * 0.45)
	var hor := Color(0.015, 0.02, 0.05).lerp(Color(0.5, 0.68, 0.92), _day).lerp(Color(1.0, 0.42, 0.16), dusk * 0.5)
	var grey := _gloom * clampf(clouds, 0.0, 1.0)
	var lit := 0.12 + 0.88 * _day
	top = top.lerp(Color(0.1, 0.11, 0.13) * lit, grey)
	hor = hor.lerp(Color(0.3, 0.32, 0.35) * lit, grey)
	if clouds > 0.0:        # cloud cover greys what the water mirrors a little, too
		var cover := clampf(clouds * 0.3, 0.0, 0.5) * (1.0 - grey)
		top = top.lerp(Color(0.06, 0.065, 0.11).lerp(Color(0.8, 0.82, 0.86), _day), cover)
	if env and env.sky and env.sky.sky_material is ShaderMaterial and (env.sky.sky_material as ShaderMaterial).shader == SKY_SHADER:
		var sky := env.sky.sky_material as ShaderMaterial
		sky.set_shader_parameter("sun_dir", turn * sun)
		sky.set_shader_parameter("moon_dir", turn * moon)
		sky.set_shader_parameter("day", _day)
		sky.set_shader_parameter("dusk", dusk)
		sky.set_shader_parameter("twinkle", 0.0 if bool(AppState.get_setting("photosensitive_safe")) else 1.0)
		sky.set_shader_parameter("cloud_amount", clouds)
		sky.set_shader_parameter("cloud_speed", 1.0 + 3.5 * _gloom)
		sky.set_shader_parameter("storm", _gloom)
		sky.set_shader_parameter("flash", _flash)
		sky.set_shader_parameter("flash_dir", turn * _strike_dir)
		sky.set_shader_parameter("star_amount", float(AppState.get_setting("camp_stars")))
		sky.set_shader_parameter("aurora_amount", float(AppState.get_setting("camp_aurora")))
		sky.set_shader_parameter("haze", mist)
		var amb := night_ambient.lerp(day_ambient, _day).lerp(Color(0.62, 0.42, 0.48), dusk * 0.35)
		env.ambient_light_color = amb.lerp(Color(0.5, 0.52, 0.56), grey * 0.7)
		env.ambient_light_energy = lerpf(night_ambient_energy, day_ambient_energy, _day) * (1.0 - 0.4 * _gloom) + _flash * 0.5
		env.fog_light_color = hor.lerp(Color(0.6, 0.66, 0.74) * (0.06 + 0.94 * _day), 0.4)
		env.fog_density = 0.0015 + 0.006 * mist + 0.006 * _gloom
	# the sun by day, the moon by night; whichever it is dims under storm cloud
	var light_dir := sun
	var light_col := Color(1.0, 0.55, 0.25).lerp(Color(1.0, 0.96, 0.88), smoothstep(0.05, 0.45, sun.y))
	var energy := sun_energy * smoothstep(0.0, 0.2, sun.y) * (1.0 - 0.75 * _gloom)
	if sun.y <= 0.02:
		light_dir = moon
		light_col = moon_color
		energy = moon_energy * smoothstep(0.05, 0.25, moon.y) * (1.0 - 0.85 * _gloom)
	_sun.light_color = light_col
	_sun.light_energy = energy
	_sun.visible = energy > 0.002
	var world_dir := turn * light_dir
	_sun.global_basis = Basis.looking_at(-world_dir, Vector3.UP if absf(world_dir.y) < 0.99 else Vector3.FORWARD)
	# the water: the sky to mirror, the glitter path's light, the fire's streak
	var glitter := Color(light_col.r, light_col.g, light_col.b) * (energy / maxf(sun_energy, 0.01)) * (2.2 if sun.y > 0.02 else 7.0) * (1.0 - grey)
	var shore := Color(0.03, 0.07, 0.05).lerp(Color(0.003, 0.005, 0.007), 1.0 - _day).lerp(hor, 0.25 * mist)
	var deep := Color(0.012, 0.05, 0.065) * (0.08 + 0.92 * _day)
	var fire_now := get_fire_amount()
	for key: String in ["lake_mat", "stream_mat"]:
		var w := _parts[key] as ShaderMaterial
		w.set_shader_parameter("sky_top", top)
		w.set_shader_parameter("sky_horizon", hor)
		w.set_shader_parameter("shore_color", shore)
		w.set_shader_parameter("deep_color", deep)
		w.set_shader_parameter("light_dir", world_dir)
		w.set_shader_parameter("light_color", Vector3(glitter.r, glitter.g, glitter.b))
		w.set_shader_parameter("fire_pos", (_parts["fire"] as Node3D).global_position + Vector3(0.0, 0.8, 0.0))
		w.set_shader_parameter("fire_color", Vector3(1.0, 0.5, 0.2) * minf(fire_now, 2.0) * (1.0 - 0.6 * _day))
		w.set_shader_parameter("wave", (1.0 if key == "lake_mat" else 2.2) * (1.0 + 1.6 * _gloom))
		w.set_shader_parameter("rain", _rain_now)
		w.set_shader_parameter("flash", _flash)
	_apply_glows()
	if _fireflies:
		var out_tonight := bool(AppState.get_setting("camp_fireflies")) and _day < 0.35 and _rain_now < 0.05
		_fireflies.emitting = out_tonight
		_fireflies.visible = out_tonight or _fireflies.visible and _day < 0.5


# ── Weather ──────────────────────────────────────────────────
## The rain the settings ask for, 0..1: the Rain slider; a thunderstorm brings at least 80%.
func _rain_target() -> float:
	var rain := clampf(float(AppState.get_setting("camp_rain")), 0.0, 1.0)
	return maxf(rain, 0.8) if bool(AppState.get_setting("camp_storm")) else rain


## The storm cloud the settings ask for, 0..1: light rain greys the sky a little, a
## thunderstorm fully.
func _gloom_target() -> float:
	return 1.0 if bool(AppState.get_setting("camp_storm")) else clampf(float(AppState.get_setting("camp_rain")) * 1.2, 0.0, 0.9)


## How much storm cloud there is right now, 0..1 (for tests).
func get_gloom() -> float:
	return _gloom


## How hard it is raining right now, 0..1 (for tests).
func get_rain() -> float:
	return _rain_now


## Called every frame: the weather eases toward the settings over weather_seconds, and
## everything that shows it follows (the sky and water are redrawn by _run_clock).
func _run_weather(delta: float) -> void:
	var step := delta / maxf(weather_seconds, 0.1)
	var rain_before := _rain_now
	_gloom = move_toward(_gloom, _gloom_target(), step)
	_rain_now = move_toward(_rain_now, _rain_target(), step)
	if not is_equal_approx(rain_before, _rain_now):
		_apply_wet()


## The rain right now (_rain_now): how many drops show, how wet everything looks, the wind.
func _apply_wet() -> void:
	_rain.amount_ratio = _rain_now
	_rain.emitting = _rain_now > 0.01
	_rain.visible = _rain_now > 0.01
	for key: String in ["ground_mat", "prop_mat", "tent_mat", "tree_mat"]:
		(_parts[key] as ShaderMaterial).set_shader_parameter("wet", _rain_now)
	(_parts["tree_mat"] as ShaderMaterial).set_shader_parameter("wind", 1.0 + 3.0 * _gloom)


## The rain: streaks falling in a box that follows the camera (_follow_camera), so it rains
## wherever the view is. The Rain slider shows a share of RAIN_DROPS.
func _build_rain() -> void:
	_rain = GPUParticles3D.new()
	_rain.name = "Rain"
	_rain.amount = RAIN_DROPS
	_rain.lifetime = 1.0
	_rain.preprocess = 1.0
	_rain.visibility_aabb = AABB(Vector3(-20.0, -20.0, -20.0), Vector3(40.0, 40.0, 40.0))
	_rain.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY     # streaks along their fall, facing the camera
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(13.0, 0.5, 13.0)
	pm.direction = Vector3(0.12, -1.0, 0.04)
	pm.spread = 2.0
	pm.initial_velocity_min = 15.0
	pm.initial_velocity_max = 19.0
	pm.gravity = Vector3.ZERO
	_rain.process_material = pm
	var streak := QuadMesh.new()
	streak.size = Vector2(0.014, 0.55)
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.albedo_color = Color(0.75, 0.8, 0.9, 0.3)
	sm.cull_mode = BaseMaterial3D.CULL_DISABLED
	streak.material = sm
	_rain.draw_pass_1 = streak
	_rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fx.add_child(_rain)


## Fireflies: slow drifting specks in a ring round the edge of the clearing.
func _build_fireflies() -> void:
	_fireflies = CPUParticles3D.new()
	_fireflies.name = "Fireflies"
	_fireflies.amount = 46
	_fireflies.lifetime = 7.0
	_fireflies.randomness = 1.0
	_fireflies.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	_fireflies.emission_ring_axis = Vector3.UP
	_fireflies.emission_ring_radius = 15.0
	_fireflies.emission_ring_inner_radius = 7.5
	_fireflies.emission_ring_height = 2.2
	_fireflies.direction = Vector3(1.0, 0.2, 0.0)
	_fireflies.spread = 180.0
	_fireflies.gravity = Vector3.ZERO
	_fireflies.initial_velocity_min = 0.08
	_fireflies.initial_velocity_max = 0.3
	var glow := Gradient.new()                        # each one fades in, glows, fades out
	glow.set_color(0, Color(0.0, 0.0, 0.0, 1.0))
	glow.add_point(0.25, Color(0.75, 1.0, 0.3, 1.0))
	glow.add_point(0.6, Color(0.6, 0.9, 0.2, 1.0))
	glow.set_color(glow.get_point_count() - 1, Color(0.0, 0.0, 0.0, 1.0))
	_fireflies.color_ramp = glow
	var speck := QuadMesh.new()
	speck.size = Vector2(0.09, 0.09)
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.vertex_color_use_as_albedo = true
	sm.albedo_color = Color(2.5, 2.5, 2.5)
	sm.albedo_texture = _soft_dot(true)
	sm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	sm.billboard_keep_scale = true
	sm.disable_fog = true           # (fog on a glow that is added to the picture shows as a pale square)
	speck.material = sm
	_fireflies.mesh = speck
	_fireflies.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fireflies.emitting = false
	_fx.add_child(_fireflies)
	_fireflies.position = Vector3(0.0, 1.5, 0.0)


## Keeps the rain's box over the camera.
func _follow_camera() -> void:
	if not _rain.visible:
		return
	var cam := get_viewport().get_camera_3d()
	if cam:
		_rain.global_position = Vector3(cam.global_position.x, cam.global_position.y + 11.0, cam.global_position.z)


## Lightning now, somewhere over the lake or the forest: the clouds and the camp light up, and
## thunder follows a moment later. Called at random in a thunderstorm (_run_lightning); tests and
## anything else may call it too.
func strike() -> void:
	_strike_t = 0.0
	var ang := _rng.randf_range(-PI, PI)
	_strike_dir = Vector3(sin(ang), _rng.randf_range(0.25, 0.6), -absf(cos(ang)) * 0.9 - 0.1).normalized()
	_thunder_wait = _rng.randf_range(0.5, 2.6)        # further away = later (and it is always close enough to hear)
	_bolt.global_basis = Basis.looking_at(-(global_basis.orthonormalized() * _strike_dir), Vector3.UP)


## The lightning's light right now, 0..1 (for tests).
func get_flash() -> float:
	return _flash


## Called every frame: starts strikes while a thunderstorm is on, and plays the current one.
## A normal strike flickers twice within STRIKE_SECONDS, as bright as Flash strength allows; in
## photosensitive-safe mode it is one slow swell over SAFE_STRIKE_SECONDS, capped at SAFE_FLASH_CAP.
func _run_lightning(delta: float) -> void:
	if bool(AppState.get_setting("camp_storm")) and _gloom > 0.6:
		_strike_wait -= delta
		if _strike_wait <= 0.0:
			_strike_wait = _rng.randf_range(STRIKE_GAP.x, STRIKE_GAP.y)
			strike()
	if _thunder_wait >= 0.0:
		_thunder_wait -= delta
		if _thunder_wait < 0.0:
			_thunder = 1.0
			_crack = 1.0
	if _strike_t < 0.0:
		return
	# (the light is worked out for where the strike is now, then the time moves on: so the very
	# first frame of a strike is its brightest, however slowly the frames come)
	var k := clampf(float(AppState.get_setting("flash_strength")), 0.0, 1.0)
	var done := false
	if bool(AppState.get_setting("photosensitive_safe")):
		_flash = minf(k, SAFE_FLASH_CAP) * sin(clampf(_strike_t / SAFE_STRIKE_SECONDS, 0.0, 1.0) * PI)
		done = _strike_t >= SAFE_STRIKE_SECONDS
	else:
		var second := 0.7 * exp(-(_strike_t - 0.22) * 12.0) if _strike_t > 0.22 else 0.0
		_flash = k * maxf(exp(-_strike_t * 9.0), second)
		done = _strike_t >= STRIKE_SECONDS
	_strike_t += delta
	if done:
		_flash = 0.0
		_strike_t = -1.0
		_hour_drawn = -100.0         # one more redraw, with the flash gone
	_bolt.visible = _flash > 0.002
	_bolt.light_energy = strike_energy * _flash


# ── Chat feeding the fire ────────────────────────────────────
## EventBus.reaction_play (Reactions, and NetSession for a co-stream, so it plays on every PC):
## anything thrown at the "campfire" target makes the fire flare when it lands.
func _on_reaction_play(d: Dictionary) -> void:
	if String(d.get("effect", "")) != "throw" or not bool(AppState.get_setting("camp_games")):
		return
	var layer := get_node_or_null("Reactions") as ReactionLayer
	if layer == null:
		return
	var hit := layer.resolve_target(d.get("target"))
	var fire_at := (_parts["fire"] as Node3D).global_position
	if bool(hit.get("fallback", false)) or (hit["pos"] as Vector3).distance_to(fire_at) > 2.0:
		return
	var strength := 0.35 * float(clampi(int(d.get("count", 1)), 1, 3))
	get_tree().create_timer(0.9).timeout.connect(func() -> void:       # about when it lands
		if is_inside_tree() and not _retired:
			flare(strength))


# ── Sound ────────────────────────────────────────────────────
## Called every frame: tops the generator buffer up with the camp's sound: the fire (a soft roar
## with crackles, louder with a bigger fire), the rain's hiss, thunder (a sharp crack, then a long
## low rumble), and crickets on dry nights.
func _fill_ambience() -> void:
	if _amb_playback == null:
		return
	var n := _amb_playback.get_frames_available()
	if n <= 0:
		return
	var fire := minf(get_fire_amount(), 2.0)
	var crickets := cricket_loudness * (1.0 - _day) * (1.0 - clampf(_rain_now * 4.0, 0.0, 1.0))
	var buf := PackedVector2Array()
	buf.resize(n)
	for i in n:
		var w := _rng.randf() * 2.0 - 1.0
		_lp_fire += (w - _lp_fire) * 0.04
		if _rng.randf() < 0.0003 * fire:
			_pop = maxf(_pop, 0.4 + _rng.randf() * 0.6)
		_pop *= 0.992
		var s := (_lp_fire * 1.6 + w * _pop * 0.5) * fire_loudness * fire
		if _rain_now > 0.01:
			_lp_rain += (w - _lp_rain) * 0.3
			s += (w - _lp_rain) * rain_loudness * _rain_now
		if _thunder > 0.001:
			_lp_thunder += (w - _lp_thunder) * 0.012
			s += (_lp_thunder * 6.0 * _thunder + w * _crack * 0.35) * thunder_loudness
			_thunder *= 0.99994
			_crack *= 0.9992
		if crickets > 0.0005:
			# chirps: a high tone switched on and off 28 times a second, in bursts
			_sample += 1
			var t := float(_sample) / MIX_RATE
			if fmod(t, 0.95) < 0.38 and sin(t * 176.0) > 0.0:
				s += sin(t * 27000.0) * crickets
		buf[i] = Vector2(s, s * 0.92)
	_amb_playback.push_buffer(buf)
