extends Room
## Log Cabin: a cozy cabin with a vaulted great room. A stone chimney stands in the middle of a
## two-storey glass wall, with the big screen above the mantel, so every seat sees the fire, the
## screen and the view outside at once. A loft runs across the back; a deck lies beyond the glass.
##   - FIRST PASS (2026-11-17): layout only, flat colours, placeholder clearing outside. The
##     plan (weather, the four outdoor scenes as their own rooms, shaders, CC0 textures) is in
##     Sen's "Log Cabin room plan" doc; the layout mockup is in the project files (log-cabin/).
##   - The set is built in code by cabin_builder.gd when the room loads (there is no Blender
##     model). This script keeps what it hands back and runs the fire, the lamps and the light.
##   - Fire ("cabin_fire", 0..2): flames in the firebox (the Forge Hall's fire.gdshader), glowing
##     coals, and a flickering light that warms the room.
##   - Lamps ("cabin_lamps"): the table lamps, chandelier, dining pendant and back-door lantern
##     are the room's house lights (LAMP_ markers); they dim for a video like any room's, and burn
##     low by day.
##   - Light outside ("cabin_light": day / dusk / night): the sun or moon, the sky's colours and
##     the ambient light. A stand-in until the plan's time of day and weather are built.
##   - Gather in ("cabin_view": great_room / den): where the presenters sit. "den" puts them on
##     the den's sofa and armchair (Sen's den picture), makes the den's screen the main one and
##     its cameras the first ones. The set is built for one view, so this setting reloads the
##     room (reload_keys); the great room's screen then mirrors the den's.
## The four settings are shared in a co-stream (NetSession.SHARED_CABIN, with the "room" group).

const Builder := preload("res://rooms/log_cabin/cabin_builder.gd")
const FIRE_SHADER := preload("res://rooms/forge_hall/fire.gdshader")
## The flames of each fire: [metres sideways, metres out into the room (+) / into the firebox (-),
## size as a share of flame_size], in the fire marker's own axes (the den's fire faces +X).
const FIRE_FLAMES: Array = [[0.0, 0.0, 1.0], [-0.22, 0.05, 0.75], [0.24, 0.04, 0.7], [-0.1, -0.08, 0.6], [0.12, -0.06, 0.55]]
## The looks for "cabin_light": sun / moon direction (the way the light travels), its colour and
## energy, the sky's top and horizon colours, the ambient light's energy, and how strong the
## lamps burn (share of full) because of the daylight.
const LIGHTS: Dictionary = {
	"day": {"dir": Vector3(0.35, -0.75, 0.55), "color": Color(1.0, 0.96, 0.9), "energy": 1.25,
		"top": Color(0.32, 0.52, 0.85), "horizon": Color(0.72, 0.8, 0.88), "ambient": 0.55, "lamps": 0.35},
	"dusk": {"dir": Vector3(0.55, -0.16, 0.82), "color": Color(1.0, 0.58, 0.32), "energy": 0.8,
		"top": Color(0.22, 0.26, 0.5), "horizon": Color(0.95, 0.55, 0.36), "ambient": 0.35, "lamps": 0.85},
	"night": {"dir": Vector3(-0.3, -0.6, 0.72), "color": Color(0.55, 0.66, 1.0), "energy": 0.14,
		"top": Color(0.015, 0.02, 0.06), "horizon": Color(0.05, 0.07, 0.13), "ambient": 0.18, "lamps": 1.0},
}
## Name the sky material carries in room_info.tres: the light is only ever changed on a sky with
## this name, never on another room's (the Environment is shared by the whole app).
const SKY_NAME: String = "LogCabinSky"
## The den's fire next to the big one: share of the light's energy and range.
const DEN_FIRE_SHARE: float = 0.55

@export_group("Fire")
## The tallest flame: width and height in metres at Fire 100%.
@export var flame_size: Vector2 = Vector2(0.55, 0.75)
## The light the fire throws: energy at Fire 100%, range in metres, colour. The den's smaller fire
## gets DEN_FIRE_SHARE of the energy and range (its light has no shadows, so a short range keeps
## it from shining through the log wall into the great room).
@export var fire_light_energy: float = 3.0
@export var fire_light_range: float = 11.0
@export var fire_light_color: Color = Color(1.0, 0.52, 0.2)
## How much the fire's light wavers (share of its energy). 0 = steady.
@export_range(0.0, 0.3) var fire_flicker: float = 0.12
## The fire's light drops to this share while the lights are dimmed for a video.
@export_range(0.0, 1.0) var fire_dimmed: float = 0.5

var _parts: Dictionary = {}       # what cabin_builder.gd built (see Builder.build)
## Holds what this script draws (the flames). Named "SunShafts" so the app doesn't count them
## as the room's own meshes (Room.get_static_meshes).
var _fx: Node3D
var _sun: DirectionalLight3D      # the sun by day and at dusk, the moon at night
var _fire_mats: Array[ShaderMaterial] = []
var _fire_meshes: Array[MeshInstance3D] = []
var _fire_lights: Array[OmniLight3D] = []   # one per fire, in the order of _parts["fires"]
var _fire_strength: Array[float] = []       # each light's share of fire_light_energy
var _lamps_by_day: float = 1.0    # how strong the lamps burn because of the daylight (LIGHTS[..]["lamps"])
var _env_drawn: int = 0           # instance id of the Environment the light was last set on
var _retired: bool = false        # another room has taken over (retire()): leave the sky alone
var _time: float = 0.0
var _last_level: float = -1.0     # the house light level the lamp glow was last set for


func _ready() -> void:
	# first of all: Room._ready() and RoomHost read the set's markers straight away
	_parts = Builder.build(self, String(AppState.get_setting("cabin_view")))
	super._ready()
	_fx = Node3D.new()
	_fx.name = "SunShafts"
	add_child(_fx)
	_sun = DirectionalLight3D.new()
	_sun.name = "SunMoon"
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 60.0
	add_child(_sun)
	_build_fire()
	EventBus.setting_changed.connect(_on_cabin_setting_changed)
	_apply_light()
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


## Room tab: the fire, the lamps and the light outside.
func get_controls() -> Array[Dictionary]:
	return [
		{"heading": "Log Cabin"},
		{"key": "cabin_fire", "label": "Fire", "min": 0.0, "max": 2.0, "step": 0.01, "format": "%d%%", "scale": 100.0,
			"tooltip": "The fire in the fireplace: 0 = out, 100% = a cozy fire, 200% = roaring."},
		{"key": "cabin_lamps", "label": "Lamps", "type": "check",
			"tooltip": "The table lamps, chandelier, dining lamp and the lantern by the back door."},
		{"key": "cabin_light", "label": "Light outside", "type": "option",
			"options": [["day", "Day"], ["dusk", "Dusk"], ["night", "Night"]],
			"tooltip": "Daylight, a sunset glow or a moonlit night outside the glass. (Weather and a running clock come later.)"},
		{"key": "cabin_view", "label": "Gather in", "type": "option",
			"options": [["great_room", "Great room"], ["den", "Den"]],
			"tooltip": "Where the presenters sit. Great room: the armchairs by the big fireplace. Den: the sofa and armchair in the small den by its own fire, with the den's screen and cameras first. Changing it reloads the room."},
	]


## "Gather in" decides where the presenters' markers and the main screen are built, which the app
## only reads when the room loads: RoomHost reloads the room when it changes.
func reload_keys() -> PackedStringArray:
	return PackedStringArray(["cabin_view"])


func _on_cabin_setting_changed(key: String, _value: Variant) -> void:
	match key:
		"cabin_fire":
			_apply_fire()
		"cabin_light":
			_apply_light()


func _process(delta: float) -> void:
	super._process(delta)
	_time += delta
	_run_fire()
	if not is_equal_approx(_level, _last_level):
		_last_level = _level
		(_parts["glow_mat"] as StandardMaterial3D).emission_energy_multiplier = 2.2 * _level
	# the app swaps the Environment when a graphics setting changes: put the light back on the new one
	if not _retired and is_inside_tree():
		var env := get_world_3d().environment
		if env and env.get_instance_id() != _env_drawn:
			_apply_light()


# ── The lamps ────────────────────────────────────────────────
## The house lights (lamps, chandelier, lantern) are off with their tick box and lower by day, on
## top of what every room does (the House lights slider, dimming for a video).
func _target_level() -> float:
	if not bool(AppState.get_setting("cabin_lamps")):
		return 0.0
	return super._target_level() * _lamps_by_day


# ── The light outside ────────────────────────────────────────
## "cabin_light": points the sun / moon, colours the sky (only this room's own sky, SKY_NAME) and
## sets the ambient light and how strong the lamps burn.
func _apply_light() -> void:
	var look: Dictionary = LIGHTS.get(String(AppState.get_setting("cabin_light")), LIGHTS["dusk"])
	var dir := (look["dir"] as Vector3).normalized()
	_sun.transform = Transform3D(Basis.looking_at(dir, Vector3.UP), Vector3(0.0, 10.0, 0.0))
	_sun.light_color = look["color"]
	_sun.light_energy = float(look["energy"])
	_lamps_by_day = float(look["lamps"])
	if _retired or not is_inside_tree():
		return
	var env := get_world_3d().environment
	if env == null:
		return
	_env_drawn = env.get_instance_id()
	var sky_mat := env.sky.sky_material as ProceduralSkyMaterial if env.sky else null
	if sky_mat == null or sky_mat.resource_name != SKY_NAME:
		return
	sky_mat.sky_top_color = look["top"]
	sky_mat.sky_horizon_color = look["horizon"]
	sky_mat.ground_horizon_color = (look["horizon"] as Color).darkened(0.2)
	sky_mat.ground_bottom_color = (look["top"] as Color).darkened(0.5)
	env.ambient_light_energy = float(look["ambient"])
	env.fog_light_color = (look["horizon"] as Color).darkened(0.1)


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
		light.omni_attenuation = 1.1
		light.shadow_enabled = false
		add_child(light, true)
		light.global_position = marker.global_transform * Vector3(0.0, 0.5, 0.75)
		_fire_lights.append(light)
		_fire_strength.append(share)


## "cabin_fire" changed: show or hide the flames (their size follows in _run_fire).
func _apply_fire() -> void:
	var lit := float(AppState.get_setting("cabin_fire")) > 0.005
	for mi in _fire_meshes:
		mi.visible = lit


## Called every frame: the flames, coals and lights of both fires follow the Fire setting; the light wavers a
## little (two slow sine waves, never a strobe; steady in photosensitive-safe mode).
func _run_fire() -> void:
	var amount := clampf(float(AppState.get_setting("cabin_fire")), 0.0, 2.0)
	for m in _fire_mats:
		m.set_shader_parameter("amount", amount)
	(_parts["ember_mat"] as StandardMaterial3D).emission_energy_multiplier = 2.0 * amount
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
