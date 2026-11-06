extends Node
## Saved camera views (Room tab > Cameras, CameraRig "Saved views"): save the camera's place as a
## view of this room, rename / reorder / hide / update / delete views, the number keys follow the
## visible order, Glide time 0 cuts, and the views come back after switching rooms.
##   <redot console exe> --path . _tests/test_camera_views.tscn -- C:/temp/sr_tests --mp-profile=test

var _fails: int = 0
var _views: Array = []


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _secs(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _ids() -> PackedStringArray:
	var out := PackedStringArray()
	for v: Dictionary in _views:
		out.append(String(v["id"]))
	return out


func _ready() -> void:
	AppState.set_setting("chat_enabled", false)
	AppState.set_setting("chat_core_url", "ws://127.0.0.1:9/ws")
	AppState.set_setting("panel_window", false)
	AppState.set_setting("camera_views", "")
	AppState.set_setting("camera_glide", 0.0)
	EventBus.camera_views_changed.connect(func(v: Array) -> void: _views = v)
	var main: Node = load("res://core/main.tscn").instantiate()
	add_child(main)
	await _secs(1.0)
	AppState.request_room("lecture_hall_panel")
	await _secs(5.0)
	var rig: CameraRig = main.get_node("CameraRig")
	var builtin := _views.size()
	_check(builtin >= 2, "the room's own cameras are listed (%d)" % builtin)
	_check(int(_views[0]["key"]) == 1 and not bool(_views[0]["saved"]), "the first is key 1 and a room camera")

	# save a view somewhere new
	var spot := Transform3D(Basis.from_euler(Vector3(-0.3, 0.8, 0.0)), Vector3(1.5, 2.2, 3.0))
	rig.global_transform = spot
	EventBus.camera_view_action.emit("save", "", "Balcony shot")
	await get_tree().process_frame
	_check(_views.size() == builtin + 1 and String(_views[-1]["name"]) == "Balcony shot" and bool(_views[-1]["saved"]),
		"Save this view adds it at the end")
	var sid := String(_views[-1]["id"])
	EventBus.camera_key_requested.emit(0)
	await get_tree().process_frame
	_check(rig.global_transform.origin.distance_to(spot.origin) > 0.1, "key 1 goes to the room's first camera")
	EventBus.camera_view_action.emit("go", sid, "")
	await get_tree().process_frame
	_check(rig.global_transform.origin.distance_to(spot.origin) < 0.01, "going to the saved view puts the camera back there (glide 0 cuts)")

	# reorder: move it to the top; key 1 is now the saved view
	for i in builtin:
		EventBus.camera_view_action.emit("up", sid, "")
	await get_tree().process_frame
	_check(_ids()[0] == sid and int(_views[0]["key"]) == 1, "moved to the top, it gets key 1")
	EventBus.camera_key_requested.emit(1)
	EventBus.camera_key_requested.emit(0)
	await get_tree().process_frame
	_check(rig.global_transform.origin.distance_to(spot.origin) < 0.01, "and key 1 goes there")

	# hide a room camera: no key, the next one moves up
	var b0 := "b0"
	EventBus.camera_view_action.emit("hide", b0, "")
	await get_tree().process_frame
	var hidden_row: Dictionary = _views[_ids().find(b0)]
	_check(bool(hidden_row["hidden"]) and int(hidden_row["key"]) == 0, "a hidden room camera has no key")
	EventBus.camera_view_action.emit("delete", b0, "")
	await get_tree().process_frame
	_check(_ids().has(b0), "a room's own camera can't be deleted")
	EventBus.camera_view_action.emit("show", b0, "")
	EventBus.camera_view_action.emit("rename", b0, "Front row")
	await get_tree().process_frame
	_check(String(_views[_ids().find(b0)]["name"]) == "Front row", "a room camera can be renamed")

	# update moves the saved view to the camera's place now
	var spot2 := Transform3D(Basis.IDENTITY, Vector3(-2.0, 1.6, 4.0))
	rig.global_transform = spot2
	EventBus.camera_view_action.emit("update", sid, "")
	rig.global_transform = spot
	EventBus.camera_view_action.emit("go", sid, "")
	await get_tree().process_frame
	_check(rig.global_transform.origin.distance_to(spot2.origin) < 0.01, "Update keeps the new place")

	# the views come back after another room and back again
	AppState.request_room("theater")
	await _secs(6.0)
	_check(not _ids().has(sid), "another room doesn't have this room's saved view")
	AppState.request_room("lecture_hall_panel")
	await _secs(6.0)
	_check(_ids().has(sid) and _ids()[0] == sid and String(_views[_ids().find(b0)]["name"]) == "Front row",
		"back in the room: the saved view, its order and the new name are still there")

	EventBus.camera_view_action.emit("delete", sid, "")
	await get_tree().process_frame
	_check(not _ids().has(sid) and _views.size() == builtin, "Delete removes a saved view")
	print("DONE fails=", _fails)
	AppState.request_quit(1 if _fails > 0 else 0)
