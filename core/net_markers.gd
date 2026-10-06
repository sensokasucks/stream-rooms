class_name NetMarkers
extends Node3D
## Streaming together: a small floating camera with a name for everyone else in the session, so
## each streamer can see where the others are looking. Moves smoothly toward the latest position
## (updates arrive about 10 times a second) and only does work while a marker is moving.
## Together tab > Show the others' cameras turns them off.

const BODY_SIZE := Vector3(0.28, 0.2, 0.36)
const COLORS: Array[Color] = [Color(1.0, 0.55, 0.2), Color(0.3, 0.75, 1.0), Color(0.6, 1.0, 0.4), Color(1.0, 0.45, 0.8)]

## A marker this close to your own camera hides, so it never fills your view (everyone starts
## at the same camera spot, for example).
const HIDE_NEAR_M: float = 1.5
const NEAR_CHECK_S: float = 0.2

var _markers: Dictionary = {}     # peer id -> {node: Node3D, label: Label3D, target: Transform3D}
var _near_timer: Timer


func _ready() -> void:
	EventBus.net_camera_moved.connect(_on_moved)
	EventBus.net_peer_left.connect(_on_left)
	EventBus.setting_changed.connect(func(key: String, value: Variant) -> void:
		if key == "together_show_cameras":
			visible = bool(value))
	visible = bool(AppState.get_setting("together_show_cameras"))
	set_process(false)
	# (a few times a second, only while there are markers: your own camera moves without telling us)
	_near_timer = Timer.new()
	_near_timer.wait_time = NEAR_CHECK_S
	_near_timer.timeout.connect(_hide_near)
	add_child(_near_timer)


func _process(delta: float) -> void:
	var moving := false
	for id: int in _markers:
		var m: Dictionary = _markers[id]
		var node: Node3D = m["node"]
		var target: Transform3D = m["target"]
		node.global_transform = node.global_transform.interpolate_with(target, clampf(delta * 12.0, 0.0, 1.0))
		if not node.global_transform.is_equal_approx(target):
			moving = true
	set_process(moving)


func _hide_near() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var me := cam.global_position
	for id: int in _markers:
		var node: Node3D = _markers[id]["node"]
		node.visible = node.global_position.distance_to(me) > HIDE_NEAR_M


func get_marker_count() -> int:
	return _markers.size()


func get_marker(peer_id: int) -> Node3D:
	return _markers[peer_id]["node"] if _markers.has(peer_id) else null


func _on_moved(peer_id: int, peer_name: String, xform: Transform3D) -> void:
	var x := xform.orthonormalized()
	if not _markers.has(peer_id):
		var node := _build(COLORS[posmod(peer_id, COLORS.size())])
		add_child(node)
		node.global_transform = x
		_markers[peer_id] = {"node": node, "label": node.get_node("Name"), "target": x}
		if _near_timer.is_stopped():
			_near_timer.start()
	var m: Dictionary = _markers[peer_id]
	m["target"] = x
	(m["label"] as Label3D).text = peer_name
	set_process(true)


func _on_left(peer_id: int) -> void:
	if _markers.has(peer_id):
		(_markers[peer_id]["node"] as Node3D).queue_free()
		_markers.erase(peer_id)
		if _markers.is_empty():
			_near_timer.stop()


func _build(color: Color) -> Node3D:
	var root := Node3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.12, 0.12, 0.14)
	mat.emission_enabled = true
	mat.emission = color * 0.35
	var body := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = BODY_SIZE
	body.mesh = box
	body.material_override = mat
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(body)
	# the lens points where the camera looks (-Z)
	var lens := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.07
	cyl.bottom_radius = 0.09
	cyl.height = 0.12
	lens.mesh = cyl
	var lens_mat := StandardMaterial3D.new()
	lens_mat.albedo_color = color
	lens_mat.emission_enabled = true
	lens_mat.emission = color
	lens.material_override = lens_mat
	lens.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lens.rotation_degrees = Vector3(90, 0, 0)
	lens.position = Vector3(0, 0, -BODY_SIZE.z * 0.5 - 0.05)
	root.add_child(lens)
	var label := Label3D.new()
	label.name = "Name"
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = false
	label.font_size = 48
	label.outline_size = 10
	label.pixel_size = 0.004
	label.modulate = color.lightened(0.3)
	label.position = Vector3(0, 0.26, 0)
	root.add_child(label)
	return root
