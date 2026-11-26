extends Node
## Not a test: a quick look at Route 81 for whoever is changing it. Loads the room on the
## Detailed look and saves screenshots of a few spots (see SHOTS), nothing is checked.
## Run it like a test, on its own:
##   powershell -ExecutionPolicy Bypass -File tools\run_tests.ps1 -Tests look_route81 -SkipImport -Screen 0
## The pictures land in C:\temp\sr_tests\look_route81\.

const Trip := preload("res://rooms/route81/r81_trip.gd")
const Land := preload("res://rooms/route81/r81_land.gd")

## [picture name, country, what to find (see _find), metres into that place, camera number,
## curves 0..1]. Cameras: 0 windshield, 2 passenger side, 3 driver side, 5 chase, 6 drone.
const SHOTS: Array = [
	["ridge_tunnel_inside", "ridge", "tube", 40.0, 0, 1.0],
	["ridge_cut", "ridge", "cut", 30.0, 5, 0.5],
	["ridge_woods_chase", "ridge", "woods", 30.0, 5, 0.5],
	["ridge_woods_drone", "ridge", "woods", 30.0, 6, 0.5],
	["ridge_overlook", "ridge", "drop", 30.0, 2, 0.5],
	["endless_overlook", "endless", "drop", 30.0, 5, 0.5],
	["farm_chase", "farm", "field", 30.0, 5, 0.5],
	["farm_side", "farm", "field", 30.0, 2, 0.5],
	["river_bridge", "river", "water", -60.0, 5, 0.5],
	["river_drone", "river", "water", 40.0, 6, 0.5],
	["city_chase", "city", "lot", 30.0, 5, 0.5],
	["coal_chase", "coal", "lot", 30.0, 5, 0.5],
	["city_side", "city", "lot", 30.0, 2, 0.5],
	["bobble_windshield", "ridge", "woods", 30.0, 0, 0.5],
	["bobble_hood", "ridge", "woods", 30.0, 4, 0.5],
	["bobble_back_seat", "ridge", "woods", 30.0, 1, 0.5],
	["ridge_drone_far", "ridge", "woods", 30.0, 6, 0.0],
]

var _out: String = ""


func _secs(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out + "/" + shot_name + ".png")
	print("SHOT " + shot_name)


## The first place from `from` on that is `what`: "tube" = inside a tunnel, any other word = an
## edge profile on the right side (both ends of the place and the next one).
func _find(from: int, what: String) -> int:
	for k in range(from, from + 4000):
		if what == "tube":
			if Trip.part_at(k) == "tube" and Trip.part_at(k + 1) == "tube":
				return k
		elif Trip.part_at(k) == "" and Trip.boundary(1, k) == what and Trip.boundary(1, k + 2) == what:
			return k
	return -1


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else "C:/temp/sr_tests/look_route81"
	DirAccess.make_dir_recursive_absolute(_out)
	AppState.set_setting("chat_enabled", false)
	AppState.set_setting("curtain_enabled", false)
	AppState.set_setting("r22_detail", "full")
	AppState.set_setting("r22_time", 14.0)
	AppState.set_setting("r22_day_minutes", 0.0)
	AppState.set_setting("r22_weather", "clear")
	AppState.set_setting("r22_speed", 0.0)
	AppState.set_setting("r22_traffic", 0.0)
	AppState.set_setting("r81_tunnels", "medium")
	AppState.set_setting("r81_views", 0.6)
	AppState.set_setting("r81_forest", 100.0)
	AppState.set_setting("r81_drift", false)
	AppState.set_setting("r81_country", "ridge")
	for n in range(1, 5):
		AppState.set_setting(AppState.presenter_key(n, "on"), true)
		AppState.set_setting(AppState.presenter_key(n, "source"), "silhouette")
	var main: Node = load("res://core/main.tscn").instantiate()
	add_child(main)
	main.get_node("ControlPanel").visible = false
	await _secs(0.5)
	var host: Node = main.get_node("RoomHost")
	AppState.request_room("route81")
	var room: Room = null
	for i in 400:
		await _secs(0.5)
		var r: Room = host.get_current_room()
		if r != null and r.name == "Route81Room":
			room = r
			break
	if room == null:
		print("DONE fails=1")
		AppState.request_quit(1)
		return
	await _secs(2.0)
	var trip: Trip = room.call("get_trip")
	# (picture names after the output folder pick some of SHOTS; the runner's --mp-profile is not one)
	var only: Array = []
	for a: String in args.slice(1):
		if not a.begins_with("--") and not a.begins_with("hide:"):
			only.append(a)
	for s: Array in SHOTS:
		if not only.is_empty() and not only.has(String(s[0])):
			continue
		AppState.set_setting("r81_country", String(s[1]))
		AppState.set_setting("r22_curves", float(s[5]))
		var k := _find(floori(Trip.START / Land.LENGTH) + 2, String(s[2]))
		if k < 0:
			print("MISSING " + String(s[0]))
			continue
		trip.set_travel(float(k) * Land.LENGTH + float(s[3]))
		EventBus.camera_preset_requested.emit(int(s[4]))
		await _secs(3.0)
		print("%s: place %d altitude %.0f look %s" % [s[0], k, trip.altitude, trip.call("_look", k)])
		await _shot(String(s[0]))
		# "hide:<node name pattern>" after the picture names: one more picture with those hidden
		for a: String in args:
			if a.begins_with("hide:"):
				var hidden: Array[Node] = trip.find_children(a.trim_prefix("hide:"), "", true, false)
				for n: Node in hidden:
					n.set("visible", false)
				await _secs(0.5)
				await _shot(String(s[0]) + "_" + a.trim_prefix("hide:").replace("*", ""))
				for n: Node in hidden:
					n.set("visible", true)
	# "swap": to the desert Cruise and back, printing what RoomHost shows every few seconds
	if args.has("swap"):
		AppState.set_setting("r22_land", "desert")
		for i in 40:
			await _secs(3.0)
			var r: Room = host.get_current_room()
			print("SWAP %d s: %s room_id=%s r22_land=%s" % [i * 3, r.name if r else "-", AppState.get_setting("room_id"), AppState.get_setting("r22_land")])
			if i == 10:
				AppState.set_setting("r22_land", "route81")
	# "fps": frames a second while driving through each country on each look (vsync may cap it)
	if args.has("fps"):
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		AppState.set_setting("r22_speed", 100.0)
		EventBus.camera_preset_requested.emit(0)
		for look: String in ["full", "low"]:
			AppState.set_setting("r22_detail", look)
			for c: String in ["ridge", "farm", "endless", "city"]:
				AppState.set_setting("r81_country", c)
				trip.set_travel(float(_find(floori(Trip.START / Land.LENGTH) + 2, "woods" if c != "farm" else "field")) * Land.LENGTH)
				await _secs(3.0)
				var f0 := Engine.get_frames_drawn()
				var t0 := Time.get_ticks_msec()
				await _secs(5.0)
				print("FPS %s %s: %.0f" % [look, c, float(Engine.get_frames_drawn() - f0) * 1000.0 / float(Time.get_ticks_msec() - t0)])
	print("DONE fails=0")
	AppState.request_quit(0)
