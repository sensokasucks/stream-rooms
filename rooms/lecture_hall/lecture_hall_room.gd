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

const MIX_RATE: float = 22050.0

@export_group("Light groups")
@export var chandelier_energy: float = 4.0
@export var chandelier_range: float = 34.0
@export var gallery_energy: float = 1.6
@export var gallery_range: float = 12.0
@export var stage_energy: float = 2.2
@export var stage_range: float = 16.0

@export_group("Set shaders")
@export var fancy_glass: bool = true
@export var glass_emission: float = 2.2
## The way sunlight travels through the room (world space). Lancets facing it get beams.
## Kept low (late afternoon) so the beams clear the gallery rail in front of the lancets.
@export var sun_direction: Vector3 = Vector3(-0.62, -0.3, -0.4)
@export var sun_shafts: bool = true
@export_range(0.0, 1.0) var shaft_intensity: float = 0.35
## How squarely a lancet must face the sun to cast a beam (0..1).
@export_range(0.0, 1.0) var shaft_min_facing: float = 0.6
@export var lancet_size: Vector2 = Vector2(1.1, 2.2)   # must match lecture_hall_gen.py
@export var polish_materials: bool = true

@export_group("Sound")
@export var ambience_enabled: bool = true
@export_range(0.0, 1.0) var room_tone_loudness: float = 0.08

var _amb_playback: AudioStreamGeneratorPlayback
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _lp: float = 0.0
var _lp2: float = 0.0
var _set_shaders: Array[ShaderMaterial] = []    # take light_level from the house lights
var _shafts: MeshInstance3D
var _shaft_mat: ShaderMaterial

const GLASS_SHADER := preload("res://rooms/lecture_hall/stained_glass.gdshader")
const SHAFT_SHADER := preload("res://rooms/lecture_hall/sun_shaft.gdshader")
const GLASS_MATERIALS := ["Glass_Lancet", "Glass_Rondel", "Glass_Fan"]
const VARNISHED := ["Oak", "Oak_Dark", "Oak_Gothic", "Door_Leaf", "Stage_Floor"]


func _ready() -> void:
	super._ready()
	_tune_lights()
	_apply_set_shaders()
	if sun_shafts:
		_build_sun_shafts()
	if ambience_enabled:
		_amb_playback = _start_generated_ambience(MIX_RATE, 0.3)
	EventBus.setting_changed.connect(_on_lh_setting_changed)


func _exit_tree() -> void:
	if EventBus.setting_changed.is_connected(_on_lh_setting_changed):
		EventBus.setting_changed.disconnect(_on_lh_setting_changed)


## Room tab: how visible the light rays from the windows are (0% = off).
func get_controls() -> Array[Dictionary]:
	if _shafts == null:
		return []
	return [
		{"heading": "Windows"},
		{"key": "sun_rays", "label": "Light rays", "min": 0.0, "max": 2.0, "step": 0.01, "format": "%d%%", "scale": 100.0,
			"tooltip": "How visible the rays of sunlight coming through the windows are. 0% = off."},
	]


func _on_lh_setting_changed(key: String, _value: Variant) -> void:
	if key == "sun_rays":
		_apply_sun_rays()


func _apply_sun_rays() -> void:
	if _shafts == null:
		return
	var amount := clampf(float(AppState.get_setting("sun_rays")), 0.0, 2.0)
	_shafts.visible = amount > 0.005
	_shaft_mat.set_shader_parameter("intensity", shaft_intensity * amount)


func _process(delta: float) -> void:
	super._process(delta)
	for m in _set_shaders:
		m.set_shader_parameter("light_level", _level)
	_fill_ambience()


# ── Set shaders ──────────────────────────────────────────────
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


func _replacement_for(m: BaseMaterial3D) -> Material:
	var n := m.resource_name
	if fancy_glass and GLASS_MATERIALS.has(n):
		var g := ShaderMaterial.new()
		g.shader = GLASS_SHADER
		g.resource_name = n
		g.set_shader_parameter("glass_tex", m.albedo_texture)
		g.set_shader_parameter("emission_strength", glass_emission * (0.8 if n == "Glass_Fan" else 1.0))
		g.set_shader_parameter("sun_dir", sun_direction.normalized())
		g.set_shader_parameter("light_level", _level)
		_set_shaders.append(g)
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


## One open box per sunlit lancet: the window's outline pushed along the sun's direction
## until it reaches the floor. All beams share one mesh and one material.
func _build_sun_shafts() -> void:
	var sun := sun_direction.normalized()
	var flat := Vector3(sun.x, 0.0, sun.z).normalized()
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var count := 0
	for n in find_children("GLASS_*", "Node3D", true, false):
		var mk := n as Node3D
		var inward := mk.global_basis.z
		inward.y = 0.0
		inward = inward.normalized()
		if inward.dot(flat) < shaft_min_facing:
			continue
		var c := to_local(mk.global_position) + inward * 0.06
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
		count += 1
	if count == 0:
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
	mat.set_shader_parameter("intensity", shaft_intensity)
	mat.set_shader_parameter("light_level", _level)
	# the Compatibility renderer has no depth texture for spatial shaders in every version,
	# so the soft fade into geometry is only used on Forward+ / Mobile
	mat.set_shader_parameter("depth_fade", not _is_compatibility_renderer())
	var screen := find_screen()
	if screen:
		var box := screen.get_aabb()
		var xf := screen.global_transform
		mat.set_shader_parameter("screen_c", xf * box.get_center())
		mat.set_shader_parameter("screen_x", xf.basis * Vector3(box.size.x * 0.5, 0.0, 0.0))
		mat.set_shader_parameter("screen_y", xf.basis * Vector3(0.0, box.size.y * 0.5, 0.0))
	_set_shaders.append(mat)
	var mi := MeshInstance3D.new()
	mi.name = "SunShafts"
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_shafts = mi
	_shaft_mat = mat
	_apply_sun_rays()


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
