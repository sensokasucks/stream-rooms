extends Node
## The Drive-In's chatters in parked cars (rooms/drive_in/drive_in_cars.gd): the lot has as many
## parking spaces as Room tab > Parking spaces, each one an audience seat; an empty lot has no
## cars (even with Show empty seats on); a chatter who talks gets a car under their seat, the
## same model and paint every time they come back; the glass is see-through; the car blinks its
## headlights when they talk; filler people get cars too; the model's own parked cars are gone
## and the streamer's pickup stays; changing Parking spaces reloads the room with that many.
## Saves screenshots (look at them: the look is not checked here). Pass "quick" after the
## folder to skip the slow Detailed screenshots.
##   <redot console exe> --path . _tests/test_drive_in_cars.tscn -- C:/temp/sr_tests --mp-profile=test

var _fails: int = 0
var _out: String = ""
var _spoken: Array[int] = []


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _secs(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out + "/" + shot_name + ".png")
	print("shot ", shot_name)


## A chat message as ChatFeed hands it on.
func _say(who: String, text: String) -> void:
	var d := {"platform": "twitch", "message": text, "user": {"id": who.to_lower(), "username": who.to_lower(), "display_name": who}}
	EventBus.chat_message_received.emit(ChatFeed._normalize(d, false))


func _cars(room: Node) -> Node:
	return room.find_child("ChatterCars", true, false)


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0]
	var quick := args.has("quick")
	DirAccess.make_dir_recursive_absolute(_out)
	EventBus.audience_spoke.connect(func(slot: int, _parts: Array) -> void: _spoken.append(slot))
	for kv: Array in [["chat_enabled", false], ["chat_core_url", "ws://127.0.0.1:9/ws"], ["panel_window", false],
			["house_lights", 1.0], ["auto_dim_house", false], ["curtain_enabled", false], ["photosensitive_safe", false],
			["flash_strength", 1.0], ["graphics_quality", "high"], ["drive_detail", "low"], ["drive_time", 21.0],
			["drive_day_minutes", 0.0], ["drive_spaces", 60.0], ["audience_enabled", true], ["audience_show_empty", true],
			["audience_fill_main", false], ["audience_names", true]]:
		AppState.set_setting(kv[0], kv[1])
	var main: Node = load("res://core/main.tscn").instantiate()
	add_child(main)
	main.get_node("ControlPanel").visible = false
	await _secs(0.5)
	AppState.request_room("drive_in")
	await _secs(6.0)
	var host: Node = main.get_node("RoomHost")
	var room: Room = host.get_current_room()
	var cars := _cars(room) if room else null
	_check(room != null and room.name == "DriveInRoom" and cars != null, "the Drive-In loaded with its parked-car audience")
	if cars == null:
		print("DONE fails=%d" % _fails)
		AppState.request_quit(1)
		return
	var view := room.find_child("Audience", true, false) as AudienceView
	_check(int(cars.call("get_space_count")) == 60 and room.get_audience_seats().size() == 60 and view != null and view.get_seat_count() >= 60,
			"60 parking spaces, each an audience seat (%d spaces, %d seats)" % [int(cars.call("get_space_count")), room.get_audience_seats().size()])
	_check(not room.show_empty_seats, "the Drive-In hides empty seats' placeholders (an empty space is just empty)")
	await _secs(0.5)
	_check((cars.call("get_parked") as Array).is_empty(), "nobody in chat: no cars on the lot, even with Show empty seats on")
	var old_car := room.find_child("Car_00", true, false) as Node3D
	var pickup_visible := false
	for n in room.find_children("Pickup_Truck", "", true, false):
		pickup_visible = pickup_visible or (n as Node3D).is_visible_in_tree()
	_check(old_car != null and not old_car.visible and pickup_visible, "Simple: the model's own parked cars are gone, the streamer's pickup stays")

	# ── chatters arrive ──
	var names: Array[String] = ["PopcornPilot", "NeonNomad", "CherrySoda", "RetroRacer", "MidnightMoth", "SlowDriveIn",
		"BigScreenBen", "ChromeFins", "MilkshakeMo", "DuskDriver", "StarlitSam", "FuzzyDice"]
	for n in names:
		_say(n, "hi from the lot, I'm %s" % n)
	await _secs(1.5)
	var parked: Array = cars.call("get_parked")
	var who: Array[String] = []
	for p: Dictionary in parked:
		who.append(String(p["who"]))
	var all_there := true
	for n in names:
		all_there = all_there and who.has(n)
	_check(parked.size() == names.size() and all_there, "each chatter who talked has a car (%d parked)" % parked.size())
	# each car is under its chatter's seat
	var under := true
	for n in names:
		var slot := AudienceManager.find_slot_by_name(n)
		var head := view.get_seat_head(slot)
		var found := false
		for p: Dictionary in parked:
			var seat: Vector3 = room.to_global(p["seat"])
			if String(p["who"]) == n and Vector2(head.x - seat.x, head.z - seat.z).length() < 0.05:
				found = true
		under = under and found
	_check(under, "every car stands under its own chatter's seat")
	var kinds := {}
	for p: Dictionary in parked:
		kinds[p["kind"]] = true
	_check(kinds.size() >= 2, "a mix of hardtops and convertibles (%s)" % str(kinds.keys()))
	# the same car when they come back
	var before := _car_of(cars, "PopcornPilot")
	AudienceManager.clear()
	await _secs(0.5)
	_check((cars.call("get_parked") as Array).is_empty(), "everyone leaves: the lot empties")
	_say("PopcornPilot", "back again")
	await _secs(1.0)
	var after := _car_of(cars, "PopcornPilot")
	_check(not before.is_empty() and not after.is_empty() and before["kind"] == after["kind"] and before["paint"] == after["paint"],
			"a chatter comes back in the same car (%s / %s)" % [str(before), str(after)])
	for n in names:
		_say(n, "and we're back")
	await _secs(1.5)

	# ── glass and headlights ──
	var glass_ok := false
	for c in cars.get_children():
		var mi := c as MeshInstance3D
		if mi == null or not mi.visible:
			continue
		for s in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(s)
			if m and m.resource_name == "glass":
				var o := mi.get_surface_override_material(s) as BaseMaterial3D
				glass_ok = o != null and o.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA and o.albedo_color.a < 0.6
		break
	_check(glass_ok, "the cars' glass is see-through")
	_spoken.clear()
	_say("NeonNomad", "honk honk")
	await _secs(0.1)
	var nomad := _car_of(cars, "NeonNomad")
	_check(not nomad.is_empty() and (nomad["node"] as Node).has_meta("blinking"), "a chatter talks: their car blinks its headlights")
	await _secs(1.0)
	_check(not nomad.is_empty() and not (nomad["node"] as Node).has_meta("blinking"), "the blink ends by itself")

	# ── filler people ──
	AppState.set_setting("audience_fill_main", true)
	AppState.set_setting("audience_crowd_fill", 0.5)
	await _secs(0.8)
	var with_fill := (cars.call("get_parked") as Array).size()
	_check(with_fill > names.size() + 10, "filler people in empty seats get cars too (%d parked)" % with_fill)
	AppState.set_setting("audience_fill_main", false)
	await _secs(0.8)
	_check((cars.call("get_parked") as Array).size() == names.size(), "fillers off: their cars go again")

	# ── screenshots ──
	var markers: Array[Node3D] = room.get_camera_markers()
	var cam := Camera3D.new()
	cam.fov = 60.0
	room.add_child(cam)
	for n in names.slice(0, 6):
		_say(n, "what a night for a movie")
	# The seating differs each run, so aim at cars that are really parked: behind one (its driver
	# through the rear window), beside another (through the side glass), and along a row.
	var aims := _aims(room, cars)
	cam.global_position = aims["behind"][0]
	cam.look_at(aims["behind"][1])
	cam.make_current()
	await _secs(1.5)
	await _shot("drive_cars_simple_night_close")
	if not quick:
		AppState.set_setting("drive_detail", "full")
		await _secs(1.0)
		await _shot("drive_cars_detailed_night_close")
		cam.global_transform = markers[2].global_transform
		await _secs(1.0)
		await _shot("drive_cars_detailed_night_wide")
		AppState.set_setting("drive_time", 13.0)
		cam.global_position = aims["row"][0]
		cam.look_at(aims["row"][1])
		await _secs(1.5)
		await _shot("drive_cars_detailed_day_close")
		cam.global_position = aims["side"][0]
		cam.look_at(aims["side"][1])
		await _secs(1.0)
		await _shot("drive_cars_detailed_day_window")
		AppState.set_setting("drive_detail", "low")
		AppState.set_setting("drive_time", 21.0)
	cam.queue_free()

	# ── fewer spaces ──
	AppState.set_setting("drive_spaces", 20.0)
	await _secs(8.0)
	room = host.get_current_room()
	cars = _cars(room) if room else null
	_check(cars != null and int(cars.call("get_space_count")) == 20 and room.get_audience_seats().size() == 20,
			"Parking spaces 20: the room reloads with 20 spaces")
	AppState.set_setting("drive_spaces", 60.0)

	print("DONE fails=%d" % _fails)
	AppState.request_quit(0 if _fails == 0 else 1)


## The car parked for `who` now: {"node", "kind", "paint"} (paint = its paint surface's colour),
## or {} when they have none.
func _car_of(cars: Node, who: String) -> Dictionary:
	for sp: Dictionary in cars.get("_spaces"):
		var car := sp["car"] as MeshInstance3D
		if car and car.visible and String(sp["who"]) == who:
			var paint := Color.BLACK
			for s in car.mesh.get_surface_count():
				var m := car.mesh.surface_get_material(s)
				if m and m.resource_name == "paint":
					var o := car.get_surface_override_material(s) as BaseMaterial3D
					if o:
						paint = o.albedo_color
			return {"node": car, "kind": String(car.get_meta("kind", "")), "paint": paint}
	return {}


## Camera spots aimed at parked cars, as [position, look-at] pairs in world space: "behind" sits
## 7 m behind a parked car (away from the screen) looking at its driver, "side" 3.2 m off the
## driver's side of a car, "row" back and to the side of a row of cars. Picks the car nearest the
## lot's middle so the camera is not out past the fence.
func _aims(room: Node3D, cars: Node) -> Dictionary:
	var parked: Array = cars.call("get_parked")
	var focus := room.to_global(Vector3(0.0, 0.0, -60.0))
	var best := Vector3.ZERO
	var best_d := INF
	for p: Dictionary in parked:
		var seat: Vector3 = room.to_global(p["seat"])
		var d := absf(seat.x - focus.x) + absf(seat.distance_to(focus) - 38.5) * 0.5
		if d < best_d:
			best_d = d
			best = seat
	var back := Vector3(best.x - focus.x, 0.0, best.z - focus.z).normalized()
	var left := back.cross(Vector3.UP)
	var head := best + Vector3(0.0, 0.25, 0.0)
	return {
		"behind": [best + back * 7.0 + Vector3(0.0, 1.6, 0.0), head],
		"side": [best + left * 3.2 + back * 0.6 + Vector3(0.0, 0.4, 0.0), head],
		"row": [best + back * 9.0 + left * 6.0 + Vector3(0.0, 2.6, 0.0), best - left * 4.0],
	}
