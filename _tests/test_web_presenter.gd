extends Node
## "Web page (transparent)" presenter source, end-to-end with devtools/web_presenter_browser.mjs.
var saved := false
func _secs(t): await get_tree().create_timer(t).timeout
func _ready():
	var out: String = OS.get_cmdline_user_args()[0]
	EventBus.presenter_texture_changed.connect(func(n, tex):
		if tex and n == 1 and not saved:
			saved = true
			await _secs(2.0)
			tex.get_image().save_png(out + "/web_presenter_feed.png")
			print("FEED presenter 1 ", tex.get_size()))
	EventBus.capture_status_changed.connect(func(info):
		if info.get("connected") and info.has("presenters"):
			print("STATUS ", (info["presenters"] as Array).slice(0, 1).map(func(p): return [p.get("want"), p.get("active"), p.get("kind"), p.get("error")])))
	var k := func(n: int, f: String) -> String: return AppState.presenter_key(n, f)
	for n in range(1, 5):
		AppState.set_setting(k.call(n, "on"), n == 1)
	AppState.set_setting(k.call(1, "source"), "web")
	AppState.set_setting(k.call(1, "url"), "http://127.0.0.1:8899/avatar_test.html")
	AppState.set_setting(k.call(1, "key_color"), Color(1, 0, 1))
	var main = load("res://core/main.tscn").instantiate()
	add_child(main)
	await _secs(0.5)
	AppState.request_room("lecture_hall_panel")
	await _secs(30.0)
	AppState.set_setting(k.call(1, "source"), "silhouette")
	AppState.set_setting(k.call(1, "url"), "")
	AppState.set_setting(k.call(1, "key_color"), Color(0, 1, 0))
	AppState.set_setting(k.call(1, "on"), false)
	await _secs(2.0)
	print("DONE")
	AppState.request_quit()
