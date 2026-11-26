extends Node
## Route 81 Cruise (rooms/route81): the room loads with what its markers promise and its road works.
##   ten cameras, four seats in the woody, no screen, every Room tab control has a default,
##   the road moves with Speed and stands still when Parked,
##   the road's rules (r81_trip.gd): both sides of every place in view join up with their
##     neighbours, tunnels come as in > tube x 4 > out with rock cuts either side, the views
##     slider at 0 leaves no overlooks, Tunnels "never" leaves no tunnels,
##   driving into a tunnel takes the daylight away (cover) and changes the region,
##   the heading swings the far ridges, the altitude moves the valley,
##   traffic comes, a stray co-stream travel message is ignored,
##   the Scenery switch goes to the desert Cruise and back.
## Saves screenshots of every camera, an overlook, a rock cut, a tunnel mouth, inside a tunnel,
## fall colours and night (look at them: the look is not checked here).
## Arguments after the output folder: "full" shoots the Detailed look (slow under a software
## renderer; the default is Low), "quick" skips the screenshots of every camera, "shots" stops
## after the scenery and tunnel screenshots (for looking at a change quickly).
##   <redot console exe> --path . _tests/test_route81.tscn -- C:/temp/sr_tests --mp-profile=test

const Trip := preload("res://rooms/route81/r81_trip.gd")
const Land := preload("res://rooms/route81/r81_land.gd")
var _fails: int = 0
var _out: String = ""


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _secs(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out + "/" + shot_name + ".png")


## Waits (up to `limit` seconds) until RoomHost shows a room named `room_name`; returns it or null.
func _wait_room(host: Node, room_name: String, limit: float) -> Room:
	var waited := 0.0
	while waited < limit:
		var r: Room = host.get_current_room()
		if r != null and r.name == room_name:
			await _secs(1.0)
			return r
		await _secs(0.5)
		waited += 0.5
	return null


## The first place at or after `from` where `test` (called with the place number) is true, or -1.
func _find_place(from: int, test: Callable) -> int:
	for k in range(from, from + 400):
		if bool(test.call(k)):
			return k
	return -1


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0]
	var full := args.has("full")
	var quick := args.has("quick")
	var shots_only := args.has("shots")
	DirAccess.make_dir_recursive_absolute(_out)
	AppState.set_setting("chat_enabled", false)
	AppState.set_setting("house_lights", 1.0)
	AppState.set_setting("auto_dim_house", false)
	AppState.set_setting("curtain_enabled", false)
	AppState.set_setting("photosensitive_safe", false)
	AppState.set_setting("flash_strength", 1.0)
	AppState.set_setting("r22_detail", "full" if full else "low")
	AppState.set_setting("r22_time", 13.0)
	AppState.set_setting("r22_day_minutes", 0.0)
	AppState.set_setting("r22_weather", "clear")
	AppState.set_setting("r22_clouds", 1.0)
	AppState.set_setting("r22_wind", 0.35)
	AppState.set_setting("r22_heat", 0.5)
	AppState.set_setting("r22_speed", 50.0)
	AppState.set_setting("r22_curves", 0.5)
	AppState.set_setting("r22_traffic", 100.0)
	AppState.set_setting("r81_tunnels", "medium")
	AppState.set_setting("r81_views", 0.6)
	AppState.set_setting("r81_forest", 100.0)
	AppState.set_setting("r81_season", "summer")
	for n in range(1, 5):
		AppState.set_setting(AppState.presenter_key(n, "on"), true)
		AppState.set_setting(AppState.presenter_key(n, "source"), "silhouette")
	var main: Node = load("res://core/main.tscn").instantiate()
	add_child(main)
	main.get_node("ControlPanel").visible = false
	await _secs(0.5)
	var host: Node = main.get_node("RoomHost")

	var t0 := Time.get_ticks_msec()
	AppState.request_room("route81")
	var room: Room = await _wait_room(host, "Route81Room", 180.0)
	_check(room != null, "the Route 81 Cruise loaded (about %.1f s)" % (float(Time.get_ticks_msec() - t0) / 1000.0))
	if room == null:
		print("DONE fails=%d" % (_fails + 1))
		AppState.request_quit(1)
		return
	_check(room.find_screen() == null, "no big screen")
	_check(room.get_camera_markers().size() == 10, "ten cameras")
	_check(room.get_presenter_setups().size() == 4, "four riders' places in the woody")
	_check(String(AppState.get_setting("r22_land")) == "route81", "the Scenery switch shows Route 81")
	var missing: Array[String] = []
	var count := 0
	for c in room.get_controls():
		if c.has("key"):
			count += 1
			if not AppState.DEFAULTS.has(String(c["key"])) or not c.has("tooltip"):
				missing.append(String(c["key"]))
	_check(count > 12 and missing.is_empty(), "all %d Room tab controls have defaults and tooltips %s" % [count, str(missing)])

	var trip: Trip = room.call("get_trip")
	var before := trip.travel
	await _secs(2.0)
	_check(trip.travel > before + 10.0 and trip.speed > 10.0, "the road moves at Speed 50 (%.1f m in 2 s)" % (trip.travel - before))
	var span := trip.in_view()
	_check(span.y - span.x >= 18 and trip.looks_in_view().size() == span.y - span.x + 1, "%d places of land in view" % trip.looks_in_view().size())

	# ── the road's rules ──
	var period := Trip.period()
	var order_ok := true
	for k in range(period * 3, period * 3 + 8):
		var j := k - period * 3
		var want := "in" if j == 0 else ("tube" if j <= 4 else ("out" if j == 5 else ""))
		order_ok = order_ok and Trip.part_at(k) == want
	_check(period == 88 and order_ok, "a tunnel every %d places: in, four tubes, out" % period)
	var b0 := period * 3
	_check(Trip.boundary(1, b0) == "cut" and Trip.boundary(-1, b0) == "cut" and Trip.boundary(1, b0 + 3) == "mount" and Trip.boundary(1, b0 + 6) == "cut",
		"rock cuts lead into and out of the mountain")
	var kinds := {}
	for b in range(100, 800):
		kinds[Trip.boundary(1, b)] = true
		kinds[Trip.boundary(-1, b)] = true
	_check(kinds.size() == 4, "the road has woods, rock cuts, overlooks and mountains (%s)" % str(kinds.keys()))
	AppState.set_setting("r81_views", 0.0)
	var drops := 0
	for b in range(100, 800):
		drops += 1 if Trip.boundary(1, b) == "drop" or Trip.boundary(-1, b) == "drop" else 0
	_check(drops == 0, "views at 0%: no overlooks")
	AppState.set_setting("r81_views", 0.6)
	AppState.set_setting("r81_tunnels", "never")
	_check(Trip.period() == 0 and Trip.part_at(b0) == "" and Trip.boundary(1, b0 + 3) != "mount", "Tunnels Never: no tunnels")
	AppState.set_setting("r81_tunnels", "medium")
	await _secs(0.5)

	if not quick:
		var cams := room.get_camera_markers()
		for i in cams.size():
			EventBus.camera_preset_requested.emit(i)
			await _secs(1.0)
			await _shot("r81_%s" % String(cams[i].name).trim_prefix("CAM_"))
	# the chase camera looks down the road: the view for the scenery shots
	EventBus.camera_preset_requested.emit(5)

	# ── an overlook on the right, then a rock cut on the right ──
	var from := floori(trip.travel / Land.LENGTH) + 2
	var k_drop := _find_place(from, func(k: int) -> bool:
		return Trip.boundary(1, k) == "drop" and Trip.boundary(1, k + 5) == "drop" and Trip.part_at(k) == "")
	_check(k_drop > 0, "found an overlook ahead (place %d)" % k_drop)
	trip.set_travel(float(k_drop) * Land.LENGTH + 180.0)
	await _secs(1.5)
	_check(trip.altitude >= 39.0 and trip.altitude <= 241.0, "the road is %.0f m above the valley" % trip.altitude)
	await _shot("r81_overlook_chase")
	EventBus.camera_preset_requested.emit(2)
	await _secs(1.0)
	await _shot("r81_overlook_passenger_side")
	EventBus.camera_preset_requested.emit(3)
	await _secs(1.0)
	await _shot("r81_overlook_driver_side")
	EventBus.camera_preset_requested.emit(0)
	await _secs(1.0)
	await _shot("r81_overlook_windshield")
	EventBus.camera_preset_requested.emit(6)
	await _secs(1.0)
	await _shot("r81_overlook_drone")
	AppState.set_setting("r81_season", "fall")
	EventBus.camera_preset_requested.emit(5)
	await _secs(1.0)
	await _shot("r81_overlook_fall")
	AppState.set_setting("r81_season", "summer")
	var k_cut := _find_place(from, func(k: int) -> bool:
		return Trip.boundary(1, k) == "cut" and Trip.boundary(1, k + 5) == "cut" and Trip.part_at(k) == "" and Trip.part_at(k + 6) == "")
	trip.set_travel(float(k_cut) * Land.LENGTH + 20.0)
	await _secs(1.5)
	await _shot("r81_rock_cut")

	# ── the tunnel ──
	var k_in := (floori(trip.travel / Land.LENGTH / float(period)) + 1) * period
	var region_before := 0
	trip.set_travel(float(k_in) * Land.LENGTH - 60.0)
	await _secs(1.5)
	region_before = trip.region
	_check(trip.cover < 0.01 and trip.tunnel_b < 0.0 and trip.tunnel_a < 0.0, "outside the tunnel: daylight (mouth %.0f m ahead)" % -trip.tunnel_a)
	await _shot("r81_tunnel_mouth")
	EventBus.camera_preset_requested.emit(0)
	trip.set_travel(float(k_in) * Land.LENGTH + 200.0)
	await _secs(1.5)
	_check(trip.cover > 0.99, "inside the tunnel the daylight is gone (cover %.2f)" % trip.cover)
	await _shot("r81_tunnel_inside_windshield")
	EventBus.camera_preset_requested.emit(5)
	await _secs(1.0)
	await _shot("r81_tunnel_inside_chase")
	trip.set_travel(float(k_in + 5) * Land.LENGTH + 5.0)
	await _secs(1.5)
	await _shot("r81_tunnel_way_out")
	trip.set_travel(float(k_in + 7) * Land.LENGTH)
	await _secs(1.0)
	_check(trip.cover < 0.01 and trip.region == region_before + 1, "out the far side, in the next region (%d > %d)" % [region_before, trip.region])

	if shots_only:
		print("DONE fails=%d" % _fails)
		AppState.request_quit(0 if _fails == 0 else 1)
		return

	# ── heading: the far view turns with the road ──
	var backdrop := room.find_child("Backdrop", true, false) as Node3D
	var turn0 := backdrop.rotation.y
	trip.set_travel(trip.travel + 1400.0)
	await _secs(0.5)
	_check(absf(backdrop.rotation.y - turn0) > 0.02 and backdrop.position.y < -100.0, "the far ridges swing with the road and lie below it (%.2f rad, %.0f m)" % [backdrop.rotation.y - turn0, backdrop.position.y])
	AppState.set_setting("r22_curves", 0.0)
	await _secs(0.3)
	_check(absf(trip.bend) < 0.0000001 and absf(trip.heading) < 0.0001, "Curves 0: dead straight")
	AppState.set_setting("r22_curves", 0.5)

	# ── parked, traffic, co-stream ──
	var traffic: Node = room.call("get_traffic")
	_check(int(traffic.call("count")) >= 1, "traffic is on the road (%d)" % int(traffic.call("count")))
	AppState.set_setting("r22_speed", 0.0)
	await _secs(8.0)
	before = trip.travel
	await _secs(1.0)
	_check(absf(trip.travel - before) < 0.01, "Parked: the land stands still")
	AppState.set_setting("r22_speed", 50.0)
	var mine := trip.travel
	EventBus.net_room_event.emit(2, "Host", "r81_travel", [mine + 500.0, 13.9])
	await _secs(0.1)
	_check(trip.travel < mine + 100.0, "not in a co-stream: a stray travel message is ignored")

	# ── weather and night ──
	var desert: Node = room.call("get_desert")
	AppState.set_setting("r22_weather", "dust")
	await _secs(1.0)
	_check(float(desert.get("dust")) < 0.01, "the desert's dust storm counts as Clear here")
	AppState.set_setting("r22_weather", "storm")
	await _secs(7.0)
	_check(float(desert.get("storm")) > 0.5, "Thunderstorm works here too")
	await _shot("r81_storm")
	AppState.set_setting("r22_weather", "clear")
	AppState.set_setting("r22_time", 22.0)
	await _secs(3.0)
	await _shot("r81_night")
	AppState.set_setting("r22_time", 13.0)

	# ── the Scenery switch ──
	AppState.set_setting("r22_land", "desert")
	var cruise: Room = await _wait_room(host, "Route22CruiseRoom", 180.0)
	_check(cruise != null and String(AppState.get_setting("room_id")) == "route22_cruise", "the Scenery switch loads the desert Cruise")
	var cam := get_viewport().get_camera_3d()
	_check(cam != null and cam.far < 10000.0, "the camera's reach is back to normal (%.0f)" % (cam.far if cam else -1.0))
	AppState.set_setting("r22_land", "route81")
	var again: Room = await _wait_room(host, "Route81Room", 180.0)
	_check(again != null and String(AppState.get_setting("room_id")) == "route81", "and back to Route 81")
	AppState.request_room("studio")
	await _secs(5.0)
	_check(String(AppState.get_setting("room_id")) == "studio", "leaving for another room works")

	print("DONE fails=%d" % _fails)
	AppState.request_quit(0 if _fails == 0 else 1)
