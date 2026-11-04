extends Room
## Throne Hall (a vast dark hall with a tall throne on a dais; blender/throne_hall_gen.py).
##   - The LAMP_* markers from Blender become three kinds of house light, tuned by name: the
##     cool blue lanterns down the nave ("Chandelier"), the blue wash on the wall behind the
##     throne ("Throne") and the warm torches on the gallery pilasters ("Gallery").
##   - Candle flames, the lantern globes and the ceiling slot glow with the house lights
##     (glow_materials on the room scene).
##   - A shaft of blue light falls from the SHAFT_Throne marker (the slot in the ceiling) onto
##     the throne, drawn with the Lecture Hall's sun_shaft.gdshader. The Throne light slider in
##     the Room tab ("throne_beam") scales it; 0 hides it.
##   - Benches: chat lines the carpet standing up (AUDIENCE_* markers 0.9 m up, from Blender).
##     The Benches tick box in the Room tab ("throne_benches") shows the BENCHES object and
##     drops the markers to bench height, so people sit. Seats are picked when the room loads,
##     so RoomHost reloads the room when that setting changes (see reload_keys()).
##   - Polished black marble and gold (clear coat / anisotropy on the imported materials).
##   - A faint generated draught (cold air moving through a stone hall) on the Ambience bus.

const MIX_RATE: float = 22050.0

@export_group("Light groups")
## Energy and range (metres) per light group; _tune_lights() picks the group from the LAMP_ name
## (contains "Chandelier", "Throne" or "Gallery").
@export var chandelier_energy: float = 7.0
@export var chandelier_range: float = 32.0
@export var chandelier_color: Color = Color(0.72, 0.82, 1.0)
@export var throne_energy: float = 4.0
@export var throne_range: float = 18.0
@export var throne_color: Color = Color(0.45, 0.55, 1.0)
@export var gallery_energy: float = 1.6
@export var gallery_range: float = 12.0
@export var gallery_color: Color = Color(1.0, 0.78, 0.5)

@export_group("Throne light")
## Width and depth (metres) of the ceiling slot the beam falls through. Must match SHAFT_SIZE
## in blender/throne_hall_gen.py.
@export var shaft_size: Vector2 = Vector2(6.0, 3.0)
@export_range(0.0, 1.0) var shaft_intensity: float = 0.3
@export var shaft_color: Color = Color(0.5, 0.65, 1.0)
## Height (metres, room space) of the dais floor: the beam stops there.
@export var dais_height: float = 1.2

@export_group("Benches")
## Height of the AUDIENCE_* markers in the .glb (standing) and where they go when the benches
## are shown (sitting). Must match STAND_Z / SEAT_Z in blender/throne_hall_gen.py.
@export var standing_height: float = 0.9
@export var bench_height: float = 0.45
@export var benches_node_name: String = "BENCHES"

@export_group("Look and sound")
## Clear coat on the marble, anisotropic gold, velvet rim on the carpet (_replacement_for).
@export var polish_materials: bool = true
@export var ambience_enabled: bool = true
@export_range(0.0, 1.0) var draught_loudness: float = 0.06

const SHAFT_SHADER := preload("res://rooms/lecture_hall/sun_shaft.gdshader")

var _amb_playback: AudioStreamGeneratorPlayback
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _lp: float = 0.0          # low-pass states for the generated draught
var _lp2: float = 0.0
var _shaft: MeshInstance3D    # the beam mesh (null without a SHAFT_Throne marker)
var _shaft_mat: ShaderMaterial
var _benches: Node3D


func _ready() -> void:
	super._ready()
	_tune_lights()
	if polish_materials:
		_apply_polish()
	_apply_benches()
	_build_shaft()
	if ambience_enabled:
		_amb_playback = _start_generated_ambience(MIX_RATE, 0.3)
	EventBus.setting_changed.connect(_on_th_setting_changed)


## The room is freed on a room swap: drop the EventBus connection with it.
func _exit_tree() -> void:
	if EventBus.setting_changed.is_connected(_on_th_setting_changed):
		EventBus.setting_changed.disconnect(_on_th_setting_changed)


## Room tab: the Benches tick box and the Throne light slider.
func get_controls() -> Array[Dictionary]:
	var out: Array[Dictionary] = [
		{"heading": "Throne Hall"},
		{"key": "throne_benches", "label": "Benches", "type": "check",
			"tooltip": "Stone benches along the carpet. On: the chat audience sits on them. Off: they stand in lines (the room reloads to re-seat everyone)."},
	]
	if _shaft != null:
		out.append({"key": "throne_beam", "label": "Throne light", "min": 0.0, "max": 2.0, "step": 0.01, "format": "%d%%", "scale": 100.0,
			"tooltip": "How strong the shaft of blue light falling on the throne is. 0% = off."})
	return out


## Settings that need the room loaded again to take effect (RoomHost reloads it): the benches
## move the audience markers, and seats are picked at load time.
func reload_keys() -> PackedStringArray:
	return PackedStringArray(["throne_benches"])


func _on_th_setting_changed(key: String, _value: Variant) -> void:
	if key == "throne_beam":
		_apply_beam()
	elif key == "throne_benches":
		_apply_benches()     # the benches show or hide at once; the reload re-seats the audience


## "throne_beam" (AppState.DEFAULTS, 0..2) times shaft_intensity; 0 hides the beam.
func _apply_beam() -> void:
	if _shaft == null:
		return
	var amount := clampf(float(AppState.get_setting("throne_beam")), 0.0, 2.0)
	_shaft.visible = amount > 0.005
	_shaft_mat.set_shader_parameter("intensity", shaft_intensity * amount)


## "throne_benches": shows or hides the BENCHES object and puts every AUDIENCE_* marker at
## bench height (on) or standing height (off). Called from _ready() before RoomHost reads the
## seats, and again when the setting changes (the reload then re-seats everyone).
func _apply_benches() -> void:
	var on := bool(AppState.get_setting("throne_benches"))
	if _benches == null:
		_benches = find_child(benches_node_name, true, false) as Node3D
	if _benches:
		_benches.visible = on
	var h := bench_height if on else standing_height
	for n in find_children(audience_prefix + "*", "Node3D", true, false):
		if n is AudienceRow:
			continue
		var p := (n as Node3D).position
		p.y = h
		(n as Node3D).position = p


## The beam follows the house lights, and the draught keeps playing.
func _process(delta: float) -> void:
	super._process(delta)
	if _shaft_mat:
		_shaft_mat.set_shader_parameter("light_level", _level)
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
		if owner_name.contains("Chandelier"):
			o.light_energy = chandelier_energy
			o.omni_range = chandelier_range
			o.light_color = chandelier_color
			o.omni_attenuation = 1.1
			o.light_volumetric_fog_energy = 0.7
		elif owner_name.contains("Throne"):
			o.light_energy = throne_energy
			o.omni_range = throne_range
			o.light_color = throne_color
			o.light_volumetric_fog_energy = 0.8
		elif owner_name.contains("Gallery"):
			o.light_energy = gallery_energy
			o.omni_range = gallery_range
			o.light_color = gallery_color
		_base_energy[l] = o.light_energy
		o.light_energy = _base_energy[l] * _level


# ── Polish ───────────────────────────────────────────────────
## Swaps every imported material that has a polished replacement (see _replacement_for).
func _apply_polish() -> void:
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


## The material to use in place of m (by its imported name from throne_hall_gen.py), or null.
func _replacement_for(m: BaseMaterial3D) -> Material:
	match m.resource_name:
		"Black_Marble":
			var b := m.duplicate() as BaseMaterial3D
			b.clearcoat_enabled = true
			b.clearcoat = 0.6
			b.clearcoat_roughness = 0.15
			b.roughness = 0.2
			return b
		"Gold":
			var g := m.duplicate() as BaseMaterial3D
			g.roughness = 0.28
			g.anisotropy_enabled = true
			g.anisotropy = 0.35
			return g
		"Carpet", "Banner":
			var c := m.duplicate() as BaseMaterial3D
			c.roughness = 1.0
			c.rim_enabled = true
			c.rim = 0.3              # velvet pile catching light at grazing angles
			c.rim_tint = 0.6
			return c
	return null


# ── The throne light ─────────────────────────────────────────
func _is_compatibility_renderer() -> bool:
	return RenderingServer.get_rendering_device() == null    # only the GL renderer has none


## One open box from the ceiling slot straight down to the dais floor: four side faces with
## UV.y 0 at the slot and 1 at the floor, as sun_shaft.gdshader expects.
func _build_shaft() -> void:
	var mk := find_child("SHAFT_Throne", true, false) as Node3D
	if mk == null:
		return
	var c := to_local(mk.global_position)
	var length := maxf(c.y - dais_height, 1.0)
	var far := Vector3(0.0, -length, 0.0)
	var half := shaft_size * 0.5
	var rim: Array[Vector3] = [c + Vector3(-half.x, 0.0, -half.y), c + Vector3(half.x, 0.0, -half.y),
			c + Vector3(half.x, 0.0, half.y), c + Vector3(-half.x, 0.0, half.y)]
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
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
	mat.set_shader_parameter("dust_amount", 0.6)
	# the Compatibility renderer has no depth texture for spatial shaders in every version,
	# so the soft fade into geometry is only used on Forward+ / Mobile
	mat.set_shader_parameter("depth_fade", not _is_compatibility_renderer())
	var screen := find_screen()
	if screen:
		var box := screen.get_aabb()
		var xf := screen.global_transform
		# the main screen's rectangle, so the shader keeps the beam from washing over the picture
		mat.set_shader_parameter("screen_c", xf * box.get_center())
		mat.set_shader_parameter("screen_x", xf.basis * Vector3(box.size.x * 0.5, 0.0, 0.0))
		mat.set_shader_parameter("screen_y", xf.basis * Vector3(0.0, box.size.y * 0.5, 0.0))
	var mi := MeshInstance3D.new()
	mi.name = "SunShafts"       # Room.get_static_meshes() skips this name
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_shaft = mi
	_shaft_mat = mat
	_apply_beam()


# ── Sound ────────────────────────────────────────────────────
## Called every frame: tops the generator buffer up with slow filtered noise (a cold draught).
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
		_lp += (w - _lp) * 0.02          # slow air movement
		_lp2 += (_lp - _lp2) * 0.03      # deep rumble under it
		var s := (_lp * 0.5 + _lp2 * 2.5) * draught_loudness
		buf[i] = Vector2(s, s * 0.95 + (_rng.randf() - 0.5) * 0.003 * draught_loudness)
	_amb_playback.push_buffer(buf)
