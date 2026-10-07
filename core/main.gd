extends Node3D
## Wiring layer for the core scene. Connects child signals to siblings and
## loads the starting room. Holds no state of its own.

@export var room_host: RoomHost
@export var camera_rig: CameraRig


func _ready() -> void:
	room_host.room_ready.connect(_on_room_ready)
	add_child(NetMarkers.new())     # the others' cameras while streaming together
	get_tree().auto_accept_quit = false     # closing the window goes through AppState.request_quit

	var start_id: String = AppState.get_setting("room_id")
	if RoomCatalog.get_info(start_id) == null and not RoomCatalog.get_ids().is_empty():
		start_id = RoomCatalog.get_ids()[0]
	AppState.request_room(start_id)
	# start behind the curtain, ready for a reveal (Shift+B)
	if bool(AppState.get_setting("curtain_start_closed")):
		AppState.set_curtain(true, "instant")

	get_window().title = AppState.with_profile(str(ProjectSettings.get_setting("application/config/name")))

	# Optional: play a file/URL passed on the command line:  redot --path . -- "C:/clip.mp4"
	# Options such as --mp-profile=guest1 start with "--" and aren't files.
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--"):
			EventBus.file_play_requested.emit.call_deferred(arg)
			break


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		AppState.request_quit(0)


func _on_room_ready(room: Room, _info: RoomInfo) -> void:
	var markers := room.get_camera_markers()
	var labels := PackedStringArray()
	for m in markers:
		labels.append(room.get_camera_label(m))
	camera_rig.set_presets(markers, labels)
	camera_rig.set_room(room)
