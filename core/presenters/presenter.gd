class_name Presenter
extends Node3D
## One presenter on a podium: the picture behind the podium (live feed with chroma key,
## green screen or silhouette), the podium lamp, and the podium itself, all shown or hidden
## together. Settings live in AppState as presenter_<n>_*; the feed comes from ScreenFeed.
## Extras: a name tag above the picture ("name") and a picture file on the front of the podium
## ("picture": png / jpg / webp / gif, animated GIFs included; see PictureFile).

const SHADER: Shader = preload("res://core/presenters/presenter.gdshader")
const SILHOUETTE: Texture2D = preload("res://core/presenters/presenter_silhouette.png")
const SOURCE_MODE: Dictionary = {"silhouette": 0, "green": 1, "camera": 2, "tab": 2, "web": 2, "ndi": 2, "spout": 2, "peer": 2}

@export var lamp_energy: float = 2.5
@export var lamp_range: float = 3.5
@export var lamp_angle: float = 40.0
@export var lamp_color: Color = Color(1.0, 0.88, 0.72)
## Emission brightness when self-lit.
@export var self_lit_glow: float = 1.2

var number: int = 0
var _podium: Node3D
var _plane: MeshInstance3D
var _mat: ShaderMaterial = ShaderMaterial.new()
var _lamp: SpotLight3D
var _label: Label3D
var _tag: Label3D                 # the name tag above the picture
var _badge: MeshInstance3D        # the podium picture
var _badge_mat: StandardMaterial3D
var _badge_path: String = ""      # the picture file the badge shows (so it isn't reloaded for nothing)
var _badge_task: int = -1
var _podium_faces: PackedVector3Array = []   # the podium's triangles, for sticking the picture to its front
var _plane_size: Vector2
var _feed: Texture2D
var _chat_look: bool = false     # the linked chatter's silhouette stands in (AudienceView draws it)


## Called by PresenterStage. marker: plane bottom centre (+Z faces the audience).
func setup(n: int, marker: Node3D, podium: Node3D, lamp_marker: Node3D, plane_size: Vector2) -> void:
	number = n
	name = "Presenter%d" % n
	_podium = podium
	global_transform = marker.global_transform.orthonormalized()
	_mat.shader = SHADER
	_mat.set_shader_parameter("silhouette", SILHOUETTE)
	_mat.set_shader_parameter("plane_aspect", plane_size.x / plane_size.y)
	_plane = MeshInstance3D.new()
	_plane.name = "Picture"
	var q := QuadMesh.new()
	q.size = plane_size
	_plane.mesh = q
	_plane.position = Vector3(0, plane_size.y * 0.5, 0)
	_plane.material_override = _mat
	_plane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_plane)
	_label = Label3D.new()
	_label.font_size = 36
	_label.pixel_size = 0.0022
	_label.outline_size = 10
	_label.position = Vector3(0, plane_size.y * 0.55, 0.01)
	_label.width = 500.0
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.modulate = Color(0.85, 0.9, 1.0)
	add_child(_label)
	_plane_size = plane_size
	_tag = Label3D.new()
	_tag.name = "NameTag"
	_tag.font_size = 72
	_tag.pixel_size = 0.0028
	_tag.outline_size = 14
	_tag.width = 900.0
	_tag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tag.position = Vector3(0, plane_size.y + 0.1, 0.02)
	_tag.modulate = Color(1.0, 0.96, 0.85)
	add_child(_tag)
	_make_badge()
	if lamp_marker:
		_lamp = SpotLight3D.new()
		_lamp.name = "PodiumLamp"
		_lamp.light_color = lamp_color
		_lamp.spot_range = lamp_range
		_lamp.spot_angle = lamp_angle
		_lamp.spot_attenuation = 0.8
		_lamp.shadow_enabled = false
		_lamp.light_volumetric_fog_energy = 0.3
		add_child(_lamp)
		_lamp.global_transform = lamp_marker.global_transform.orthonormalized()
	_apply_all()


func _ready() -> void:
	EventBus.setting_changed.connect(_on_setting_changed)
	EventBus.presenter_texture_changed.connect(_on_texture)
	EventBus.presenter_look_changed.connect(_on_look)


func _exit_tree() -> void:
	EventBus.setting_changed.disconnect(_on_setting_changed)
	EventBus.presenter_texture_changed.disconnect(_on_texture)
	EventBus.presenter_look_changed.disconnect(_on_look)


## The picture plane (AudienceView makes it follow the presenter spot's moves).
func get_picture() -> MeshInstance3D:
	return _plane


# ── Settings → looks ─────────────────────────────────────────
func _setting(field: String) -> Variant:
	return AppState.get_setting(AppState.presenter_key(number, field))


func _apply_all() -> void:
	var on := bool(_setting("on"))
	visible = on
	if _podium:
		_podium.visible = on
	var source := String(_setting("source"))
	var mode: int = SOURCE_MODE.get(source, 0)
	var live := mode == 2
	if live and _feed == null:
		mode = 3
	_mat.set_shader_parameter("mode", mode)
	# silhouette mode with a linked chatter: their chat-style silhouette replaces this picture
	_plane.visible = not (mode == 0 and _chat_look)
	_mat.set_shader_parameter("feed", _feed)
	if _feed:
		_mat.set_shader_parameter("feed_aspect", float(_feed.get_width()) / maxf(_feed.get_height(), 1.0))
	_mat.set_shader_parameter("key_on", bool(_setting("key")))
	_mat.set_shader_parameter("key_color", _setting("key_color"))
	_mat.set_shader_parameter("similarity", float(_setting("key_similarity")))
	_mat.set_shader_parameter("smoothness", float(_setting("key_smoothness")))
	_mat.set_shader_parameter("spill", float(_setting("key_spill")))
	_mat.set_shader_parameter("zoom", float(_setting("zoom")))
	_mat.set_shader_parameter("offset_y", float(_setting("offset_y")))
	_mat.set_shader_parameter("self_lit", bool(_setting("self_lit")))
	_mat.set_shader_parameter("glow", self_lit_glow)
	if _lamp:
		var e := lamp_energy * clampf(float(_setting("light")), 0.0, 3.0)
		_lamp.light_energy = e
		_lamp.visible = on and e > 0.001
	_tag.text = String(_setting("name")).strip_edges()
	_tag.visible = on and _tag.text != ""
	_apply_badge(on)
	_label.visible = on and live and _feed == null
	if _label.visible:
		_label.text = "Presenter %d\n%s" % [number,
			"waiting for the camera (sender page)" if source == "camera"
			else "open the web page in the sender page" if source == "web"
			else "waiting for NDI source %s" % String(_setting("ndi")) if source == "ndi"
			else "waiting for Spout sender %s" % String(_setting("spout")) if source == "spout"
			else "waiting for %s's avatar (Together)" % String(_setting("peer")) if source == "peer"
			else "pick a tab or window in the sender page"]


# ── Podium picture ───────────────────────────────────────────
## The podium picture: a quad stuck to the podium's real front surface. A ray is cast at the
## podium's shape (its triangles) from the audience's side, at the chosen height and sideways
## offset, so the picture lands on the surface it hits and faces the way that surface faces (a
## slanted front works). It's a child of the podium mesh, so it turns with the podium. Without a
## podium it hangs just below the picture.
func _make_badge() -> void:
	_badge = MeshInstance3D.new()
	_badge.name = "PodiumPicture"
	_badge.mesh = QuadMesh.new()
	_badge_mat = StandardMaterial3D.new()
	_badge_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	_badge_mat.alpha_scissor_threshold = 0.5
	_badge_mat.cull_mode = BaseMaterial3D.CULL_BACK
	_badge_mat.roughness = 0.9
	_badge.material_override = _badge_mat
	_badge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_badge.visible = false
	var mesh_node := _podium_mesh()
	if mesh_node:
		mesh_node.add_child(_badge)
		if mesh_node.mesh:
			_podium_faces = mesh_node.mesh.get_faces()
	else:
		add_child(_badge)
	_place_badge()


func _podium_mesh() -> MeshInstance3D:
	if _podium == null:
		return null
	if _podium is MeshInstance3D:
		return _podium
	var meshes := _podium.find_children("*", "MeshInstance3D", true, false)
	if meshes.is_empty():
		return null
	return meshes[0] as MeshInstance3D


## Where the picture goes and how big it may be (also after a size / position setting changes).
func _place_badge() -> void:
	var pic_scale := clampf(float(_setting("picture_scale")), 0.2, 3.0)
	var dx := float(_setting("picture_x"))      # + = to the right, as the audience sees it
	var dy := float(_setting("picture_y"))      # + = up
	var mesh_node := _podium_mesh()
	if mesh_node == null:
		_badge.position = Vector3(-dx, -0.4 + dy, 0.02)
		_badge.basis = Basis()
		_badge.set_meta("max_size", Vector2(0.5, 0.5) * pic_scale)
		_fit_badge()
		return
	var box := mesh_node.get_aabb()
	# the audience direction (this presenter's +Z) and up, in the podium's own space
	var to_podium := mesh_node.global_transform.basis.inverse()
	var front_dir := (to_podium * global_transform.basis.z).normalized()
	var up_dir := (to_podium * global_transform.basis.y).normalized()
	var right_dir := -(to_podium * global_transform.basis.x).normalized()   # the audience's right
	var front_axis := front_dir.abs().max_axis_index()
	var up_axis := up_dir.abs().max_axis_index()
	if up_axis == front_axis:
		up_axis = Vector3.AXIS_Y if front_axis != Vector3.AXIS_Y else Vector3.AXIS_Z
	var side_axis := 3 - front_axis - up_axis
	var dir_sign := 1.0 if front_dir[front_axis] >= 0.0 else -1.0
	var aim := box.get_center()
	aim[up_axis] = box.position[up_axis] + box.size[up_axis] * 0.55
	aim += up_dir * dy + right_dir * dx
	# a ray from well in front of the podium, straight at it
	var dir := Vector3.ZERO
	dir[front_axis] = -dir_sign
	var origin := aim
	origin[front_axis] = (box.end[front_axis] if dir_sign > 0.0 else box.position[front_axis]) + dir_sign * 1.0
	var hit := _nearest_hit(origin, dir)
	var normal := -dir
	var pos := origin + dir * (1.0 - 0.015)      # the bounding box's front, if the ray misses
	if not hit.is_empty():
		normal = hit["normal"]
		pos = hit["point"] + normal * 0.012
	var up := Vector3.ZERO
	up[up_axis] = 1.0 if up_dir[up_axis] >= 0.0 else -1.0
	if absf(normal.dot(up)) > 0.95:
		up = -dir                                 # (a flat top: keep the picture upright anyway)
	_badge.position = pos
	_badge.basis = Basis.looking_at(-normal, up)   # the quad faces its +Z: onto the surface normal
	var width := clampf(box.size[side_axis] * 0.6, 0.15, 0.7)
	var height := clampf(box.size[up_axis] * 0.5, 0.15, 0.7)
	_badge.set_meta("max_size", Vector2(width, height) * pic_scale)
	_fit_badge()


## The podium triangle the ray hits first: {point, normal} in the podium's space, or {}.
func _nearest_hit(origin: Vector3, dir: Vector3) -> Dictionary:
	var best := {}
	var best_d := INF
	var i := 0
	while i + 2 < _podium_faces.size():
		var hit: Variant = Geometry3D.ray_intersects_triangle(origin, dir, _podium_faces[i], _podium_faces[i + 1], _podium_faces[i + 2])
		if hit != null:
			var d := origin.distance_to(hit)
			if d < best_d:
				best_d = d
				var n := (_podium_faces[i + 1] - _podium_faces[i]).cross(_podium_faces[i + 2] - _podium_faces[i]).normalized()
				if n.dot(dir) > 0.0:
					n = -n                     # face the picture towards where the ray came from
				best = {"point": hit, "normal": n}
		i += 3
	return best


## The quad's size: the picture's shape inside the space allowed (times the size setting).
func _fit_badge() -> void:
	var tex := _badge_mat.albedo_texture
	var max_size: Vector2 = _badge.get_meta("max_size", Vector2(0.5, 0.5))
	if tex == null:
		(_badge.mesh as QuadMesh).size = max_size
		return
	var aspect := float(tex.get_width()) / maxf(float(tex.get_height()), 1.0)
	var size := Vector2(max_size.y * aspect, max_size.y)
	if size.x > max_size.x:
		size = Vector2(max_size.x, max_size.x / aspect)
	(_badge.mesh as QuadMesh).size = size


func _apply_badge(on: bool) -> void:
	var path := String(_setting("picture")).strip_edges()
	if path != _badge_path:
		_badge_path = path
		_badge_mat.albedo_texture = null
		_badge.visible = false
		if path != "":
			_load_badge(path)
	_badge_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if bool(_setting("picture_self_lit")) else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	_place_badge()
	_badge.visible = on and _badge_mat.albedo_texture != null


## Reads and decodes the picture off the main thread (an animated GIF can take a moment).
func _load_badge(path: String) -> void:
	var bytes := PictureFile.read_file(path)
	if bytes.is_empty():
		@warning_ignore("integer_division")
		EventBus.status_message.emit("Presenter %d: couldn't read that picture (png, jpg, webp or gif, up to %d MB)." % [number, PictureFile.MAX_BYTES / (1024 * 1024)], true)
		return
	var out: Array = [null]
	var task := WorkerThreadPool.add_task(func() -> void: out[0] = PictureFile.texture_from_bytes(bytes), false, "podium picture")
	_badge_task = task
	_finish_badge.call_deferred(task, path, out)


func _finish_badge(task: int, path: String, out: Array) -> void:
	WorkerThreadPool.wait_for_task_completion(task)
	if not is_inside_tree() or path != _badge_path:
		return
	var tex: Texture2D = out[0]
	if tex == null:
		EventBus.status_message.emit("Presenter %d: that picture couldn't be decoded." % number, true)
		return
	_badge_mat.albedo_texture = tex
	_fit_badge()
	_badge.visible = bool(_setting("on"))


func _on_setting_changed(key: String, _value: Variant) -> void:
	if key.begins_with("presenter_%d_" % number):
		_apply_all()


func _on_look(n: int, look: bool) -> void:
	if n == number and look != _chat_look:
		_chat_look = look
		_apply_all()


func _on_texture(n: int, tex: Texture2D) -> void:
	if n != number:
		return
	var had := _feed != null
	_feed = tex
	if had != (tex != null) or tex == null:
		_apply_all()
	else:
		_mat.set_shader_parameter("feed", tex)
		_mat.set_shader_parameter("feed_aspect", float(tex.get_width()) / maxf(tex.get_height(), 1.0))
