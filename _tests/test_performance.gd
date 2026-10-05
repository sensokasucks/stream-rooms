extends Node
## Most chatters in the crowd, graphics quality presets, frame-rate cap.
func _secs(t): await get_tree().create_timer(t).timeout
func _shot(path):
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
func _b2g(v: Vector3) -> Vector3:
	return Vector3(v.x, v.z, -v.y)
var _t: float = 0.0
func _chat(name: String, text: String = "hi") -> void:
	_t += 1.0
	EventBus.chat_message_received.emit({"name": name, "username": name.to_lower(), "platform": "kick",
		"user_id": name.to_lower(), "text": text, "timestamp": Time.get_unix_time_from_system() - 1000.0 + _t})
func _count() -> Array:
	var main := 0
	var crowd := 0
	for i in AudienceManager._slots.size():
		if AudienceManager._slots[i] != "":
			match AudienceManager.get_slot_kind(i):
				0: main += 1
				1: crowd += 1
	return [main, crowd]
func _ok(label: String, cond: bool) -> void:
	print(("PASS " if cond else "FAIL ") + label)
func _ready():
	var out: String = OS.get_cmdline_user_args()[0]
	AppState.set_setting("chat_enabled", false)
	AppState.set_setting("seating_by_platform", false)
	AppState.set_setting("audience_crowd", true)
	AppState.set_setting("audience_crowd_move_down", true)
	AppState.set_setting("audience_crowd_max", 0)
	AppState.set_setting("audience_idle_min", 60.0)
	AppState.set_setting("audience_crowd_idle_min", 60.0)
	GraphicsQuality.set_level("high")
	var main = load("res://core/main.tscn").instantiate()
	add_child(main)
	main.get_node("ControlPanel").visible = false
	await _secs(0.5)
	AppState.request_room("lecture_hall")
	await _secs(4.0)
	AppState.set_curtain(false, "instant")
	var host = main.get_node("RoomHost")
	var room = host.get_current_room()
	var aud: AudienceView = room.find_child("Audience", false, false)
	var mains := 0
	for i in aud.get_seat_count():
		if AudienceManager.get_slot_kind(i) == 0:
			mains += 1
	print("main seats=", mains, " total=", aud.get_seat_count())
	# ── crowd cap ──
	AudienceManager.clear()
	AppState.set_setting("audience_crowd_max", 20)
	for n in mains + 50:
		_chat("V%03d" % n)
	await _secs(0.2)
	var c := _count()
	print("cap 20, ", mains + 50, " chatters: main=", c[0], " crowd=", c[1], " rich=", aud._rich.size(), " fillers=", aud.get_filler_count())
	_ok("crowd holds at most 20", c[1] == 20 and c[0] == mains)
	# the newest chatter got a seat; the quietest gave theirs up
	_chat("Newest")
	await _secs(0.1)
	_ok("newcomer seated when full", AudienceManager.find_slot_for_user("kick", "newest") >= 0)
	c = _count()
	_ok("still 20 after a newcomer", c[1] == 20)
	# lowering the cap: the quietest crowd chatters leave
	AppState.set_setting("audience_crowd_max", 5)
	await _secs(0.1)
	c = _count()
	_ok("lowered to 5 -> crowd=5", c[1] == 5)
	_ok("newest kept (most recent)", AudienceManager.find_slot_for_user("kick", "newest") >= 0)
	# no limit again: new chatters overflow freely
	AppState.set_setting("audience_crowd_max", 0)
	for n in 30:
		_chat("W%03d" % n)
	await _secs(0.1)
	c = _count()
	_ok("no limit -> crowd grows past 5 (" + str(c[1]) + ")", c[1] == 35)
	AudienceManager.clear()
	# ── graphics quality ──
	var we: WorldEnvironment = main.get_node("WorldEnvironment")
	var src: Environment = host.get_room_environment()
	_ok("high uses the room's own env", we.environment == src and src.sdfgi_enabled and src.volumetric_fog_enabled)
	var cam: CameraRig = main.get_node("CameraRig")
	cam.global_position = _b2g(Vector3(0, -8, 4.0))
	cam.look_at(_b2g(Vector3(0, 4, 3.0)), Vector3.UP)
	await _secs(0.5)
	await _shot(out + "/perf_high.png")
	AppState.set_setting("graphics_quality", "low")
	await _secs(0.3)
	var e: Environment = we.environment
	var vp := get_viewport()
	print("low: sdfgi=", e.sdfgi_enabled, " fog=", e.volumetric_fog_enabled, " ssao=", e.ssao_enabled, " ambient ", src.ambient_light_energy, "->", e.ambient_light_energy,
		" msaa=", vp.msaa_3d, " fxaa=", vp.screen_space_aa, " scale=", vp.scaling_3d_scale, " mode=", vp.scaling_3d_mode, " atlas=", vp.positional_shadow_atlas_size)
	_ok("low switches", AppState.get_setting("gfx_gi") == false and AppState.get_setting("gfx_fog") == "off" and is_equal_approx(float(AppState.get_setting("gfx_render_scale")), 0.75))
	_ok("low env copy, room env untouched", e != src and not e.sdfgi_enabled and not e.volumetric_fog_enabled and not e.ssao_enabled and src.sdfgi_enabled)
	_ok("low viewport", vp.msaa_3d == Viewport.MSAA_DISABLED and is_equal_approx(vp.scaling_3d_scale, 0.75) and vp.positional_shadow_atlas_size == 2048)
	await _shot(out + "/perf_low.png")
	AppState.set_setting("graphics_quality", "medium")
	await _secs(0.3)
	e = we.environment
	_ok("medium: no GI, fog + SSAO on, MSAA 2x, full res", not e.sdfgi_enabled and e.volumetric_fog_enabled and e.ssao_enabled and vp.msaa_3d == Viewport.MSAA_2X and is_equal_approx(vp.scaling_3d_scale, 1.0))
	await _shot(out + "/perf_medium.png")
	# one switch moved -> custom
	AppState.set_setting("gfx_ssao", false)
	await _secs(0.1)
	_ok("a switch makes it custom", AppState.get_setting("graphics_quality") == "custom" and not we.environment.ssao_enabled)
	AppState.set_setting("gfx_ssao", true)
	_ok("switch back -> medium again", AppState.get_setting("graphics_quality") == "medium")
	# room change keeps the level
	AppState.request_room("classroom")
	await _secs(4.0)
	e = we.environment
	_ok("classroom loads at medium (no SDFGI)", not e.sdfgi_enabled and host.get_room_environment().sdfgi_enabled)
	AppState.set_setting("graphics_quality", "high")
	await _secs(0.2)
	_ok("high restores the room env", we.environment == host.get_room_environment() and vp.msaa_3d == Viewport.MSAA_2X and vp.positional_shadow_atlas_size == int(ProjectSettings.get_setting("rendering/lights_and_shadows/positional_shadow/atlas_size", 4096)))
	# ── frame-rate cap ──
	_ok("default fps cap 60", Engine.max_fps == 60)
	AppState.set_setting("fps_cap", 30)
	_ok("fps 30", Engine.max_fps == 30)
	AppState.set_setting("fps_cap", 0)
	_ok("unlimited", Engine.max_fps == 0)
	AppState.set_setting("vsync", false)
	_ok("vsync off", DisplayServer.window_get_vsync_mode() == DisplayServer.VSYNC_DISABLED)
	AppState.set_setting("vsync", true)
	AppState.set_setting("fps_cap", 60)
	_ok("back to 60", Engine.max_fps == 60)
	# (xvfb's GL driver can't turn V-Sync back on; a real GPU can)
	print("vsync mode after turning it back on: ", DisplayServer.window_get_vsync_mode())
	# panel
	var panel = main.get_node("ControlPanel")
	panel.visible = true
	panel._tabs.current_tab = 1
	AppState.set_setting("graphics_quality", "low")
	await _secs(0.5)
	_ok("panel hint follows", panel._gfx_hint.text.begins_with("Low"))
	var sc: ScrollContainer = panel._tabs.get_current_tab_control() as ScrollContainer
	if sc:
		sc.scroll_vertical = 100000
	await _secs(0.5)
	await _shot(out + "/perf_panel.png")
	GraphicsQuality.set_level("high")
	AppState.set_setting("audience_crowd_max", 0)
	AppState.set_setting("audience_idle_min", 10.0)
	AppState.set_setting("audience_crowd_idle_min", 10.0)
	get_tree().quit()
