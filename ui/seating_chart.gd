class_name SeatingChart
extends Control
## A top-down seating chart of the current room for the Seating tab: every seat as a dot,
## coloured by what its section allows under the seating plan (a platform's colour, a mix, or
## grey for "anyone"), taken seats as bigger dots in their chatter's platform colour, and
## each section's name. Click a section to pick it for editing.

signal section_picked(id: String)
signal floors_changed(has_top: bool)

const BOTTOM: String = "bottom"
const TOP: String = "top"

const STAGE_H: float = 18.0
const MARGIN: float = 10.0
const LETTER: Dictionary = {"kick": "K", "twitch": "T", "youtube": "Y", "other": "O"}
const LEGEND_H: float = 16.0

var selected: String = ""
## Which floor is drawn: BOTTOM (main seats, the lower tier, the stage) or TOP (balcony + gallery).
var floor_shown: String = BOTTOM
var _has_top: bool = false
var _chart: Dictionary = {}
var _dots: Array[Vector2] = []           # slot -> position on the chart (NAN = not drawn)
var _redraw_in: float = -1.0


func _ready() -> void:
	custom_minimum_size = Vector2(0, 330)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL     # keyboard: arrows pick the previous / next section
	tooltip_text = "Click a section (or Tab here and use the arrow keys) to choose who may sit there."
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	EventBus.seating_changed.connect(_refresh)
	EventBus.audience_seated.connect(func(_s: int) -> void: _soon())
	EventBus.audience_left.connect(func(_s: int) -> void: _soon())
	resized.connect(_refresh)
	_refresh()


func _process(delta: float) -> void:
	if _redraw_in >= 0.0:
		_redraw_in -= delta
		if _redraw_in < 0.0:
			_refresh()


func _soon() -> void:
	if _redraw_in < 0.0:
		_redraw_in = 0.3       # seats fill in bursts: redraw once they settle


func _refresh() -> void:
	_chart = AudienceManager.get_chart()
	var had := _has_top
	_has_top = false
	for id in _chart.get("sections", PackedStringArray()):
		if floor_of(String(id)) == TOP:
			_has_top = true
			break
	if not _has_top:
		floor_shown = BOTTOM
	if had != _has_top:
		floors_changed.emit(_has_top)
	_layout()
	queue_redraw()


## Does this room have seats upstairs (so the Seating tab offers the floor buttons)?
func has_top_floor() -> bool:
	return _has_top


func show_floor(which: String) -> void:
	floor_shown = which
	_refresh()


## A section's floor: the quadrants and the lower tier (1xx) are downstairs; the balcony (2xx)
## and gallery (3xx) upstairs.
static func floor_of(id: String) -> String:
	if id.is_valid_int() and int(id) >= 200:
		return TOP
	return BOTTOM


func _on_floor(i: int, sections: PackedStringArray, kinds: PackedByteArray) -> bool:
	if i < kinds.size() and kinds[i] == AudienceManager.KIND_PRESENTER:
		return floor_shown == BOTTOM
	return floor_of(sections[i] if i < sections.size() else "") == floor_shown


## Seats projected top-down, the stage at the top, the audience's left on the left.
func _layout() -> void:
	_dots.clear()
	var spots: Array = _chart.get("spots", [])
	var kinds: PackedByteArray = _chart.get("kinds", PackedByteArray())
	var secs: PackedStringArray = _chart.get("sections", PackedStringArray())
	if spots.is_empty():
		return
	var centre := Vector3.ZERO
	var count := 0
	for i in spots.size():
		if i < kinds.size() and kinds[i] == AudienceManager.KIND_PRESENTER:
			continue
		centre += spots[i] as Vector3
		count += 1
	centre /= maxf(count, 1)
	var stage: Vector3 = _chart.get("stage") if _chart.get("stage") is Vector3 else centre + Vector3(0, 0, -100)
	var a := Vector3(centre.x - stage.x, 0, centre.z - stage.z).normalized()
	if a.length() < 0.5:
		a = Vector3.BACK
	var right := (-a).cross(Vector3.UP).normalized()
	var raw: Array[Vector2] = []
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in spots.size():
		var d := (spots[i] as Vector3) - stage
		var p := Vector2(d.dot(right), d.dot(a))
		raw.append(p)
		if (i < kinds.size() and kinds[i] == AudienceManager.KIND_PRESENTER) or not _on_floor(i, secs, kinds):
			continue
		lo = lo.min(p)
		hi = hi.max(p)
	lo.y = minf(lo.y, 0.0)          # keep the stage line in view
	var area := size - Vector2(MARGIN * 2.0, MARGIN * 2.0 + STAGE_H + LEGEND_H + 30.0)   # room for the legend + stacked level names
	var span := (hi - lo).max(Vector2(1, 1))
	var k := minf(area.x / span.x, area.y / span.y)
	var offset := Vector2(MARGIN, MARGIN + STAGE_H) + (area - span * k) * 0.5
	for i in raw.size():
		_dots.append(offset + (raw[i] - lo) * k if _on_floor(i, secs, kinds) else Vector2(NAN, NAN))


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.02, 0.03, 0.9))
	if has_focus():
		draw_rect(Rect2(Vector2.ONE, size - Vector2(2, 2)), Color(1.0, 0.85, 0.2), false, 2.0)
	var font := get_theme_default_font()
	var spots: Array = _chart.get("spots", [])
	if spots.is_empty():
		draw_string(font, Vector2(MARGIN, size.y * 0.5), "This room has no audience seats.", HORIZONTAL_ALIGNMENT_CENTER, size.x - MARGIN * 2.0, 14, Color(1, 1, 1, 0.5))
		return
	# stage / screen
	draw_rect(Rect2(MARGIN + size.x * 0.25, MARGIN, size.x * 0.5 - MARGIN, STAGE_H - 6.0), Color(0.3, 0.3, 0.36))
	draw_string(font, Vector2(MARGIN + size.x * 0.25, MARGIN + 11.0), "STAGE / SCREEN", HORIZONTAL_ALIGNMENT_CENTER, size.x * 0.5 - MARGIN, 11, Color(1, 1, 1, 0.8))
	var sections: PackedStringArray = _chart.get("sections", PackedStringArray())
	var kinds: PackedByteArray = _chart.get("kinds", PackedByteArray())
	var taken: PackedStringArray = _chart.get("taken", PackedStringArray())
	var plan_on := bool(AppState.get_setting("seating_by_platform"))
	var colours: Dictionary = {}          # section -> colour
	var sums: Dictionary = {}             # section -> [sum Vector2, n]
	for i in _dots.size():
		var kind := int(kinds[i]) if i < kinds.size() else 0
		var id := sections[i] if i < sections.size() else ""
		var p := _dots[i]
		if is_nan(p.x):
			continue
		if kind == AudienceManager.KIND_PRESENTER:
			draw_rect(Rect2(p - Vector2(5, 3), Vector2(10, 6)), Color(1.0, 0.8, 0.4, 0.8))
			if i < taken.size() and taken[i] != "":
				draw_circle(p, 4.0, AudienceManager.platform_color(taken[i]))
			continue
		if not colours.has(id):
			colours[id] = _section_colour(id, plan_on)
		var c: Color = colours[id]
		var r := 2.4 if kind == AudienceManager.KIND_CROWD else 3.2
		if id == selected and selected != "":
			draw_circle(p, r + 1.6, Color(1, 1, 1, 0.9))
		draw_circle(p, r, c)
		if i < taken.size() and taken[i] != "":
			draw_circle(p, r + 0.8, AudienceManager.platform_color(taken[i]).lightened(0.15))
		if id != "":
			if not sums.has(id):
				sums[id] = [Vector2.ZERO, 0]
			sums[id][0] += p
			sums[id][1] += 1
	# section names
	for id: String in sums.keys():
		var at: Vector2 = (sums[id][0] as Vector2) / float(sums[id][1])
		# levels stack on top of each other seen from above: spread their names apart
		if id.is_valid_int() and int(id) >= 100:
			if floor_shown == TOP:
				at.y += (8.0 if int(id) >= 300 else -8.0)     # the gallery sits right above the balcony
		# the name plus who may sit there as letters (K T Y O), so it doesn't hang on colour alone
		var text := id
		var allowed := AudienceManager.get_section_platforms(id) if plan_on else PackedStringArray()
		if not allowed.is_empty():
			var letters := PackedStringArray()
			for g in AudienceManager.PLATFORMS:
				if allowed.has(g):
					letters.append(LETTER[g])
			text += " " + "".join(letters)
		var w := maxf(40.0, font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 10.0)
		draw_rect(Rect2(at - Vector2(w * 0.5, 9), Vector2(w, 14)), Color(0, 0, 0, 0.7))
		draw_string(font, at + Vector2(-w * 0.5, 2), text, HORIZONTAL_ALIGNMENT_CENTER, w, 12,
			Color(1, 1, 0.6) if id == selected else Color(1, 1, 1, 0.95))
	# legend
	var x := MARGIN
	var y := size.y - 6.0
	for g in AudienceManager.PLATFORMS:
		draw_circle(Vector2(x + 5, y - 4), 4.0, AudienceManager.platform_color(g))
		var name := "%s %s" % [LETTER[g], String(AudienceManager.PLATFORM_LABELS[g])]
		draw_string(font, Vector2(x + 12, y), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.85))
		x += 22.0 + font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	draw_circle(Vector2(x + 5, y - 4), 4.0, Color(0.45, 0.45, 0.5))
	draw_string(font, Vector2(x + 12, y), "Anyone", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.8))


## A section's colour: its one platform, a blend of several, or grey for anyone.
func _section_colour(id: String, plan_on: bool) -> Color:
	var allowed := AudienceManager.get_section_platforms(id)
	if not plan_on or allowed.is_empty():
		return Color(0.45, 0.45, 0.5, 0.9)
	var c := Color(0, 0, 0, 0)
	for g in allowed:
		c += AudienceManager.platform_color(g)
	c /= float(allowed.size())
	c.a = 1.0
	return c.darkened(0.35)


func _gui_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_right") or event.is_action_pressed("ui_down"):
		_step_section(1)
		accept_event()
		return
	if event.is_action_pressed("ui_left") or event.is_action_pressed("ui_up"):
		_step_section(-1)
		accept_event()
		return
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var sections: PackedStringArray = _chart.get("sections", PackedStringArray())
	var best := -1
	var best_d := 18.0
	for i in _dots.size():
		if i >= sections.size() or sections[i] == "" or is_nan(_dots[i].x):
			continue
		var d := _dots[i].distance_to(mb.position)
		if d < best_d:
			best_d = d
			best = i
	if best >= 0:
		selected = sections[best]
		queue_redraw()
		section_picked.emit(selected)
		accept_event()


## Keyboard: the next / previous section on the floor shown, in order (Q1-Q4, then 101 ...).
func _step_section(dir: int) -> void:
	var ids: Array[String] = []
	var sections: PackedStringArray = _chart.get("sections", PackedStringArray())
	for i in mini(sections.size(), _dots.size()):
		var id := sections[i]
		if id != "" and not is_nan(_dots[i].x) and not ids.has(id):
			ids.append(id)
	if ids.is_empty():
		return
	ids.sort_custom(func(a: String, b: String) -> bool:
		var qa := a.begins_with("Q")
		var qb := b.begins_with("Q")
		if qa != qb:
			return qa
		return a.naturalnocasecmp_to(b) < 0)
	var at := ids.find(selected)
	at = (at + dir + ids.size()) % ids.size() if at >= 0 else (0 if dir > 0 else ids.size() - 1)
	selected = ids[at]
	queue_redraw()
	section_picked.emit(selected)
