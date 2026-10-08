extends CanvasLayer
## BoardHud: Stream Core's chat games boards (polls, predictions, the hype meter, cheer vs
## boo, heists, trivia ...) stacked in the top-right corner of the picture.
## "board_hud": auto = only in rooms without a reply screen (that screen shows them there),
## on = always, off = never. Boards stay up in clean feed: they're part of the show.
## Boards come from ChatFeed (EventBus.board_changed / board_cleared).

const WIDTH: float = 430.0
const BAR_BG: Color = Color(0.1, 0.12, 0.17, 1.0)
const BAR_FILL: Color = Color(0.25, 0.72, 1.0)
const WIN: Color = Color(0.33, 0.99, 0.09)
const BOO: Color = Color(1.0, 0.32, 0.27)

var _root: VBoxContainer
var _panels: Dictionary = {}      # board id -> {panel, board, time: Label}
var _tick: float = 0.0


func _ready() -> void:
	layer = 6
	_root = VBoxContainer.new()
	_root.position = Vector2(16, 16)
	_root.add_theme_constant_override("separation", 10)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	EventBus.board_changed.connect(_on_board)
	EventBus.board_cleared.connect(_on_cleared)
	EventBus.setting_changed.connect(func(k: String, _v: Variant) -> void:
		if k in ["board_hud", "board_hud_scale"]:
			_refresh_visible())
	EventBus.room_changed.connect(func(_id: String) -> void: _refresh_visible.call_deferred())
	for b: Dictionary in ChatFeed.get_boards():
		_on_board(b)
	_refresh_visible()


func _process(delta: float) -> void:
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 0.5
	_refresh_visible()
	var now := Time.get_unix_time_from_system()
	for id: String in _panels.keys():
		var e: Dictionary = _panels[id]
		var b: Dictionary = e["board"]
		var t: Label = e["time"]
		if b.get("ends_at") != null and String(b.get("state", "")) == "open":
			t.text = "%ds" % maxi(0, ceili(float(b["ends_at"]) - now))
		else:
			t.text = ""


## How many boards are up (for tests).
func get_board_count() -> int:
	return _panels.size()


func _refresh_visible() -> void:
	var mode := String(AppState.get_setting("board_hud"))
	var on := mode == "on"
	if mode == "auto":
		on = true
		for n in get_tree().get_nodes_in_group("reply_screen"):
			if (n as Node3D).is_visible_in_tree():
				on = false
				break
	visible = on and not _panels.is_empty()
	var sc := clampf(float(AppState.get_setting("board_hud_scale")), 0.5, 2.5)
	_root.scale = Vector2(sc, sc)
	var vw := get_viewport().get_visible_rect().size.x
	_root.position = Vector2(vw - maxf(_root.size.x, WIDTH) * sc - 16.0, 16.0)


func _on_cleared(id: String) -> void:
	var e: Variant = _panels.get(id)
	if e == null:
		return
	_panels.erase(id)
	var p: Control = (e as Dictionary)["panel"]
	var tw := create_tween()
	tw.tween_property(p, "modulate:a", 0.0, 0.3)
	tw.tween_callback(p.queue_free)
	_refresh_visible()


func _on_board(b: Dictionary) -> void:
	var id := String(b.get("id", ""))
	var old: Variant = _panels.get(id)
	var panel := _build(b)
	if old != null:
		var old_panel: Control = (old as Dictionary)["panel"]
		var at := old_panel.get_index()
		old_panel.queue_free()
		_root.add_child(panel)
		_root.move_child(panel, at)
	else:
		_root.add_child(panel)
		panel.modulate.a = 0.0
		create_tween().tween_property(panel, "modulate:a", 1.0, 0.25)
	_panels[id] = {"panel": panel, "board": b, "time": panel.get_meta("time")}
	_refresh_visible()
	_tick = 0.0


func _build(b: Dictionary) -> PanelContainer:
	var kind := String(b.get("kind", "bars"))
	var closed := String(b.get("state", "")) == "closed"
	var compact := kind == "meter"
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(WIDTH, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.035, 0.045, 0.07, 0.86)
	sb.set_corner_radius_all(12)
	sb.set_border_width_all(2)
	sb.border_color = WIN if closed else Color(1, 1, 1, 0.12)
	sb.set_content_margin_all(8.0 if compact else 12.0)
	panel.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4 if compact else 6)
	panel.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var title := _label(String(b.get("title", "")), 18 if compact else 22, Color.WHITE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.add_child(title)
	var time := _label("", 18, Color(1, 1, 1, 0.6))
	head.add_child(time)
	panel.set_meta("time", time)
	var lines: Array = b.get("lines", []) if b.get("lines") is Array else []
	var i := 0
	for l: Variant in lines:
		if not l is Dictionary:
			continue
		v.add_child(_line(l as Dictionary, kind, i))
		i += 1
	var footer := String(b.get("footer", ""))
	if footer != "":
		var f := _label(footer, 15, WIN if closed else Color(1, 1, 1, 0.6))
		f.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(f)
	return panel


func _line(l: Dictionary, kind: String, index: int) -> Control:
	var win := bool(l.get("win", false))
	var label_text := String(l.get("label", ""))
	var note := String(l.get("note", "")) if l.get("note") != null else str(l.get("value", ""))
	if kind == "question":
		var box := VBoxContainer.new()
		var q := _label(label_text, 20, WIN if win else Color.WHITE)
		q.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		q.custom_minimum_size = Vector2(WIDTH - 30, 0)
		box.add_child(q)
		if note != "":
			box.add_child(_label(note, 15, Color(1, 1, 1, 0.6)))
		return box
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var lab := _label(label_text, 17, WIN if win else Color(0.93, 0.94, 0.97))
	lab.custom_minimum_size = Vector2(140, 0)
	lab.clip_text = true
	lab.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(lab)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = clampf(float(l.get("pct", 0.0)), 0.0, 1.0)
	bar.custom_minimum_size = Vector2(0, 14)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bg := StyleBoxFlat.new()
	bg.bg_color = BAR_BG
	bg.set_corner_radius_all(7)
	var fill := StyleBoxFlat.new()
	fill.set_corner_radius_all(7)
	fill.bg_color = WIN if win else BAR_FILL
	if kind == "tug":
		fill.bg_color = WIN if index == 0 else BOO
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)
	row.add_child(bar)
	var n := _label(note, 15, Color(1, 1, 1, 0.7))
	n.custom_minimum_size = Vector2(90, 0)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(n)
	return row


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = SafeText.clean(text)
	l.add_theme_font_override("font", SpeechBubble.shared_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("outline_size", 4)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
