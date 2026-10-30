extends Node
## The Style editor (ui/style_editor.gd) and the styles it saves (core/audience/audience_style.gd):
## Light / Dark bubbles look as before, a custom bubble style reaches the room's bubbles, every
## built-in silhouette draws, a silhouette style reaches the seats and the filler crowd, a picture
## from the PC imports as a silhouette, and presets save and delete. Saves screenshots to look at.
## Group looks (mods, a platform) reach the right seats and bubbles; many pictures import at once
## and a random mix spreads them over the chatters.
##   <redot console exe> --path . _tests/test_style_editor.tscn -- C:/temp/sr_tests --mp-profile=test

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
	var guess := AudienceStyle.guess_head(saved)
	_check(guess.y > 0.1 and guess.y < 0.5, "its head is guessed near the top (%s)" % str(guess))
	_check(AudienceStyle.merge_figure({"shape": "custom", "file": "C:/somewhere/else.png"})["shape"] == "classic",
		"a custom silhouette only reads pictures it imported")

	# the editor window: presets and saving
	var panel: Node = main.find_child("ControlPanel", true, false)
	panel._open_style_editor()
	await _secs(1.0)
	var ed: StyleEditor = panel._style_editor
	_check(ed != null and is_instance_valid(ed), "the Style editor opens")
	if ed != null:
		ed._on_picture_picked(src)
		await _secs(0.3)
		_check(AudienceStyle.figure()["shape"] == "custom", "picking a picture in the editor switches the audience to it")
		var comic := -1
		for i in ed._bubble_presets.item_count:
			if String(ed._bubble_presets.get_item_metadata(i)) == "Comic":
				comic = i
		ed._on_bubble_preset(comic)
		_check(String(AppState.get_setting("audience_bubble_theme")) == "custom" and float(AudienceStyle.bubble()["outline"]) == 8.0,
			"the Comic preset becomes the custom style")
		AudienceStyle.save_preset("bubble", "My comic", ed._jsonable(ed._bubble))
		ed._fill_bubble_presets()
		_check(AudienceStyle.bubble_preset_names().has("My comic") and not AudienceStyle.bubble_preset("My comic").is_empty(), "a look saves as a preset")
		var dark_i := -1
		for i in ed._bubble_presets.item_count:
			if String(ed._bubble_presets.get_item_metadata(i)) == "Dark":
				dark_i = i
		ed._on_bubble_preset(dark_i)
		_check(String(AppState.get_setting("audience_bubble_theme")) == "dark", "the Dark preset goes back to the Audience tab's Dark")
		# many pictures at once, then a random mix of them for everyone
		var src2 := out + "/style_test_picture_b.png"
		pic.resize(200, 400)
		pic.save_png(src2)
		ed._on_many_picked(PackedStringArray([src, src2]))
		var mine := AudienceStyle.figure_preset_names()
		_check(mine.has("style_test_picture") and mine.has("style_test_picture_b"), "many pictures become saved looks (%s)" % str(mine))
		AudienceStyle.set_group_look("all", "silhouette", "style_test_picture|style_test_picture_b|bot")
		var got := {}
		for who in ["Ann", "Bo", "Cy", "Di", "Ed", "Flo", "Gus", "Hal", "Ivy", "Jo"]:
			var f := AudienceStyle.figure_for({"name": who, "platform": "twitch", "roles": ""})
			got[String(f["shape"]) + String(f["file"])] = true
			if who == "Ann":
				_check(f == AudienceStyle.figure_for({"name": "ann", "platform": "kick", "roles": ""}), "a chatter keeps the same pick")
		_check(got.size() >= 2, "a random mix gives different chatters different silhouettes (%d kinds)" % got.size())
		ed._fill_group_picks()
		var all_pick: OptionButton = (ed._group_picks["all"] as Array)[1]
		_check(all_pick.get_item_text(all_pick.selected) == "Mix of 3", "the Groups tab shows the mix")
		AppState.set_setting("audience_style_groups", "")
		AudienceStyle.save_preset("bubble", "My comic", {})
		_check(not AudienceStyle.bubble_preset_names().has("My comic"), "and a saved preset deletes")
		await _secs(0.5)
		await RenderingServer.frame_post_draw
		ed.get_texture().get_image().save_png(out + "/style_editor_window.png")
		var tabs: TabContainer = ed.find_children("*", "TabContainer", true, false)[0]
		for t in [1, 2]:
			tabs.current_tab = t
			await _secs(0.3)
			await RenderingServer.frame_post_draw
			ed.get_texture().get_image().save_png(out + "/style_editor_tab%d.png" % t)
		ed.queue_free()

	# group looks: mods get the Comic bubble and cat ears, other Twitch chatters a hair bun
	AppState.set_setting("audience_silhouette", "")
	AppState.set_setting("audience_bubble_theme", "light")
	AudienceStyle.set_group_look("mod", "bubble", "Comic")
	AudienceStyle.set_group_look("mod", "silhouette", "ears")
	AudienceStyle.set_group_look("twitch", "silhouette", "bun")
	var feed: Node = ChatFeed
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
	AudienceStyle.set_group_look("twitch", "silhouette", "")
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
