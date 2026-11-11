extends Room
## Forge Hall (a tall stone workshop with light strips, a forge fireplace and skylights;
## blender/forge_hall_gen.py builds the model, from the owner's reference picture).
##   - The LAMP_* markers from Blender become two kinds of house light, tuned by name: the warm
##     hanging lanterns ("Lantern") and a cyan wash either side of the seats ("Neon").
##   - The fire: flames are drawn at the FIRE_Main (firebox) and FIRE_Slot (under the hearth)
##     markers with fire.gdshader, and a flickering orange light stands in front of the firebox.
##     The Fire slider in the Room tab ("forge_fire") scales the flames, the light, the embers
##     and the crackle; 0 puts the fire out. The flicker is gentle (a few percent, slow) and
##     stops in photosensitive-safe mode.
##   - The light strips (materials Neon_Cyan / Neon_Orange / Neon_Purple, the glowing pipes
##     and the round sign) are scaled by the Light strips slider ("forge_neon"). Like the
##     lantern glass they also dim with the house lights (glow_materials on the room scene).
##   - Sunbeams fall from the two skylights (SHAFT_Sky_n markers) to the floor, drawn with the
##     Lecture Hall's sun_shaft.gdshader, and each leaves a soft barred patch of light on the
##     floor. The Light rays slider ("sun_rays", shared with the Lecture Hall) scales both.
##   - A generated fire sound (a low roar with crackles) on the Ambience bus.

const MIX_RATE: float = 22050.0
const SHAFT_SHADER := preload("res://rooms/lecture_hall/sun_shaft.gdshader")
const FIRE_SHADER := preload("res://rooms/forge_hall/fire.gdshader")
const SUN_PATCH := preload("res://rooms/forge_hall/textures/sun_patch.png")
## Imported material names (blender/forge_hall_gen.py, setup_materials) that the two sliders scale.
const NEON_MATERIALS: PackedStringArray = ["Neon_Cyan", "Neon_Orange", "Neon_Purple", "Pipe_Glow", "Rune_Sign"]
const FIRE_MATERIALS: PackedStringArray = ["Embers"]

@export_group("Light groups")
## Energy and range (metres) per light group; _tune_lights() picks the group from the LAMP_ name
## (contains "Lantern" or "Neon").
@export var lantern_energy: float = 3.2
@export var lantern_range: float = 13.0
@export var lantern_color: Color = Color(1.0, 0.72, 0.42)
@export var neon_energy: float = 1.4
@export var neon_range: float = 11.0
@export var neon_color: Color = Color(0.3, 0.85, 1.0)

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
## Half the skylight pane: x = along the hall, y = up the roof slope (metres). Must match
## SKY_HW and the SKY_S0..SKY_S1 stretch of slope in blender/forge_hall_gen.py.
@export var skylight_half: Vector2 = Vector2(1.4, 2.71)
## The way the sunlight travels, in the room's own space (down, across the hall towards the
## forge and a little towards the back).
@export var sun_direction: Vector3 = Vector3(0.5, -1.0, 0.12)
@export_range(0.0, 1.0) var shaft_intensity: float = 0.3
@export var shaft_color: Color = Color(1.0, 0.82, 0.55)
## Brightness of the patches of sunlight on the floor at Light rays 100%.
@export_range(0.0, 2.0) var patch_strength: float = 0.5

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
var _time: float = 0.0
var _last_level: float = -1.0    # the house light level the patches / fire were last set for


func _ready() -> void:
	super._ready()
	# remember each glow material's own brightness: the sliders scale it from there
	for g in _glow:
		g["base"] = float(g["energy"])
	_tune_lights()
	_fx = Node3D.new()
	_fx.name = "SunShafts"          # Room.get_static_meshes() skips everything under this name
	add_child(_fx)
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


## Room tab: the Fire, Light strips and Light rays sliders.
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
			"tooltip": "How visible the sunbeams from the skylights and their patches on the floor are. 0% = off."})
	return out


func _on_fh_setting_changed(key: String, _value: Variant) -> void:
	match key:
		"forge_fire":
			_apply_fire()
		"forge_neon":
			_apply_neon()
		"sun_rays":
			_apply_sun_rays()


## The sunbeams and the fire follow the house lights; the fire flickers; the sound keeps playing.
func _process(delta: float) -> void:
	super._process(delta)
	_time += delta
	if not is_equal_approx(_level, _last_level):
		_last_level = _level
		if _shaft_mat:
			_shaft_mat.set_shader_parameter("light_level", _level)
		_apply_sun_patches()
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
	_scale_glow(NEON_MATERIALS, amount)
	for o in _neon_lights:
		_base_energy[o] = neon_energy * amount
		o.light_energy = neon_energy * amount * _level


## Sets the glow of every glow material named in `names` to its own brightness times amount.
func _scale_glow(names: PackedStringArray, amount: float) -> void:
	for g in _glow:
		var m := g["mat"] as BaseMaterial3D
		if names.has(m.resource_name):
			g["energy"] = float(g["base"]) * amount
			m.emission_energy_multiplier = float(g["energy"]) * _level


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
