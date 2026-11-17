extends Node
## Route 22: both scenes load with what their markers promise and their parts work.
##   Drive-In (route22): screen, ten cameras, four podiums, 30 chat seats, the marquee's text
##     setting, Lot lights, two-way traffic on Route 22.
##   Cruise (route22_cruise): ten cameras, four seats in the woody, no screen, the road moving
##     (travel grows with Speed, Parked stops it), road pieces in view with no type twice,
##     billboards with filler ads, traffic, the weather switch, a co-stream host's travel,
##     the Landmarks and stops, Plant life and Animals sliders.
##   The Scene switch loads the other scene, both ways.
## Every control on the Room tab has a default. Saves a screenshot per camera of each scene and
## a few weathers (look at them: the look is not checked here).
##   <redot console exe> --path . _tests/test_route22.tscn -- C:/temp/sr_tests --mp-profile=test

const Trip := preload("res://rooms/route22/r22_trip.gd")
const Pieces := preload("res://rooms/route22/r22_pieces.gd")
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


## Every control with a key has a default in AppState.DEFAULTS.
func _controls_have_defaults(room: Room, what: String) -> void:
	var missing: Array[String] = []
	var n := 0
	for c in room.get_controls():
		if c.has("key"):
			n += 1
			if not AppState.DEFAULTS.has(String(c["key"])):
				missing.append(String(c["key"]))
			if not c.has("tooltip"):
				missing.append(String(c["key"]) + " (no tooltip)")
	_check(n > 15 and missing.is_empty(), "%s: all %d Room tab controls have defaults and tooltips %s" % [what, n, str(missing)])


## Waits (up to `limit` seconds) until RoomHost shows a room named `room_name`; returns it or null.
## (Loading takes a few seconds on a PC and up to a minute under the software renderer.)
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


func _shoot_cameras(room: Room, prefix: String) -> void:
	var cams := room.get_camera_markers()
	for i in cams.size():
		EventBus.camera_preset_requested.emit(i)
		await _secs(1.0)
		await _shot("%s_%s" % [prefix, String(cams[i].name).trim_prefix("CAM_")])
	EventBus.camera_preset_requested.emit(0)


func _ready() -> void:
	_out = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(_out)
	AppState.set_setting("chat_enabled", false)
	AppState.set_setting("house_lights", 1.0)
	AppState.set_setting("auto_dim_house", false)
	AppState.set_setting("audience_seat_gap", 1.0)
	AppState.set_setting("curtain_enabled", false)
	AppState.set_setting("photosensitive_safe", false)
	AppState.set_setting("flash_strength", 1.0)
	# the flat-colour look: the detailed one is very slow on the pull request check's software renderer
	AppState.set_setting("r22_detail", "low")
	AppState.set_setting("graphics_quality", "high")
	AppState.set_setting("r22_scene", "drivein")
	AppState.set_setting("r22_time", 18.2)
	AppState.set_setting("r22_day_minutes", 0.0)
	AppState.set_setting("r22_weather", "clouddeck")
	AppState.set_setting("r22_clouds", 1.0)
	AppState.set_setting("r22_wind", 0.35)
	AppState.set_setting("r22_heat", 0.5)
	AppState.set_setting("r22_speed", 50.0)
	AppState.set_setting("r22_curves", 0.5)
	AppState.set_setting("r22_traffic", 100.0)
	AppState.set_setting("r22_bb_amount", 100.0)
	AppState.set_setting("r22_bb_folder", "user://r22_test_no_pictures")
	AppState.set_setting("r22_bb_core", "")
	AppState.set_setting("r22_bb_filler", true)
	AppState.set_setting("r22_marquee", "tonight: chat's pick")
	AppState.set_setting("r22_lot_lights", true)
	AppState.set_setting("r22_neon", true)
	for n in range(1, 5):
		AppState.set_setting(AppState.presenter_key(n, "on"), true)
		AppState.set_setting(AppState.presenter_key(n, "source"), "silhouette")
	var main: Node = load("res://core/main.tscn").instantiate()
	add_child(main)
	main.get_node("ControlPanel").visible = false
	await _secs(0.5)
	var host: Node = main.get_node("RoomHost")

	# ── the Drive-In ──
	var t0 := Time.get_ticks_msec()
	AppState.request_room("route22")
	var room: Room = await _wait_room(host, "Route22Room", 120.0)
	_check(room != null and room.name == "Route22Room", "the Route 22 Drive-In loaded (%s, about %.1f s)" % [room.name if room else "no room", float(Time.get_ticks_msec() - t0) / 1000.0])
	if room == null or room.name != "Route22Room":
		print("DONE fails=%d" % (_fails + 1))
		AppState.request_quit(1)
		return
	_check(room.find_screen() != null, "the drive-in has its big screen")
	var cams := room.get_camera_markers()
	_check(cams.size() == 10 and room.get_camera_label(cams[0]) == "Drive In", "ten cameras, Drive In first (%d, %s)" % [cams.size(), room.get_camera_label(cams[0]) if cams.size() > 0 else ""])
	var pres := room.get_presenter_setups()
	var pods := 0
	for p in pres:
		pods += 1 if p["podium"] != null else 0
	_check(pres.size() == 4 and pods == 4, "four presenters, each at a podium (%d / %d)" % [pres.size(), pods])
	var seats := room.get_audience_seats()
	_check(seats.size() == 30, "30 chat seats (%d)" % seats.size())
	var facing := 0
	for s in seats:
		# each seat faces the screen (the -Z end): its +Z axis points roughly towards -Z
		facing += 1 if s.basis.z.z < -0.3 else 0
	_check(facing == 30, "every seat faces the screen (%d)" % facing)
	_check(room.find_child("BEAM_Projector", true, false) != null, "the projection booth has its beam marker")
	_check(String(room.call("get_marquee_text")) == "TONIGHT: CHAT'S PICK", "the marquee shows the Marquee text in capitals (%s)" % room.call("get_marquee_text"))
	AppState.set_setting("r22_marquee", "double feature")
	await _secs(0.2)
	_check(String(room.call("get_marquee_text")) == "DOUBLE FEATURE", "changing the Marquee text changes the sign")
	_controls_have_defaults(room, "Drive-In")
	await _secs(6.0)
	var traffic: Node = room.call("get_traffic")
	_check(int(traffic.call("count")) >= 1, "traffic comes by on Route 22 at How busy 100 (%d)" % int(traffic.call("count")))
	await _shoot_cameras(room, "r22_drivein")
	AppState.set_setting("r22_time", 21.5)
	await _secs(2.0)
	await _shot("r22_drivein_night")
	AppState.set_setting("r22_lot_lights", false)
	await _secs(3.0)
	await _shot("r22_drivein_night_lot_lights_off")
	AppState.set_setting("r22_lot_lights", true)
	AppState.set_setting("r22_time", 13.0)
	AppState.set_setting("r22_weather", "clear")
	await _secs(6.0)
	await _shot("r22_drivein_noon")
	EventBus.camera_preset_requested.emit(9)
	await _secs(1.0)
	await _shot("r22_drivein_noon_rocks")
	EventBus.camera_preset_requested.emit(0)

	# ── the Scene switch: to the Cruise ──
	AppState.set_setting("r22_time", 18.2)
	AppState.set_setting("r22_weather", "clouddeck")
	t0 = Time.get_ticks_msec()
	AppState.set_setting("r22_scene", "cruise")
	var cruise: Room = await _wait_room(host, "Route22CruiseRoom", 120.0)
	_check(cruise != null and cruise.name == "Route22CruiseRoom" and String(AppState.get_setting("room_id")) == "route22_cruise",
		"the Scene switch loads the Cruise (%s, about %.1f s)" % [cruise.name if cruise else "no room", float(Time.get_ticks_msec() - t0) / 1000.0])
	if cruise == null or cruise.name != "Route22CruiseRoom":
		print("DONE fails=%d" % (_fails + 1))
		AppState.request_quit(1)
		return
	_check(cruise.find_screen() == null, "the Cruise has no big screen")
	_check(cruise.get_camera_markers().size() == 10, "ten cameras on the Cruise")
	_check(cruise.get_presenter_setups().size() == 4, "four riders' places in the woody")
	_controls_have_defaults(cruise, "Cruise")
	var trip: Trip = cruise.call("get_trip")
	var before := trip.travel
	await _secs(2.0)
	_check(trip.travel > before + 10.0 and trip.speed > 10.0, "the road moves at Speed 50 (%.1f m in 2 s, %.1f m/s)" % [trip.travel - before, trip.speed])
	var kinds := trip.types_in_view()
	var unique := {}
	for k in kinds:
		unique[k] = true
	_check(kinds.size() >= 8 and unique.size() == kinds.size(), "%d road pieces in view, no type twice" % kinds.size())
	# the bag: across 5 rounds every type comes once a round, and no type within SPACING of itself
	var spaced := true
	var counts := {}
	for k in range(0, Pieces.TYPES.size() * 5):
		var t := trip.type_at(k)
		counts[t] = int(counts.get(t, 0)) + 1
		for j in range(maxi(0, k - Trip.SPACING + 1), k):
			if trip.type_at(j) == t:
				spaced = false
	_check(spaced and counts.size() == Pieces.TYPES.size(), "the piece order: every type each round, never two of a type close together")
	# Landmarks and stops: at 50 about half the places in view are plain desert, at 0 all of
	# them, and no piece (landmark or plain) is ever in two places
	for share: float in [50.0, 0.0]:
		AppState.set_setting("r22_scenery", share)
		await _secs(0.5)
		var mix := trip.types_in_view()
		var plain := mix.count("plain")
		var marks := {}
		for k in mix:
			if k != "plain":
				marks[k] = true
		var on_show := 0
		for piece in trip.get_children():
			on_show += 1 if (piece as Node3D).visible and String(piece.name).begins_with("Piece_") else 0
		var want_ok := (plain == mix.size()) if share == 0.0 else (plain >= mix.size() / 2 - 1 and plain <= mix.size() / 2 + 1)
		if share == 0.0:
			await _secs(1.0)
			await _shot("r22_cruise_lonely_road")
		_check(want_ok and marks.size() == mix.size() - plain and on_show == mix.size(), "Landmarks and stops %d%%: %d of %d places plain desert, none shown twice" % [int(share), plain, mix.size()])
	AppState.set_setting("r22_scenery", 100.0)
	await _secs(0.5)
	_check(not trip.types_in_view().has("plain"), "Landmarks and stops back at 100%: no plain stretches")
	# Plant life: 30% draws about 30% of each brush MultiMesh, 100% all of it
	AppState.set_setting("r22_plants", 30.0)
	await _secs(0.3)
	var brush := cruise.find_children("Brush_*", "MultiMeshInstance3D", true, false)
	var thin := brush.size() > 0
	for b in brush:
		var mm := (b as MultiMeshInstance3D).multimesh
		thin = thin and mm.visible_instance_count == roundi(float(mm.instance_count) * 0.3)
	AppState.set_setting("r22_plants", 100.0)
	await _secs(0.3)
	var full := brush.size() > 0
	for b in brush:
		full = full and (b as MultiMeshInstance3D).multimesh.visible_instance_count == -1
	_check(thin and full, "Plant life thins the brush out and fills it back in (%d patches)" % brush.size())
	# (the boards stand on the road pieces, under each piece's "Boards" node)
	var shown := 0
	for b in cruise.find_children("Picture", "MeshInstance3D", true, false):
		shown += 1 if (b as MeshInstance3D).is_visible_in_tree() and String(b.name).begins_with("Picture") else 0
	_check(shown >= 1, "billboards with filler ads stand along the road (%d faces)" % shown)
	var traffic2: Node = cruise.call("get_traffic")
	await _secs(8.0)
	_check(int(traffic2.call("count")) >= 1, "traffic on the Cruise road (%d)" % int(traffic2.call("count")))
	await _shoot_cameras(cruise, "r22_cruise")
	# parked
	AppState.set_setting("r22_speed", 0.0)
	await _secs(20.0)
	before = trip.travel
	await _secs(1.0)
	_check(absf(trip.travel - before) < 0.01, "Parked: the desert stands still")
	AppState.set_setting("r22_speed", 50.0)
	# a co-stream host's distance: a guest jumps onto it (role is "off" here, so this one ignores it)
	var mine := trip.travel
	EventBus.net_room_event.emit(2, "Host", "r22_travel", [mine + 500.0, 13.9])
	await _secs(0.1)
	_check(trip.travel < mine + 100.0, "not in a co-stream: a stray travel message is ignored")
	# weathers
	var desert: Node = cruise.call("get_desert")
	for w: String in ["storm", "dust", "afterrain", "clear"]:
		AppState.set_setting("r22_weather", w)
		await _secs(7.0)
		await _shot("r22_cruise_" + w)
		if w == "storm":
			_check(float(desert.get("storm")) > 0.5, "Thunderstorm darkens the sky (%.2f)" % float(desert.get("storm")))
		if w == "afterrain":
			_check(float(desert.get("wet")) > 0.5, "After rain wets the road (%.2f)" % float(desert.get("wet")))
	AppState.set_setting("r22_time", 22.0)
	await _secs(3.0)
	await _shot("r22_cruise_night")
	EventBus.camera_preset_requested.emit(5)
	await _secs(1.0)
	await _shot("r22_cruise_night_chase")
	EventBus.camera_preset_requested.emit(0)
	# coyotes: send a pack across now (night), and one howl
	AppState.set_setting("r22_coyotes", true)
	var extras := cruise.find_child("Extras", true, false)
	extras.set("_pack_wait", 0.0)
	await _secs(1.0)
	var dogs := 0
	for c in extras.find_children("Coyote", "MeshInstance3D", false, false):
		dogs += 1 if (c as Node3D).visible else 0
	_check(dogs >= 1, "a pack of coyotes trots across at night (%d)" % dogs)
	desert.call("howl", 0.6)
	await _secs(0.5)
	_check(float(desert.get("_howl_t")) >= 0.0, "a howl starts in the desert sound")
	AppState.set_setting("r22_coyotes", false)
	await _secs(0.5)
	dogs = 0
	for c in extras.find_children("Coyote", "MeshInstance3D", false, false):
		dogs += 1 if (c as Node3D).visible else 0
	_check(dogs == 0, "Coyotes off sends them away")
	# Animals at 0: the time to the next jackrabbit or lizard stands still (none ever comes)
	AppState.set_setting("r22_animals", 0.0)
	var out_now := bool((extras.get("_critter") as Node3D).visible)
	var wait0 := float(extras.get("_critter_wait"))
	await _secs(1.0)
	# (one already running across finishes its run, so only check when none is out)
	_check(out_now or is_equal_approx(float(extras.get("_critter_wait")), wait0), "Animals 0%%: no more animals come (wait stays %.1f s)" % wait0)
	AppState.set_setting("r22_animals", 100.0)

	# ── and back ──
	AppState.set_setting("r22_scene", "drivein")
	var back: Room = await _wait_room(host, "Route22Room", 120.0)
	_check(back != null and back.name == "Route22Room" and back.get_audience_seats().size() == 30, "the Scene switch goes back to the Drive-In")
	AppState.request_room("studio")
	await _secs(5.0)
	_check(String(AppState.get_setting("room_id")) == "studio", "leaving Route 22 for another room works")

	print("DONE fails=%d" % _fails)
	AppState.request_quit(0 if _fails == 0 else 1)
