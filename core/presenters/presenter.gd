class_name Presenter
extends Node3D
## One presenter on a podium: the picture behind the podium (live feed with chroma key,
## green screen or silhouette), the podium lamp, and the podium itself, all shown or hidden
## together. Settings live in AppState as presenter_<n>_*; the feed comes from ScreenFeed.

const SHADER: Shader = preload("res://core/presenters/presenter.gdshader")
const SILHOUETTE: Texture2D = preload("res://core/presenters/presenter_silhouette.png")
const SOURCE_MODE: Dictionary = {"silhouette": 0, "green": 1, "camera": 2, "tab": 2, "web": 2, "ndi": 2, "spout": 2}

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
	_label.visible = on and live and _feed == null
	if _label.visible:
		_label.text = "Presenter %d\n%s" % [number,
			"waiting for the camera (sender page)" if source == "camera"
			else "open the web page in the sender page" if source == "web"
			else "waiting for NDI source %s" % String(_setting("ndi")) if source == "ndi"
			else "waiting for Spout sender %s" % String(_setting("spout")) if source == "spout"
			else "pick a tab or window in the sender page"]


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
