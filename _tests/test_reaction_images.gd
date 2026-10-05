extends Node
## Reaction pictures: a thrown "img:boot" becomes a Sprite3D with Core's picture.
## Needs `python3 -m http.server 3898 --directory /tmp/imgsrv` (stands in for Core's /reactions/images/).
func _secs(t): await get_tree().create_timer(t).timeout
func _shot(path):
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
func _fire(obj_url: String, effect: String, target: Variant, count: int = 1, impact: String = "bounce") -> void:
	EventBus.reaction_play.emit({"id": "t%d" % randi(), "reaction": "boot", "label": "Boot", "effect": effect,
		"params": {"object": "img:boot", "impact": impact, "stick_sec": 20.0, "count": count,
			"object_image": {"name": "boot", "url": obj_url, "animated": obj_url.ends_with(".gif")}},
		"count": count, "from": {"platform": "twitch", "id": "viewer0", "username": "Viewer0", "display_name": "Viewer0"},
		"target": target, "route": "game"})
func _ready():
	var out: String = OS.get_cmdline_user_args()[0]
	AppState.set_setting("chat_enabled", false)
	AppState.set_setting("chat_core_url", "ws://127.0.0.1:3898/ws")
	AppState.set_setting("reactions_enabled", true)
	print("core url=", ReactionLayer._core_url("/reactions/images/boot.png?v=1"))
	var main = load("res://core/main.tscn").instantiate()
	add_child(main)
	await _secs(0.5)
	AppState.request_room("lecture_hall_panel")
	await _secs(4.0)
	var room = main.get_node("RoomHost").get_current_room()
	var layer = room.find_child("Reactions", true, false)
	for i in 3:
		EventBus.chat_message_received.emit({"platform": "twitch", "user_id": "viewer%d" % i, "name": "Viewer%d" % i, "color": "",
			"text": "hi", "emotes": [], "avatar": "", "timestamp": Time.get_unix_time_from_system(), "history": false, "system": false})
	await _secs(0.5)
	_fire("/reactions/images/boot.png?v=1", "throw", {"type": "stage", "name": "stage"}, 3)
	_fire("/reactions/images/blob.gif?v=1", "fall_down", {"type": "stage", "name": "stage"}, 6)
	await _secs(3.0)
	var sprites := []
	for c in layer.get_children():
		if c is Sprite3D and (c as Sprite3D).texture != null and (c as Sprite3D).texture != ReactionLayer._splat_texture():
			sprites.append("%s %s" % [(c as Sprite3D).texture.get_class(), (c as Sprite3D).texture.get_size()])
	print("picture sprites=", sprites.size(), " ", sprites.slice(0, 4))
	EventBus.camera_preset_requested.emit(12)
	await _secs(1.0)
	_fire("/reactions/images/boot.png?v=1", "throw", {"type": "stage", "name": "stage"}, 4, "stick")
	await _secs(2.5)
	await _shot(out + "/boot_thrown.png")
	get_tree().quit()
