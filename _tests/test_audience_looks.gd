extends Node
## Audience looks: the bubble and silhouette looks (core/audience/audience_style.gd) and how they
## arrive from Stream Core's Audience looks page ("audience_looks" packets, core/audience/core_looks.gd).
## Light / Dark bubbles look as before, a custom bubble style reaches the room's bubbles, every
## built-in silhouette draws, a silhouette style reaches the seats and the filler crowd, a picture
## imports as a silhouette. A packet from Core sets the looks (not before Core's looks were ever
## saved), a Core stored picture is used once it's here (classic until then), group looks (mods,
## a platform) reach the right seats and bubbles, and a random mix spreads looks over the chatters.
## No Core runs: packets go straight into ChatFeed._handle. Saves screenshots to look at.
##   <redot console exe> --path . _tests/test_audience_looks.tscn -- C:/temp/sr_tests --mp-profile=test

var _fails: int = 0


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _secs(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)


func _ready() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(out)
	AppState.set_setting("chat_enabled", false)
	AppState.set_setting("chat_core_url", "ws://127.0.0.1:9/ws")
	AppState.set_setting("panel_window", false)
	AppState.set_setting("audience_enabled", true)
	AppState.set_setting("audience_crowd", true)
	AppState.set_setting("audience_bubble_tints", true)
	# (the test profile keeps settings between runs: set a different value first so each one applies)
	AppState.set_setting("audience_bubble_theme", "dark")
	AppState.set_setting("audience_bubble_theme", "light")
	AppState.set_setting("audience_silhouette", "{}")
	AppState.set_setting("audience_silhouette", "")
	AppState.set_setting("audience_saved_styles", "")
	AppState.set_setting("audience_style_groups", "{}")
	AppState.set_setting("audience_style_groups", "")
	var main: Node = load("res://core/main.tscn").instantiate()
	add_child(main)
	await _secs(1.0)
	AppState.request_room("lecture_hall_panel")
	await _secs(5.0)
	var room: Room = main.get_node("RoomHost").get_current_room()
	var view: AudienceView = room.find_child("Audience", true, false)
	_check(view != null, "the lecture hall has an audience")

	# Light and Dark are the exact looks from before the editor
	var light := AudienceStyle.bubble()
	_check(AudienceStyle.color_of(light, "fill").is_equal_approx(SpeechBubble.FILL)
		and AudienceStyle.color_of(light, "highlighted").is_equal_approx(SpeechBubble.TINT_FILLS["highlighted"][0]),
		"the Light look keeps the old white and purple")
	AppState.set_setting("audience_bubble_theme", "dark")
	var dark := AudienceStyle.bubble()
	_check(AudienceStyle.color_of(dark, "fill").is_equal_approx(SpeechBubble.DARK_FILL)
		and AudienceStyle.color_of(dark, "paid").is_equal_approx(SpeechBubble.TINT_FILLS["paid"][1]),
		"the Dark look keeps the old dark fill and gold")
	AppState.set_setting("audience_bubble_theme", "light")

	# a custom bubble style reaches the room's bubbles
	ChatFeed.send_test_chat()
	await _secs(2.0)
	var slot := -1
	for i in view._rich:
		if bool(view._seats[i]["seated"]) and String(view._seats[i]["kind"]) == "seat":
			slot = i
			break
	_check(slot >= 0, "test chat seated someone")
	AppState.set_setting("audience_bubble_style", JSON.stringify({"shape": 4, "outline": 0.0, "tail": "none",
		"fill": "203040ff", "text_size": 40, "bold": true}))
	AppState.set_setting("audience_bubble_theme", "custom")
	if slot >= 0:
		view._seats[slot]["parts"] = ["A cloud with no outline"]
		view._show_bubble(slot)
		var b: SpeechBubble = view._seats[slot]["bubble"]
		_check(b != null and b._style == 4 and b._outline == 0.0 and b._tail_at < 0.0,
			"the custom style draws a cloud with no outline and no tail")
		_check(b != null and absf(b._fill.r - Color.html("203040").r) < 0.08, "with the custom fill")
	await _secs(0.5)
	await _shot(out + "/style_custom_bubbles.png")

	# every built-in silhouette draws at the size the seats expect
	for id: String in AudienceStyle.FIGURE_SHAPES.keys():
		var tex := AudienceStyle.figure_texture({"shape": id})
		_check(tex != null and tex.get_width() == AudienceStyle.FIGURE_W and tex.get_height() == AudienceStyle.FIGURE_H,
			"the %s silhouette is %dx%d" % [id, AudienceStyle.FIGURE_W, AudienceStyle.FIGURE_H])

	# a silhouette style reaches the seats and the crowd
	AppState.set_setting("audience_silhouette", JSON.stringify({"shape": "bot", "size": 1.2, "paint": "fixed", "color": "33ccaaff"}))
	await _secs(0.5)
	var bot_tex := AudienceStyle.figure_texture({"shape": "bot"})
	if slot >= 0:
		var spr: Sprite3D = view._seats[slot]["sprite"]
		_check(spr.texture == bot_tex, "the seated chatter is a robot now")
		var expect := view.bust_height * 1.2 * float(view._seats[slot]["scale"]) / float(bot_tex.get_height())
		_check(absf(spr.pixel_size - expect) < 0.00001, "and 20% bigger")
		var c: Color = view._seats[slot]["color"]
		var want := Color.html("33ccaa")
		# (a speaker is brighter for a while, so compare the hue)
		_check(absf(c.h - want.h) < 0.03, "painted in the fixed colour (%s)" % str(c))
	if view._crowd != null:
		var q: QuadMesh = view._crowd.multimesh.mesh
		_check(absf(q.size.y - view.bust_height * 1.2) < 0.001, "the filler crowd grew with them")
		_check(view._crowd._mat.get_shader_parameter("silhouette") == bot_tex, "and are robots too")
	EventBus.camera_preset_requested.emit(12)
	await _secs(1.0)
	await _shot(out + "/style_robots.png")

	# a picture from the PC becomes a silhouette
	var pic := Image.create_empty(300, 400, false, Image.FORMAT_RGBA8)
	pic.fill(Color(0, 0, 0, 0))
	for y in 400:
		for x in 300:
			var head := Vector2(x, y).distance_to(Vector2(150, 110)) < 70.0
			var body := y > 200 and absf(x - 150) < 130 - (y - 200) * -0.1
			if head or body:
				pic.set_pixel(x, y, Color(0.9, 0.3, 0.2))
	var src := out + "/style_test_picture.png"
	pic.save_png(src)
	var saved := AudienceStyle.import_picture(src)
	_check(saved.begins_with(AudienceStyle.PICTURE_DIR) and FileAccess.file_exists(saved)
		and FileAccess.file_exists(saved.replace(".png", "_shape.png")), "a picture imports into %s (%s)" % [AudienceStyle.PICTURE_DIR, saved])
	var shape_tex := AudienceStyle.figure_texture({"shape": "custom", "file": saved})
	_check(shape_tex != null and shape_tex.get_height() == AudienceStyle.FIGURE_H, "and loads as a silhouette")
	if shape_tex != null:
		var img := shape_tex.get_image()
		var mid := img.get_pixel(128, 280)
		_check(mid.a > 0.9 and mid.r < 0.3, "its body is dark (%s)" % str(mid))
	_check(AudienceStyle.merge_figure({"shape": "custom", "file": "C:/somewhere/else.png"})["shape"] == "classic",
		"a custom silhouette only reads pictures it imported")

	# looks from Stream Core: nothing changes until Core's looks were saved once ("edited")
	var feed: Node = ChatFeed
	var looks: CoreLooks = feed._looks
	_check(looks != null, "ChatFeed has the Core looks handler")
	AppState.set_setting("audience_bubble_theme", "light")
	AppState.set_setting("audience_silhouette", "")
	feed._handle(JSON.stringify({"type": "audience_looks", "data": {"edited": false, "bubble_theme": "dark"}}))
	_check(String(AppState.get_setting("audience_bubble_theme")) == "light", "looks Core never saved don't reset the room's")
	var packet := {"edited": true, "bubble_theme": "custom",
		"bubble": {"outline": 8.0, "outline_mode": "fixed", "outline_color": "111111ff", "bold": true},
		"silhouette": {"shape": "custom", "file": "media:fox", "paint": "chatter"},
		"saved": {"bubble": {"My comic": {"outline": 8.0, "shape": 4}},
			"silhouette": {"Fox": {"shape": "custom", "file": "media:fox"}, "Robo": {"shape": "bot"}}},
		"groups": {"all": {"silhouette": "Fox|Robo|ears"}},
		"pictures": {}}
	feed._handle(JSON.stringify({"type": "audience_looks", "data": packet}))
	_check(String(AppState.get_setting("audience_bubble_theme")) == "custom" and float(AudienceStyle.bubble()["outline"]) == 8.0,
		"Core's custom bubble style reaches the room")
	_check(AudienceStyle.figure()["shape"] == "classic", "a Core picture that isn't here yet shows the classic silhouette")
	_check(not AudienceStyle.bubble_preset("My comic").is_empty(), "Core's saved bubble looks arrive")
	# the picture arrives (as a download would hand it over), then the same packet uses it
	var fox := pic.save_png_to_buffer()
	var fox_file := looks.save_picture("fox", 7, "/media/fox.png?v=7", fox)
	_check(fox_file.begins_with(AudienceStyle.PICTURE_DIR + "core_") and FileAccess.file_exists(fox_file),
		"a Core picture imports as %s" % fox_file)
	packet["pictures"] = {"fox": {"url": "/media/fox.png?v=7", "version": 7}}
	feed._handle(JSON.stringify({"type": "audience_looks", "data": packet}))
	_check(not looks.is_busy(), "a picture already here isn't downloaded again")
	var fig := AudienceStyle.figure()
	_check(fig["shape"] == "custom" and String(fig["file"]) == fox_file, "and everyone sits as the Core picture now")
	var own: Dictionary = AudienceStyle.saved("silhouette")
	_check(own.get("Fox") is Dictionary and String((own["Fox"] as Dictionary).get("file", "")) == fox_file,
		"saved silhouette looks point at the picture here too")
	# a random mix spreads Core's looks over the chatters
	var got := {}
	for who in ["Ann", "Bo", "Cy", "Di", "Ed", "Flo", "Gus", "Hal", "Ivy", "Jo"]:
		var f := AudienceStyle.figure_for({"name": who, "platform": "twitch", "roles": ""})
		got[String(f["shape"]) + String(f["file"])] = true
		if who == "Ann":
			_check(f == AudienceStyle.figure_for({"name": "ann", "platform": "kick", "roles": ""}), "a chatter keeps the same pick")
	_check(got.size() >= 2, "a random mix gives different chatters different silhouettes (%d kinds)" % got.size())
	await _secs(0.5)
	await _shot(out + "/looks_from_core.png")
	# the Audience tab's button opens Core's page: check the address it builds
	_check(ChatFeed.core_url("/admin/#looks") == "http://127.0.0.1:9/admin/#looks", "the Audience looks button points at Core's page")

	# group looks: mods get the Comic bubble and cat ears, other Twitch chatters a hair bun
	feed._handle(JSON.stringify({"type": "audience_looks", "data": {"edited": true, "bubble_theme": "light",
		"groups": {"mod": {"bubble": "Comic", "silhouette": "ears"}, "twitch": {"silhouette": "bun"}}}}))
	_check(String(AppState.get_setting("audience_silhouette")) == "" and AudienceStyle.saved("silhouette").is_empty(),
		"a new packet replaces the old looks")
	EventBus.chat_message_received.emit(feed._normalize({"platform": "twitch", "message": "mod here",
		"user": {"id": "modmo", "username": "modmo", "display_name": "ModMo", "is_mod": true}}, false))
	EventBus.chat_message_received.emit(feed._normalize({"platform": "twitch", "message": "just a viewer",
		"user": {"id": "viewvi", "username": "viewvi", "display_name": "ViewVi"}}, false))
	EventBus.chat_message_received.emit(feed._normalize({"platform": "kick", "message": "kick viewer",
		"user": {"id": "kicky", "username": "kicky", "display_name": "Kicky"}}, false))
	await _secs(1.0)
	var mod_slot := AudienceManager.find_slot_by_name("ModMo")
	var viewer_slot := AudienceManager.find_slot_by_name("ViewVi")
	var kick_slot := AudienceManager.find_slot_by_name("Kicky")
	var ears := AudienceStyle.figure_texture({"shape": "ears"})
	var bun := AudienceStyle.figure_texture({"shape": "bun"})
	_check(mod_slot >= 0 and String(AudienceManager.get_seat_member(mod_slot).get("roles", "")) == "mod", "the mod's role is kept")
	if mod_slot >= 0 and bool(view._seats[mod_slot]["rich"]):
		_check((view._seats[mod_slot]["sprite"] as Sprite3D).texture == ears, "the mod sits with cat ears (Mods win over Twitch)")
		view._show_bubble(mod_slot)
		var mb: SpeechBubble = view._seats[mod_slot]["bubble"]
		_check(mb != null and mb._outline == 8.0, "and gets the Comic bubble")
	if viewer_slot >= 0 and bool(view._seats[viewer_slot]["rich"]):
		_check((view._seats[viewer_slot]["sprite"] as Sprite3D).texture == bun, "a Twitch viewer gets the Twitch hair bun")
		view._show_bubble(viewer_slot)
		var vb: SpeechBubble = view._seats[viewer_slot]["bubble"]
		_check(vb != null and vb._outline == 5.0, "and the main bubble")
	if kick_slot >= 0 and bool(view._seats[kick_slot]["rich"]):
		_check((view._seats[kick_slot]["sprite"] as Sprite3D).texture == AudienceStyle.CLASSIC_TEX, "a Kick viewer keeps the main silhouette")
	feed._handle(JSON.stringify({"type": "audience_looks", "data": {"edited": true, "bubble_theme": "light",
		"groups": {"mod": {"bubble": "Comic", "silhouette": "ears"}}}}))
	await _secs(0.3)
	if viewer_slot >= 0 and bool(view._seats[viewer_slot]["rich"]):
		_check((view._seats[viewer_slot]["sprite"] as Sprite3D).texture == AudienceStyle.CLASSIC_TEX, "taking the Twitch look away puts them back")
	AppState.set_setting("audience_style_groups", "")

	# back to the classic look
	AppState.set_setting("audience_silhouette", "")
	await _secs(0.3)
	if slot >= 0:
		_check((view._seats[slot]["sprite"] as Sprite3D).texture == AudienceStyle.CLASSIC_TEX, "an empty style is the classic silhouette again")
	AppState.set_setting("audience_bubble_theme", "light")
	print("DONE fails=", _fails)
	AppState.request_quit(1 if _fails > 0 else 0)
