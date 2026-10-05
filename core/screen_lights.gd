class_name ScreenLights
extends Node3D
## Attached to the current room by RoomHost. Puts the shared screen texture on
## the room's TVScreen mesh (and any SCREEN_Mirror_* meshes), and drives three
## spotlights + a fill light from the left / centre / right colours of the picture.
## Mirror screens get a soft spill light each. Freed together with the room.

const SCREEN_SHADER: Shader = preload("res://core/screen.gdshader")
## Same picture, but see-through (for rooms with RoomInfo.screen_hologram).
const HOLO_SHADER: Shader = preload("res://core/screen_holo.gdshader")
## AppState setting -> screen shader parameter, for hologram rooms.
const HOLO_PARAMS: Dictionary = {
	"holo_amount": "holo_amount", "holo_glitch": "holo_glitch", "holo_lines": "holo_lines",
	"holo_speed": "holo_speed", "holo_noise": "holo_noise",
	"holo_color1": "holo_color1", "holo_color2": "holo_color2",
}
const SPOT_ENERGY: float = 4.0
const SPILL_ENERGY: float = 1.5
const BEAM_ENERGY: float = 6.0
const MIRROR_ENERGY: float = 2.0
## Must match film_fps in screen.gdshader.
const FILM_FPS: float = 18.0
## Render layer 20: projection screens, so the projector beam can skip them.
const PROJECTED_LAYER: int = 1 << 19
const ALL_LAYERS: int = (1 << 20) - 1

@export var response_speed: float = 10.0
@export var cast_shadows: bool = true

var _screen: MeshInstance3D
var _mat: ShaderMaterial = ShaderMaterial.new()
var _spots: Array[SpotLight3D] = []
var _spill: OmniLight3D
var _beam: SpotLight3D
var _mirror_lights: Array[OmniLight3D] = []
var _multiplier: float = 1.0
var _film: float = 0.0          # current film dirt (drives the light flicker)
var _room_film: float = 0.0     # the room's own film amount (RoomInfo)
var _hologram: bool = false
var _params: Dictionary = {}    # every shader parameter set, so a shader swap can restore them
var _targets: Array[Color] = [ScreenFeed.IDLE_COLOR, ScreenFeed.IDLE_COLOR, ScreenFeed.IDLE_COLOR]
var _last_screen: Array[Color] = []
var _colors: Array[Color] = [ScreenFeed.IDLE_COLOR, ScreenFeed.IDLE_COLOR, ScreenFeed.IDLE_COLOR]


## Called once by RoomHost right after the room is added to the tree.
## projector: optional BEAM_Projector marker - adds a visible beam aimed at the screen.
## mirrors: optional extra screens that show the same picture.
func setup(screen: MeshInstance3D, info: RoomInfo, initial_texture: Texture2D,
		projector: Node3D = null, mirrors: Array[MeshInstance3D] = []) -> void:
	_screen = screen
	_multiplier = info.screen_light_multiplier
	_hologram = info.screen_hologram
	_mat.shader = SCREEN_SHADER
	_set_param("idle_color", ScreenFeed.IDLE_COLOR)
	_set_param("led_amount", info.screen_led_amount)
	_set_param("led_count", info.screen_led_count)
	_set_param("film_tint", info.screen_film_tint)
	_set_param("screen_matte", info.screen_matte)
	_room_film = info.screen_film_amount
	_apply_film()
	if _hologram:
		for key in HOLO_PARAMS.keys():
			_apply_holo(key)
		_apply_holo("holo_transparency")
	_screen.material_override = _mat
	_build_lights(info.screen_light_range)
	if projector:
		_build_beam(projector)
		if info.screen_matte > 0.0:
			# The picture already *is* the projector's light; don't let the beam light
			# wash it out a second time (it still lights the fabric border and the wall).
			_screen.layers = PROJECTED_LAYER
			_beam.light_cull_mask = ALL_LAYERS & ~PROJECTED_LAYER
			_beam.light_projector = _beam_gate_texture()
	for m in mirrors:
		_add_mirror(m)
	_set_texture(initial_texture)
	_apply_glow()


func _ready() -> void:
	EventBus.screen_texture_changed.connect(_set_texture)
	EventBus.screen_colors_changed.connect(_on_colors)
	EventBus.setting_changed.connect(_on_setting_changed)
	EventBus.curtain_covering_changed.connect(_on_curtain)


func _exit_tree() -> void:
	EventBus.screen_texture_changed.disconnect(_set_texture)
	EventBus.screen_colors_changed.disconnect(_on_colors)
	EventBus.curtain_covering_changed.disconnect(_on_curtain)
	EventBus.setting_changed.disconnect(_on_setting_changed)


func _process(delta: float) -> void:
	if _spots.is_empty():
		return
	var k := clampf(delta * response_speed, 0.0, 1.0)
	var total := Color(0, 0, 0)
	var strength: float = float(AppState.get_setting("screen_light")) * _multiplier * _film_flicker() * _opacity_light()
	for i in 3:
		_colors[i] = _colors[i].lerp(_targets[i], k)
		_apply(_spots[i], _colors[i], SPOT_ENERGY * strength)
		total += _colors[i]
	var avg := total / 3.0
	_apply(_spill, avg, SPILL_ENERGY * strength)
	if _beam:
		_apply(_beam, avg, BEAM_ENERGY * _film_flicker())
	var mirror_strength: float = float(AppState.get_setting("screen_light")) * _opacity_light()
	for l in _mirror_lights:
		_apply(l, avg, MIRROR_ENERGY * mirror_strength)


# ── Private ──────────────────────────────────────────────────
## Matches the shutter flicker in screen.gdshader (same frame rate), so the light
## on the room flickers with the picture.
func _film_flicker() -> float:
	if _film <= 0.0:
		return 1.0
	var fr := floorf(Time.get_ticks_msec() / 1000.0 * FILM_FPS)
	return 1.0 - minf(_film, 1.5) * 0.14 * fposmod(sin(fr * 12.9898) * 43758.5453, 1.0)


func _set_texture(tex: Texture2D) -> void:
	_set_param("has_texture", tex != null)
	_set_param("screen_texture", tex)


func _on_colors(left: Color, center: Color, right: Color) -> void:
	_last_screen = [left, center, right]
	if AppState.is_curtain_covering():
		return          # the curtain hides the picture: its colours mustn't light the room
	_targets = [left, center, right]


## Curtain closed: a dim warm glow instead of the picture's light (nothing on the screen leaks
## into the room). Open: back to the picture's colours.
func _on_curtain(covering: bool) -> void:
	if covering:
		var glow: Color = (AppState.get_setting("curtain_color") as Color).lightened(0.25) * 0.35
		_targets = [glow, glow, glow]
	elif _last_screen.size() == 3:
		_targets.assign(_last_screen)      # (assign: a plain duplicate() isn't an Array[Color])


func _apply_glow() -> void:
	_set_param("brightness", float(AppState.get_setting("screen_glow")))


func _on_setting_changed(key: String, _value: Variant) -> void:
	if key == "screen_glow":
		_apply_glow()
	elif key == "film_look":
		_apply_film()
	elif _hologram and (HOLO_PARAMS.has(key) or key == "holo_transparency"):
		_apply_holo(key)


## Film look setting: up to 100% scales the whole look; above that only the dirt grows.
func _apply_film() -> void:
	var s := maxf(float(AppState.get_setting("film_look")), 0.0)
	_set_param("film_amount", _room_film * minf(s, 1.0))
	_film = _room_film * s
	_set_param("film_dirt", _film)


func _apply_holo(key: String) -> void:
	var v: Variant = AppState.get_setting(key)
	if key == "holo_transparency":
		_set_param("holo_alpha", 1.0 - clampf(float(v), 0.0, 1.0))
		# Only use the see-through shader when it's needed: opaque screens still show up
		# in screen-space reflections (the wet road), transparent ones don't.
		var want := HOLO_SHADER if float(v) > 0.001 else SCREEN_SHADER
		if _mat.shader != want:
			_mat.shader = want
			for k in _params.keys():
				_mat.set_shader_parameter(k, _params[k])
	else:
		_set_param(HOLO_PARAMS[key], v)


func _set_param(param: String, value: Variant) -> void:
	_params[param] = value
	_mat.set_shader_parameter(param, value)


## A see-through hologram screen throws less light on the room.
func _opacity_light() -> float:
	if not _hologram:
		return 1.0
	return 1.0 - 0.6 * clampf(float(AppState.get_setting("holo_transparency")), 0.0, 1.0)


func _apply(light: Light3D, c: Color, base_energy: float) -> void:
	# Hue -> light_color, brightness -> light_energy, so dark scenes darken the room.
	var m := maxf(c.r, maxf(c.g, c.b))
	if m > 0.001:
		light.light_color = Color(c.r / m, c.g / m, c.b / m)
	light.light_energy = m * base_energy
	light.visible = light.light_energy > 0.005


## Centre, outward normal, "across" (left-to-right as seen by a viewer) and width of a flat screen.
func _screen_frame(mesh: MeshInstance3D) -> Dictionary:
	var aabb := mesh.get_aabb()
	var xf := mesh.global_transform
	var center := xf * aabb.get_center()
	var size := aabb.size
	var normal := Vector3.ZERO
	# Prefer the mesh's own normal (exact); fall back to the thinnest bounding-box axis.
	if mesh.mesh and mesh.mesh.get_surface_count() > 0:
		var normals: Variant = mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
		if normals is PackedVector3Array and not (normals as PackedVector3Array).is_empty():
			normal = (xf.basis * (normals as PackedVector3Array)[0]).normalized()
	if normal == Vector3.ZERO:
		var thin := Vector3.BACK
		if size.x <= size.y and size.x <= size.z:
			thin = Vector3.RIGHT
		elif size.y <= size.z:
			thin = Vector3.UP
		normal = (xf.basis * thin).normalized()
		var room_origin := get_parent_node_3d().global_position if get_parent_node_3d() else Vector3.ZERO
		if normal.dot(room_origin - center) < 0.0:
			normal = -normal
	# Viewer looks along -normal; their right is (-normal) x up.
	var across := (-normal).cross(Vector3.UP).normalized()
	var width := absf((xf.basis * size).dot(across))
	return {"center": center, "normal": normal, "across": across, "width": width}


func _build_beam(projector: Node3D) -> void:
	# Aim from the booth at the screen centre and size the cone to just cover the screen.
	var aabb := _screen.get_aabb()
	var center := _screen.global_transform * aabb.get_center()
	var from := projector.global_position
	var dist := from.distance_to(center)
	var half_width := (_screen.global_transform.basis * aabb.size).length() * 0.5
	_beam = SpotLight3D.new()
	_beam.name = "ProjectorBeam"
	add_child(_beam)
	_beam.look_at_from_position(from, center, Vector3.UP)
	_beam.spot_range = dist + 5.0
	_beam.spot_angle = clampf(rad_to_deg(atan(half_width / maxf(dist, 0.1))) * 1.1, 2.0, 60.0)
	_beam.spot_angle_attenuation = 0.4
	_beam.spot_attenuation = 0.2
	_beam.shadow_enabled = false
	_beam.light_volumetric_fog_energy = 3.0
	_beam.light_specular = 0.0
	_beam.light_energy = 0.0


## The beam's projector texture: a mask of exactly where the picture is, seen from the
## projector. Each texel is traced as a ray from the beam onto the screen plane, so a
## projector that sits low or off to one side (keystone) still lights only the picture
## and never spills a bright wedge onto the fabric or the wall around it.
## Godot maps the texture as seen from the light: column 0 = light's left (-X),
## row 0 = light's top (+Y), across the full cone (tan(spot_angle) at distance 1).
func _beam_gate_texture() -> ImageTexture:
	var f := _screen_frame(_screen)
	var center: Vector3 = f["center"]
	var normal: Vector3 = f["normal"]
	var across: Vector3 = f["across"]
	var up_s := normal.cross(across).normalized()
	var extent := _screen.global_transform.basis * _screen.get_aabb().size
	var half_w: float = float(f["width"]) * 0.5
	var half_h := absf(extent.dot(up_s)) * 0.5
	if half_h < 0.01:
		half_h = absf(extent.y) * 0.5
	var origin := _beam.global_position
	var bb := _beam.global_transform.basis.orthonormalized()
	var t := tan(deg_to_rad(_beam.spot_angle))
	var n := 256
	var img := Image.create(n, n, false, Image.FORMAT_L8)
	for y in n:
		for x in n:
			var ndc := Vector2((x + 0.5) / n * 2.0 - 1.0, 1.0 - (y + 0.5) / n * 2.0)
			var dir := bb * Vector3(ndc.x * t, ndc.y * t, -1.0)
			var denom := dir.dot(normal)
			var e := 0.0
			var dist := (center - origin).dot(normal) / denom if absf(denom) > 1e-5 else -1.0
			if dist > 0.0:
				var hit := origin + dir * dist
				var u := absf((hit - center).dot(across)) / half_w
				var v := absf((hit - center).dot(up_s)) / half_h
				# soft edge just inside the picture, so nothing lands outside it
				e = minf(smoothstep(1.0, 0.97, u), smoothstep(1.0, 0.95, v))
			img.set_pixel(x, y, Color(e, e, e))
	return ImageTexture.create_from_image(img)


func _add_mirror(mesh: MeshInstance3D) -> void:
	mesh.material_override = _mat
	var f := _screen_frame(mesh)
	var l := OmniLight3D.new()
	l.name = "MirrorSpill_%s" % mesh.name
	add_child(l)
	l.global_position = f["center"] + f["normal"] * 3.0
	l.omni_range = maxf(12.0, float(f["width"]) * 2.0)
	l.omni_attenuation = 1.2
	l.light_volumetric_fog_energy = 0.5
	l.light_energy = 0.0
	_mirror_lights.append(l)


func _build_lights(spot_range: float) -> void:
	var f := _screen_frame(_screen)
	var center: Vector3 = f["center"]
	var normal: Vector3 = f["normal"]
	var across: Vector3 = f["across"]
	var width: float = f["width"]
	for i in 3:
		var s := SpotLight3D.new()
		s.name = "ScreenSpot%d" % i
		add_child(s)
		# left third of the picture -> spot on the viewer's left
		var pos := center + normal * 0.3 + across * ((float(i) - 1.0) * width / 3.0)
		s.look_at_from_position(pos, pos + normal, Vector3.UP)
		s.spot_range = spot_range
		s.spot_angle = 72.0
		s.spot_angle_attenuation = 0.8
		s.spot_attenuation = 0.9
		s.shadow_enabled = cast_shadows
		s.shadow_blur = 2.0
		s.shadow_normal_bias = 2.5   # side walls are hit at grazing angles; avoid shadow acne stripes
		s.light_volumetric_fog_energy = 0.6
		s.light_energy = 0.0
		_spots.append(s)

	_spill = OmniLight3D.new()
	_spill.name = "ScreenSpill"
	add_child(_spill)
	_spill.global_position = center + normal * 2.0
	_spill.omni_range = spot_range * 0.75
	_spill.omni_attenuation = 1.2
	_spill.light_volumetric_fog_energy = 0.0
	_spill.light_energy = 0.0
