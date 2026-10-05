class_name SideChats
extends Node3D
## Two tall chat windows beside the main screen ("chat_left" / "chat_right": left and right as
## the audience sees the screen). RoomHost adds this to every room with a main screen.
## Each window is a ChatScreen, so what it shows (platforms, Stream Core replies) and its
## looks come from its own settings; this node only places them and rebuilds them when their
## size or position settings change.

const WINDOWS: PackedStringArray = ["chat_left", "chat_right"]
## Metres the windows stay in front of the stage curtain (its pelmet, folds and tassels).
const CURTAIN_CLEARANCE: float = 0.4
const GEOMETRY: PackedStringArray = ["_width", "_height", "_gap", "_lift"]

var _screen: MeshInstance3D
var _towards: Vector3 = Vector3.BACK      # from the screen toward the audience (flat)
var _windows: Dictionary = {}             # window key -> ChatScreen
var _pending: Dictionary = {}             # window key -> seconds until it's rebuilt (slider drags)
var _extra_gap: float = 0.0
var _height_scale: float = 1.0
var _forward: float = 0.0


## screen: the room's main screen. audience_point: somewhere in the audience (a camera).
## extra_gap / height_scale / forward: the room's own adjustment (Room.side_chat_*).
func setup(screen: MeshInstance3D, audience_point: Vector3, extra_gap: float = 0.0, height_scale: float = 1.0, forward: float = 0.0) -> void:
	_forward = forward
	_screen = screen
	_extra_gap = extra_gap
	_height_scale = height_scale
	var box := screen.global_transform * screen.get_aabb()
	var t := audience_point - box.get_center()
	t.y = 0.0
	_towards = t.normalized() if t.length() > 0.01 else Vector3.BACK
	# square up with the screen itself (the camera may be off to one side): the screen's flat
	# normal, turned to face the audience
	var z := screen.global_transform.basis.z
	z.y = 0.0
	if z.length() > 0.01 and absf(z.normalized().dot(_towards)) > 0.7:     # (only if z really is its normal)
		z = z.normalized()
		_towards = z if z.dot(_towards) >= 0.0 else -z
	for w in WINDOWS:
		_build(w)


func _ready() -> void:
	EventBus.setting_changed.connect(_on_setting_changed)


func _exit_tree() -> void:
	EventBus.setting_changed.disconnect(_on_setting_changed)


## The window for "chat_left" / "chat_right" (for tests).
func get_chat_window(key: String) -> ChatScreen:
	return _windows.get(key)


func _build(key: String) -> void:
	var old: Variant = _windows.get(key)
	if old != null and is_instance_valid(old):
		(old as Node).queue_free()
	var box := _screen.global_transform * _screen.get_aabb()
	var c := box.get_center()
	var n := _towards
	var right := Vector3.UP.cross(n).normalized()          # the audience's right
	var screen_w := absf(box.size.dot(right.abs()))
	var screen_h := box.size.y
	var w := clampf(float(AppState.get_setting(key + "_width")), 0.5, 8.0)
	var h := screen_h * clampf(float(AppState.get_setting(key + "_height")) * _height_scale, 0.1, 2.0)
	var gap := float(AppState.get_setting(key + "_gap")) + _extra_gap
	var lift := float(AppState.get_setting(key + "_lift"))
	var side := -1.0 if key == "chat_left" else 1.0
	var top := c + right * side * (screen_w * 0.5 + gap + w * 0.5) + Vector3.UP * (screen_h * 0.5 + lift) + n * (0.03 + _forward)
	var win := ChatScreen.new()
	win.name = "SideChat_" + key.trim_prefix("chat_")
	win.setup(Vector2(w, h), key)
	add_child(win)
	win.global_transform = Transform3D(Basis(right, Vector3.UP, n), top)
	_windows[key] = win


func _process(delta: float) -> void:
	for k: String in _pending.keys():
		_pending[k] = float(_pending[k]) - delta
		if float(_pending[k]) <= 0.0:
			_pending.erase(k)
			_build(k)


func _on_setting_changed(key: String, _value: Variant) -> void:
	for w in WINDOWS:
		for g in GEOMETRY:
			if key == w + g:
				_pending[w] = 0.15      # rebuilt once the slider stops moving
				return
