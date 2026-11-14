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
##   - The fire ("camp_fire", 0..2): flames (the Forge Hall's fire.gdshader), a flickering
##     light, sparks, smoke, glowing coals and a crackle. flare() makes it leap up for a few
##     seconds: the fire games call it when a stick lands, and so does any chat reaction thrown
##     at the "campfire" target.
##   - The big screen ("camp_screen"): switching it off hides the sheet and everything the app
##     hangs on it (its lights, the curtain, the side chat windows), which opens the view over
##     the lake. The posts stay: the string lights hang from them. The sound keeps playing.
##   - The close woods ("camp_close_woods"): a thick belt of trees right round the clearing and
##     behind the screen that hides the lake, for a camp deep in the forest. Off by default.
##   - Set detail ("camp_detail", each PC's own, not shared): the low-poly set, or the detailed
##     one (photo textures, trees with leaf cards, grass and ferns) near the fire or everywhere.
##     "auto" follows the Graphics quality. See _apply_detail().
##   - String lights and tent lanterns ("camp_string_lights") are the room's house lights; they
##     glow weakly by day and fully at night, and dim for a video like any room's lamps.
##   - Fire games (campfire_games.gd, "camp_games"): hold M to roast a marshmallow on a stick
##     that pokes out of your avatar, press T to toss a stick on the fire.
##   - A generated soundscape on the Ambience bus: the fire, and crickets at night.
## The time, sky and fire settings are shared in a co-stream (NetSession.SHARED_BASE, with the
## host's "room" group), so everyone sits under the same sky.

const Builder := preload("res://rooms/campfire/campfire_builder.gd")
const Games := preload("res://rooms/campfire/campfire_games.gd")
const SKY_SHADER := preload("res://rooms/campfire/camp_sky.gdshader")
const BUTTERFLY_SHADER := preload("res://rooms/campfire/camp_butterfly.gdshader")
const SHAFT_SHADER := preload("res://rooms/campfire/camp_shaft.gdshader")
const MIST_SHADER := preload("res://rooms/campfire/camp_mist.gdshader")
## The sky shader's cloud shapes (three noise fields in r, g, b; textures/make_textures.py).
## Handed to the sky material in _apply_time, as the material lives in room_info.tres.
const SKY_NOISE := preload("res://rooms/campfire/textures/sky_noise.png")
const FIRE_SHADER := preload("res://rooms/forge_hall/fire.gdshader")
const MIX_RATE: float = 22050.0
## The flames: [metres east, metres south, size as a share of flame_size].
const FIRE_FLAMES: Array = [[0.0, 0.0, 1.0], [-0.26, 0.08, 0.7], [0.25, 0.06, 0.76], [-0.1, -0.2, 0.82], [0.12, 0.2, 0.62], [-0.38, -0.08, 0.45], [0.4, -0.05, 0.5]]
## The things the app hangs on the big screen, hidden with it (see _apply_screen).
const SCREEN_PARTS: PackedStringArray = ["ScreenLights", "StageCurtain", "StandbyCard", "SideChats"]
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

@export_group("Sound")
@export var ambience_enabled: bool = true
@export_range(0.0, 1.0) var fire_loudness: float = 0.06
@export_range(0.0, 1.0) var cricket_loudness: float = 0.012

var _parts: Dictionary = {}       # what campfire_builder.gd built (see Builder.build)
## Holds what this script draws (flames, fireflies). Named "SunShafts" so the app doesn't
## count them as the room's own meshes (Room.get_static_meshes).
var _fx: Node3D
var _games: Node3D                # campfire_games.gd
var _sun: DirectionalLight3D      # the sun by day, the moon by night
var _fire_mats: Array[ShaderMaterial] = []
var _fire_meshes: Array[MeshInstance3D] = []
var _fire_light: OmniLight3D
var _sparks: CPUParticles3D
var _burst: CPUParticles3D        # the shower of sparks when the fire flares
var _smoke: CPUParticles3D
var _fireflies: CPUParticles3D
var _butterflies: CPUParticles3D  # out by day (camp_butterflies), as the fireflies are by night
var _shafts: Array[MeshInstance3D] = []   # the sunbeams through the trees (_build_shafts)
var _shaft_mat: ShaderMaterial
var _mist_mat: ShaderMaterial     # the mist sheets on the lake (_build_mist)
var _hour: float = 18.6           # the room's clock, hours 0..24 (starts at "camp_time")
var _hour_drawn: float = -99.0    # the hour the sky was last drawn for
var _env_drawn: int = 0           # instance id of the Environment it was drawn on
var _day: float = 0.0             # 0 = night, 1 = full day (from _apply_time)
var _flare: float = 0.0           # extra fire from a stick, 0..1.2, dying away
var _flare_shown: float = 0.0     # what the flames and light show of it (eased; slower in safe mode)
var _retired: bool = false        # another room has taken over (retire()): leave the sky alone
var _time: float = 0.0
var _last_level: float = -1.0     # the house light level the glows were last set for
var _screen_nodes: Array[Node3D] = []     # the screen's parts, found once the app has added them
# the generated sound
var _amb_playback: AudioStreamGeneratorPlayback
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _lp_fire: float = 0.0         # low-pass state: the fire's roar
var _pop: float = 0.0             # the current crackle, dying away
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
	_build_fireflies()
	_build_butterflies()
	_build_shafts()
	_build_mist()
	_apply_autumn()
	_coal_look()
	_games = Games.new()
	_games.name = "FireGames"
	_fx.add_child(_games)
	_games.setup(self)
	_hour = fposmod(float(AppState.get_setting("camp_time")), 24.0)
	_rng.randomize()
	if ambience_enabled:
		_amb_playback = _start_generated_ambience(MIX_RATE, 0.3)
	EventBus.setting_changed.connect(_on_camp_setting_changed)
	EventBus.room_changed.connect(_on_camp_room_changed)
	EventBus.reaction_play.connect(_on_reaction_play)
	_apply_detail()
	_apply_fire()


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


## Room tab: the fire, the screen, the hour and the sky.
func get_controls() -> Array[Dictionary]:
	return [
		{"heading": "Lakeside Campfire"},
		{"key": "camp_fire", "label": "Fire", "min": 0.0, "max": 2.0, "step": 0.01, "format": "%d%%", "scale": 100.0,
			"tooltip": "How big the campfire is: its flames, the light it throws, its sparks and its crackle. 0% = out."},
		{"key": "camp_screen", "label": "Big screen", "type": "check",
			"tooltip": "On: the big screen hangs between the two posts. Off: the screen is taken down, which opens the view over the lake. The sound of whatever is playing carries on."},
		{"key": "camp_close_woods", "label": "Woods close around the camp", "type": "check",
			"tooltip": "On: thick trees stand right round the clearing, behind the screen and down both sides of the fire, so the lake is hidden and the camp is a cul-de-sac deep in the forest. Off: the open view over the lake."},
		{"key": "camp_detail", "label": "Set detail", "type": "option",
			"options": [["auto", "Auto (follows Graphics quality)"], ["low", "Low-poly"], ["near", "Detailed near the fire"], ["full", "Detailed everywhere"]],
			"tooltip": "How detailed the camp is drawn on this PC. Detailed: photo textures on the ground, bark, rocks and cloth, trees with real leaves and needles (firs, pines, oaks, birches, maples), grass tufts and ferns. Detailed near the fire: the same, but the far hillsides keep their simple trees, which is lighter. Low-poly: the simple flat-coloured set, the lightest. Auto picks from Graphics quality: High = everywhere, Medium = near the fire, Low = low-poly. Each PC in a co-stream chooses its own."},
		{"key": "camp_string_lights", "label": "String lights and lanterns", "type": "check",
			"tooltip": "The string lights between the posts and the lanterns in the tents. They glow softly by day and fully at night, and follow the House lights slider."},
		{"key": "camp_fireflies", "label": "Fireflies at night", "type": "check",
			"tooltip": "Small drifting lights round the edge of the clearing on dry nights."},
		{"key": "camp_butterflies", "label": "Butterflies by day", "type": "check",
			"tooltip": "A few small butterflies flutter over the grass and the flowers while it is light."},
		{"key": "camp_games", "label": "Fire games (M and T keys)", "type": "check",
			"tooltip": "On: hold M in the room window to roast a marshmallow on a stick that pokes out of your avatar, and press T to toss a stick on the fire. In a co-stream everyone sees everyone's. Chat can feed the fire too, by throwing a reaction at the target \"campfire\"."},
		{"heading": "Time of day"},
		{"key": "camp_time", "label": "Time of day", "min": 0.0, "max": 24.0, "step": 0.1, "format": "%.1f h",
			"tooltip": "The hour at the camp, 0 to 24. 6 = sunrise, 12 = noon, 18 = sunset. The sun sets over the lake's left side; at night the moon crosses above the lake."},
		{"key": "camp_day_minutes", "label": "Day length", "min": 0.0, "max": 120.0, "step": 1.0, "format": "%d min", "zero": "Clock stopped",
			"tooltip": "Lets the clock run: how many minutes a full day and night takes, starting from the Time of day. 0 = the clock stands still."},
		{"heading": "Sky"},
		{"key": "camp_clouds", "label": "Clouds", "min": 0.0, "max": 2.0, "step": 0.01, "format": "%d%%", "scale": 100.0,
			"tooltip": "How much cloud drifts across the sky in fair weather. 0% = a clear sky (and the lightest on a slow graphics card), 200% = overcast."},
		{"key": "camp_stars", "label": "Stars", "min": 0.0, "max": 2.0, "step": 0.01, "format": "%d%%", "scale": 100.0,
			"tooltip": "How bright the stars and the Milky Way are at night. 0% = none."},
		{"key": "camp_aurora", "label": "Aurora", "min": 0.0, "max": 2.0, "step": 0.01, "format": "%d%%", "scale": 100.0,
			"tooltip": "Green and violet northern lights over the lake at night. 0% = none (and lighter on a slow graphics card)."},
		{"key": "camp_mist", "label": "Mist", "min": 0.0, "max": 1.0, "step": 0.01, "format": "%d%%", "scale": 100.0,
			"tooltip": "The haze over the lake and between the mountain ridges, and the mist lying on the water (thickest at dawn and dusk)."},
		{"key": "sun_rays", "label": "Light rays", "min": 0.0, "max": 2.0, "step": 0.01, "format": "%d%%", "scale": 100.0,
			"tooltip": "How visible the sunbeams through the trees are while the sun is low (morning and evening). 0% = off."},
		{"heading": "Season"},
		{"key": "camp_autumn", "label": "Autumn colours", "type": "check",
			"tooltip": "On: the birches turn yellow, the maples red and orange and the oaks russet. The firs and pines stay green. Shared in a co-stream."},
	]


func _on_camp_setting_changed(key: String, _value: Variant) -> void:
	match key:
		"camp_fire":
			_apply_fire()
		"camp_time":
			_hour = fposmod(float(AppState.get_setting("camp_time")), 24.0)
		"camp_autumn":
			_apply_autumn()
		"camp_clouds", "camp_stars", "camp_aurora", "camp_mist", "camp_string_lights", "sun_rays", "photosensitive_safe":
			_hour_drawn = -100.0        # _run_clock redraws the sky and lights next frame
		"camp_screen":
			_apply_screen()
		"camp_close_woods", "camp_detail", "graphics_quality":
			_apply_detail()


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
	_run_clock(delta)
	_run_fire(delta)
	if not is_equal_approx(_level, _last_level):
		_last_level = _level
		_apply_glows()
	_keep_screen_hidden()
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


## The look the set is drawn in on this PC: "low" (the low-poly set), "near" (detailed, but the
## far forest stays low-poly) or "full" (detailed everywhere). From "camp_detail" (Room tab >
## Set detail, each PC's own); its "auto" follows "graphics_quality": low = "low",
## medium = "near", high and custom = "full".
func detail_level() -> String:
	var choice := String(AppState.get_setting("camp_detail"))
	if choice in ["low", "near", "full"]:
		return choice
	match String(AppState.get_setting("graphics_quality")):
		"low":
			return "low"
		"medium":
			return "near"
	return "full"


## Shows the right lot of every group of plants and switches the photo textures on or off.
## Called once when the room loads and whenever "camp_detail", "graphics_quality" or
## "camp_close_woods" changes. campfire_builder.gd built both lots of everything, hidden or
## not; nothing is built or loaded here, so switching is instant.
##   the far forest: low-poly unless the level is "full"
##   the near forest: low-poly only at "low"
##   the close woods ("camp_close_woods": thick trees round the clearing and behind the
##     screen): hidden while the setting is off, else low-poly at "low" and detailed otherwise
##   grass tufts and ferns: only with the detailed looks
func _apply_detail() -> void:
	var level := detail_level()
	var detailed := level != "low"
	var woods := bool(AppState.get_setting("camp_close_woods"))
	for n: Node3D in _parts["lowpoly_far"]:
		n.visible = level != "full"
	for n: Node3D in _parts["lowpoly_near"]:
		n.visible = not detailed
	for n: Node3D in _parts["close_woods"]:
		n.visible = woods and not detailed
	(_parts["detail_far"] as Node3D).visible = level == "full"
	(_parts["detail_near"] as Node3D).visible = detailed
	(_parts["close_woods_detail"] as Node3D).visible = woods and detailed
	(_parts["undergrowth"] as Node3D).visible = detailed
	for m: ShaderMaterial in _parts["detail_mats"]:
		m.set_shader_parameter("detail", 1.0 if detailed else 0.0)


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


## How big the fire burns right now, 0..2.4: the Fire slider plus a flare. The fire games read it too (a bigger fire toasts faster).
func get_fire_amount() -> float:
	var set_to := clampf(float(AppState.get_setting("camp_fire")), 0.0, 2.0)
	if set_to <= 0.005:
		return 0.0
	return set_to + _flare_shown * 0.9


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
## One lamp for the sun and the moon (only one of them lights the camp at a time).
func _build_sun() -> void:
	_sun = DirectionalLight3D.new()
	_sun.name = "SunMoon"
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 70.0
	_sun.light_angular_distance = 1.0
	add_child(_sun)


## Called every frame. Moves the clock on while "camp_day_minutes" is above 0, and redraws the
## sky and lights when the hour has moved by time_step or the app swapped the Environment (a graphics setting changed).
func _run_clock(delta: float) -> void:
	if _retired:
		return
	var day_minutes := float(AppState.get_setting("camp_day_minutes"))
	if day_minutes > 0.0:
		_hour = fposmod(_hour + delta * 24.0 / (day_minutes * 60.0), 24.0)
	var env := get_world_3d().environment if is_inside_tree() else null
	var env_id := env.get_instance_id() if env else 0
	if absf(_hour - _hour_drawn) >= time_step or env_id != _env_drawn:
		_hour_drawn = _hour
		_env_drawn = env_id
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


## Everything that follows the hour (_hour): the sky shader's
## uniforms, the sun / moon lamp, the ambient light and mist, and what the water mirrors.
## env = the Environment in use; it is only touched when it is this room's own (its sky uses
## camp_sky.gdshader), never another room's.
func _apply_time(env: Environment) -> void:
	var sun := sun_at(_hour)
	var moon := moon_at(_hour)
	_day = smoothstep(-0.12, 0.22, sun.y)
	var dusk := (1.0 - smoothstep(0.0, 0.4, absf(sun.y))) * smoothstep(-0.3, -0.05, sun.y)
	var clouds := clampf(float(AppState.get_setting("camp_clouds")), 0.0, 2.0)
	var mist := clampf(float(AppState.get_setting("camp_mist")), 0.0, 1.0)
	var turn := global_basis.orthonormalized()                   # the shaders work in world space
	# the same sky colours camp_sky.gdshader mixes, for the water's mirror and the mist
	var top := Color(0.004, 0.006, 0.02).lerp(Color(0.08, 0.27, 0.72), _day).lerp(Color(0.34, 0.27, 0.6), dusk * 0.6)
	var hor := Color(0.015, 0.02, 0.05).lerp(Color(0.5, 0.68, 0.92), _day).lerp(Color(0.92, 0.5, 0.38), dusk * 0.6)
	if clouds > 0.0:        # cloud cover greys what the water mirrors a little, too
		var cover := clampf(clouds * 0.3, 0.0, 0.5)
		top = top.lerp(Color(0.06, 0.065, 0.11).lerp(Color(0.8, 0.82, 0.86), _day), cover)
	if env and env.sky and env.sky.sky_material is ShaderMaterial and (env.sky.sky_material as ShaderMaterial).shader == SKY_SHADER:
		var sky := env.sky.sky_material as ShaderMaterial
		sky.set_shader_parameter("cloud_noise", SKY_NOISE)
		sky.set_shader_parameter("sun_dir", turn * sun)
		sky.set_shader_parameter("moon_dir", turn * moon)
		sky.set_shader_parameter("day", _day)
		sky.set_shader_parameter("dusk", dusk)
		sky.set_shader_parameter("twinkle", 0.0 if bool(AppState.get_setting("photosensitive_safe")) else 1.0)
		sky.set_shader_parameter("cloud_amount", clouds)
		sky.set_shader_parameter("star_amount", float(AppState.get_setting("camp_stars")))
		sky.set_shader_parameter("aurora_amount", float(AppState.get_setting("camp_aurora")))
		sky.set_shader_parameter("haze", mist)
		var amb := night_ambient.lerp(day_ambient, _day).lerp(Color(0.62, 0.42, 0.48), dusk * 0.35)
		env.ambient_light_color = amb
		env.ambient_light_energy = lerpf(night_ambient_energy, day_ambient_energy, _day)
		env.fog_light_color = hor.lerp(Color(0.6, 0.66, 0.74) * (0.06 + 0.94 * _day), 0.4)
		env.fog_density = 0.0015 + 0.006 * mist
	# the sun by day, the moon by night
	var light_dir := sun
	var light_col := Color(1.0, 0.55, 0.25).lerp(Color(1.0, 0.96, 0.88), smoothstep(0.05, 0.45, sun.y))
	var energy := sun_energy * smoothstep(0.0, 0.2, sun.y)
	if sun.y <= 0.02:
		light_dir = moon
		light_col = moon_color
		energy = moon_energy * smoothstep(0.05, 0.25, moon.y)
	_sun.light_color = light_col
	_sun.light_energy = energy
	_sun.visible = energy > 0.002
	var world_dir := turn * light_dir
	_sun.global_basis = Basis.looking_at(-world_dir, Vector3.UP if absf(world_dir.y) < 0.99 else Vector3.FORWARD)
	# the water: the sky to mirror, the glitter path's light, the fire's streak
	var glitter := Color(light_col.r, light_col.g, light_col.b) * (energy / maxf(sun_energy, 0.01)) * (2.2 if sun.y > 0.02 else 7.0)
	var shore := Color(0.03, 0.07, 0.05).lerp(Color(0.003, 0.005, 0.007), 1.0 - _day).lerp(hor, 0.25 * mist)
	var deep := Color(0.012, 0.05, 0.065) * (0.08 + 0.92 * _day)
	var fire_now := get_fire_amount()
	var lake := _parts["lake_mat"] as ShaderMaterial
	lake.set_shader_parameter("shore_color", shore)
	lake.set_shader_parameter("deep_color", deep)
	lake.set_shader_parameter("fire_pos", (_parts["fire"] as Node3D).global_position + Vector3(0.0, 0.8, 0.0))
	lake.set_shader_parameter("fire_color", Vector3(1.0, 0.5, 0.2) * minf(fire_now, 2.0) * (1.0 - 0.6 * _day))
	# (the stream has its own shader, camp_stream.gdshader: it only needs the sky and the light)
	(_parts["stream_mat"] as ShaderMaterial).set_shader_parameter("daylight", 0.08 + 0.92 * _day)
	for key: String in ["lake_mat", "stream_mat"]:
		var w := _parts[key] as ShaderMaterial
		w.set_shader_parameter("sky_top", top)
		w.set_shader_parameter("sky_horizon", hor)
		w.set_shader_parameter("light_dir", world_dir)
		w.set_shader_parameter("light_color", Vector3(glitter.r, glitter.g, glitter.b))
	_apply_glows()
	_apply_shafts(turn * sun, light_col)
	if _mist_mat:
		# the mist on the lake: a little all day, most at dawn and dusk and through the night
		_mist_mat.set_shader_parameter("amount", mist * clampf(0.2 + 0.8 * maxf(dusk, 0.7 * (1.0 - _day)), 0.0, 1.0))
		_mist_mat.set_shader_parameter("color", hor.lerp(Color(0.75, 0.8, 0.86) * (0.08 + 0.92 * _day), 0.5))
	if _fireflies:
		var out_tonight := bool(AppState.get_setting("camp_fireflies")) and _day < 0.35
		_fireflies.emitting = out_tonight
		_fireflies.visible = out_tonight or _fireflies.visible and _day < 0.5
	if _butterflies:
		# out while it is light; at dusk the last ones finish their flight and no new ones come
		var out_today := bool(AppState.get_setting("camp_butterflies")) and _day > 0.55
		_butterflies.emitting = out_today
		_butterflies.visible = out_today or _butterflies.visible and _day > 0.35


# ── Fireflies ────────────────────────────────────────────────
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


# ── Sunbeams, mist, autumn ───────────────────────────────────
## Sunbeams: ten long flat strips (camp_shaft.gdshader) that _apply_shafts lays along the
## sun's direction among the trees on the sun's side of the clearing. They only show while
## the sun is low; the "sun_rays" slider (Light rays, shared with the Lecture and Forge Halls)
## scales them.
func _build_shafts() -> void:
	_shaft_mat = ShaderMaterial.new()
	_shaft_mat.shader = SHAFT_SHADER
	var holder := Node3D.new()
	holder.name = "Shafts"
	_fx.add_child(holder)
	for i in 10:
		var strip := QuadMesh.new()
		strip.size = Vector2(1.4 + 0.5 * float(i % 3), 22.0)
		var mi := MeshInstance3D.new()
		mi.mesh = strip
		mi.material_override = _shaft_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		holder.add_child(mi)
		_shafts.append(mi)


## Called by _apply_time with where the sun is (a unit vector pointing at it, in the room's
## own turn) and its colour. The beams stand in a fan on the sun's side, 9 to 17 m from the
## fire, each running from the ground up towards the sun. Strongest with the sun 5 to 20
## degrees up; none at noon or at night.
func _apply_shafts(sun: Vector3, sun_col: Color) -> void:
	var low := smoothstep(0.03, 0.12, sun.y) * smoothstep(0.5, 0.25, sun.y)
	var strength := low * float(AppState.get_setting("sun_rays")) * 0.16
	for i in _shafts.size():
		var mi := _shafts[i]
		mi.visible = strength > 0.002
		if not mi.visible:
			continue
		var az := atan2(sun.z, sun.x) + (float(i) - 4.5) * 0.2
		var reach := 9.0 + 8.0 * fposmod(float(i) * 0.37, 1.0)
		var foot := Vector3(cos(az) * reach * 1.25, 0.0, sin(az) * reach)
		# the strip's long side follows the sun; its flat side is turned to the camp
		var across := sun.cross(Vector3(-foot.x, 0.0, -foot.z).normalized()).normalized()
		mi.global_transform = Transform3D(Basis(across, sun, across.cross(sun)), global_position + foot + sun * 10.5)
	if _shaft_mat:
		_shaft_mat.set_shader_parameter("color", Color(sun_col.r, sun_col.g, sun_col.b) * strength)


## Mist on the lake: three big flat sheets just above the water (camp_mist.gdshader), one over
## another. _apply_time sets how thick it is (the Mist slider, most at dawn and dusk).
func _build_mist() -> void:
	_mist_mat = ShaderMaterial.new()
	_mist_mat.shader = MIST_SHADER
	_mist_mat.set_shader_parameter("noise", SKY_NOISE)
	var holder := Node3D.new()
	holder.name = "Mist"
	_fx.add_child(holder)
	for i in 3:
		var sheet := PlaneMesh.new()
		sheet.size = Vector2(170.0, 80.0)
		var mi := MeshInstance3D.new()
		mi.mesh = sheet
		mi.material_override = _mist_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(mi)
		mi.position = Vector3(0.0, Builder.WATER_Y + 0.3 + 0.5 * float(i), -52.0)


## Autumn ("camp_autumn", Room tab > Autumn colours; shared in a co-stream): the leafy trees
## change colour, the firs and pines stay green. The detailed trees do it in their leaf
## materials (camp_foliage.gdshader `autumn`, with a colour range per species); the low-poly
## round trees get their MultiMesh colours multiplied (their first, summer colours are kept in
## the node's "summer" metadata so switching back is exact).
func _apply_autumn() -> void:
	var on := bool(AppState.get_setting("camp_autumn"))
	var mats: Dictionary = _parts.get("plant_mats", {})
	# [leaf material, the two ends of its autumn colour range]
	for row: Array in [["leaves", Color(0.62, 0.36, 0.1), Color(0.5, 0.2, 0.07)], ["leaves_birch", Color(0.95, 0.74, 0.1), Color(0.9, 0.58, 0.08)],
			["leaves_maple", Color(0.9, 0.42, 0.06), Color(0.72, 0.1, 0.05)]]:
		var m := mats.get(row[0]) as ShaderMaterial
		if m:
			m.set_shader_parameter("autumn", 1.0 if on else 0.0)
			m.set_shader_parameter("fall_a", row[1])
			m.set_shader_parameter("fall_b", row[2])
	var turns: Array[Color] = [Color(3.2, 0.75, 0.3), Color(3.2, 1.25, 0.3), Color(3.0, 0.45, 0.3)]      # x green = orange, yellow, red
	for list_key: String in ["lowpoly_far", "lowpoly_near", "close_woods"]:
		for n: Node3D in _parts.get(list_key, []):
			var mmi := n as MultiMeshInstance3D
			if mmi == null or not String(mmi.name).contains("Round"):
				continue
			var mm := mmi.multimesh
			if not mmi.has_meta("summer"):
				var first := PackedColorArray()
				for i in mm.instance_count:
					first.append(mm.get_instance_color(i))
				mmi.set_meta("summer", first)
			var summer: PackedColorArray = mmi.get_meta("summer")
			for i in mm.instance_count:
				mm.set_instance_color(i, summer[i] * turns[i % 3] if on else summer[i])


# ── Butterflies ──────────────────────────────────────────────
## Butterflies: a few small ones wandering low over the grass round the clearing by day
## (setting camp_butterflies; _apply_time switches them with the daylight). Each is one small
## square drawn by camp_butterfly.gdshader, which cuts it to two wings and makes them beat.
func _build_butterflies() -> void:
	_butterflies = CPUParticles3D.new()
	_butterflies.name = "Butterflies"
	_butterflies.amount = 16
	_butterflies.lifetime = 14.0
	_butterflies.randomness = 1.0
	_butterflies.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	_butterflies.emission_ring_axis = Vector3.UP
	_butterflies.emission_ring_radius = 14.0
	_butterflies.emission_ring_inner_radius = 3.5
	_butterflies.emission_ring_height = 0.9
	_butterflies.direction = Vector3(1.0, 0.0, 0.0)
	_butterflies.spread = 180.0
	_butterflies.flatness = 0.8                       # they wander sideways more than up and down
	_butterflies.gravity = Vector3.ZERO
	_butterflies.initial_velocity_min = 0.25
	_butterflies.initial_velocity_max = 0.7
	_butterflies.tangential_accel_min = -0.25         # a curving path round the fire, either way
	_butterflies.tangential_accel_max = 0.25
	var fade := Gradient.new()                        # alpha only: each one fades in and out
	fade.set_color(0, Color(1.0, 1.0, 1.0, 0.0))
	fade.add_point(0.08, Color(1.0, 1.0, 1.0, 1.0))
	fade.add_point(0.92, Color(1.0, 1.0, 1.0, 1.0))
	fade.set_color(fade.get_point_count() - 1, Color(1.0, 1.0, 1.0, 0.0))
	_butterflies.color_ramp = fade
	var kinds := Gradient.new()                       # each one takes a colour from along this
	kinds.set_color(0, Color(0.98, 0.85, 0.25))
	kinds.add_point(0.35, Color(0.95, 0.95, 0.9))
	kinds.add_point(0.7, Color(0.95, 0.55, 0.15))
	kinds.set_color(kinds.get_point_count() - 1, Color(0.45, 0.6, 0.95))
	_butterflies.color_initial_ramp = kinds
	var wing := QuadMesh.new()
	wing.size = Vector2(0.13, 0.1)
	var wm := ShaderMaterial.new()
	wm.shader = BUTTERFLY_SHADER
	wing.material = wm
	_butterflies.mesh = wing
	_butterflies.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_butterflies.emitting = false
	_fx.add_child(_butterflies)
	_butterflies.position = Vector3(0.0, 0.75, 0.0)


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
## with crackles, louder with a bigger fire) and crickets at night.
func _fill_ambience() -> void:
	if _amb_playback == null:
		return
	var n := _amb_playback.get_frames_available()
	if n <= 0:
		return
	var fire := minf(get_fire_amount(), 2.0)
	var crickets := cricket_loudness * (1.0 - _day)
	var buf := PackedVector2Array()
	buf.resize(n)
	for i in n:
		var w := _rng.randf() * 2.0 - 1.0
		_lp_fire += (w - _lp_fire) * 0.04
		if _rng.randf() < 0.0003 * fire:
			_pop = maxf(_pop, 0.4 + _rng.randf() * 0.6)
		_pop *= 0.992
		var s := (_lp_fire * 1.6 + w * _pop * 0.5) * fire_loudness * fire
		if crickets > 0.0005:
			# chirps: a high tone switched on and off 28 times a second, in bursts
			_sample += 1
			var t := float(_sample) / MIX_RATE
			if fmod(t, 0.95) < 0.38 and sin(t * 176.0) > 0.0:
				s += sin(t * 27000.0) * crickets
		buf[i] = Vector2(s, s * 0.92)
	_amb_playback.push_buffer(buf)
