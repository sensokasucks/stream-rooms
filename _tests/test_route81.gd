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
const Vistas := preload("res://rooms/route81/r81_vistas.gd")
const Places := preload("res://rooms/route81/r81_places.gd")
const Billboards := preload("res://rooms/route22/r22_billboards.gd")
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
	for k in range(from, from + 3000):
		if bool(test.call(k)):
			return k
	return -1


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0]
	var full := args.has("full")
	var quick := args.has("quick")
	var shots_only := args.has("shots")
	# "countries" = only round 3's part (the farm valley, the river, the Endless Mountains)
	var countries_only := args.has("countries")
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
	# (the first parts test the ridge country's road; the countries have their own part below)
	AppState.set_setting("r81_country", "ridge")
	AppState.set_setting("r81_bb_amount", 100.0)
	AppState.set_setting("r81_bb_folder", "user://r81_test_no_pictures")
	AppState.set_setting("r81_bb_core", "")
	AppState.set_setting("r81_bb_filler", true)
	for shape: String in Billboards.SHAPES_81:
		AppState.set_setting("r81_bb_" + shape, true)
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
	_check(kinds.has("woods") and kinds.has("cut") and kinds.has("drop") and kinds.has("mount") and not kinds.has("field") and not kinds.has("water"),
		"the ridge road has woods, rock cuts, overlooks and mountains (%s)" % str(kinds.keys()))
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

	var from := floori(trip.travel / Land.LENGTH) + 2
	var k_drop := -1
	if not countries_only:
		# ── an overlook on the right, then a rock cut on the right ──
		k_drop = _find_place(from, func(k: int) -> bool:
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

		# ── streetlights before and after the tunnel; a power line through the woods ──
		var sp := Trip.street_period()
		_check(Trip.lit_at(sp - 1) and Trip.lit_at(sp + 6) and not Trip.lit_at(sp + 3) and not Trip.lit_at(sp + 30),
			"streetlights stand before and after a tunnel, not inside it or far from it")
		trip.set_travel(float(k_in - 5) * Land.LENGTH + 30.0)
		AppState.set_setting("r22_time", 22.5)
		for choice: String in ["sodium", "led", "mixed", "off"]:
			AppState.set_setting("r81_lights", choice)
			await _secs(1.2)
			await _shot("r81_streetlights_%s" % choice)
		var lamp_glow := float((room.call("get_kit")["street_a"] as ShaderMaterial).get_shader_parameter("glow"))
		_check(lamp_glow < 0.01, "Streetlights Off: the lamps are dark at night (%.2f)" % lamp_glow)
		AppState.set_setting("r81_lights", "sodium")
		await _secs(0.3)
		lamp_glow = float((room.call("get_kit")["street_a"] as ShaderMaterial).get_shader_parameter("glow"))
		_check(lamp_glow > 0.8, "Sodium at night: the lamps shine (%.2f)" % lamp_glow)
		AppState.set_setting("r22_time", 13.0)
		await _secs(0.5)
		lamp_glow = float((room.call("get_kit")["street_a"] as ShaderMaterial).get_shader_parameter("glow"))
		_check(lamp_glow < 0.05, "by day they are off (%.2f)" % lamp_glow)
		var k_wires := _find_place(from, func(k: int) -> bool: return Trip.wires_at(k))
		_check(k_wires > 0, "found a power line crossing ahead (place %d)" % k_wires)
		if k_wires > 0:
			trip.set_travel(float(k_wires) * Land.LENGTH - 70.0)
			await _secs(1.5)
			await _shot("r81_power_line")

	# ── the countries: farm valley, river crossing, Endless Mountains ──
	AppState.set_setting("r81_country", "tour")
	_check(Trip.country(0) == "ridge" and Trip.country(1) == "farm" and Trip.country(2) == "river" and Trip.country(3) == "endless" and Trip.country(4) == "coal"
		and Trip.country(5) == "city" and Trip.country(6) == "ridge", "the tour: ridge, farm valley, river, Endless Mountains, coal plateau, city valley, and round again")
	_check(Trip.region_of(period + 2) == 0 and Trip.region_of(period + 3) == 1, "the country changes in the middle of a tunnel")
	AppState.set_setting("r81_country", "farm")
	await _secs(0.5)
	_check(Places.FEATURES.size() == 12, "twelve kinds of roadside place")
	kinds = {}
	for b in range(100, 800):
		kinds[Trip.boundary(1, b)] = true
		kinds[Trip.boundary(-1, b)] = true
	_check(kinds.has("field") and kinds.has("lawn") and kinds.has("lot") and kinds.has("mount"), "farm valley: fields, towns and lots between the tunnels (%s)" % str(kinds.keys()))
	# every kind of place, in the country it belongs to
	for group: Array in [["farm", ["farm", "amish", "town_cozy", "town_historic", "gas", "truck_stop", "old_station"]],
			["coal", ["coal_town", "dead_town", "mine_fire", "breaker"]], ["city", ["city"]]]:
		var land := String(group[0])
		AppState.set_setting("r81_country", land)
		await _secs(0.5)
		for feature: String in group[1]:
			# the third place of one on the right (its middle, or near it)
			var k_f := _find_place(from, func(k: int) -> bool:
				var f := Trip.feature_at(1, k)
				return not f.is_empty() and String(f[0]) == feature and int(f[1]) == 2)
			_check(k_f > 0, "found a %s ahead (place %d)" % [feature, k_f])
			if k_f <= 0:
				continue
			var meshes := 0
			for i in 7:
				meshes += 1 if Places.build(feature, i, 1) != null else 0
				if Places.build(feature, i, -1) != null:
					meshes += 1
			_check(meshes >= 2, "the %s builds on both sides (%d meshes)" % [feature, meshes])
			EventBus.camera_preset_requested.emit(5)
			trip.set_travel(float(k_f) * Land.LENGTH - 130.0)
			await _secs(1.5)
			_check((trip.altitude < 80.0) == (land != "coal"), "%s country's road is %s (%.0f m)" % [land, "high" if land == "coal" else "low", trip.altitude])
			var placed: Array = room.find_children("PlacesR", "MeshInstance3D", true, false).filter(func(n: Node) -> bool:
				return (n as MeshInstance3D).mesh != null and (n as MeshInstance3D).is_visible_in_tree())
			_check(placed.size() >= 1, "the %s stands by the road (%d places)" % [feature, placed.size()])
			await _shot("r81_%s_chase" % feature)
			EventBus.camera_preset_requested.emit(6)
			await _secs(1.0)
			await _shot("r81_%s_drone" % feature)
			# (the driver's side camera looks across the car to the right of the road)
			EventBus.camera_preset_requested.emit(3)
			trip.set_travel(float(k_f) * Land.LENGTH + 30.0)
			await _secs(1.0)
			await _shot("r81_%s_driver_side" % feature)
	# the mine fire smokes
	AppState.set_setting("r81_country", "coal")
	var k_fire := _find_place(from, func(k: int) -> bool:
		var f := Trip.feature_at(1, k)
		return not f.is_empty() and String(f[0]) == "mine_fire" and int(f[1]) == 2)
	trip.set_travel(float(k_fire) * Land.LENGTH - 60.0)
	await _secs(1.5)
	var plumes: Array = trip.find_children("Smoke*", "CPUParticles3D", true, false).filter(func(n: Node) -> bool: return (n as CPUParticles3D).is_visible_in_tree() and (n as CPUParticles3D).emitting)
	_check(plumes.size() >= 2 and Places.smoke_spots("mine_fire", 2, 1).size() == 2 and Places.smoke_spots("dead_town", 2, 1).is_empty(), "smoke rises over the mine fire, not over the other dead town (%d plumes)" % plumes.size())
	AppState.set_setting("r81_country", "farm")
	await _secs(0.5)
	# a town at night
	var k_town := _find_place(from, func(k: int) -> bool:
		var f := Trip.feature_at(1, k)
		return not f.is_empty() and String(f[0]) == "town_cozy" and int(f[1]) == 2)
	if k_town > 0:
		AppState.set_setting("r22_time", 21.5)
		EventBus.camera_preset_requested.emit(5)
		trip.set_travel(float(k_town) * Land.LENGTH - 130.0)
		await _secs(1.5)
		await _shot("r81_town_cozy_night")
		AppState.set_setting("r22_time", 13.0)
	# Route 81's own billboards: one shape at a time, in a stretch of plain fields
	var boards: Billboards = room.call("get_billboards")
	_check(boards != null and boards.prefix == "r81_bb_" and boards.folder() == "user://r81_test_no_pictures" and boards.picture_count() == 0,
		"Route 81 has its own billboard set (settings r81_bb_, its own folder)")
	var k_board := _find_place(from, func(k: int) -> bool:
		var slots := Trip.board_slots(k)
		return slots.size() >= 1 and float(slots[0][1]) > 0.0 and (slots[0][2] as Array).has("barn") and Trip.board_slots(k + 1).size() >= 1)
	_check(k_board > 0, "found a field with room for billboards (place %d)" % k_board)
	EventBus.camera_preset_requested.emit(5)
	# (looked for under the trip: the riders' pictures in the car are called "Picture" too)
	for only: String in Billboards.SHAPES_81:
		for shape: String in Billboards.SHAPES_81:
			AppState.set_setting("r81_bb_" + shape, shape == only)
		trip.set_travel(float(k_board) * Land.LENGTH - 60.0)
		await _secs(1.2)
		var faces: Array = trip.find_children("Picture", "MeshInstance3D", true, false).filter(func(n: Node) -> bool: return (n as MeshInstance3D).is_visible_in_tree())
		var frames: Array = trip.find_children("Board_" + only, "Node3D", true, false)
		_check(frames.size() >= 1 and faces.size() >= frames.size(), "billboards: the %s shape stands along the road (%d boards, %d faces)" % [only, frames.size(), faces.size()])
		await _shot("r81_billboard_%s" % only)
	for shape: String in Billboards.SHAPES_81:
		AppState.set_setting("r81_bb_" + shape, true)
	AppState.set_setting("r81_bb_amount", 0.0)
	await _secs(1.0)
	var left: Array = trip.find_children("Picture", "MeshInstance3D", true, false).filter(func(n: Node) -> bool: return (n as MeshInstance3D).is_visible_in_tree())
	_check(left.is_empty(), "How common 0: no billboards (%d: %s)" % [left.size(), str(left[0].get_path()) if not left.is_empty() else ""])
	AppState.set_setting("r81_bb_amount", 100.0)
	AppState.set_setting("r81_season", "fall")
	await _secs(1.0)
	await _shot("r81_farm_valley_fall")
	AppState.set_setting("r81_season", "summer")

	AppState.set_setting("r81_country", "river")
	await _secs(0.5)
	var k_bridge := _find_place(from, func(k: int) -> bool:
		return Trip.boundary(1, k) == "water" and Trip.boundary(1, k - 1) != "water")
	_check(k_bridge > 0 and Trip.boundary(-1, k_bridge) == "water" and Trip.boundary(1, k_bridge + 8) == "water" and Trip.boundary(1, k_bridge + 9) == "drop"
		and Trip.bridge_at(k_bridge + 3) and not Trip.bridge_at(k_bridge + 10), "river country: a bridge of eight places, water on both sides (from place %d)" % k_bridge)
	EventBus.camera_preset_requested.emit(5)
	trip.set_travel(float(k_bridge) * Land.LENGTH - 150.0)
	await _secs(1.5)
	_check(trip.altitude < 50.0, "the river road is low (%.0f m)" % trip.altitude)
	await _shot("r81_bridge_ahead")
	trip.set_travel(float(k_bridge + 3) * Land.LENGTH)
	await _secs(1.5)
	var decks: Array = room.find_children("Bridge", "MeshInstance3D", true, false).filter(func(n: Node) -> bool:
		return (n as MeshInstance3D).mesh != null and (n as MeshInstance3D).is_visible_in_tree())
	_check(decks.size() >= 8, "the bridge's deck and railings are in view (%d places)" % decks.size())
	await _shot("r81_bridge_chase")
	for cam: int in [0, 3, 6]:
		EventBus.camera_preset_requested.emit(cam)
		await _secs(1.0)
		await _shot("r81_bridge_cam%d" % cam)
	EventBus.camera_preset_requested.emit(5)

	AppState.set_setting("r81_country", "endless")
	await _secs(0.5)
	var k_high := _find_place(from, func(k: int) -> bool:
		return Trip.boundary(1, k) == "drop" and Trip.boundary(1, k + 5) == "drop" and Trip.part_at(k) == "")
	trip.set_travel(float(k_high) * Land.LENGTH + 180.0)
	await _secs(1.5)
	_check(trip.altitude > 130.0 and trip.altitude <= 296.0, "the Endless Mountains' road is high (%.0f m)" % trip.altitude)
	await _shot("r81_endless_overlook")
	EventBus.camera_preset_requested.emit(6)
	await _secs(1.0)
	await _shot("r81_endless_drone")
	EventBus.camera_preset_requested.emit(5)
	AppState.set_setting("r81_tunnels", "never")
	AppState.set_setting("r81_country", "tour")
	_check(Trip.country(Trip.region_of(10)) == "ridge" and Trip.country(Trip.region_of(Trip.NO_TUNNEL_COUNTRY + 10)) == "farm" and Trip.boundary(1, Trip.NO_TUNNEL_COUNTRY) == "woods",
		"Tunnels Never: the country still changes, through the woods")
	AppState.set_setting("r81_tunnels", "medium")
	AppState.set_setting("r81_country", "ridge")
	await _secs(0.5)

	# ── round 4's weather: valley fog, drizzle, "Weather changes by itself" ──
	# (mist eases in over about 12 s and the drizzle over about 7 s: r22_desert.gd)
	var sky: Node = room.call("get_desert")
	AppState.set_setting("r22_weather", "fog")
	await _secs(14.0)
	_check(float(sky.get("mist")) > 0.5 and float(sky.get("storm")) < 0.05, "Valley fog: mist without a storm (%.2f)" % float(sky.get("mist")))
	_check(absf(float(trip.get("mist")) - float(sky.get("mist"))) < 0.05, "the far view gets the same mist as the sky")
	await _shot("r81_fog")
	AppState.set_setting("r22_weather", "drizzle")
	await _secs(9.0)
	var rain: CPUParticles3D = sky.get("_rain")
	_check(float(sky.get("drizzle")) > 0.5 and float(sky.get("storm")) < 0.05, "Drizzle: light rain without thunder")
	_check(rain != null and rain.emitting and rain.amount <= 300, "the drizzle is a thin rain (a third of the storm's drops)")
	await _shot("r81_drizzle")
	AppState.set_setting("r22_weather", "clear")
	_check(not bool(AppState.DEFAULTS["r81_drift"]), "Weather changes by itself is off unless asked for")
	_check(String(room.call("next_weather", "storm", 0.1)) == "afterrain" and String(room.call("next_weather", "fog", 0.1)) == "clear",
		"drifting weather: a storm clears up, fog lifts")
	_check(String(room.call("next_weather", "clear", 0.99)) == "drizzle" and String(room.call("next_weather", "dust", 0.1)) == "clouddeck",
		"drifting weather: every roll gives a weather, and the desert's dust counts as clear")
	var reached: Dictionary = {}
	var at := "clear"
	for n in 400:
		at = String(room.call("next_weather", at, fmod(float(n) * 0.377, 1.0)))
		reached[at] = true
	_check(reached.size() == 6, "drifting weather reaches all six weathers (%d)" % reached.size())
	await _secs(2.0)

	if countries_only:
		print("DONE fails=%d" % _fails)
		AppState.request_quit(0 if _fails == 0 else 1)
		return

	# ── the distant views: every region shows four, and each one builds and shows ──
	var vistas := room.find_child("Vistas", true, false) as Node3D
	_check(vistas != null and (vistas.call("showing") as PackedStringArray).size() == 4, "this region shows four distant views (%s)" % [vistas.call("showing") if vistas else "none"])
	var seen := {}
	for r in 12:
		var list: Array = Vistas.picks(r)
		_check(list.size() == 4 and String(list[0][0]) != String(list[1][0]), "region %d: two different valley views, a ridge thing and a mast (%s)" % [r, list])
		for pick: Array in list:
			seen[String(pick[0])] = true
	_check(seen.size() == Vistas.VALLEY.size() + Vistas.RIDGE.size() + 1, "twelve regions show every view there is (%d)" % seen.size())
	# a look at each from above the car, on an overlook, through a long lens
	trip.set_travel(float(k_drop) * Land.LENGTH + 180.0)
	await _secs(1.0)
	var lens := Camera3D.new()
	lens.far = 30000.0
	lens.fov = 24.0
	add_child(lens)
	var spot: Vector3 = Trip.region_spot(trip.region)
	var names: Array = Array(Vistas.VALLEY) + Array(Vistas.RIDGE) + ["radio"]
	for view: String in names:
		vistas.call("show_views", [[view, 1.0]], spot)
		await _secs(0.3)
		var shown := vistas.get_child(vistas.get_child_count() - 1) as Node3D
		var mesh_node := (shown if shown is MeshInstance3D else shown.get_child(shown.get_child_count() - 1)) as MeshInstance3D
		var ok := mesh_node != null and mesh_node.mesh != null and mesh_node.mesh.get_surface_count() > 0
		_check(ok, "the %s view builds" % view)
		if ok:
			lens.global_position = Vector3(0.0, 45.0, 0.0)
			lens.look_at(mesh_node.global_transform * mesh_node.get_aabb().get_center())
			# (the ridge things are small and far: a longer lens for them)
			lens.fov = 24.0 if Vistas.VALLEY.has(view) else 9.0
			lens.make_current()
			await _secs(0.5)
			await _shot("r81_view_%s" % view)
	AppState.set_setting("r22_time", 22.5)
	vistas.call("show_views", [["town", 1.0]], spot)
	lens.fov = 24.0
	lens.look_at((vistas.get_child(vistas.get_child_count() - 1) as Node3D).global_position)
	await _secs(1.5)
	await _shot("r81_view_town_night")
	AppState.set_setting("r22_time", 13.0)
	lens.queue_free()
	vistas.call("show_region", trip.region + 1000, spot)
	vistas.call("show_region", trip.region, spot)
	EventBus.camera_preset_requested.emit(5)
	await _secs(1.0)

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
