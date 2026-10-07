extends Node
## Without the godot-ndi extension: NDI UI shows "not loaded", requests fail gracefully, the rest runs.
func _secs(t): await get_tree().create_timer(t).timeout
func _ready():
	EventBus.ndi_sources_changed.connect(func(n, a): print("NDI sources ", n, " available=", a))
	EventBus.status_message.connect(func(t, e): print("STATUS ", t, " err=", e))
	var main = load("res://core/main.tscn").instantiate()
	add_child(main)
	await _secs(1.0)
	print("available=", NdiReceiver.is_available())
	EventBus.ndi_connect_requested.emit("PC (OBS)")
	AppState.set_setting(AppState.presenter_key(2, "source"), "ndi")
	AppState.request_room("lecture_hall_panel")
	await _secs(4.0)
	print("source mode=", AppState.get_source_mode(), " ndi label=", main.get_node("ControlPanel")._ndi_label.text)
	AppState.set_setting(AppState.presenter_key(2, "source"), "camera")
	print("DONE")
	AppState.request_quit()
