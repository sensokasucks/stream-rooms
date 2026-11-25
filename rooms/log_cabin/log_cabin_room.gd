extends Room
## Log Cabin: a cozy cabin with a vaulted great room. A stone chimney stands in the middle of a
## two-storey glass wall, with the big screen above the mantel, so every seat sees the fire, the
## screen and the view outside at once. A loft runs across the back; a deck lies beyond the glass.
##   - The plan (weather, the four outdoor scenes as their own rooms) is in Sen's "Log Cabin room
##     plan" doc; mockups and screenshots are in the project files (log-cabin/).
##   - The set is built in code by cabin_builder.gd when the room loads (there is no Blender
##     model). This script keeps what it hands back and runs the fire, the lamps, the clock and
##     the sky, the chimney smoke and the Set detail switch.
##   - Fire ("cabin_fire", 0..2): flames in the firebox (the Forge Hall's fire.gdshader), glowing
##     coals (cabin_embers.gdshader), a flickering light that warms the room and smoke from both
##     chimneys.
##   - Lamps ("cabin_lamps"): the table lamps, chandelier, dining pendant and back-door lantern
##     are the room's house lights (LAMP_ markers); they dim for a video like any room's, and burn
##     low by day. Their shades glow with them (cabin_shade.gdshader).
##   - Time of day ("cabin_time", hours; "cabin_day_minutes" lets the clock run), Clouds and Stars
##     ("cabin_clouds", "cabin_stars"): the Lakeside Campfire's sky (camp_sky.gdshader, set in
##     room_info.tres) with the same sun and moon paths, the sun / moon lamp and the ambient light
##     (_apply_time, ported from the Drive-In's).
##   - Weather ("cabin_weather" clear / cloudy / rain / storm / snow, "cabin_fog", "cabin_wind",
##     "cabin_snow" for snow on the ground, and "cabin_weather_fx", each PC's own amount of rain
##     and snow drawn): the shared weather module, rooms/weather/room_weather.gd. It makes the
##     rain, snow, lightning, wet and frosty glass, wet and snowy surfaces outside, fog, the wind in
##     the trees and the sound (rain on the roof, wind, thunder, the fire's crackle); this script
##     makes it (_build_weather), runs it every frame and lets it adjust the sky in _apply_time.
##   - Gather in ("cabin_view": great_room / den): where the presenters sit. "den" puts them on
##     the den's sofa and armchair (Sen's den picture), makes the den's screen the main one and
##     its cameras the first ones. The set is built for one view, so this setting reloads the
##     room (reload_keys); the great room's screen then mirrors the den's.
##   - Set detail ("cabin_detail", each PC's own, never shared): Simple = flat vertex colours and
##     plain cone trees; Detailed = the CC0 photo textures (textures/, from make_textures.py) with
##     their bumps, leaf-card trees, ferns and grass round the clearing (the campfire's), and a
##     reflection probe so the glass and the polished wood show the warm room at night.
##   - Scene (`scene`, set in each room's .tscn): what is built round the cabin. "clearing" = the
##     plain clearing of the Log Cabin room (cabin_builder.gd _build_clearing); "forest" = Cabin:
##     Appalachian Forest (rooms/cabin_forest/, cabin_forest.gd: the valley, the creek, the
##     hardwoods and hemlocks; the sky draws layered blue ridges). The forest adds Season
##     ("cabin_season" summer / autumn: the leaves, the forest floor and the far treetops turn)
##     and fireflies on clear summer nights. "lake" = Cabin: Lakeside (rooms/cabin_lake/,
##     cabin_lake.gd: a lawn down to a beach and a lake, pines, firs and birches, a dock, a canoe,
##     reeds and lily pads; the sky keeps its own mountains, which the lake mirrors). The lake
##     has Season and fireflies too, and loons calling now and then (_run_loons). "ocean" =
##     Cabin: Ocean (rooms/cabin_ocean/, cabin_ocean.gd: a grassy bluff over a beach and the open
##     sea, rolling surf, wind-bent pines, driftwood, a lighthouse on an islet; the sky draws a
##     flat sea horizon, `open_sea`). It adds the surf's sound, gulls (seen and heard by day), the
##     lighthouse's turning beams at dusk, at night and in fog, and a foghorn in heavy fog
##     (_apply_ocean, _run_ocean). No Season or fireflies on the windy coast. "north" = Cabin:
##     Frozen North (rooms/cabin_north/, cabin_north.gd: deep snow, a frozen lake with
##     wind-polished ice, spruces, snowshoes by the door, a sled; the sky keeps its own low
##     mountains). Snow on the ground never drops below cabin_north.gd's SNOW_FLOOR there (the
##     weather's snow_floor), so the frost on the glass and trees comes with it; the aurora
##     ("cabin_aurora", only on this room's Room tab) hangs over the ice on clear nights; the ice
##     creaks and booms now and then (_run_ice). No Season or fireflies.
## All cabin_ settings but cabin_detail are shared in a co-stream (NetSession.SHARED_CABIN, with the
## "room" group).

const Builder := preload("res://rooms/log_cabin/cabin_builder.gd")
const Forest := preload("res://rooms/log_cabin/cabin_forest.gd")
const Lake := preload("res://rooms/log_cabin/cabin_lake.gd")
const Ocean := preload("res://rooms/log_cabin/cabin_ocean.gd")
const North := preload("res://rooms/log_cabin/cabin_north.gd")
## The gulls' call (public domain, the US National Park Service's Sound Gallery; sounds/README.md).
const GULL := preload("res://rooms/log_cabin/sounds/gull_1.ogg")
## The surf's generated sound: its mix rate, and seconds between one breaking wave and the next
## (the same as cabin_surf.gdshader's `period`).
const SURF_RATE: float = 22050.0
const SURF_PERIOD: float = 8.0
## How long one turn of the lighthouse's beams takes (seconds).
const BEAM_TURN: float = 16.0
## The loons' calls (public domain, Yellowstone National Park's sound library; sounds/README.md).
const LOONS: Array[AudioStream] = [preload("res://rooms/log_cabin/sounds/loon_1.ogg"),
	preload("res://rooms/log_cabin/sounds/loon_2.ogg"), preload("res://rooms/log_cabin/sounds/loon_3.ogg")]
const FIRE_SHADER := preload("res://rooms/forge_hall/fire.gdshader")
## The flames of each fire: [metres sideways, metres out into the room (+) / into the firebox (-),
## size as a share of flame_size], in the fire marker's own axes (the den's fire faces +X).
const FIRE_FLAMES: Array = [[0.0, 0.0, 1.0], [-0.22, 0.05, 0.75], [0.24, 0.04, 0.7], [-0.1, -0.08, 0.6], [0.12, -0.06, 0.55]]
const SKY_SHADER := preload("res://rooms/campfire/camp_sky.gdshader")
## The Season setting's tooltip in each scene room.
const SEASON_TIPS: Dictionary = {
	"forest": "The forest's season. Summer: green leaves, and fireflies on clear nights. Autumn: the oaks, maples, poplars and birches turn orange, red and gold, the forest floor turns brown and the far slopes go copper. The hemlocks stay green.",
	"lake": "The lake's season. Summer: green leaves, and fireflies on clear nights. Autumn: the birches turn gold and the pine needles go brown. The pines and firs stay green.",
}
const Weather := preload("res://rooms/weather/room_weather.gd")
const CAMP_TEX := "res://rooms/campfire/textures/"
## The den's fire next to the big one: share of the light's energy and range.
const DEN_FIRE_SHARE: float = 0.55

## What is built round the cabin: "clearing" (the Log Cabin), "forest" (Cabin: Appalachian
## Forest), "lake" (Cabin: Lakeside), "ocean" (Cabin: Ocean) or "north" (Cabin: Frozen North).
## Each scene room's .tscn sets it.
@export_enum("clearing", "forest", "lake", "ocean", "north") var scene: String = "clearing"

@export_group("Fire")
## The tallest flame: width and height in metres at Fire 100%.
@export var flame_size: Vector2 = Vector2(0.55, 0.75)
## The light the fire throws: energy at Fire 100%, range in metres, colour. The den's smaller fire
## gets DEN_FIRE_SHARE of the energy and range (its light has no shadows, so a short range keeps
## it from shining through the log wall into the great room).
@export var fire_light_energy: float = 3.0
@export var fire_light_range: float = 9.5
@export var fire_light_color: Color = Color(1.0, 0.52, 0.2)
## How much the fire's light wavers (share of its energy). 0 = steady.
@export_range(0.0, 0.3) var fire_flicker: float = 0.12
## The fire's light drops to this share while the lights are dimmed for a video.
@export_range(0.0, 1.0) var fire_dimmed: float = 0.5
## Puffs of smoke rising from each chimney at Fire 100% (more when roaring, none when out).
@export var smoke_puffs: int = 18

@export_group("Sun and sky")
## The sun's and the moon's light (the moon's is a cool blue).
@export var sun_energy: float = 1.2
@export var moon_energy: float = 0.14
@export var moon_color: Color = Color(0.62, 0.7, 0.95)
## The ambient light by day and by night. Kept low: the cabin is meant to be lit by the fire and
## the lamps, with the daylight coming in through the glass.
@export var day_ambient: Color = Color(0.62, 0.66, 0.74)
@export var day_ambient_energy: float = 0.45
@export var night_ambient: Color = Color(0.12, 0.13, 0.22)
@export var night_ambient_energy: float = 0.16
## How strong the lamps burn by full day (share of full); they come up as it gets dark.
@export_range(0.0, 1.0) var lamps_by_day: float = 0.35
## The sky and lights are redrawn when the clock has moved this many hours.
@export var time_step: float = 0.02

var _parts: Dictionary = {}       # what cabin_builder.gd built (see Builder.build)
## Holds what this script draws (the flames). Named "SunShafts" so the app doesn't count them
## as the room's own meshes (Room.get_static_meshes).
var _fx: Node3D
var _sun: DirectionalLight3D      # the sun by day and at dusk, the moon at night
var _fire_mats: Array[ShaderMaterial] = []
var _fire_meshes: Array[MeshInstance3D] = []
var _fire_lights: Array[OmniLight3D] = []   # one per fire, in the order of _parts["fires"]
var _fire_strength: Array[float] = []       # each light's share of fire_light_energy
var _smoke: Array[CPUParticles3D] = []   # one per chimney (Builder's smoke_spots)
var _smoke_mat: StandardMaterial3D        # the puffs' material, tinted by the daylight
var _fireflies: CPUParticles3D            # the scene's fireflies on clear summer nights (null in the clearing)
var _loon_player: AudioStreamPlayer       # the lake's loons (null in the other scenes)
var _loon_wait: float = 8.0               # seconds until the loons may call again
# the coast (Cabin: Ocean only)
var _surf_pb: AudioStreamGeneratorPlayback   # the surf's generated sound
var _surf_t: float = 0.0                  # the surf sound's own clock (seconds)
var _surf_lp: float = 0.0                 # its noise, low-passed (the roar) ...
var _surf_lp2: float = 0.0                # ... and less so (the hiss of the wash)
var _surf_rng := RandomNumberGenerator.new()
var _gull_player: AudioStreamPlayer
var _gull_wait: float = 6.0               # seconds until the gulls may call again
var _horn_player: AudioStreamPlayer       # the foghorn (a generated tone)
var _horn_wait: float = 4.0               # seconds until the next blast while the fog is heavy
var horn_blasts: int = 0                  # how many times the foghorn has sounded (for tests)
var _gull_paths: Array[Vector4] = []      # per gull: centre x, centre z, radius, speed (radians a second)
# the frozen lake (Cabin: Frozen North only)
var _ice_player: AudioStreamPlayer        # the ice's creaks and booms (generated sounds)
var _ice_sounds: Array[AudioStreamWAV] = []
var _ice_wait: float = 10.0               # seconds until the ice may sound again
var ice_calls: int = 0                    # how many times the ice has sounded (for tests)
## Catches the lit room once (and again when the light changes a lot) so the glass and polished
## surfaces reflect the warm inside instead of the sky. Detailed look only.
var _probe: ReflectionProbe
var _probe_day: float = -1.0      # the daylight the probe last caught the room in
var _hour: float = 17.5           # the room's clock, hours 0..24 (starts at "cabin_time")
var _hour_drawn: float = -99.0    # the hour the sky was last drawn for
var _day: float = 0.0             # 0 = night, 1 = full day (from _apply_time)
var _env_drawn: int = 0           # instance id of the Environment the sky was last drawn on
var _weather: Weather             # the shared weather (rooms/weather/room_weather.gd)
var _retired: bool = false        # another room has taken over (retire()): leave the sky alone
var _time: float = 0.0
var _last_level: float = -1.0     # the house light level the lamp glow was last set for
var _last_probe_level: float = -1.0   # the house light level a frame ago (the probe waits for it to settle)


func _ready() -> void:
	# first of all: Room._ready() and RoomHost read the set's markers straight away
	var view := String(AppState.get_setting("cabin_view"))
	if scene == "forest":
		_parts = Forest.build(self, view)
	elif scene == "lake":
		_parts = Lake.build(self, view)
	elif scene == "ocean":
		_parts = Ocean.build(self, view)
	elif scene == "north":
		_parts = North.build(self, view)
	else:
		_parts = Builder.build(self, view)
	super._ready()
	_fx = Node3D.new()
	_fx.name = "SunShafts"
	add_child(_fx)
	_sun = DirectionalLight3D.new()
	_sun.name = "SunMoon"
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 60.0
	add_child(_sun)
	# pools of light, not a flat wash: the lamps (Room made them from the LAMP_ markers with the
	# scene's lamp_energy / lamp_range) fall off faster than Room's default
	for l in find_child("LIGHTS_House", false, false).find_children("*", "OmniLight3D", true, false):
		(l as OmniLight3D).omni_attenuation = 1.9
	_build_fire()
	_build_smoke()
	_build_probe()
	_build_weather()
	if scene in ["forest", "lake"]:
		_build_fireflies()
		_apply_season()
	if scene == "ocean":
		_build_coast_sounds()
	if scene == "north":
		_build_ice_sounds()
	if scene == "lake":
		_loon_player = AudioStreamPlayer.new()
		_loon_player.name = "Loons"
		_loon_player.bus = AudioManager.AMBIENCE_BUS
		add_child(_loon_player)
	_hour = fposmod(float(AppState.get_setting("cabin_time")), 24.0)
	EventBus.setting_changed.connect(_on_cabin_setting_changed)
	_apply_detail()
	_apply_fire()


## The room is freed on a room swap: drop the EventBus connection with it.
func _exit_tree() -> void:
	if EventBus.setting_changed.is_connected(_on_cabin_setting_changed):
		EventBus.setting_changed.disconnect(_on_cabin_setting_changed)


## RoomHost calls this (through propagate_call) when another room replaces this one, three
## seconds before it is freed: stop touching the sky, which is the new room's now.
func retire() -> void:
	_retired = true
	_exit_tree()


## Room tab: the set's detail, the fire, the lamps, where everyone gathers, the hour and the sky.
func get_controls() -> Array[Dictionary]:
	var list: Array[Dictionary] = [
		{"heading": "Log Cabin"},
		{"key": "cabin_detail", "label": "Set detail", "type": "option",
			"options": [["auto", "Auto (follows Graphics quality)"], ["low", "Simple"], ["full", "Detailed"]],
			"tooltip": "How detailed the cabin is drawn on this PC. Detailed: photo textures on the logs, stone, floors, leather and wool with their bumps, reflections of the warm room in the glass, and a forest of leaf trees, ferns and grass outside. Simple: flat colours and plain trees, the lightest for a slow graphics card. Auto picks from Graphics quality: Low = Simple, otherwise Detailed. Each PC in a co-stream chooses its own."},
		{"key": "cabin_fire", "label": "Fire", "min": 0.0, "max": 2.0, "step": 0.01, "format": "%d%%", "scale": 100.0,
			"tooltip": "The fires in the fireplaces: 0 = out, 100% = a cozy fire, 200% = roaring. Smoke rises from the chimneys while they burn."},
		{"key": "cabin_lamps", "label": "Lamps", "type": "check",
			"tooltip": "The table lamps, chandelier, dining lamp and the lantern by the back door. They burn lower by day."},
		{"key": "cabin_view", "label": "Gather in", "type": "option",
			"options": [["great_room", "Great room"], ["den", "Den"]],
			"tooltip": "Where the presenters sit. Great room: the armchairs by the big fireplace. Den: the sofa and armchair in the small den by its own fire, with the den's screen and cameras first. Changing it reloads the room."},
		{"heading": "Time of day"},
		{"key": "cabin_time", "label": "Time of day", "min": 0.0, "max": 24.0, "step": 0.1, "format": "%.1f h",
			"tooltip": "The hour outside the cabin, 0 to 24. 6 = sunrise, 12 = noon, 17.5 = golden hour, 18 = sunset, 21 = a moonlit night. The lamps come up as it gets dark."},
		{"key": "cabin_day_minutes", "label": "Day length", "min": 0.0, "max": 120.0, "step": 1.0, "format": "%d min", "zero": "Clock stopped",
			"tooltip": "Lets the clock run: how many minutes a full day and night takes, starting from the Time of day. 0 = the clock stands still."},
		{"heading": "Sky"},
		{"key": "cabin_clouds", "label": "Clouds", "min": 0.0, "max": 2.0, "step": 0.01, "format": "%d%%", "scale": 100.0,
			"tooltip": "How much cloud drifts across the sky. 0% = a clear sky, 200% = overcast. (Rain, storms, fog and snow come with the weather.)"},
		{"key": "cabin_stars", "label": "Stars", "min": 0.0, "max": 2.0, "step": 0.01, "format": "%d%%", "scale": 100.0,
			"tooltip": "How bright the stars and the Milky Way are at night. 0% = none."},
		{"heading": "Weather"},
		{"key": "cabin_weather", "label": "Weather", "type": "option",
			"options": [["clear", "Clear"], ["cloudy", "Cloudy"], ["rain", "Rain"], ["storm", "Storm"], ["snow", "Snow"]],
			"tooltip": "The weather outside. Rain and storms run down the windows and wet everything outside, with rain drumming on the roof; a storm adds strong wind, lightning (soft and slow in photosensitive-safe mode) and thunder, and the lamps dip now and then; snow drifts down, frosts the glass and slowly piles up on the ground and roofs. The glass dries and the snow melts slowly after."},
		{"key": "cabin_fog", "label": "Fog", "type": "option",
			"options": [["off", "Off"], ["light", "Light"], ["heavy", "Heavy"]],
			"tooltip": "Fog outside, on top of any weather. Heavy fog swallows the trees within about 30 metres, so the fire and lamps are all you see. The inside of the cabin stays clear."},
		{"key": "cabin_wind", "label": "Wind", "min": 0.0, "max": 2.0, "step": 0.01, "format": "%d%%", "scale": 100.0,
			"tooltip": "How hard the wind blows: the trees sway, the rain slants, the snow drifts sideways, the chimney smoke leans and you hear it. 0% = still, 200% = a gale. A storm always blows hard."},
		{"key": "cabin_snow", "label": "Snow on the ground", "min": 0.0, "max": 1.0, "step": 0.01, "format": "%d%%", "scale": 100.0,
			"tooltip": "Snow lying on the ground, the roofs, the deck and the railings (and frost on the trees). More piles up on top while it snows, and melts away slowly after."},
		{"key": "cabin_weather_fx", "label": "Rain and snow amount", "min": 0.0, "max": 1.0, "step": 0.01, "format": "%d%%", "scale": 100.0,
			"tooltip": "How many raindrops and snowflakes this PC draws. Lower it on a slow graphics card; the wet glass, the sound and the snow on the ground stay. Each PC in a co-stream chooses its own."},
	]
	if scene == "north":
		# the aurora, with the sky's own settings
		var sky_at := list.size()
		for i in list.size():
			if String(list[i].get("key", "")) == "cabin_stars":
				sky_at = i + 1
				break
		list.insert(sky_at, {"key": "cabin_aurora", "label": "Aurora", "min": 0.0, "max": 2.0, "step": 0.01, "format": "%d%%", "scale": 100.0,
			"tooltip": "The northern lights: slow green and violet curtains over the frozen lake on clear nights (cloud, snow and fog hide them). 0% = none, 200% = a strong display. They move slowly, so they are fine in photosensitive-safe mode."})
	if SEASON_TIPS.has(scene):
		# the scene's own setting, right after Gather in
		var at := list.size()
		for i in list.size():
			if String(list[i].get("heading", "")) == "Time of day":
				at = i
				break
		list.insert(at, {"key": "cabin_season", "label": "Season", "type": "option",
			"options": [["summer", "Summer"], ["autumn", "Autumn"]],
			"tooltip": SEASON_TIPS.get(scene, "")})
	return list


## "Gather in" decides where the presenters' markers and the main screen are built, which the app
## only reads when the room loads: RoomHost reloads the room when it changes.
func reload_keys() -> PackedStringArray:
	return PackedStringArray(["cabin_view"])


func _on_cabin_setting_changed(key: String, _value: Variant) -> void:
	match key:
		"cabin_fire":
			_apply_fire()
			_hour_drawn = -100.0        # (the lake mirrors the fire's glow)
		"cabin_time":
			_hour = fposmod(float(AppState.get_setting("cabin_time")), 24.0)
		"cabin_clouds", "cabin_stars", "cabin_aurora", "photosensitive_safe", "cabin_weather", "cabin_fog", "cabin_wind":
			_hour_drawn = -100.0        # _run_clock redraws the sky next frame
		"cabin_lamps":
			_probe_day = -1.0           # the reflections catch the room again
			_hour_drawn = -100.0        # (and the lake mirrors the lit windows)
		"cabin_season":
			_apply_season()
			_hour_drawn = -100.0        # (the fireflies follow the season)
		"cabin_detail", "graphics_quality":
			_apply_detail()


func _process(delta: float) -> void:
	super._process(delta)
	_time += delta
	if _loon_player:
		_run_loons(delta)
	if scene == "ocean":
		_run_ocean(delta)
	if _ice_player:
		_run_ice(delta)
	_run_fire()
	_weather.fire = clampf(float(AppState.get_setting("cabin_fire")), 0.0, 2.0)
	_weather.run(delta)
	_lean_smoke()
	_run_clock(delta)
	if not is_equal_approx(_level, _last_level):
		_last_level = _level
		(_parts["glow_mat"] as ShaderMaterial).set_shader_parameter("level", _level)
	# the reflections are caught again when the light has changed a lot (dusk falling, lamps off)
	if _probe and _probe.visible and absf(_day - _probe_day) > 0.15 and absf(_level - _last_probe_level) < 0.01:
		_recapture()
	_last_probe_level = _level


# ── The lamps ────────────────────────────────────────────────
## The house lights (lamps, chandelier, lantern) are off with their tick box and lower by day, on
## top of what every room does (the House lights slider, dimming for a video).
func _target_level() -> float:
	if not bool(AppState.get_setting("cabin_lamps")):
		return 0.0
	var level := super._target_level() * lerpf(1.0, lamps_by_day, _day)
	return level * _weather.lamp_factor() if _weather else level


# ── Set detail ───────────────────────────────────────────────
## The look the set is drawn in on this PC: "low" (Simple) or "full" (Detailed). From
## "cabin_detail" (Room tab > Set detail, each PC's own); its "auto" follows "graphics_quality":
## low = "low", anything else = "full". The same rule as the Drive-In's and the campfire's.
func detail_level() -> String:
	var choice := String(AppState.get_setting("cabin_detail"))
	if choice in ["low", "full"]:
		return choice
	return "low" if String(AppState.get_setting("graphics_quality")) == "low" else "full"


## Shows the Simple or the Detailed look: `detail` on every textured material (Builder's
## detail_mats), the plain cone trees or the leaf-card forest, and the reflection probe. Called
## when the room loads and whenever "cabin_detail" or "graphics_quality" changes. Both looks were
## built when the room loaded, so nothing is built or loaded here.
func _apply_detail() -> void:
	var detailed := detail_level() == "full"
	for m: ShaderMaterial in _parts["detail_mats"]:
		m.set_shader_parameter("detail", 1.0 if detailed else 0.0)
	(_parts["simple_trees"] as Node3D).visible = not detailed
	(_parts["detailed_plants"] as Node3D).visible = detailed
	if _probe:
		_probe.visible = detailed
		_probe_day = -1.0


# ── Reflections ──────────────────────────────────────────────
## A reflection probe that fills the great room (box projection, so the reflections sit where the
## walls are). It renders once, not every frame; _recapture asks for another picture when the
## light has changed a lot. Without it the glass would reflect the sky even at night.
func _build_probe() -> void:
	_probe = ReflectionProbe.new()
	_probe.name = "CabinReflections"
	_probe.update_mode = ReflectionProbe.UPDATE_ONCE
	_probe.box_projection = true
	_probe.interior = true          # inside: no sky light added to what it catches
	_probe.size = Vector3(13.4, 9.0, 10.4)
	_probe.origin_offset = Vector3.ZERO
	_probe.max_distance = 40.0
	_fx.add_child(_probe)
	_probe.position = Vector3(0.0, 4.4, 4.2)


## Has the probe catch the room again (setting a property makes a once-only probe render anew).
func _recapture() -> void:
	_probe_day = _day
	_probe.intensity = 1.0 if _probe.intensity != 1.0 else 0.999


# ── Weather ──────────────────────────────────────────────────
## Makes the shared weather (rooms/weather/room_weather.gd) with what the builder made for it:
## the indoors (shelters), the dripping roof edges, the surface materials (wet, snow), the glass
## and the detailed trees.
func _build_weather() -> void:
	_weather = Weather.new()
	_weather.name = "Weather"
	if scene == "north":
		_weather.snow_floor = North.SNOW_FLOOR        # (the north is always under snow)
		_weather.tree_snow = 1.0                       # (snow heaped on the spruces' boughs)
	_fx.add_child(_weather)
	var mats: Array = (_parts["surface_mats"] as Dictionary).values()
	_weather.setup(self, "cabin_", SKY_SHADER, _parts["shelters"], _parts["eaves"], mats,
		_parts["glass_mat"], _parts["tree_mats"])


## The chimney smoke leans away with the wind (every frame; two particle systems).
func _lean_smoke() -> void:
	var w := _weather.wind()
	for p in _smoke:
		p.gravity = Vector3(0.12 + 0.25 * w, 0.05 - 0.02 * w, 0.06 + 0.08 * w)
	# a strong wind tears the smoke up: the puffs thin out, so they don't sail off across the
	# sky as separate white balls (wind() is 0..2; 1.4 = a storm)
	if _smoke_mat:
		_smoke_mat.albedo_color.a = 1.0 - 0.6 * clampf(w / 1.4, 0.0, 1.0)


# ── The forest: season and fireflies ─────────────────────────
## Season ("cabin_season", the scene rooms): in autumn the leaf cards turn
## (campfire_trees.gd's foliage shader `autumn`, with the campfire's colour ranges), the forest
## floor photo goes browner, the far treetops coloured into the land go copper and the far
## low-poly round trees turn orange, gold and red. The hemlocks stay green.
func _apply_season() -> void:
	var autumn := String(AppState.get_setting("cabin_season")) == "autumn"
	var leaf_mats: Dictionary = _parts.get("leaf_mats", {})
	# [leaf material, the two ends of its autumn colour range]
	for row: Array in [["leaves", Color(0.62, 0.36, 0.1), Color(0.5, 0.2, 0.07)], ["leaves_birch", Color(0.95, 0.74, 0.1), Color(0.9, 0.58, 0.08)],
			["leaves_maple", Color(0.9, 0.42, 0.06), Color(0.72, 0.1, 0.05)]]:
		var m := leaf_mats.get(row[0]) as ShaderMaterial
		if m:
			m.set_shader_parameter("autumn", 1.0 if autumn else 0.0)
			m.set_shader_parameter("fall_a", row[1])
			m.set_shader_parameter("fall_b", row[2])
	var litter := _parts.get("litter_mat") as ShaderMaterial
	if litter:
		litter.set_shader_parameter("photo_tint", Color(1.08, 0.86, 0.66) if autumn else Color(0.74, 0.88, 0.58))
		litter.set_shader_parameter("far_tint", Vector3(2.1, 1.05, 0.5) if autumn else Vector3.ONE)
	# the far round trees: each one's summer colour (kept the first time) times orange, gold or red
	var turns: Array[Color] = [Color(3.2, 1.35, 0.2), Color(3.0, 1.9, 0.25), Color(3.3, 0.95, 0.15)]  # copper, gold, rust (less red-pink than plain red)
	for n: Node3D in _parts.get("far_trees", []):
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
			mm.set_instance_color(i, summer[i] * turns[i % 3] if autumn else summer[i])


## Fireflies (the Lakeside Campfire's): slow drifting specks round the yard's edge and over the
## creek; _apply_time lets them out on dry summer nights.
func _build_fireflies() -> void:
	_fireflies = CPUParticles3D.new()
	_fireflies.name = "Fireflies"
	_fireflies.amount = 60
	_fireflies.lifetime = 7.0
	_fireflies.randomness = 1.0
	_fireflies.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	_fireflies.emission_ring_axis = Vector3.UP
	_fireflies.emission_ring_radius = 22.0
	_fireflies.emission_ring_inner_radius = 10.0
	_fireflies.emission_ring_height = 2.4
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
	var dot := GradientTexture2D.new()
	dot.width = 32
	dot.height = 32
	dot.fill = GradientTexture2D.FILL_RADIAL
	dot.fill_from = Vector2(0.5, 0.5)
	dot.fill_to = Vector2(1.0, 0.5)
	var dg := Gradient.new()
	dg.set_color(0, Color.WHITE)
	dg.set_color(1, Color.BLACK)
	dot.gradient = dg
	sm.albedo_texture = dot
	sm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	sm.billboard_keep_scale = true
	sm.disable_fog = true           # (fog on a glow that is added to the picture shows as a pale square)
	speck.material = sm
	_fireflies.mesh = speck
	_fireflies.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fireflies.emitting = false
	_fireflies.visible = false
	_fx.add_child(_fireflies, true)
	_fireflies.position = Vector3(Forest.YARD.x, 0.6, Forest.YARD.y)


# ── Time of day and the sky ──────────────────────────────────
## Called every frame. Moves the clock on while "cabin_day_minutes" is above 0, and redraws the
## sky and lights when the hour has moved by time_step or the app swapped the Environment (a
## graphics setting changed).
func _run_clock(delta: float) -> void:
	if _retired:
		return
	var day_minutes := float(AppState.get_setting("cabin_day_minutes"))
	if day_minutes > 0.0:
		_hour = fposmod(_hour + delta * 24.0 / (day_minutes * 60.0), 24.0)
	var env := get_world_3d().environment if is_inside_tree() else null
	var env_id := env.get_instance_id() if env else 0
	if absf(_hour - _hour_drawn) >= time_step or env_id != _env_drawn:
		_hour_drawn = _hour
		_env_drawn = env_id
		_apply_time(env)


## The hour the room's clock shows now, 0..24 (for tests; "cabin_time" only says where it started).
func get_hour() -> float:
	return _hour


## 0 = night, 1 = full day, at the hour last drawn (for tests).
func get_daylight() -> float:
	return _day


## Where the sun is at an hour: a unit vector pointing AT it. The Lakeside Campfire's path
## (campfire_room.gd sun_at): it rises on the right (+X), is highest at noon and sets to the left.
## The cabin's glass faces -Z, so the low evening sun comes in from the front left.
static func sun_at(hour: float) -> Vector3:
	var a := (hour - 6.0) / 12.0 * PI
	return Vector3(cos(a), sin(a), -0.5 * cos(a) - 0.25).normalized()


## Where the moon is: it crosses the sky in front of the cabin while the sun is down.
static func moon_at(hour: float) -> Vector3:
	var b := (hour - 18.0) / 12.0 * PI
	return Vector3(cos(b) * 0.8, sin(b) * 0.75 + 0.12, -0.62).normalized()


## Everything that follows the hour (_hour): the sky shader's uniforms, the sun / moon lamp, the
## ambient light, the haze and the smoke's colour. env = the Environment in use; it is only
## touched when it is this room's own (its sky uses camp_sky.gdshader), never another room's.
func _apply_time(env: Environment) -> void:
	var sun := sun_at(_hour)
	var moon := moon_at(_hour)
	_day = smoothstep(-0.12, 0.22, sun.y)
	var dusk := (1.0 - smoothstep(0.0, 0.4, absf(sun.y))) * smoothstep(-0.3, -0.05, sun.y)
	var clouds := clampf(float(AppState.get_setting("cabin_clouds")), 0.0, 2.0)
	var turn := global_basis.orthonormalized()                   # the shaders work in world space
	# the horizon colour camp_sky.gdshader mixes, for the haze
	var hor := Color(0.015, 0.02, 0.05).lerp(Color(0.5, 0.68, 0.92), _day).lerp(Color(0.92, 0.5, 0.38), dusk * 0.6)
	var haze := hor.lerp(Color(0.6, 0.66, 0.74) * (0.06 + 0.94 * _day), 0.4)
	if env and env.sky and env.sky.sky_material is ShaderMaterial and (env.sky.sky_material as ShaderMaterial).shader == SKY_SHADER:
		var sky := env.sky.sky_material as ShaderMaterial
		sky.set_shader_parameter("cloud_noise", load(CAMP_TEX + "sky_noise.png"))
		sky.set_shader_parameter("sun_dir", turn * sun)
		sky.set_shader_parameter("moon_dir", turn * moon)
		sky.set_shader_parameter("day", _day)
		sky.set_shader_parameter("dusk", dusk)
		sky.set_shader_parameter("twinkle", 0.0 if bool(AppState.get_setting("photosensitive_safe")) else 1.0)
		sky.set_shader_parameter("cloud_amount", clouds)
		sky.set_shader_parameter("star_amount", float(AppState.get_setting("cabin_stars")))
		sky.set_shader_parameter("aurora_amount", _aurora(clouds))
		sky.set_shader_parameter("haze", 0.35)
		sky.set_shader_parameter("blue_ridges", 1.0 if scene == "forest" else 0.0)
		sky.set_shader_parameter("open_sea", 1.0 if scene == "ocean" else 0.0)
		env.ambient_light_color = night_ambient.lerp(day_ambient, _day).lerp(Color(0.66, 0.46, 0.42), dusk * 0.35)
		env.ambient_light_energy = lerpf(night_ambient_energy, day_ambient_energy, _day)
		env.fog_light_color = haze
		# (thinner in the scene rooms: the forest sky's blue ridges carry the haze, and over the lake
		# thick haze turned the island pale)
		env.fog_density = 0.003 * lerpf(1.0, 0.6, _day) * (0.45 if scene == "forest" else 0.3 if scene in ["lake", "north"] else 0.4 if scene == "ocean" else 1.0)
		# the weather has the last word on the clouds, the fog and how dull the light is
		_weather.apply_env(env, sky, haze)
	# the sun by day, the moon by night; cloud dims both
	var light_dir := sun
	var light_col := Color(1.0, 0.55, 0.25).lerp(Color(1.0, 0.96, 0.88), smoothstep(0.05, 0.45, sun.y))
	var energy := sun_energy * smoothstep(0.0, 0.2, sun.y)
	if sun.y <= 0.02:
		light_dir = moon
		light_col = moon_color
		energy = moon_energy * smoothstep(0.05, 0.25, moon.y)
	energy *= lerpf(1.0, 0.45, clampf(clouds - 1.0, 0.0, 1.0)) * _weather.sun_share()
	_sun.light_color = light_col
	_sun.light_energy = energy
	_sun.visible = energy > 0.002
	var world_dir := turn * light_dir
	_sun.global_basis = Basis.looking_at(-world_dir, Vector3.UP if absf(world_dir.y) < 0.99 else Vector3.FORWARD)
	if _parts.has("stream_mat"):
		# the creek (camp_stream.gdshader, unshaded): the sky to mirror and the light to glint
		var water := _parts["stream_mat"] as ShaderMaterial
		var glitter := light_col * (energy / maxf(sun_energy, 0.01)) * (2.2 if sun.y > 0.02 else 7.0)
		water.set_shader_parameter("daylight", 0.08 + 0.92 * _day * lerpf(0.6, 1.0, _weather.sun_share()))
		water.set_shader_parameter("sky_top", Color(0.01, 0.015, 0.04).lerp(Color(0.12, 0.3, 0.7), _day))
		water.set_shader_parameter("sky_horizon", hor)
		water.set_shader_parameter("light_dir", world_dir)
		water.set_shader_parameter("light_color", Vector3(glitter.r, glitter.g, glitter.b))
	if _parts.has("lake_mat"):
		_apply_lake(hor, light_col * (energy / maxf(sun_energy, 0.01)) * (2.2 if sun.y > 0.02 else 7.0), world_dir)
	if _parts.has("sea_mat"):
		_apply_ocean(hor, light_col, light_col * (energy / maxf(sun_energy, 0.01)) * (2.2 if sun.y > 0.02 else 7.0), world_dir, dusk)
	if _fireflies:
		# out on summer nights while it is dry (they wait out rain and snow)
		var tonight := String(AppState.get_setting("cabin_season")) == "summer" and _day < 0.35 \
			and _weather.kind() in ["clear", "cloudy"]
		_fireflies.emitting = tonight
		_fireflies.visible = tonight or _fireflies.visible and _day < 0.5
	if _smoke_mat:
		# pale grey smoke by day, barely-there blue-grey by night
		# (greyer under rain clouds: sun_share() is 1 on a clear day, 0.18 in a storm). Its alpha
		# is _lean_smoke()'s, every frame.
		var a := _smoke_mat.albedo_color.a
		_smoke_mat.albedo_color = Color(0.2, 0.21, 0.25).lerp(Color(0.85, 0.84, 0.82), _day).lerp(Color(0.9, 0.7, 0.6), dusk * 0.4) \
			* lerpf(0.6, 1.0, _weather.sun_share() if _weather else 1.0)
		_smoke_mat.albedo_color.a = a


# ── The fire ─────────────────────────────────────────────────
## For each fire (the great room's and the den's, Builder's "fires" markers): the flames
## (camera-facing rectangles with the Forge Hall's fire shader) and the fire's light, out in the
## room just in front of the firebox so it reaches the seats. Offsets are in the marker's axes.
func _build_fire() -> void:
	var fires: Array[Marker3D] = _parts["fires"]
	for n in fires.size():
		var marker := fires[n]
		var share := 1.0 if n == 0 else DEN_FIRE_SHARE
		for k in FIRE_FLAMES.size():
			var f: Array = FIRE_FLAMES[k]
			var size := flame_size * float(f[2]) * (1.0 if n == 0 else 0.85)
			var quad := QuadMesh.new()
			quad.size = size
			var mat := ShaderMaterial.new()
			mat.shader = FIRE_SHADER
			mat.set_shader_parameter("seed", float(k + n * FIRE_FLAMES.size()) * 1.37)
			var mi := MeshInstance3D.new()
			mi.name = "FireFlame"
			mi.mesh = quad
			mi.material_override = mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_fx.add_child(mi, true)
			# (the shader turns the rectangle to face the camera and counts height from its bottom)
			mi.global_position = marker.global_transform * Vector3(float(f[0]), size.y * 0.5 + 0.05, float(f[1]))
			mi.extra_cull_margin = maxf(size.x, size.y) * 2.0
			_fire_mats.append(mat)
			_fire_meshes.append(mi)
		var light := OmniLight3D.new()
		light.name = "FireLight"
		light.light_color = fire_light_color
		light.omni_range = fire_light_range * share
		light.omni_attenuation = 1.5
		light.shadow_enabled = false
		add_child(light, true)
		light.global_position = marker.global_transform * Vector3(0.0, 0.5, 0.75)
		_fire_lights.append(light)
		_fire_strength.append(share)


## Smoke from each chimney top (Builder's smoke_spots): a few soft puffs that rise slowly, lean
## away on the breeze, swell and fade. CPU particles like the campfire's (they work the same on
## every renderer); slow on purpose. _apply_fire starts and stops them, _apply_time tints them.
func _build_smoke() -> void:
	_smoke_mat = StandardMaterial3D.new()
	_smoke_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_smoke_mat.vertex_color_use_as_albedo = true
	_smoke_mat.albedo_texture = _soft_puff()
	_smoke_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_smoke_mat.billboard_keep_scale = true
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.25))
	grow.add_point(Vector2(1.0, 1.0))
	var fade := Gradient.new()
	fade.set_color(0, Color(1.0, 1.0, 1.0, 0.0))
	fade.add_point(0.12, Color(1.0, 1.0, 1.0, 0.32))
	fade.set_color(fade.get_point_count() - 1, Color(1.0, 1.0, 1.0, 0.0))
	var spots: Array[Vector3] = _parts["smoke_spots"]
	for n in spots.size():
		var p := CPUParticles3D.new()
		p.name = "ChimneySmoke"
		p.amount = smoke_puffs
		p.lifetime = 9.0
		p.preprocess = 9.0                # already rising when the room appears
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = 0.15
		p.direction = Vector3.UP
		p.spread = 8.0
		p.gravity = Vector3(0.12, 0.05, 0.06)   # the breeze: a slow lean to the side, a little lift
		p.initial_velocity_min = 0.35
		p.initial_velocity_max = 0.55
		p.scale_amount_min = 0.7
		p.scale_amount_max = 1.1
		p.scale_amount_curve = grow
		p.color_ramp = fade
		var puff := QuadMesh.new()
		puff.size = Vector2(1.8, 1.8) * (1.0 if n == 0 else 0.75)
		puff.material = _smoke_mat
		p.mesh = puff
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		p.visibility_aabb = AABB(Vector3(-4.0, -1.0, -4.0), Vector3(12.0, 9.0, 8.0))
		_fx.add_child(p, true)
		p.global_position = spots[n]
		_smoke.append(p)


## A soft round puff picture (white, fading out to the edge) for the smoke.
static func _soft_puff() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	g.add_point(0.45, Color(1.0, 1.0, 1.0, 0.55))
	g.set_color(g.get_point_count() - 1, Color(1.0, 1.0, 1.0, 0.0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	return t


## "cabin_fire" changed: show or hide the flames (their size follows in _run_fire) and start or
## stop the chimney smoke (more puffs for a bigger fire).
func _apply_fire() -> void:
	var lit := float(AppState.get_setting("cabin_fire")) > 0.005
	for mi in _fire_meshes:
		mi.visible = lit
	var amount := clampf(float(AppState.get_setting("cabin_fire")), 0.0, 2.0)
	for p in _smoke:
		p.emitting = lit
		p.amount = maxi(4, int(round(float(smoke_puffs) * clampf(amount, 0.3, 2.0))))


## Called every frame: the flames, coals and lights of both fires follow the Fire setting; the light wavers a
## little (two slow sine waves, never a strobe; steady in photosensitive-safe mode).
func _run_fire() -> void:
	var amount := clampf(float(AppState.get_setting("cabin_fire")), 0.0, 2.0)
	for m in _fire_mats:
		m.set_shader_parameter("amount", amount)
	(_parts["ember_mat"] as ShaderMaterial).set_shader_parameter("amount", amount)
	var lit := amount > 0.005
	for light in _fire_lights:
		light.visible = lit
	if not lit:
		return
	var waver := 1.0
	if fire_flicker > 0.0 and not bool(AppState.get_setting("photosensitive_safe")):
		waver += fire_flicker * (0.6 * sin(_time * 5.3) + 0.4 * sin(_time * 8.9 + 1.7))
	var show_dim := lerpf(fire_dimmed, 1.0, clampf(super._target_level(), 0.0, 1.0)) if AppState.is_playback_active() else 1.0
	for i in _fire_lights.size():
		_fire_lights[i].light_energy = fire_light_energy * _fire_strength[i] * amount * show_dim * waver


## The great room fire's light (for tests).
func get_fire_light() -> OmniLight3D:
	return _fire_lights[0]


## Every fire's light: the great room's, then the den's (for tests).
func get_fire_lights() -> Array[OmniLight3D]:
	return _fire_lights


## The sun / moon lamp (for tests).
func get_sun() -> DirectionalLight3D:
	return _sun


# ── The lake ─────────────────────────────────────────────────
## The lake's water (Cabin: Lakeside; the Lakeside Campfire's camp_water.gdshader, unshaded):
## the sky colours to mirror, the far shore's colour, the glitter path under the sun or the moon,
## the cabin's warm windows streaking across it at night, and the waves, which grow with the wind
## (a storm whips it up). Called by _apply_time whenever the sky is redrawn (the hour moved, or
## the weather or the lamps changed).
func _apply_lake(hor: Color, glitter: Color, light_dir: Vector3) -> void:
	var lake := _parts["lake_mat"] as ShaderMaterial
	var dull := _weather.sun_share() if _weather else 1.0         # 1 on a clear day, low under rain clouds
	var top := Color(0.01, 0.015, 0.04).lerp(Color(0.12, 0.3, 0.7), _day).lerp(hor, 1.0 - dull)
	lake.set_shader_parameter("sky_top", top)
	lake.set_shader_parameter("sky_horizon", hor)
	lake.set_shader_parameter("shore_color", Color(0.03, 0.07, 0.05).lerp(Color(0.003, 0.005, 0.007), 1.0 - _day).lerp(hor, 0.3 * (1.0 - dull)))
	lake.set_shader_parameter("deep_color", Color(0.012, 0.05, 0.065) * (0.08 + 0.92 * _day))
	lake.set_shader_parameter("light_dir", light_dir)
	lake.set_shader_parameter("light_color", Vector3(glitter.r, glitter.g, glitter.b) * dull)
	# the cabin's glass glows warm at night: a streak on the water from the middle of the gable
	var warm := float(AppState.get_setting("cabin_fire")) * 0.5 + (0.6 if bool(AppState.get_setting("cabin_lamps")) else 0.0)
	lake.set_shader_parameter("fire_pos", global_transform * Vector3(0.0, 2.5, -1.0))
	lake.set_shader_parameter("fire_color", Vector3(1.0, 0.55, 0.25) * warm * (1.0 - 0.85 * _day))
	var w := _weather.wind() if _weather else 0.4
	lake.set_shader_parameter("wave", 0.6 + 0.9 * w)
	lake.set_shader_parameter("flow", Vector2(0.03, -0.02) * (1.0 + 2.0 * w))


## The loons (Cabin: Lakeside): every so often one of the three recordings plays on the Ambience
## bus, nearer or further off. They call most at dawn, dusk and through the night, now and then
## by day, and keep quiet in rain, a storm or snow. Every frame (cheap: a countdown).
func _run_loons(delta: float) -> void:
	_loon_wait -= delta
	if _loon_wait > 0.0 or _loon_player.playing:
		return
	var quiet := _weather != null and _weather.kind() in ["rain", "storm", "snow"]
	# (dawn, dusk and night: _day below 0.6; a waiting time of about one to three minutes)
	var lively := _day < 0.6
	_loon_wait = randf_range(50.0, 110.0) if lively else randf_range(120.0, 260.0)
	if not quiet:
		call_loon(randf())


## One loon call now: amount 0..1 = how near it sounds. (Tests call it too.)
func call_loon(amount: float) -> void:
	if _loon_player == null:
		return
	_loon_player.stream = LOONS[randi() % LOONS.size()]
	_loon_player.volume_db = linear_to_db(lerpf(0.25, 0.9, clampf(amount, 0.0, 1.0)))
	_loon_player.play()


# ── The coast (Cabin: Ocean) ─────────────────────────────────
## The sea, the surf, the lighthouse's light, for the hour and the weather (called by
## _apply_time whenever the sky is redrawn). The sea is the lake's water shader with nothing
## mirrored on the horizon and bigger waves (the coast is breezier than its Wind slider says);
## the surf gets the daylight and grows with the wind; the lighthouse's beams show from dusk on
## and in fog, strongest in fog at night.
func _apply_ocean(hor: Color, light_col: Color, glitter: Color, light_dir: Vector3, dusk: float) -> void:
	var sea := _parts["sea_mat"] as ShaderMaterial
	var dull := _weather.sun_share() if _weather else 1.0
	var w := _weather.wind() if _weather else 0.4
	var top := Color(0.01, 0.015, 0.04).lerp(Color(0.12, 0.3, 0.7), _day).lerp(hor, 1.0 - dull)
	sea.set_shader_parameter("sky_top", top)
	sea.set_shader_parameter("sky_horizon", hor)
	sea.set_shader_parameter("deep_color", Color(0.01, 0.06, 0.08) * (0.08 + 0.92 * _day))
	sea.set_shader_parameter("light_dir", light_dir)
	sea.set_shader_parameter("light_color", Vector3(glitter.r, glitter.g, glitter.b) * dull)
	sea.set_shader_parameter("fire_color", Vector3.ZERO)
	sea.set_shader_parameter("wave", 1.1 + 1.1 * w)
	sea.set_shader_parameter("flow", Vector2(0.02, 0.06) * (1.0 + 1.5 * w))
	var surf := _parts["surf_mat"] as ShaderMaterial
	surf.set_shader_parameter("daylight", (0.06 + 0.94 * _day) * lerpf(0.7, 1.0, dull))
	surf.set_shader_parameter("light_color", Color(1.0, 1.0, 1.0).lerp(light_col, 0.5 * dusk))
	surf.set_shader_parameter("size", 0.9 + 0.6 * w)
	surf.set_shader_parameter("period", SURF_PERIOD)
	var fog := String(AppState.get_setting("cabin_fog"))
	var murk := 1.0 if fog == "heavy" else 0.5 if fog == "light" else 0.0
	var dark := 1.0 - smoothstep(0.15, 0.7, _day)
	(_parts["beam_mat"] as ShaderMaterial).set_shader_parameter("strength", clampf(dark * (0.6 + 0.6 * murk) + murk * 0.5, 0.0, 1.2))
	var lamp := _parts["lamp"] as MeshInstance3D
	lamp.visible = dark > 0.05 or murk > 0.0
	(_parts["lamp_mat"] as StandardMaterial3D).albedo_color = Color.WHITE * clampf(dark + murk * 0.6, 0.0, 1.0)


## The coast's sounds: the surf (generated, on the Ambience bus like the weather's sound), the
## gulls' recording and the foghorn (a low two-tone blast generated once here: no file needed).
func _build_coast_sounds() -> void:
	_surf_rng.seed = 7
	_surf_pb = _start_generated_ambience(SURF_RATE, 0.3)
	_gull_player = AudioStreamPlayer.new()
	_gull_player.name = "Gulls"
	_gull_player.bus = AudioManager.AMBIENCE_BUS
	_gull_player.stream = GULL
	add_child(_gull_player)
	_horn_player = AudioStreamPlayer.new()
	_horn_player.name = "Foghorn"
	_horn_player.bus = AudioManager.AMBIENCE_BUS
	_horn_player.stream = _make_foghorn()
	add_child(_horn_player)
	# each gull's circle: over the beach and the water in front, some near, some further out
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	for i in (_parts["gulls"] as Array).size():
		var cx := rng.randf_range(-60.0, 60.0)
		var cz := Ocean.edge_z(cx) - rng.randf_range(15.0, 70.0)
		_gull_paths.append(Vector4(cx, cz, rng.randf_range(14.0, 35.0), rng.randf_range(0.12, 0.25) * (1.0 if rng.randf() < 0.5 else -1.0)))


## A foghorn: 2.8 s of a low tone (two notes a little apart, rich in overtones) that swells in
## and fades out, as a sound the player can play again and again.
func _make_foghorn() -> AudioStreamWAV:
	var rate := 22050
	var count := int(rate * 2.8)
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in count:
		var t := float(i) / float(rate)
		var env := smoothstep(0.0, 0.35, t) * smoothstep(2.8, 2.0, t)
		var s := 0.0
		for h in 6:                                  # the overtones of a reedy horn
			var k := float(h + 1)
			s += sin(TAU * 110.0 * k * t) / (k * 1.3) + 0.6 * sin(TAU * 131.0 * k * t) / (k * 1.5)
		data.encode_s16(i * 2, int(clampf(s * env * 0.28, -1.0, 1.0) * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	return wav


## Every frame on the coast: the beams turn (the lamp brightens as one sweeps past the viewer,
## unless photosensitive-safe is on), the gulls fly their circles by day, the surf's sound is fed,
## and now and then a gull calls or (in heavy fog) the foghorn sounds.
func _run_ocean(delta: float) -> void:
	var beam := _parts["beam"] as Node3D
	beam.rotate_y(delta * TAU / BEAM_TURN)
	var lamp := _parts["lamp"] as MeshInstance3D
	var cam := get_viewport().get_camera_3d()
	if cam and lamp.visible:
		# how straight a beam points at the camera (both beams: the cone lies along the pivot's X)
		var to_cam := (cam.global_position - beam.global_position)
		to_cam.y = 0.0
		var facing := absf(beam.global_basis.x.normalized().dot(to_cam.normalized()))
		var swell := 0.0 if bool(AppState.get_setting("photosensitive_safe")) else pow(facing, 40.0) * 1.2
		lamp.scale = Vector3.ONE * (1.0 + swell)
	# the gulls: out by day in fair weather, gliding round their circles, banking into the turn
	var kind := _weather.kind() if _weather else "clear"
	var flying := _day > 0.3 and kind in ["clear", "cloudy"]
	var gulls: Array = _parts["gulls"]
	for i in gulls.size():
		var g := gulls[i] as Node3D
		g.visible = flying
		if not flying:
			continue
		var path := _gull_paths[i]
		var a := _time * path.w + float(i) * 1.7
		var pos := Vector3(path.x + cos(a) * path.z, Ocean.SEA_Y + 16.0 + 5.0 * sin(_time * 0.3 + float(i)) + float(i) * 1.5, path.y + sin(a) * path.z)
		var ahead := Vector3(-sin(a), 0.0, cos(a)) * signf(path.w)
		g.global_transform = Transform3D(Basis.looking_at(ahead, Vector3.UP) * Basis(Vector3.BACK, -0.35 * signf(path.w)), pos).scaled_local(Vector3.ONE * 1.3)
	_fill_surf()
	_gull_wait -= delta
	if _gull_wait <= 0.0:
		_gull_wait = randf_range(25.0, 70.0)
		if flying and not _gull_player.playing:
			_gull_player.pitch_scale = randf_range(0.9, 1.1)
			_gull_player.volume_db = linear_to_db(randf_range(0.25, 0.7))
			_gull_player.play()
	_horn_wait -= delta
	if _horn_wait <= 0.0:
		_horn_wait = 30.0
		if String(AppState.get_setting("cabin_fog")) == "heavy":
			_horn_player.volume_db = linear_to_db(0.35)
			_horn_player.play()
			horn_blasts += 1


## The surf's sound: a deep roar that swells as each wave breaks (every SURF_PERIOD seconds,
## like the painted surf), with the hiss of the wash running up the sand after it. Louder in a
## wind. Generated sample by sample into the ambience stream (only what it has room for).
func _fill_surf() -> void:
	if _surf_pb == null:
		return
	var n := _surf_pb.get_frames_available()
	if n <= 0:
		return
	var w := _weather.wind() if _weather else 0.4
	var loud := 0.05 + 0.05 * w
	var buf := PackedVector2Array()
	buf.resize(n)
	for i in n:
		_surf_t += 1.0 / SURF_RATE
		var phase := fmod(_surf_t / SURF_PERIOD, 1.0)
		# the crash: a quick rise, a slow fall; the wash: a hiss that follows it
		var crash := smoothstep(0.0, 0.06, phase) * exp(-phase * 5.0)
		var wash := smoothstep(0.08, 0.25, phase) * exp(-(phase - 0.08) * 3.0)
		var r := _surf_rng.randf() * 2.0 - 1.0
		_surf_lp += (r - _surf_lp) * 0.03
		_surf_lp2 += (r - _surf_lp2) * 0.3
		var sample := (_surf_lp * (0.35 + 1.6 * crash) * 2.2 + _surf_lp2 * wash * 0.25) * loud
		buf[i] = Vector2(sample, sample * 0.97)
	_surf_pb.push_buffer(buf)


# ── The frozen lake ──────────────────────────────────────────
## The aurora for the sky (camp_sky.gdshader `aurora_amount`; the shader itself only shows it at
## night, over the north = straight out over the ice): "cabin_aurora" in Cabin: Frozen North,
## fading out as the clouds thicken, and none at all in snow, rain, a storm or fog. 0 elsewhere.
func _aurora(clouds: float) -> float:
	if scene != "north":
		return 0.0
	if _weather != null and (_weather.kind() in ["rain", "storm", "snow"] or String(AppState.get_setting("cabin_fog")) != "off"):
		return 0.0
	return clampf(float(AppState.get_setting("cabin_aurora")), 0.0, 2.0) * (1.0 - smoothstep(0.4, 1.3, clouds))


## The ice's sounds (Cabin: Frozen North): a player on the Ambience bus and three generated sounds
## (_make_ice_sound): a long singing twang, a short one and a deep boom.
func _build_ice_sounds() -> void:
	_ice_player = AudioStreamPlayer.new()
	_ice_player.name = "Ice"
	_ice_player.bus = AudioManager.AMBIENCE_BUS
	add_child(_ice_player)
	_ice_sounds = [_make_ice_sound(1.6, 2400.0, 160.0, 0.0), _make_ice_sound(0.7, 1800.0, 300.0, 0.0), _make_ice_sound(2.2, 900.0, 60.0, 1.0)]


## One sound of lake ice under strain: the "pew" of a crack running through the ice (a falling
## whistle: the high notes arrive first, as they travel fastest through ice), from `top` Hz down
## to `bottom` Hz over `secs` seconds, with a short crackle at its start; `boom` 0..1 adds a deep
## thud under it. As a WAV the player can play again and again.
func _make_ice_sound(secs: float, top: float, bottom: float, boom: float) -> AudioStreamWAV:
	var rate := 22050
	var count := int(rate * secs)
	var data := PackedByteArray()
	data.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(top + bottom)
	var phase := 0.0
	var thud_phase := 0.0
	var hiss := 0.0
	for i in count:
		var t := float(i) / float(rate)
		var k := t / secs
		# the pitch falls fast at first, then slowly (the shape of the real thing)
		var f := bottom + (top - bottom) * pow(1.0 - k, 3.0)
		phase += TAU * f / float(rate)
		var env := smoothstep(0.0, 0.01, t) * pow(1.0 - k, 1.6)
		var s := sin(phase) * 0.6 + sin(phase * 2.01) * 0.15
		# the crackle at the start: filtered noise for the first tenth of a second
		hiss += (rng.randf_range(-1.0, 1.0) - hiss) * 0.4
		s += hiss * (1.0 - smoothstep(0.0, 0.1, t)) * 0.8
		if boom > 0.0:
			thud_phase += TAU * (48.0 - 18.0 * k) / float(rate)
			s += sin(thud_phase) * boom * smoothstep(0.0, 0.04, t) * exp(-t * 2.2) * 1.4
		data.encode_s16(i * 2, int(clampf(s * env * 0.3, -1.0, 1.0) * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	return wav


## Every frame on the frozen lake (cheap: a countdown): now and then the ice sounds, nearer or
## further off. Most often as the light changes (dawn and dusk, when the ice cools or warms),
## less often by day and night.
func _run_ice(delta: float) -> void:
	_ice_wait -= delta
	if _ice_wait > 0.0:
		return
	var changing := _day > 0.05 and _day < 0.8
	_ice_wait = randf_range(25.0, 70.0) if changing else randf_range(60.0, 150.0)
	ice_sound(randf())


## One ice sound now: amount 0..1 = how near it sounds. (Tests call it too.)
func ice_sound(amount: float) -> void:
	if _ice_player == null:
		return
	_ice_player.stream = _ice_sounds[randi() % _ice_sounds.size()]
	_ice_player.volume_db = lerpf(-20.0, -7.0, clampf(amount, 0.0, 1.0))
	_ice_player.pitch_scale = randf_range(0.85, 1.15)
	_ice_player.play()
	ice_calls += 1
