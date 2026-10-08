extends Node
## Odd chat text: a space followed by combining marks (Zalgo text, a stray U+FE0F or U+200D...)
## made Redot's line breaker log "Parameter "sd" is null" / "p_start < 0 || p_length < 0" on every
## layout of the chat window and speech bubbles. SafeText.clean removes those marks; this checks
## what it keeps, lays such messages out in a speech bubble and a chat-window style label, and
## counts those errors in this run's log. Also: EmoteCache tidies JPEGs Redot would turn down.
##   <redot console exe> --path . _tests/test_odd_text.tscn -- C:/temp/sr_tests --mp-profile=test

var _fails: int = 0


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


static func _s(cps: Array) -> String:
	var s := ""
	for x: Variant in cps:
		s += String(x) if x is String else String.chr(int(x))
	return s


func _ready() -> void:
	await get_tree().process_frame
	var zalgo := _s(["hello  ", 0x301, 0x337, "world ", 0x200D, "and ", 0xFE0F, "more\t", 0x34F, "!"])
	var odd: Array[String] = [zalgo, _s([0x301, "starts with a mark"]), _s(["tag ", 0xE0041, 0xE0042, " end"]), _s(["a", 0x3000, 0x20D0, "b"])]

	# what clean keeps
	_check(SafeText.clean("plain ascii  text") == "plain ascii  text", "plain text is left alone")
	_check(SafeText.clean(zalgo) == "hello  world and more\t!", "marks after blanks are removed (%s)" % SafeText.clean(zalgo).c_escape())
	var family := _s([0x1F468, 0x200D, 0x1F469, 0x200D, 0x1F467, " ", 0x2764, 0xFE0F, " Zo", 0x308, "e caf", 0xE9])
	_check(SafeText.clean(family) == family, "emoji sequences and accents on letters are kept")
	_check(SafeText.clean(_s([0x301, "x"])) == "x", "a mark at the very start is removed")

	# lay them out the way the chat window and the bubbles do
	var bubble := SpeechBubble.new()
	add_child(bubble)
	var rtl := RichTextLabel.new()
	rtl.fit_content = true
	rtl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(rtl)
	await get_tree().process_frame
	for t in odd:
		var sz := bubble.set_content("Odd" + _s([0x301]), [t, " ", t], Color.ORANGE, 0, {})
		_check(sz.x > 0 and bubble._rtl.get_parsed_text().contains("more") == t.contains("more"), "a bubble shows %s" % t.c_escape())
		for w in [380.0, 60.0, 20.0]:
			rtl.clear()
			rtl.add_text("  ")
			rtl.add_text(SafeText.clean(t))
			rtl.size = Vector2(w, 0)
			rtl.get_content_height()

	# JPEGs: a missing end marker and stray bytes between header blocks
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	img.fill(Color.CORNFLOWER_BLUE)
	var good := img.save_jpg_to_buffer()
	_check(EmoteCache._tidy_jpeg(good) == good, "a good JPEG is left alone")
	var no_end := good.slice(0, good.size() - 2)
	var stray := good.slice(0, 20) + PackedByteArray([0x12, 0x34]) + good.slice(20)    # (APP0 ends at 20)
	for pair: Array in [["no end marker", no_end], ["stray header bytes", stray]]:
		var out := Image.new()
		var err := out.load_jpg_from_buffer(EmoteCache._tidy_jpeg(pair[1] as PackedByteArray))
		_check(err == OK and out.get_width() == 64, "a JPEG with %s loads after tidying" % pair[0])

	# the engine's own errors only show in the log
	await get_tree().process_frame
	var path := ProjectSettings.globalize_path(String(ProjectSettings.get_setting("debug/file_logging/log_path", "user://logs/godot.log")))
	var log_text := FileAccess.get_file_as_string(path)
	if log_text == "":
		print("NOTE no log file at %s: check the console for \"sd\" is null errors" % path)
	else:
		var n := log_text.count("Parameter \"sd\" is null") + log_text.count("p_start < 0 || p_length < 0")
		_check(n == 0, "no text layout errors in the log (%d)" % n)
	print("DONE fails=", _fails)
	AppState.request_quit(1 if _fails > 0 else 0)
