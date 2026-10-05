extends Node
## Closing / opening the curtain with "mute while closed" on, sound on, chat flowing, in the panel room.
func _secs(t): await get_tree().create_timer(t).timeout
func _ready():
	AppState.set_setting("curtain_mute", true)
	AppState.set_setting("curtain_sound", 0.5)
	AppState.set_setting("chat_enabled", false)
	var main = load("res://core/main.tscn").instantiate()
	add_child(main)
	await _secs(0.5)
	AppState.request_room("lecture_hall_panel")
	await _secs(5.0)
	var video := AudioServer.get_bus_index("Video")
	for round in 3:
		AppState.set_curtain(false, "normal")
		await _secs(2.5)
		print("open  round ", round, ": video bus db=", AudioServer.get_bus_volume_db(video), " muted(-80 dB)=", AudioServer.get_bus_volume_db(video) <= -79.0)
		AppState.set_curtain(true, "normal")
		await _secs(2.5)
		print("closed round ", round, ": video bus db=", AudioServer.get_bus_volume_db(video), " muted(-80 dB)=", AudioServer.get_bus_volume_db(video) <= -79.0)
		AppState.set_setting("curtain_mute", round % 2 == 0)
		await _secs(0.3)
	AppState.set_curtain(false, "reveal")
	await _secs(6.0)
	print("after reveal: db=", AudioServer.get_bus_volume_db(video), " muted(-80 dB)=", AudioServer.get_bus_volume_db(video) <= -79.0)
	AppState.set_setting("curtain_mute", false)
	AppState.set_setting("curtain_sound", 0.04)
	print("DONE no crash")
	get_tree().quit()
