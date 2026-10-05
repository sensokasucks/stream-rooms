class_name WebcamDisplay
extends Node3D
## In-room picture frame for the webcam feed from the browser sender.
## RoomHost places it at the room's WEBCAM_Frame marker. Hidden when there is no
## webcam feed or when the "webcam_in_room" setting is off.

@export var width_m: float = 1.2
@export var border_m: float = 0.06
@export var brightness: float = 1.0

var _quad: MeshInstance3D
var _frame: MeshInstance3D
var _mat: StandardMaterial3D = StandardMaterial3D.new()
var _texture: Texture2D


func _ready() -> void:
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.albedo_color = Color(brightness, brightness, brightness)
	_quad = MeshInstance3D.new()
	_quad.mesh = QuadMesh.new()
	_quad.material_override = _mat
	_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_quad)
	_frame = MeshInstance3D.new()
	_frame.mesh = BoxMesh.new()
	var frame_mat := StandardMaterial3D.new()
	frame_mat.albedo_color = Color(0.05, 0.04, 0.035)
	frame_mat.roughness = 0.6
	_frame.material_override = frame_mat
	add_child(_frame)
	_resize(16.0 / 9.0)
	EventBus.webcam_texture_changed.connect(_on_webcam_texture)
	EventBus.setting_changed.connect(_on_setting_changed)
	_refresh_visibility()


func _exit_tree() -> void:
	EventBus.webcam_texture_changed.disconnect(_on_webcam_texture)
	EventBus.setting_changed.disconnect(_on_setting_changed)


func set_texture(tex: Texture2D) -> void:
	_on_webcam_texture(tex)


func _on_webcam_texture(tex: Texture2D) -> void:
	_texture = tex
	_mat.albedo_texture = tex
	if tex and tex.get_height() > 0:
		_resize(float(tex.get_width()) / float(tex.get_height()))
	_refresh_visibility()


func _on_setting_changed(key: String, _value: Variant) -> void:
	if key == "webcam_in_room":
		_refresh_visibility()


func _refresh_visibility() -> void:
	visible = _texture != null and bool(AppState.get_setting("webcam_in_room"))


func _resize(aspect: float) -> void:
	var h := width_m / maxf(aspect, 0.1)
	(_quad.mesh as QuadMesh).size = Vector2(width_m, h)
	(_frame.mesh as BoxMesh).size = Vector3(width_m + border_m * 2.0, h + border_m * 2.0, 0.04)
	_frame.position = Vector3(0, 0, -0.025)
