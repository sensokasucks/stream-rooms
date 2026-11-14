extends Room
## Lecture hall (Victorian Gothic university theatre).
##   - The LAMP_* markers from Blender become three kinds of house light, tuned by name:
##     the chandelier, the lit gallery arcade high on the walls, and a warm stage wash.
##   - Chandelier bulbs and the arcade glow dim with the house lights (glow_materials),
##     including the House lights dimmer in the Room tab.
##   - A faint generated room tone (air handling in a big wooden hall) on the Ambience bus.
##   - Set shaders: backlit stained glass (stained_glass.gdshader) on the lancets, rose
##     rondels and door fanlights; dusty sunbeams (sun_shaft.gdshader) from the lancets that
##     face the sun, built from the GLASS_n markers; varnished wood, velvet carpet and
##     translucent marble. The glass and beams follow the house lights.
##   - Time of day ("lh_time", hours; "lh_day_minutes" lets the clock run; "lh_clouds"): the
##     sky outside the windows (window_sky.gdshaderinc, drawn on the glass) and the sunbeams
##     follow the hour: the sun rises on one side of the hall, sets on the other, and its beams
##     come in through whichever lancets face it, golden when it is low; at night the moon sends
##     faint blue beams. _run_clock() / _apply_time().
##   - Window glass ("lh_glass"): the tall lancets' pale diamond panes (or all their panes) are
##     clear glass you see the sky and the town's roofs through, or all stained glass as before.
##   - Set detail ("lh_detail", each PC's own): "detailed" swaps the woods, walls, carpet and
##     leather for photo-textured copies (detail/, made by detail/make_detail_textures.py from
##     CC0 Poly Haven photos) with normal and roughness maps; "simple" keeps the painted look,
##     which is lighter on a slow graphics card. "auto" follows Graphics quality (Low = simple).
##     _apply_detail(). The photo textures are only loaded once a PC picks the detailed look.
## Both Lecture Hall rooms (lecture_hall and lecture_hall_panel) use this script and these settings.

const MIX_RATE: float = 22050.0

@export_group("Light groups")
## Energy and range (metres) per light group; _tune_lights() picks the group from the LAMP_ name
## (contains "Chandelier", "Gallery" or "Stage").
@export var chandelier_energy: float = 9.0
@export var chandelier_range: float = 34.0
@export var gallery_energy: float = 1.6
@export var gallery_range: float = 12.0
@export var stage_energy: float = 2.2
@export var stage_range: float = 16.0

@export_group("Set shaders")
## Use stained_glass.gdshader on the GLASS_MATERIALS (off = the plain imported materials).
@export var fancy_glass: bool = true
@export var glass_emission: float = 2.2
@export var sun_shafts: bool = true
## The beams' colour while the sun is high; a low sun turns it golden orange (_apply_time).
@export var shaft_color: Color = Color(1.0, 0.84, 0.6)
## Moonbeams at night: colour, and strength compared with the sun's.
@export var moon_color: Color = Color(0.55, 0.65, 1.0)
@export_range(0.0, 1.0) var moon_strength: float = 0.3
@export_range(0.0, 1.0) var shaft_intensity: float = 0.35
## How squarely a lancet must face the sun to cast a beam (0..1).
@export_range(0.0, 1.0) var shaft_min_facing: float = 0.6
@export var lancet_size: Vector2 = Vector2(1.1, 2.2)   # must match lecture_hall_gen.py
## Clear coat on the VARNISHED woods and leather, velvet rim on the carpet, glossy brass and
## subsurface marble (_replacement_for).
@export var polish_materials: bool = true

@export_group("Time of day")
## How far the hour must move (hours) before the sky uniforms and beams are redrawn: 0.05 h =
## 3 minutes of room time, small enough that the beams glide.
@export var time_step: float = 0.05
## The sun's path in the room's own axes (X across the hall, Z towards the audience's end):
## it rises on the -X side (sun_east), passes high over the hall leaning to sun_south, sets on
## +X. Chosen so 16:30 gives the old fixed late-afternoon beams.
@export var sun_east: Vector3 = Vector3(-1.0, 0.0, 0.0)
@export var sun_south: Vector3 = Vector3(0.0, 0.0, 1.0)
@export var sun_lean: float = 0.45

@export_group("Sound")
@export var ambience_enabled: bool = true
@export_range(0.0, 1.0) var room_tone_loudness: float = 0.08

var _amb_playback: AudioStreamGeneratorPlayback
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
# low-pass filter states for the generated room tone
var _lp: float = 0.0
var _lp2: float = 0.0
var _set_shaders: Array[ShaderMaterial] = []    # take light_level from the house lights
## The sun beam mesh (null when no lancet faces the sun); the "sun_rays" setting scales it.
var _shafts: MeshInstance3D
var _shaft_mat: ShaderMaterial
## The glass materials (stained_glass.gdshader): _apply_time() hands them the sky.
var _glass_mats: Array[ShaderMaterial] = []
## The lancets the light can come through: [centre (room space), inward direction (flat)].
var _lancets: Array = []
var _hour: float = 16.5           # the room's clock, hours 0..24 (starts at "lh_time")
var _hour_drawn: float = -99.0    # the hour the sky and beams were last drawn for
var _beam_strength: float = 1.0   # 0..1 from the hour: 0 = no sun or moon to make beams
## Surfaces that have a detailed look: {mi, surface, simple (override material or null), name}.
var _detail_slots: Array[Dictionary] = []
## Material name -> the detailed copy (made on first use, see _detailed_material()).
var _detailed: Dictionary = {}
var _detail_on: bool = false

const GLASS_SHADER := preload("res://rooms/lecture_hall/stained_glass.gdshader")
const SHAFT_SHADER := preload("res://rooms/lecture_hall/sun_shaft.gdshader")
## Imported material names (from blender/lecture_hall_gen.py) that the set shaders replace.
const GLASS_MATERIALS := ["Glass_Lancet", "Glass_Rondel", "Glass_Fan"]
const VARNISHED := ["Oak", "Oak_Dark", "Oak_Gothic", "Door_Leaf", "Stage_Floor"]
const SKY_NOISE := preload("res://rooms/lecture_hall/detail/sky_noise.png")
## Materials with a detailed look, and which maps detail/ has for them (each is
## detail/<lower-case name>.jpg, _n.jpg = normal map, _r.jpg = roughness). Keep in step with
## detail/make_detail_textures.py.
const DETAIL_MATS := {
	"Oak": "nr", "Oak_Gothic": "nr", "Stage_Floor": "nr", "Door_Leaf": "nr", "Oak_Dark": "nr",
	"Leather": "nr", "Carpet": "n", "Red_Wall": "n", "Ochre_Panel": "n", "Ceiling_Panel": "n",
}
## Materials that are a plain colour in the simple look: the detailed texture carries the colour.
const DETAIL_OWN_COLOUR := ["Oak_Dark", "Leather"]
const DETAIL_DIR := "res://rooms/lecture_hall/detail/"


func _ready() -> void:
	super._ready()
	_tune_lights()
	_apply_set_shaders()
	_find_detail_slots()
	_apply_detail()
	_find_lancets()
	if sun_shafts and not _lancets.is_empty():
		_make_sun_shafts()
	_hour = fposmod(float(AppState.get_setting("lh_time")), 24.0)
	_run_clock(0.0)
	if ambience_enabled:
		_amb_playback = _start_generated_ambience(MIX_RATE, 0.3)
	EventBus.setting_changed.connect(_on_lh_setting_changed)


## The room is freed on a room swap: drop the EventBus connection with it.
func _exit_tree() -> void:
	if EventBus.setting_changed.is_connected(_on_lh_setting_changed):
		EventBus.setting_changed.disconnect(_on_lh_setting_changed)


## Room tab: the hall's look (Set detail), the windows (Window glass, Light rays) and the time
## of day outside. The control panel builds them (Room.get_controls() in rooms/room.gd has the
## format) and hands them on to Stream Core's Stream Rooms settings.
func get_controls() -> Array[Dictionary]:
	var c: Array[Dictionary] = [
		{"heading": "Lecture Hall"},
		{"key": "lh_detail", "label": "Set detail", "type": "option",
			"options": [["auto", "Auto (follows Graphics quality)"], ["simple", "Simple"], ["detailed", "Detailed (photo textures)"]],
			"tooltip": "How the hall is drawn on this PC. Detailed: real wood grain on the desks, rails, carved panels, doors and stage, plaster on the walls, pile on the carpet and crinkles in the leather, with bumps that catch the light. Simple: the plain painted look, lighter on a slow graphics card. Auto picks from Graphics quality: Low = Simple, otherwise Detailed. Each PC in a co-stream chooses its own."},
		{"heading": "Windows"},
		{"key": "lh_glass", "label": "Window glass", "type": "option",
			"options": [["quarries", "Clear diamond panes (see the sky)"], ["clear", "All clear panes"], ["stained", "All stained glass"]],
			"tooltip": "The tall windows high on the walls. Clear diamond panes: the pale panes round the coloured pictures are clear, so you see the sky, the clouds, the sun or moon and the town's roofs through them. All clear panes: only the coloured border stays. All stained glass: every pane coloured, as before. The round windows and the door fanlights stay stained glass."},
	]
	if _shafts != null:
		c.append({"key": "sun_rays", "label": "Light rays", "min": 0.0, "max": 2.0, "step": 0.01, "format": "%d%%", "scale": 100.0,
			"tooltip": "How visible the rays of sunlight (or moonlight at night) coming through the windows are. They follow the Time of day. 0% = off."})
	c.append_array([
		{"heading": "Time of day"},
		{"key": "lh_time", "label": "Time of day", "min": 0.0, "max": 24.0, "step": 0.1, "format": "%.1f h",
			"tooltip": "The hour outside, 0 to 24. 6 = sunrise, 12 = noon, 18 = sunset. The sky in the windows, the glow of the stained glass and the sunbeams follow it: morning light comes in on one side of the hall, evening light on the other."},
		{"key": "lh_day_minutes", "label": "Day length", "min": 0.0, "max": 120.0, "step": 1.0, "format": "%d min", "zero": "Clock stopped",
			"tooltip": "Lets the clock run: how many minutes a full day and night takes, starting from the Time of day. 0 = the clock stands still."},
		{"key": "lh_clouds", "label": "Clouds", "min": 0.0, "max": 2.0, "step": 0.01, "format": "%d%%", "scale": 100.0,
			"tooltip": "How much cloud drifts across the sky outside. 0% = a clear sky, 200% = overcast. Passing clouds also dim the sunlight on the glass for a moment."},
	])
	return c


func _on_lh_setting_changed(key: String, _value: Variant) -> void:
	match key:
		"sun_rays":
			_apply_sun_rays()
		"lh_detail", "graphics_quality":
			_apply_detail()
		"lh_time":
			_hour = fposmod(float(AppState.get_setting("lh_time")), 24.0)
			_hour_drawn = -99.0      # _run_clock redraws next frame
		"lh_clouds", "lh_glass", "photosensitive_safe":
			_hour_drawn = -99.0


## "sun_rays" (AppState.DEFAULTS, 0..2) times shaft_intensity; 0 hides the beams.
func _apply_sun_rays() -> void:
	if _shafts == null:
		return
	var amount := clampf(float(AppState.get_setting("sun_rays")), 0.0, 2.0) * _beam_strength
	_shafts.visible = amount > 0.005 and _shafts.mesh != null
	_shaft_mat.set_shader_parameter("intensity", shaft_intensity * amount)


## Set shaders (glass, beams) follow the house light level.
func _process(delta: float) -> void:
	super._process(delta)
	for m in _set_shaders:
		m.set_shader_parameter("light_level", _level)
	_run_clock(delta)
	_fill_ambience()


# ── Set shaders ──────────────────────────────────────────────
## Swaps every imported material that has a replacement (see _replacement_for).
func _apply_set_shaders() -> void:
	var made: Dictionary = {}     # original material -> replacement (shared stays shared)
	for n in find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			if mi.get_surface_override_material(s) != null:
				continue      # already swapped (glow materials)
			var m := mi.mesh.surface_get_material(s) as BaseMaterial3D
			if m == null:
				continue
			if not made.has(m):
				made[m] = _replacement_for(m)
			if made[m] != null:
				mi.set_surface_override_material(s, made[m])


## The material to use in place of m (by its imported name), or null to keep it.
func _replacement_for(m: BaseMaterial3D) -> Material:
	var n := m.resource_name
	if fancy_glass and GLASS_MATERIALS.has(n):
		var g := ShaderMaterial.new()
		g.shader = GLASS_SHADER
		g.resource_name = n
		g.set_shader_parameter("glass_tex", m.albedo_texture)
		g.set_shader_parameter("emission_strength", glass_emission * (0.8 if n == "Glass_Fan" else 1.0))
		g.set_shader_parameter("light_level", _level)
		g.set_shader_parameter("sky_noise", SKY_NOISE)
		g.set_shader_parameter("is_lancet", n == "Glass_Lancet")
		_set_shaders.append(g)
		_glass_mats.append(g)
		return g
	if not polish_materials:
		return null
	if VARNISHED.has(n):
		var w := m.duplicate() as BaseMaterial3D
		w.clearcoat_enabled = true
		w.clearcoat = 0.35 if n != "Stage_Floor" else 0.5
		w.clearcoat_roughness = 0.3
		return w
	match n:
		"Carpet":
			var c := m.duplicate() as BaseMaterial3D
			c.roughness = 1.0
			c.rim_enabled = true
			c.rim = 0.3              # velvet pile catching light at grazing angles
			c.rim_tint = 0.6
			return c
		"Leather":
			var l := m.duplicate() as BaseMaterial3D
			l.clearcoat_enabled = true
			l.clearcoat = 0.25
			l.clearcoat_roughness = 0.45
			return l
		"Marble":
			var mb := m.duplicate() as BaseMaterial3D
			mb.subsurf_scatter_enabled = true
			mb.subsurf_scatter_strength = 0.35
			mb.roughness = 0.3
			return mb
		"Brass":
			var b := m.duplicate() as BaseMaterial3D
			b.roughness = 0.28
			b.anisotropy_enabled = true
			b.anisotropy = 0.35
			return b
	return null


func _is_compatibility_renderer() -> bool:
	return RenderingServer.get_rendering_device() == null    # only the GL renderer has none


## Remembers every lancet (GLASS_n markers from the generator: at the glass's centre, +Z into
## the hall) as [centre in room space, inward direction made flat].
func _find_lancets() -> void:
	for n in find_children("GLASS_*", "Node3D", true, false):
		var mk := n as Node3D
		var inward := global_basis.inverse() * mk.global_basis.z
		inward.y = 0.0
		_lancets.append([to_local(mk.global_position), inward.normalized()])


## The (empty) beam mesh and its material; _rebuild_shafts() fills the mesh in for the hour.
func _make_sun_shafts() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = SHAFT_SHADER
	mat.set_shader_parameter("intensity", shaft_intensity)
	mat.set_shader_parameter("light_level", _level)
	mat.set_shader_parameter("color", shaft_color)
	# the Compatibility renderer has no depth texture for spatial shaders in every version,
	# so the soft fade into geometry is only used on Forward+ / Mobile
	mat.set_shader_parameter("depth_fade", not _is_compatibility_renderer())
	var screen := find_screen()
	if screen:
		var box := screen.get_aabb()
		var xf := screen.global_transform
		# the main screen's rectangle, so the shader can keep the beams from washing over the picture
		mat.set_shader_parameter("screen_c", xf * box.get_center())
		mat.set_shader_parameter("screen_x", xf.basis * Vector3(box.size.x * 0.5, 0.0, 0.0))
		mat.set_shader_parameter("screen_y", xf.basis * Vector3(0.0, box.size.y * 0.5, 0.0))
	_set_shaders.append(mat)
	var mi := MeshInstance3D.new()
	mi.name = "SunShafts"
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_shafts = mi
	_shaft_mat = mat


## One open box per lancet the light comes in through: the window's outline pushed along
## `travel` (the way the light moves, room space) until it reaches the floor. All beams share
## one mesh and one material. No lancet faces the light (or travel is zero): no mesh.
## Called by _apply_time() whenever the hour has moved; a dozen quads, so it is cheap.
func _rebuild_shafts(travel: Vector3) -> void:
	if _shafts == null:
		return
	_shafts.mesh = null
	if travel.length_squared() < 0.0001 or travel.y > -0.02:
		return
	var sun := travel.normalized()
	var flat := Vector3(sun.x, 0.0, sun.z).normalized()
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	for lancet: Array in _lancets:
		var inward: Vector3 = lancet[1]
		if inward.dot(flat) < shaft_min_facing:
			continue
		var c: Vector3 = lancet[0] + inward * 0.06
		var across := Vector3.UP.cross(inward).normalized()
		var half := lancet_size * 0.5
		var rim: Array[Vector3] = [c - across * half.x - Vector3.UP * half.y, c + across * half.x - Vector3.UP * half.y,
				c + across * half.x + Vector3.UP * half.y, c - across * half.x + Vector3.UP * half.y]
		var length := minf(c.y / maxf(-sun.y, 0.05) * 1.05, 32.0)
		var far := sun * length
		for i in 4:
			var a: Vector3 = rim[i]
			var b: Vector3 = rim[(i + 1) % 4]
			var nrm := (b - a).cross(far).normalized()
			var quad: Array[Vector3] = [a, b, b + far, a, b + far, a + far]
			var quv: Array[Vector2] = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 0), Vector2(1, 1), Vector2(0, 1)]
			for k in 6:
				verts.append(quad[k])
				norms.append(nrm)
				uvs.append(quv[k])
	if verts.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_shafts.mesh = mesh


# ── Time of day ──────────────────────────────────────────────
## Called every frame. Moves the clock on while "lh_day_minutes" is above 0, and redraws the
## sky and the beams when the hour has moved by time_step (or a setting asked for it by
## resetting _hour_drawn).
func _run_clock(delta: float) -> void:
	var day_minutes := float(AppState.get_setting("lh_day_minutes"))
	if day_minutes > 0.0:
		_hour = fposmod(_hour + delta * 24.0 / (day_minutes * 60.0), 24.0)
	if absf(_hour - _hour_drawn) >= time_step:
		_hour_drawn = _hour
		_apply_time()


## The hour the room's clock shows now, 0..24 (for tests; "lh_time" only says where it started).
func get_hour() -> float:
	return _hour


## Pointing AT the sun for an hour, room space: up at 6, highest at 12 (leaning to sun_south),
## down at 18; below the floor at night.
func sun_towards(hour: float) -> Vector3:
	var a := (hour - 6.0) / 12.0 * PI
	return (sun_east.normalized() * cos(a) + Vector3.UP * sin(a) * 0.85 + sun_south.normalized() * sun_lean).normalized()


## Everything that follows the hour (_hour; 6 = sunrise, 12 = noon, 18 = sunset): the sky on the
## glass (sun, moon, day / dusk amounts, clouds, the Window glass choice) and the beams, from
## the sun while it is up and from the moon at night, through the lancets facing the light.
func _apply_time() -> void:
	var sun := sun_towards(_hour)
	var moon := (-sun + Vector3.UP * 0.35).normalized()     # opposite the sun, a little higher
	var day := smoothstep(-0.12, 0.22, sun.y)
	var dusk := (1.0 - smoothstep(0.0, 0.4, absf(sun.y))) * smoothstep(-0.3, -0.05, sun.y)
	var turn := global_basis.orthonormalized()               # the glass shader works in world space
	var glass_mode: int = {"stained": 0, "quarries": 1, "clear": 2}.get(String(AppState.get_setting("lh_glass")), 1)
	for g in _glass_mats:
		g.set_shader_parameter("sun_to", turn * sun)
		g.set_shader_parameter("moon_to", turn * moon)
		g.set_shader_parameter("day", day)
		g.set_shader_parameter("dusk", dusk)
		g.set_shader_parameter("cloud_amount", clampf(float(AppState.get_setting("lh_clouds")), 0.0, 2.0))
		g.set_shader_parameter("star_amount", 1.0)
		g.set_shader_parameter("glass_mode", glass_mode)
	# the light through the windows
	var travel := Vector3.ZERO
	_beam_strength = 0.0
	var colour := shaft_color
	if sun.y > 0.03:
		travel = -sun
		_beam_strength = smoothstep(0.03, 0.2, sun.y)
		colour = Color(1.0, 0.55, 0.25).lerp(shaft_color, smoothstep(0.1, 0.5, sun.y))
	elif moon.y > 0.1:
		travel = -moon
		_beam_strength = moon_strength * smoothstep(0.1, 0.3, moon.y)
		colour = moon_color
	# clouds dim the beams a little on average
	_beam_strength *= 1.0 - 0.25 * clampf(float(AppState.get_setting("lh_clouds")) - 0.5, 0.0, 1.5)
	if _shaft_mat:
		_shaft_mat.set_shader_parameter("color", colour)
	_rebuild_shafts(travel)
	_apply_sun_rays()


# ── Set detail ───────────────────────────────────────────────
## Finds every surface whose material has a detailed look (DETAIL_MATS), and remembers what it
## shows in the simple look (the override _apply_set_shaders put there, or none).
func _find_detail_slots() -> void:
	for n in find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(s) as BaseMaterial3D
			if m != null and DETAIL_MATS.has(m.resource_name):
				_detail_slots.append({"mi": mi, "surface": s, "simple": mi.get_surface_override_material(s), "name": m.resource_name})


## True when this PC should draw the detailed look: "lh_detail" (Room tab > Set detail), whose
## "auto" follows Graphics quality (low = simple).
func wants_detail() -> bool:
	match String(AppState.get_setting("lh_detail")):
		"simple":
			return false
		"detailed":
			return true
	return String(AppState.get_setting("graphics_quality")) != "low"


## Shows the simple or the detailed look on every detail surface. Called when the room loads
## and when "lh_detail" or "graphics_quality" changes.
func _apply_detail() -> void:
	_detail_on = wants_detail()
	for slot in _detail_slots:
		var mi := slot["mi"] as MeshInstance3D
		var s := int(slot["surface"])
		if _detail_on:
			var base: Material = slot["simple"] if slot["simple"] != null else mi.mesh.surface_get_material(s)
			mi.set_surface_override_material(s, _detailed_material(String(slot["name"]), base as BaseMaterial3D))
		else:
			mi.set_surface_override_material(s, slot["simple"])


## True when the detailed look is showing (for tests).
func is_detailed() -> bool:
	return _detail_on


## The detailed copy of a material: its simple look (with the clear coat and so on) plus the
## photo colour, normal and roughness maps from detail/. Made once per material name; the
## textures are only loaded here, so a PC on the simple look never loads them.
func _detailed_material(mat_name: String, base: BaseMaterial3D) -> BaseMaterial3D:
	if _detailed.has(mat_name):
		return _detailed[mat_name]
	var d := base.duplicate() as BaseMaterial3D
	var file := DETAIL_DIR + mat_name.to_lower()
	d.albedo_texture = load(file + ".jpg") as Texture2D
	if DETAIL_OWN_COLOUR.has(mat_name):
		d.albedo_color = Color.WHITE            # the texture carries the colour
	var maps := String(DETAIL_MATS[mat_name])
	if maps.contains("n"):
		d.normal_enabled = true
		d.normal_texture = load(file + "_n.jpg") as Texture2D
		d.normal_scale = 1.0
	if maps.contains("r"):
		d.roughness_texture = load(file + "_r.jpg") as Texture2D
		d.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GRAYSCALE
		d.roughness = 1.0                       # the map holds the roughness itself
	d.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_detailed[mat_name] = d
	return d


## Sets each house light from its group's energy / range (LAMP_ lights are children named
## "Light", so the group comes from the parent's name) and records the new base energy.
func _tune_lights() -> void:
	for l in _house_lights:
		var owner_name := String(l.get_parent().name) if l.name == &"Light" else String(l.name)
		var o := l as OmniLight3D
		if o == null:
			continue
		if owner_name.contains("Chandelier"):
			o.light_energy = chandelier_energy
			o.omni_range = chandelier_range
			o.omni_attenuation = 1.1
			o.light_volumetric_fog_energy = 0.6
		elif owner_name.contains("Gallery"):
			o.light_energy = gallery_energy
			o.omni_range = gallery_range
		elif owner_name.contains("Stage"):
			o.light_energy = stage_energy
			o.omni_range = stage_range
			o.light_color = Color(1.0, 0.86, 0.66)
		_base_energy[l] = o.light_energy
		o.light_energy = _base_energy[l] * _level


## Called every frame: tops the generator buffer up with filtered noise (air rush and rumble).
func _fill_ambience() -> void:
	if _amb_playback == null:
		return
	var n := _amb_playback.get_frames_available()
	if n <= 0:
		return
	var buf := PackedVector2Array()
	buf.resize(n)
	for i in n:
		var w := _rng.randf() * 2.0 - 1.0
		_lp += (w - _lp) * 0.04          # soft air rush
		_lp2 += (_lp - _lp2) * 0.05      # low rumble
		var s := (_lp * 0.6 + _lp2 * 2.0) * room_tone_loudness
		buf[i] = Vector2(s, s * 0.95 + (_rng.randf() - 0.5) * 0.004 * room_tone_loudness)
	_amb_playback.push_buffer(buf)
