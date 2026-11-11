extends Room
## Forge Hall (a tall hall of carved stone slabs with circuit-board light inlays, a forge
## fireplace, slanted windows under a diamond-plate ceiling and art alcoves; the model comes from
## blender/forge_hall_gen.py, after the owner's reference picture and cross-section sketch).
##   - The LAMP_* markers from Blender become two kinds of house light, tuned by name: the warm
##     hanging lanterns ("Lantern") and a cyan wash either side of the seats ("Neon").
##   - The fire: flames are drawn at the FIRE_Main (firebox) and FIRE_Slot (under the hearth)
##     markers with fire.gdshader, and a flickering orange light stands in front of the firebox.
##     The Fire slider in the Room tab ("forge_fire") scales the flames, the light, the embers
##     and the crackle; 0 puts the fire out. The flicker is gentle (a few percent, slow) and
##     stops in photosensitive-safe mode.
##   - The light inlays (materials Neon_Cyan / Neon_Orange / Neon_Purple: lines set flush into
##     the floor, walls and pillars like the traces of a circuit board; plus the glowing pipes
##     and the round sign) are scaled by the Light strips slider ("forge_neon"). Like the
##     lantern glass they also dim with the house lights (glow_materials on the room scene).
##   - The screen: the model only has a flat TVScreen rectangle. _shape_screen() swaps its mesh
##     for one that is moved, resized and bent from the "forge_screen_*" settings (Room tab >
##     Screen shape). The LED dots and hologram look are the app's own (RoomInfo.screen_led_amount
##     / screen_hologram on room_info.tres; core/screen_lights.gd), with their sliders added to
##     the Room tab by RoomHost.
##   - Art frames: one in each wall alcove (ART_n markers). _build_art() makes a frame and a
##     canvas; the frame material ("forge_art_frame"), the style ("forge_art_style": a lit
##     picture or a see-through hologram, art_holo.gdshader) and each picture ("forge_art_n",
##     blank = the built-in poster textures/art_n.png) are settings on the Room tab.
##   - Sunbeams fall from two of the slanted windows (SHAFT_Sky_n markers) to the floor, drawn with the
##     Lecture Hall's sun_shaft.gdshader, and each leaves a soft barred patch of light on the
##     floor. The Light rays slider ("sun_rays", shared with the Lecture Hall) scales both.
##   - A generated fire sound (a low roar with crackles) on the Ambience bus.

const MIX_RATE: float = 22050.0
const SHAFT_SHADER := preload("res://rooms/lecture_hall/sun_shaft.gdshader")
const FIRE_SHADER := preload("res://rooms/forge_hall/fire.gdshader")
const SUN_PATCH := preload("res://rooms/forge_hall/textures/sun_patch.png")
const ART_HOLO_SHADER := preload("res://rooms/forge_hall/art_holo.gdshader")
const MARBLE := preload("res://rooms/forge_hall/textures/slab_marble.png")
## The built-in posters (blender/make_forge_textures.py), %d = the frame's number.
const ART_BUILTIN: String = "res://rooms/forge_hall/textures/art_%d.png"
## How many art frames there can be: must match the "forge_art_1".."forge_art_5" settings in
## AppState.DEFAULTS and the ALCOVES list in blender/forge_hall_gen.py.
const ART_COUNT: int = 5
## Columns the bent screen is cut into (a flat screen uses the same mesh).
const SCREEN_COLUMNS: int = 40
## Imported material names (blender/forge_hall_gen.py, setup_materials) that the two sliders scale.
const NEON_MATERIALS: PackedStringArray = ["Neon_Cyan", "Neon_Orange", "Neon_Purple", "Pipe_Glow", "Rune_Sign"]
const FIRE_MATERIALS: PackedStringArray = ["Embers"]

@export_group("Light groups")
## Energy and range (metres) per light group; _tune_lights() picks the group from the LAMP_ name
## (contains "Lantern" or "Neon").
@export var lantern_energy: float = 3.2
@export var lantern_range: float = 16.0
@export var lantern_color: Color = Color(1.0, 0.72, 0.42)
@export var neon_energy: float = 1.4
@export var neon_range: float = 11.0
@export var neon_color: Color = Color(0.3, 0.85, 1.0)
## The inlays' glow at Light strips 100%, as a share of what the model's materials have (there
## are a lot of them now, and at full strength their bloom hid the stone).
@export_range(0.0, 1.0) var neon_strength: float = 0.6

@export_group("Fire")
## The firebox flames: width and height in metres (the slot's are lower and a little wider).
@export var flame_size: Vector2 = Vector2(1.5, 1.7)
@export var slot_flame_size: Vector2 = Vector2(1.6, 0.55)
## The light the fire throws: energy at Fire 100% with the house lights up, and its range (metres).
@export var fire_light_energy: float = 4.5
@export var fire_light_range: float = 12.0
@export var fire_light_color: Color = Color(1.0, 0.52, 0.2)
## How much the fire's light wavers (share of its energy). 0 = steady.
@export_range(0.0, 0.3) var fire_flicker: float = 0.1
## The fire's light drops to this share while the house lights are dimmed for a video, so it
## doesn't wash over the picture.
@export_range(0.0, 1.0) var fire_dimmed: float = 0.35

@export_group("Sunbeams")
## Half the window pane the sun comes through: x = along the hall, y = up the slanted glass
## (metres). Must match SKY_HW and SKY_HALF_SLANT in blender/forge_hall_gen.py.
@export var skylight_half: Vector2 = Vector2(1.25, 1.37)
## The way the sunlight travels, in the room's own space (down, across the hall towards the
## forge and a little towards the back).
@export var sun_direction: Vector3 = Vector3(0.7, -1.0, 0.12)
@export_range(0.0, 1.0) var shaft_intensity: float = 0.3
@export var shaft_color: Color = Color(1.0, 0.82, 0.55)
## Brightness of the patches of sunlight on the floor at Light rays 100%.
@export_range(0.0, 2.0) var patch_strength: float = 0.5

@export_group("Screen shape")
## The part of the screen wall the screen may cover, in the TVScreen mesh's own space (metres:
## x across the wall, y up from the floor). It is the screen alcove (ALC_HW / ALC_TOP in
## blender/forge_hall_gen.py) less a small margin; _shape_screen() keeps the screen inside it.
@export var screen_area: Rect2 = Rect2(-4.95, 0.4, 9.9, 7.1)
## Half the angle (degrees) the screen wraps through at Bend 100%.
@export var screen_bend_degrees: float = 50.0

@export_group("Alcove art")
## The largest a picture is drawn (metres, width x height); it keeps its own shape inside that.
@export var art_max_size: Vector2 = Vector2(1.4, 2.0)
## Width of the frame's bars and how far they stand out from the wall (metres).
@export var art_frame_width: float = 0.09
@export var art_frame_depth: float = 0.07
## How far a hologram floats in front of the alcove's back wall (metres).
@export var art_holo_float: float = 0.14
@export var art_holo_tint: Color = Color(0.45, 0.95, 1.0)
## Glow of the "neon" frame material at Light strips 100% with the house lights up.
@export var art_neon_energy: float = 2.5

@export_group("Sound")
@export var ambience_enabled: bool = true
@export_range(0.0, 1.0) var fire_loudness: float = 0.07

var _amb_playback: AudioStreamGeneratorPlayback
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _lp: float = 0.0             # low-pass state for the fire's roar
var _pop: float = 0.0            # the current crackle, dying away
var _shafts: MeshInstance3D      # the sunbeams (null without SHAFT_Sky markers)
var _shaft_mat: ShaderMaterial
var _patches: MeshInstance3D     # the patches of sunlight on the floor
var _patch_mat: StandardMaterial3D
## Holds what this script draws (flames, sunbeams, patches). Named "SunShafts" so the app
## doesn't count them as the room's own meshes.
var _fx: Node3D
var _fire_mats: Array[ShaderMaterial] = []
var _fire_meshes: Array[MeshInstance3D] = []
var _fire_light: OmniLight3D
var _neon_lights: Array[OmniLight3D] = []
var _screen_box: AABB            # the TVScreen rectangle as the model has it (set once in _shape_screen)
var _screen_has_box: bool = false
## One entry per art frame: {n: int (1..), root: Node3D, canvas: MeshInstance3D,
## bars: Array of MeshInstance3D (top, bottom, left, right), tex: Texture2D (what it shows now),
## path: String (the picture file that was asked for last, "" = the built-in poster)}.
var _art: Array[Dictionary] = []
var _art_frame_mat: StandardMaterial3D     # shared by every frame's bars
var _time: float = 0.0
var _last_level: float = -1.0    # the house light level the patches / fire were last set for


func _ready() -> void:
	super._ready()
	# remember each glow material's own brightness: the sliders scale it from there
	for g in _glow:
		g["base"] = float(g["energy"])
	_tune_lights()
	# before anything reads the screen: RoomHost places the screen's lights, the curtain and
	# the camera's focus from this mesh right after _ready
	_shape_screen()
	_fx = Node3D.new()
	_fx.name = "SunShafts"          # Room.get_static_meshes() skips everything under this name
	add_child(_fx)
	_build_art()
	_build_fire()
	_build_sunbeams()
	_apply_neon()
	_apply_fire()
	if ambience_enabled:
		_amb_playback = _start_generated_ambience(MIX_RATE, 0.3)
	EventBus.setting_changed.connect(_on_fh_setting_changed)


## The room is freed on a room swap: drop the EventBus connection with it.
func _exit_tree() -> void:
	if EventBus.setting_changed.is_connected(_on_fh_setting_changed):
		EventBus.setting_changed.disconnect(_on_fh_setting_changed)


## The screen's place, size and bend change where RoomHost puts the screen's lights and the
## curtain, which it only works out when the room loads: so it reloads the room a moment after
## one of these stops changing (the screen itself already moves while the slider is dragged).
func reload_keys() -> PackedStringArray:
	return PackedStringArray(["forge_screen_x", "forge_screen_y", "forge_screen_size", "forge_screen_bend"])


## Room tab: the Fire, Light strips and Light rays sliders, the screen's shape and the alcove
## art. (RoomHost adds the LED dots and Hologram screen sliders after these.)
func get_controls() -> Array[Dictionary]:
	var out: Array[Dictionary] = [
		{"heading": "Forge Hall"},
		{"key": "forge_fire", "label": "Fire", "min": 0.0, "max": 2.0, "step": 0.01, "format": "%d%%", "scale": 100.0,
			"tooltip": "How big the forge fire is: its flames, the light it throws and its crackle. 0% = out."},
		{"key": "forge_neon", "label": "Light strips", "min": 0.0, "max": 2.0, "step": 0.01, "format": "%d%%", "scale": 100.0,
			"tooltip": "How bright the cyan, orange and purple light strips and the glowing pipes are. 0% = off."},
	]
	if _shafts != null:
		out.append({"key": "sun_rays", "label": "Light rays", "min": 0.0, "max": 2.0, "step": 0.01, "format": "%d%%", "scale": 100.0,
			"tooltip": "How visible the sunbeams from the slanted windows and their patches on the floor are. 0% = off."})
	out.append({"heading": "Screen shape"})
	out.append({"key": "forge_screen_bend", "label": "Bend", "min": -1.0, "max": 1.0, "step": 0.01, "format": "%d%%", "scale": 100.0,
		"tooltip": "Bends the screen. Above 0% its edges wrap towards the audience (concave), below 0% its middle bulges out at them (convex). 0% = flat. The room reloads a moment after you let go."})
	out.append({"key": "forge_screen_size", "label": "Size", "min": 0.4, "max": 1.15, "step": 0.01, "format": "%d%%", "scale": 100.0,
		"tooltip": "How big the screen is. 100% = 8.6 metres wide. It never grows past its alcove."})
	out.append({"key": "forge_screen_x", "label": "Move left/right", "min": -3.0, "max": 3.0, "step": 0.05, "format": "%.2f m",
		"tooltip": "Slides the screen along its wall: left (-) or right (+), in metres. It stops at the alcove's edges, so make it smaller first to move it further."})
	out.append({"key": "forge_screen_y", "label": "Move up/down", "min": -2.0, "max": 2.0, "step": 0.05, "format": "%.2f m",
		"tooltip": "Slides the screen down (-) or up (+) its wall, in metres. It stops at the alcove's edges."})
	if not _art.is_empty():
		out.append({"heading": "Alcove art"})
		out.append({"key": "forge_art_frame", "label": "Frame", "type": "option",
			"options": [["brass", "Brass"], ["steel", "Steel"], ["wood", "Dark wood"], ["marble", "Marble"], ["neon", "Light strip"], ["none", "No frame"]],
			"tooltip": "What the frames round the alcove art are made of. Light strip glows and follows the Light strips slider."})
		out.append({"key": "forge_art_style", "label": "Art style", "type": "option",
			"options": [["picture", "Picture"], ["hologram", "Hologram"]],
			"tooltip": "Picture: flat on the wall, lit by the room. Hologram: see-through and glowing, floating in front of the wall with scan lines."})
		for a in _art:
			out.append({"key": "forge_art_%d" % int(a["n"]), "label": "Art %d" % int(a["n"]), "type": "picture",
				"placeholder": "blank = the built-in poster",
				"tooltip": "The picture in alcove %d (counted from the front of the left wall, then the right wall, then the back wall). PNG, JPG, WebP or GIF (animated GIFs play), up to 3 MB. Blank = the built-in poster." % int(a["n"])})
	return out


func _on_fh_setting_changed(key: String, _value: Variant) -> void:
	match key:
		"forge_fire":
			_apply_fire()
		"forge_neon":
			_apply_neon()
		"sun_rays":
			_apply_sun_rays()
		"forge_screen_x", "forge_screen_y", "forge_screen_size", "forge_screen_bend":
			_shape_screen()         # shown at once; RoomHost reloads the room shortly after
		"forge_art_frame", "forge_art_style", "photosensitive_safe":
			_apply_art_frame()
			for a in _art:
				_apply_art(a)
		_:
			if key.begins_with("forge_art_"):
				for a in _art:
					if key == "forge_art_%d" % int(a["n"]):
						_load_art(a)


## The sunbeams and the fire follow the house lights; the fire flickers; the sound keeps playing.
func _process(delta: float) -> void:
	super._process(delta)
	_time += delta
	if not is_equal_approx(_level, _last_level):
		_last_level = _level
		if _shaft_mat:
			_shaft_mat.set_shader_parameter("light_level", _level)
		_apply_sun_patches()
		_apply_art_level()
	_flicker_fire()
	_fill_ambience()


# ── Lights ───────────────────────────────────────────────────
## Sets each house light from its group's energy / range / colour (LAMP_ lights are children
## named "Light", so the group comes from the parent's name) and records the new base energy.
func _tune_lights() -> void:
	for l in _house_lights:
		var owner_name := String(l.get_parent().name) if l.name == &"Light" else String(l.name)
		var o := l as OmniLight3D
		if o == null:
			continue
		if owner_name.contains("Lantern"):
			o.light_energy = lantern_energy
			o.omni_range = lantern_range
			o.light_color = lantern_color
			o.light_volumetric_fog_energy = 0.6
		elif owner_name.contains("Neon"):
			o.light_energy = neon_energy
			o.omni_range = neon_range
			o.light_color = neon_color
			_neon_lights.append(o)
		_base_energy[l] = o.light_energy
		o.light_energy = float(_base_energy[l]) * _level


## "forge_neon" (AppState.DEFAULTS, 0..2): scales the glow of the NEON_MATERIALS and the two cyan
## wash lights. Room._process then keeps dimming them with the house lights from the new value.
func _apply_neon() -> void:
	var amount := clampf(float(AppState.get_setting("forge_neon")), 0.0, 2.0)
	_scale_glow(NEON_MATERIALS, amount * neon_strength)
	for o in _neon_lights:
		_base_energy[o] = neon_energy * amount
		o.light_energy = neon_energy * amount * _level
	_apply_art_level()          # the "Light strip" art frames follow this slider too


## Sets the glow of every glow material named in `names` to its own brightness times amount.
func _scale_glow(names: PackedStringArray, amount: float) -> void:
	for g in _glow:
		var m := g["mat"] as BaseMaterial3D
		if names.has(m.resource_name):
			g["energy"] = float(g["base"]) * amount
			m.emission_energy_multiplier = float(g["energy"]) * _level


# ── The screen's shape ───────────────────────────────────────
## Swaps the TVScreen mesh for one moved, resized and bent from the "forge_screen_x / _y /
## _size / _bend" settings (AppState.DEFAULTS). Called from _ready (before RoomHost reads the
## screen) and again whenever one of the four changes.
## The model's rectangle is thin along the mesh's own Z and faces +Z (the audience), with
## UV (0, 0) at its top left as the audience sees it; the new mesh keeps all of that, so the
## app's screen material works on it unchanged. It is a strip of SCREEN_COLUMNS columns along
## an arc: Bend x screen_bend_degrees is half the angle the arc turns through. The picture's
## width along the arc stays the same, and the arc is always in front of the wall: bent
## inwards (concave) the edges come forward, bent outwards (convex) the middle does.
func _shape_screen() -> void:
	var screen := find_screen()
	if screen == null or screen.mesh == null:
		return
	if not _screen_has_box:
		_screen_box = screen.mesh.get_aabb()
		_screen_has_box = true
	var box := _screen_box
	# size first (so it fits the alcove), then the place (so it stays inside it)
	var fit := minf(screen_area.size.x / box.size.x, screen_area.size.y / box.size.y)
	var k := clampf(float(AppState.get_setting("forge_screen_size")), 0.2, fit)
	var w := box.size.x * k
	var h := box.size.y * k
	var mid := box.get_center()
	var cx := clampf(mid.x + float(AppState.get_setting("forge_screen_x")),
		screen_area.position.x + w * 0.5, screen_area.end.x - w * 0.5)
	var cy := clampf(mid.y + float(AppState.get_setting("forge_screen_y")),
		screen_area.position.y + h * 0.5, screen_area.end.y - h * 0.5)
	var z0 := box.end.z                     # the model's screen surface (just off the wall)
	var bend := clampf(float(AppState.get_setting("forge_screen_bend")), -1.0, 1.0)
	var half_angle := absf(bend) * deg_to_rad(screen_bend_degrees)
	var flat := half_angle < 0.002
	var radius := 0.0 if flat else (w * 0.5) / half_angle
	var deepest := 0.0 if flat else radius * (1.0 - cos(half_angle))   # how far the arc's ends are from its middle
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for i in SCREEN_COLUMNS + 1:
		var t := float(i) / SCREEN_COLUMNS          # 0 = the audience's left edge, 1 = right
		var a := (t * 2.0 - 1.0) * half_angle       # this column's angle round the arc
		var x := (t - 0.5) * w
		var z := z0
		var n := Vector3(0.0, 0.0, 1.0)
		if not flat:
			x = radius * sin(a)
			var depth := radius * (1.0 - cos(a))    # 0 in the middle, `deepest` at the edges
			if bend > 0.0:
				z = z0 + depth                      # concave: the edges come towards the audience
				n = Vector3(-sin(a), 0.0, cos(a))
			else:
				z = z0 + deepest - depth            # convex: the middle comes towards the audience
				n = Vector3(sin(a), 0.0, cos(a))
		verts.append(Vector3(cx + x, cy + h * 0.5, z))
		verts.append(Vector3(cx + x, cy - h * 0.5, z))
		norms.append(n)
		norms.append(n)
		uvs.append(Vector2(t, 0.0))
		uvs.append(Vector2(t, 1.0))
		if i < SCREEN_COLUMNS:
			var v := i * 2                          # this column's top; +1 = its bottom, +2 / +3 = the next column's
			# clockwise as the audience sees it (Redot's front face)
			idx.append_array(PackedInt32Array([v, v + 2, v + 3, v, v + 3, v + 1]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	screen.mesh = mesh


# ── Alcove art ───────────────────────────────────────────────
## A frame (four bars) and a canvas at every ART_n marker (the middle of an alcove's back wall,
## +Z facing into the room). They live under _fx so they aren't counted as the room's meshes.
func _build_art() -> void:
	_art_frame_mat = StandardMaterial3D.new()
	_apply_art_frame()
	for n in range(1, ART_COUNT + 1):
		var marker := find_child("ART_%d" % n, true, false) as Node3D
		if marker == null:
			continue
		var root := Node3D.new()
		root.name = "ArtFrame%d" % n
		_fx.add_child(root)
		root.global_transform = Transform3D(marker.global_basis.orthonormalized(), marker.global_position)
		var canvas := MeshInstance3D.new()
		canvas.name = "Canvas"
		canvas.mesh = QuadMesh.new()
		canvas.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(canvas)
		var bars: Array[MeshInstance3D] = []
		for b in 4:
			var bar := MeshInstance3D.new()
			bar.name = "Bar%d" % b
			bar.mesh = BoxMesh.new()
			bar.material_override = _art_frame_mat
			root.add_child(bar)
			bars.append(bar)
		var a := {"n": n, "root": root, "canvas": canvas, "bars": bars, "tex": null, "path": ""}
		_art.append(a)
		_load_art(a)


## "forge_art_frame" (AppState.DEFAULTS): what the shared frame material looks like.
## "none" hides the bars (see _apply_art).
func _apply_art_frame() -> void:
	var m := _art_frame_mat
	m.albedo_texture = null
	m.emission_enabled = false
	m.metallic = 1.0
	m.roughness = 0.35
	m.uv1_triplanar = false
	match String(AppState.get_setting("forge_art_frame")):
		"steel":
			m.albedo_color = Color(0.62, 0.65, 0.7)
			m.roughness = 0.3
		"wood":
			m.albedo_color = Color(0.3, 0.18, 0.09)
			m.metallic = 0.0
			m.roughness = 0.7
		"marble":
			m.albedo_color = Color(1.0, 1.0, 1.0)
			m.albedo_texture = MARBLE
			m.uv1_triplanar = true      # the bars have no useful UVs of their own
			m.metallic = 0.25
			m.roughness = 0.25
		"neon":
			m.albedo_color = Color(0.05, 0.12, 0.14)
			m.metallic = 0.0
			m.emission_enabled = true
			m.emission = Color(0.3, 0.9, 1.0)
		_:
			m.albedo_color = Color(0.8, 0.62, 0.28)    # brass
	_apply_art_level()


## What follows the house lights and the Light strips slider in the art: the "Light strip"
## frame's glow and the holograms' brightness. Called when either changes.
func _apply_art_level() -> void:
	if _art_frame_mat == null:
		return
	var strips := clampf(float(AppState.get_setting("forge_neon")), 0.0, 2.0)
	_art_frame_mat.emission_energy_multiplier = art_neon_energy * strips * _level
	for a in _art:
		var sm := (a["canvas"] as MeshInstance3D).material_override as ShaderMaterial
		if sm:
			sm.set_shader_parameter("level", _level)


## Picks frame a's picture: the file in its "forge_art_n" setting, or the built-in poster when
## that is blank. A file is read and decoded off the main thread, like a podium picture
## (core/presenters/presenter.gd), because an animated GIF can take a moment.
func _load_art(a: Dictionary) -> void:
	var n := int(a["n"])
	var path := String(AppState.get_setting("forge_art_%d" % n)).strip_edges()
	a["path"] = path
	if path == "":
		a["tex"] = load(ART_BUILTIN % n) if ResourceLoader.exists(ART_BUILTIN % n) else null
		_apply_art(a)
		return
	var bytes := PictureFile.read_file(path)
	if bytes.is_empty():
		@warning_ignore("integer_division")
		EventBus.status_message.emit("Alcove art %d: couldn't read that picture (png, jpg, webp or gif, up to %d MB)." % [n, PictureFile.MAX_BYTES / (1024 * 1024)], true)
		return
	var out: Array = [null]
	var task := WorkerThreadPool.add_task(func() -> void: out[0] = PictureFile.texture_from_bytes(bytes), false, "alcove art")
	_finish_art.call_deferred(task, a, path, out)


## Main thread, after the decode: show the picture unless another was asked for meanwhile.
func _finish_art(task: int, a: Dictionary, path: String, out: Array) -> void:
	WorkerThreadPool.wait_for_task_completion(task)
	if not is_inside_tree() or path != String(a["path"]):
		return
	if out[0] == null:
		EventBus.status_message.emit("Alcove art %d: that picture couldn't be decoded." % int(a["n"]), true)
		return
	a["tex"] = out[0]
	_apply_art(a)


## Sizes frame a's canvas to its picture (the picture's own shape, as big as fits art_max_size),
## puts the four bars round it and gives the canvas the material for "forge_art_style":
## "picture" = flat on the wall and lit by the room (with a little glow of its own so it still
## reads when the lights are down), "hologram" = art_holo.gdshader, floating off the wall.
func _apply_art(a: Dictionary) -> void:
	var canvas := a["canvas"] as MeshInstance3D
	var tex := a["tex"] as Texture2D
	canvas.visible = tex != null
	var size := art_max_size
	if tex != null and tex.get_height() > 0:
		var shape := float(tex.get_width()) / float(tex.get_height())
		size = Vector2(minf(art_max_size.x, art_max_size.y * shape), 0.0)
		size.y = size.x / shape
	(canvas.mesh as QuadMesh).size = size
	var holo := String(AppState.get_setting("forge_art_style")) == "hologram"
	if holo:
		var sm := ShaderMaterial.new()
		sm.shader = ART_HOLO_SHADER
		sm.set_shader_parameter("picture", tex)
		sm.set_shader_parameter("tint", art_holo_tint)
		sm.set_shader_parameter("level", _level)
		sm.set_shader_parameter("flicker", 0.0 if bool(AppState.get_setting("photosensitive_safe")) else 1.0)
		canvas.material_override = sm
		canvas.position = Vector3(0.0, 0.0, art_holo_float)
	else:
		var pm := StandardMaterial3D.new()
		pm.albedo_texture = tex
		pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR    # cut-out pictures keep their outline
		pm.roughness = 0.6
		pm.emission_enabled = true
		pm.emission_texture = tex
		pm.emission = Color(1.0, 1.0, 1.0)
		pm.emission_energy_multiplier = 0.18
		canvas.material_override = pm
		canvas.position = Vector3(0.0, 0.0, 0.012)
	# the bars: top, bottom, left, right, overlapping at the corners
	var fw := art_frame_width
	var bars: Array = a["bars"]
	var framed := String(AppState.get_setting("forge_art_frame")) != "none"
	var spans: Array[Vector2] = [Vector2(size.x + fw * 2.0, fw), Vector2(size.x + fw * 2.0, fw), Vector2(fw, size.y), Vector2(fw, size.y)]
	var spots: Array[Vector2] = [Vector2(0.0, (size.y + fw) * 0.5), Vector2(0.0, -(size.y + fw) * 0.5),
		Vector2(-(size.x + fw) * 0.5, 0.0), Vector2((size.x + fw) * 0.5, 0.0)]
	for b in 4:
		var bar := bars[b] as MeshInstance3D
		bar.visible = framed
		(bar.mesh as BoxMesh).size = Vector3(spans[b].x, spans[b].y, art_frame_depth)
		bar.position = Vector3(spots[b].x, spots[b].y, art_frame_depth * 0.5)


# ── The fire ─────────────────────────────────────────────────
## Flames at both FIRE_ markers and the light in front of the firebox. The markers sit at the
## bottom centre of the flames with +Z facing into the room.
func _build_fire() -> void:
	var main := find_child("FIRE_Main", true, false) as Node3D
	var slot := find_child("FIRE_Slot", true, false) as Node3D
	if main:
		# three rectangles crossing in the middle, so the fire has body from every side
		for k in 3:
			_add_flame(main, flame_size, deg_to_rad(-60.0 + 60.0 * k), float(k))
		_fire_light = OmniLight3D.new()
		_fire_light.name = "FireLight"
		_fire_light.light_color = fire_light_color
		_fire_light.omni_range = fire_light_range
		_fire_light.omni_attenuation = 1.2
		_fire_light.shadow_enabled = false
		_fire_light.light_volumetric_fog_energy = 0.8
		add_child(_fire_light)
		_fire_light.global_position = main.global_position + main.global_basis.z * 1.0 + Vector3.UP * 0.8
	if slot:
		_add_flame(slot, slot_flame_size, 0.0, 5.0)


## One upright flame rectangle at marker, turned by yaw (radians) round the vertical; seed_value
## makes its flames move differently from the others'.
func _add_flame(marker: Node3D, size: Vector2, yaw: float, seed_value: float) -> void:
	var quad := QuadMesh.new()
	quad.size = size
	var mat := ShaderMaterial.new()
	mat.shader = FIRE_SHADER
	mat.set_shader_parameter("seed", seed_value)
	var mi := MeshInstance3D.new()
	mi.name = "FireFlame"
	mi.mesh = quad
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fx.add_child(mi, true)     # true: keeps a readable name (FireFlame, FireFlame2 ...)
	# QuadMesh: centred, facing +Z, UV.y 0 at the top: the shader wants 0 at the logs, so the
	# rectangle is turned upside down (and UV.x mirrored, which a flame doesn't mind)
	var b := marker.global_basis.orthonormalized().rotated(Vector3.UP, yaw)
	mi.global_transform = Transform3D(Basis(-b.x, -b.y, b.z), marker.global_position + Vector3.UP * size.y * 0.5)
	_fire_mats.append(mat)
	_fire_meshes.append(mi)


## "forge_fire" (AppState.DEFAULTS, 0..2): the flames, the embers' glow and (through
## _flicker_fire) the light. 0 hides the flames.
func _apply_fire() -> void:
	var amount := clampf(float(AppState.get_setting("forge_fire")), 0.0, 2.0)
	for m in _fire_mats:
		m.set_shader_parameter("amount", amount)
	for mi in _fire_meshes:
		mi.visible = amount > 0.005
	_scale_glow(FIRE_MATERIALS, amount)


## Called every frame: the fire light's energy from the Fire slider and the house light level,
## wavering a little (two slow sine waves, never a strobe; steady in photosensitive-safe mode).
func _flicker_fire() -> void:
	if _fire_light == null:
		return
	var amount := clampf(float(AppState.get_setting("forge_fire")), 0.0, 2.0)
	_fire_light.visible = amount > 0.005
	if not _fire_light.visible:
		return
	var waver := 1.0
	if fire_flicker > 0.0 and not bool(AppState.get_setting("photosensitive_safe")):
		waver += fire_flicker * (0.6 * sin(_time * 5.3) + 0.4 * sin(_time * 8.9 + 1.7))
	_fire_light.light_energy = fire_light_energy * amount * lerpf(fire_dimmed, 1.0, _level) * waver


# ── Sunbeams ─────────────────────────────────────────────────
func _is_compatibility_renderer() -> bool:
	return RenderingServer.get_rendering_device() == null    # only the GL renderer has none


## One beam per SHAFT_Sky_n marker: the pane's outline pushed along sun_direction down to the
## floor (four side faces, UV.y 0 at the glass and 1 at the floor, as sun_shaft.gdshader
## expects), plus a flat patch of light where it lands. The marker's X axis runs along the
## hall and its -Z axis up the roof slope (see build_markers in the generator).
func _build_sunbeams() -> void:
	var dir := sun_direction.normalized()
	if dir.y > -0.05:
		return                      # the sun has to shine downwards
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var pverts := PackedVector3Array()
	var puvs := PackedVector2Array()
	var inv := global_transform.affine_inverse()
	for n in find_children("SHAFT_Sky*", "Node3D", true, false):
		var xf := inv * (n as Node3D).global_transform
		var hx := xf.basis.x.normalized() * skylight_half.x
		var hy := -xf.basis.z.normalized() * skylight_half.y
		var c := xf.origin
		var rim: Array[Vector3] = [c - hx - hy, c + hx - hy, c + hx + hy, c - hx + hy]
		var land: Array[Vector3] = []
		for p in rim:
			land.append(p + dir * (p.y / -dir.y))      # where this corner's ray meets the floor (y = 0)
		for i in 4:
			var j := (i + 1) % 4
			var nrm := (rim[j] - rim[i]).cross(land[i] - rim[i]).normalized()
			var quad: Array[Vector3] = [rim[i], rim[j], land[j], rim[i], land[j], land[i]]
			var quv: Array[Vector2] = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 0), Vector2(1, 1), Vector2(0, 1)]
			for k in 6:
				verts.append(quad[k])
				norms.append(nrm)
				uvs.append(quv[k])
		# the patch: 2 cm above the floor so it never flickers against it
		var lift := Vector3.UP * 0.02
		var pq: Array[Vector3] = [land[0], land[1], land[2], land[0], land[2], land[3]]
		var pu: Array[Vector2] = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 0), Vector2(1, 1), Vector2(0, 1)]
		for k in 6:
			pverts.append(pq[k] + lift)
			puvs.append(pu[k])
	if verts.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := ShaderMaterial.new()
	mat.shader = SHAFT_SHADER
	mat.set_shader_parameter("color", shaft_color)
	mat.set_shader_parameter("intensity", shaft_intensity)
	mat.set_shader_parameter("light_level", _level)
	mat.set_shader_parameter("dust_amount", 0.8)
	# the Compatibility renderer has no depth texture for spatial shaders in every version,
	# so the soft fade into geometry is only used on Forward+ / Mobile
	mat.set_shader_parameter("depth_fade", not _is_compatibility_renderer())
	var screen := find_screen()
	if screen:
		var box := screen.get_aabb()
		var sxf := screen.global_transform
		# the main screen's rectangle, so the shader keeps the beams from washing over the picture
		mat.set_shader_parameter("screen_c", sxf * box.get_center())
		mat.set_shader_parameter("screen_x", sxf.basis * Vector3(box.size.x * 0.5, 0.0, 0.0))
		mat.set_shader_parameter("screen_y", sxf.basis * Vector3(0.0, box.size.y * 0.5, 0.0))
	var mi := MeshInstance3D.new()
	mi.name = "Beams"
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fx.add_child(mi)
	_shafts = mi
	_shaft_mat = mat
	# the patches: the barred-window picture added onto the floor
	var parrays := []
	parrays.resize(Mesh.ARRAY_MAX)
	parrays[Mesh.ARRAY_VERTEX] = pverts
	parrays[Mesh.ARRAY_TEX_UV] = puvs
	var pmesh := ArrayMesh.new()
	pmesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, parrays)
	_patch_mat = StandardMaterial3D.new()
	_patch_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_patch_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_patch_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_patch_mat.albedo_texture = SUN_PATCH
	var pmi := MeshInstance3D.new()
	pmi.name = "Patches"
	pmi.mesh = pmesh
	pmi.material_override = _patch_mat
	pmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fx.add_child(pmi)
	_patches = pmi
	_apply_sun_rays()


## "sun_rays" (AppState.DEFAULTS, 0..2) times shaft_intensity; 0 hides the beams and patches.
func _apply_sun_rays() -> void:
	if _shafts == null:
		return
	var amount := clampf(float(AppState.get_setting("sun_rays")), 0.0, 2.0)
	_shafts.visible = amount > 0.005
	_patches.visible = _shafts.visible
	_shaft_mat.set_shader_parameter("intensity", shaft_intensity * amount)
	_apply_sun_patches()


## The floor patches' brightness: Light rays times patch_strength times the house light level.
func _apply_sun_patches() -> void:
	if _patch_mat == null:
		return
	var amount := clampf(float(AppState.get_setting("sun_rays")), 0.0, 2.0)
	var k := patch_strength * amount * _level
	_patch_mat.albedo_color = Color(shaft_color.r * k, shaft_color.g * k, shaft_color.b * k)


# ── Sound ────────────────────────────────────────────────────
## Called every frame: tops the generator buffer up with the fire: a soft low roar (filtered
## noise) with a crackle now and then (a short burst that dies away). Louder with a bigger fire.
func _fill_ambience() -> void:
	if _amb_playback == null:
		return
	var n := _amb_playback.get_frames_available()
	if n <= 0:
		return
	var amount := clampf(float(AppState.get_setting("forge_fire")), 0.0, 2.0)
	var buf := PackedVector2Array()
	buf.resize(n)
	for i in n:
		var w := _rng.randf() * 2.0 - 1.0
		_lp += (w - _lp) * 0.04
		if _rng.randf() < 0.00035 * amount:          # about eight crackles a second at 100%
			_pop = 0.4 + _rng.randf() * 0.6
		_pop *= 0.992
		var s := (_lp * 1.6 + w * _pop * 0.5) * fire_loudness * amount
		buf[i] = Vector2(s, s * 0.9)
	_amb_playback.push_buffer(buf)
