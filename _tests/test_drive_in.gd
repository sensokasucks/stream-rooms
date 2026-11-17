extends Node
## Drive-In's outdoor look (rooms/drive_in/drive_in_room.gd): the room loads with its five
## cameras and its screen, the Room tab lists its controls, Set detail swaps the Simple and the
## Detailed look (photo ground, the belt of detailed trees, grass tufts and ferns, the model's
## simple trees hidden, modelled props and cars in place of the plain blocks), Time of day moves the sun and the moon and turns the lot's lamps down
## by day, the fireflies come out at night only, and the sky is the Lakeside Campfire's.
## Saves screenshots of the looks into the output folder (look at them: the look is not checked
## here). Pass "quick" after the folder to skip the slow Detailed screenshots.
##   <redot console exe> --path . _tests/test_drive_in.tscn -- C:/temp/sr_tests --mp-profile=test

const DI := preload("res://rooms/drive_in/drive_in_room.gd")
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
	print("shot ", shot_name)


## Sets the hour and waits for the sky and lights to follow.
func _at(hour: float) -> void:
	AppState.set_setting("drive_time", hour)
	await _secs(1.0)


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0]
	var quick := args.has("quick")
	DirAccess.make_dir_recursive_absolute(_out)
	AppState.set_setting("chat_enabled", false)
	AppState.set_setting("house_lights", 1.0)
	AppState.set_setting("auto_dim_house", false)
	AppState.set_setting("curtain_enabled", false)
	AppState.set_setting("photosensitive_safe", false)
	AppState.set_setting("graphics_quality", "high")
	AppState.set_setting("drive_detail", "low")
	AppState.set_setting("drive_time", 21.0)
	AppState.set_setting("drive_day_minutes", 0.0)
	AppState.set_setting("drive_clouds", 0.5)
	AppState.set_setting("drive_stars", 1.0)
	AppState.set_setting("drive_aurora", 0.0)
	AppState.set_setting("drive_mist", 0.35)
	AppState.set_setting("drive_fireflies", true)
	var main: Node = load("res://core/main.tscn").instantiate()
	add_child(main)
	main.get_node("ControlPanel").visible = false
	await _secs(0.5)
	AppState.request_room("drive_in")
	await _secs(5.0)
	var host: Node = main.get_node("RoomHost")
	var room: Room = host.get_current_room()
	_check(room != null and room.name == "DriveInRoom" and room.get_script() == DI, "the Drive-In loaded with its own script (%s)" % (room.name if room else "no room"))
	if room == null:
		print("DONE fails=%d" % _fails)
		AppState.request_quit(1)
		return
	_check(room.find_screen() != null and room.get_camera_markers().size() == 5, "screen and five cameras are there")
	_check(room.get_node_or_null("Moonlight") == null and room.find_child("SunMoon", true, false) != null, "the model's fixed moonlight is replaced by the sun / moon lamp")
	var keys: Array[String] = []
	for c: Dictionary in room.get_controls():
		if c.has("key"):
			keys.append(String(c["key"]))
	_check(keys.has("drive_detail") and keys.has("drive_time") and keys.has("drive_aurora") and keys.has("drive_mist"), "the Room tab lists Set detail, Time of day and the sky sliders")
	var env: Environment = get_viewport().world_3d.environment
	var sky_mat := env.sky.sky_material as ShaderMaterial if env and env.sky else null
	_check(sky_mat != null and sky_mat.shader == DI.SKY_SHADER, "the sky is the Lakeside Campfire's sky shader")
	_check(NetSession.SHARED_BASE.has("drive_time") and not NetSession.SHARED_BASE.has("drive_detail"), "the hour is shared in a co-stream, Set detail is not")

	# ── Set detail ──
	var trees := room.find_child("Trees", true, false) as Node3D
	var detailed := room.find_child("DetailedPlants", true, false) as Node3D
	_check(trees != null and trees.is_visible_in_tree() and detailed != null and not detailed.visible, "Simple: the model's own trees, no detailed plants")
	var counts: Dictionary = room.call("get_plant_counts")
	var tall := 0
	for k: String in ["fir", "young_fir", "pine", "oak", "maple", "birch"]:
		tall += int(counts.get(k, 0))
	_check(tall >= 250 and int(counts.get("oak", 0)) > 20 and int(counts.get("birch", 0)) > 10 and int(counts.get("grass", 0)) > 3000, "the Detailed look has a mixed belt of trees and grass (%s)" % str(counts))
	var ground_ok := true
	for mi_any in room.find_children("*", "MeshInstance3D", true, false):
		var mi := mi_any as MeshInstance3D
		for s in (mi.mesh.get_surface_count() if mi.mesh else 0):
			var m := mi.mesh.surface_get_material(s)
			if m and m.resource_name == "Asphalt" and mi.get_surface_override_material(s) != null:
				ground_ok = false
	_check(ground_ok, "Simple: the asphalt keeps the model's own material")
	AppState.set_setting("drive_detail", "full")
	await _secs(0.3)
	var swapped := false
	for mi_any in room.find_children("*", "MeshInstance3D", true, false):
		var mi := mi_any as MeshInstance3D
		for s in (mi.mesh.get_surface_count() if mi.mesh else 0):
			var m := mi.mesh.surface_get_material(s)
			if m and m.resource_name == "Asphalt" and mi.get_surface_override_material(s) is ShaderMaterial:
				swapped = true
	_check(swapped and detailed.visible and not trees.is_visible_in_tree(), "Detailed: photo asphalt and the detailed trees in place of the simple ones")
	var props: Dictionary = room.call("get_prop_counts")
	var blocks := room.find_child("Speaker_Posts", true, false) as Node3D
	var modelled := room.find_child("DetailedProps", true, false) as Node3D
	_check(int(props.get("speaker_post", 0)) >= 100 and int(props.get("light_pole", 0)) == 8 and int(props.get("wall_lamp", 0)) == 2
			and int(props.get("lawn_chair", 0)) >= 1 and int(props.get("cooler", 0)) == 1 and int(props.get("popcorn", 0)) == 1,
			"Detailed: modelled speaker posts, lot lights, lamps, chairs, cooler and popcorn (%s)" % str(props))
	var cars := room.find_child("DetailedCars", true, false) as Node3D
	var old_car := room.find_child("Car_00", true, false) as Node3D
	_check(int(props.get("classic", 0)) + int(props.get("convertible", 0)) == 16 and int(props.get("pickup", 0)) == 1 and cars != null and cars.visible
			and old_car != null and not old_car.visible, "Detailed: the 16 parked cars and the pickup are Route 22's modelled ones")
	_check(modelled != null and modelled.visible and blocks != null and not blocks.visible, "Detailed: the model's plain blocks are hidden under the modelled props")
	AppState.set_setting("drive_detail", "auto")
	AppState.set_setting("graphics_quality", "low")
	await _secs(0.3)
	_check(String(room.call("detail_level")) == "low" and not detailed.visible, "Auto with Graphics quality Low = Simple")
	AppState.set_setting("graphics_quality", "high")
	await _secs(0.3)
	_check(String(room.call("detail_level")) == "full", "Auto with Graphics quality High = Detailed")
	AppState.set_setting("drive_detail", "low")
	await _secs(0.3)

	# ── Time of day ──
	await _at(12.0)
	var sun := room.find_child("SunMoon", true, false) as DirectionalLight3D
	_check(float(room.call("get_daylight")) > 0.9 and sun.light_energy > 1.0, "noon: full day, the sun is up")
	await _secs(2.0)
	var lamp := room.find_child("LAMP_1", true, false)
	var lamp_light: Light3D = null
	if lamp:
		for c in lamp.find_children("*", "Light3D", true, false):
			lamp_light = c as Light3D
	_check(lamp_light == null or not lamp_light.visible or lamp_light.light_energy < 0.05, "the lot's lamps are off by day")
	var fireflies_out := false
	for f in room.find_children("Fireflies*", "CPUParticles3D", true, false):
		fireflies_out = fireflies_out or (f as CPUParticles3D).emitting
	_check(not fireflies_out, "no fireflies by day")
	await _at(22.0)
	await _secs(2.0)
	_check(float(room.call("get_daylight")) < 0.05 and sun.light_energy > 0.05 and sun.light_energy < 0.3, "night: the moon lights the lot")
	_check(lamp_light == null or lamp_light.light_energy > 0.5, "the lot's lamps are on at night")
	fireflies_out = false
	for f in room.find_children("Fireflies*", "CPUParticles3D", true, false):
		fireflies_out = fireflies_out or (f as CPUParticles3D).emitting
	_check(fireflies_out, "fireflies at night")
	AppState.set_setting("drive_day_minutes", 1.0)
	var before := float(room.call("get_hour"))
	await _secs(2.0)
	_check(fposmod(float(room.call("get_hour")) - before, 24.0) > 0.3, "with Day length set the clock runs")
	AppState.set_setting("drive_day_minutes", 0.0)

	# ── screenshots ──
	# Simple look first (fast), then the Detailed one (slow under the cloud's software drawing).
	var cams := room.get_camera_markers()
	await _at(21.0)
	await _secs(1.0)
	EventBus.camera_preset_requested.emit(0)
	await _secs(1.5)
	await _shot("simple_night_truck")
	if not quick:
		AppState.set_setting("drive_detail", "full")
		for row: Array in [[21.0, 0, "night"], [17.7, 0, "sunset"], [12.5, 0, "noon"], [12.5, 2, "noon"], [7.0, 2, "morning"], [21.0, 2, "night"],
				[12.5, 3, "noon"], [21.0, 1, "night"], [21.0, 4, "night"]]:
			await _at(float(row[0]))
			EventBus.camera_preset_requested.emit(int(row[1]))
			await _secs(1.5)
			await _shot("detailed_%s_%s" % [row[2], String(cams[int(row[1])].name).trim_prefix("CAM_")])
		AppState.set_setting("drive_aurora", 1.2)
		AppState.set_setting("drive_mist", 0.7)
		await _at(23.0)
		EventBus.camera_preset_requested.emit(2)
		await _secs(1.5)
		await _shot("detailed_aurora_mist_Lot_Overview")
		AppState.set_setting("drive_aurora", 0.0)
		AppState.set_setting("drive_mist", 0.35)
		AppState.set_setting("drive_detail", "low")
		await _at(12.5)
		EventBus.camera_preset_requested.emit(2)
		await _secs(1.5)
		await _shot("simple_noon_Lot_Overview")

	# ── leaving for another room and coming back ──
	AppState.request_room("studio")
	await _secs(5.0)
	AppState.request_room("drive_in")
	await _secs(5.0)
	var again: Room = host.get_current_room()
	_check(again != null and again != room and again.name == "DriveInRoom", "the room survives a swap away and back")

	print("DONE fails=%d" % _fails)
	AppState.request_quit(0 if _fails == 0 else 1)
