class_name ChatScreen
extends Node3D
## A chat window in the room. Every window has a settings key (its "window"):
##   chat_screen   under the main screen (rooms with a CHAT_Screen marker)
##   reply_screen  above the main screen (rooms with a REPLY_Screen marker)
##   chat_left / chat_right   tall windows beside the main screen (SideChats, every room)
## What a window shows is up to the user:
##   <window>_chat      the platforms whose chat it shows ("kick,twitch,youtube,other"; "" = no
##                      chat). One platform per window keeps chats apart (Twitch's rules ask for
##                      that); several mix them.
##   <window>_replies   Stream Core's answers to chat commands (its API-free reply path, since
##                      Core can't post into Kick / YouTube chat) plus chat games boards:
##                      off | on | fallback (only while the room has no reply screen showing).
##                      A window with chat platforms only shows replies to those platforms.
## Replies stay up for reply_screen_hold_s seconds. A window with no chat hides itself while
## it has nothing to show.
## The node is the panel's top centre, +Z faces the audience.
## Reads the same chat as the virtual audience (ChatFeed -> Stream Core), so it follows the
## audience's "Ignore names" and "Hide !commands" options and its name colours.
## Messages flow top-to-bottom through N columns (like a newspaper); the oldest drop off
## when the panel is full. Drawn in 2D into a SubViewport that only redraws when chat changes.

## Pixels per metre of the panel (capped at MAX_PX wide).
const PX_PER_M: float = 300.0
const MAX_PX: int = 3072
const KEEP: int = 80
const MAX_TEXT: int = 300
const BASE_TEXT: int = 32
const PAD: float = 16.0
const GAP: float = 22.0
const BAR_W: float = 5.0
const LINE_GAP: float = 8.0
const TEXT_COLOR: Color = Color(0.93, 0.93, 0.95)
const EMOJI_FONTS: PackedStringArray = ["Segoe UI Emoji", "Apple Color Emoji", "Noto Color Emoji", "Twemoji Mozilla"]

static var _font: Font
static var _bold: Font

var _size: Vector2 = Vector2(8.6, 1.5)
var _vp: SubViewport
var _bg: Panel
var _bg_style: StyleBoxFlat = StyleBoxFlat.new()
var _status: Label
var _header: Label
var _header_rule: ColorRect
var _header_h: float = 0.0
var _quad: MeshInstance3D
var _mat: StandardMaterial3D = StandardMaterial3D.new()
## One per message: {name, hex, parts: Array, avatar, urls: PackedStringArray, node: Control, rtl: RichTextLabel, bar: ColorRect}
var _cards: Array[Dictionary] = []
var _dirty: bool = true
var _animating: bool = false
var _key: String = "chat_screen"      # settings prefix (the window)
var _platforms: PackedStringArray = []   # platform groups whose chat this window shows
var _reply_mode: String = "off"
var _showing_replies: bool = false
var _expire_in: float = 0.5
var _board_clock: float = 1.0

const REPLY_COLOR: Color = Color(0.33, 0.99, 0.09)
## Card backgrounds for messages that stand out: Super Chat / Bits gold, Twitch highlight purple.
const TINT_COLORS: Dictionary = {"paid": Color(0.55, 0.42, 0.06, 0.75), "highlighted": Color(0.46, 0.37, 0.74, 0.75)}


## size_m: metres; window: the settings key (see the top of this file).
func setup(size_m: Vector2, window: String = "chat_screen") -> void:
	_size = size_m
	_key = window


func get_window_key() -> String:
	return _key


## True while this window shows Stream Core replies (for tests and the corner boards).
func is_showing_replies() -> bool:
	return _showing_replies


func _ready() -> void:
	add_to_group("chat_windows")
	var px := Vector2i(roundi(_size.x * PX_PER_M), roundi(_size.y * PX_PER_M))
	if px.x > MAX_PX:
		px = Vector2i(MAX_PX, roundi(float(MAX_PX) * _size.y / _size.x))
	_vp = SubViewport.new()
	_vp.size = px
	_vp.transparent_bg = true
	_vp.disable_3d = true
	_vp.gui_disable_input = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_vp)
	_bg = Panel.new()
	_bg.size = Vector2(px)
	_bg_style.set_corner_radius_all(18)
	_bg.add_theme_stylebox_override("panel", _bg_style)
	_vp.add_child(_bg)
	_status = Label.new()
	_status.size = Vector2(px)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 30)
	_status.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
	_vp.add_child(_status)
	_header = Label.new()
	_header.clip_text = true
	_header.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_header.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_header.add_theme_font_override("font", _bold_font())
	_header.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	_vp.add_child(_header)
	_header_rule = ColorRect.new()
	_vp.add_child(_header_rule)

	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.albedo_color = Color(0.9, 0.9, 0.9)
	_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	_mat.albedo_texture = _vp.get_texture()
	_quad = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = _size
	_quad.mesh = q
	_quad.position = Vector3(0, -_size.y * 0.5, 0)
	_quad.material_override = _mat
	_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_quad)

	EventBus.core_reply_received.connect(_on_reply)
	EventBus.board_changed.connect(_on_board)
	EventBus.board_cleared.connect(_on_board_cleared)
	EventBus.chat_message_received.connect(_on_chat)
	EventBus.chat_status_changed.connect(_on_status)
	EventBus.emote_ready.connect(_on_emote_ready)
	EventBus.setting_changed.connect(_on_setting_changed)
	_apply_style()
	_read_sources()
	_refresh_visibility()


func _exit_tree() -> void:
	EventBus.core_reply_received.disconnect(_on_reply)
	EventBus.board_changed.disconnect(_on_board)
	EventBus.board_cleared.disconnect(_on_board_cleared)
	EventBus.chat_message_received.disconnect(_on_chat)
	EventBus.chat_status_changed.disconnect(_on_status)
	EventBus.emote_ready.disconnect(_on_emote_ready)
	EventBus.setting_changed.disconnect(_on_setting_changed)


func _process(delta: float) -> void:
	if _showing_replies:
		_expire_in -= delta
		if _expire_in <= 0.0:
			_expire_in = 0.5
			_expire_replies()
			_board_clock -= 0.5
			if _board_clock <= 0.0:
				_board_clock = 1.0
				for c in _cards:
					if c.has("board") and (c["board"] as Dictionary).get("ends_at") != null:
						_fill(c)       # countdown
						_dirty = true
	if _dirty and visible:
		_dirty = false
		_layout()
		# animated emotes on the panel: redraw every frame so they play; otherwise only on change
		_animating = false
		for c in _cards:
			_animating = _animating or (bool(c.get("animated", false)) and (c["node"] as Control).visible)
		_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if _animating else SubViewport.UPDATE_ONCE


## How many messages it holds (for tests).
func get_message_count() -> int:
	return _cards.size()


## How many are on the panel right now (for tests).
func get_visible_count() -> int:
	var n := 0
	for c in _cards:
		if (c["node"] as Control).visible:
			n += 1
	return n


func clear() -> void:
	for c in _cards:
		(c["node"] as Control).queue_free()
	_cards.clear()
	_dirty = true


# ── Replies ──────────────────────────────────────────────────
func _on_reply(r: Dictionary) -> void:
	if not _showing_replies:
		return
	var plat := String(r.get("platform", ""))
	if not _reply_allowed(plat):
		return        # a reply to another platform's chatter: that platform's window shows it
	var text := String(r.get("message", "")).strip_edges()
	if text == "":
		return
	var hold := float(AppState.get_setting("reply_screen_hold_s"))
	var ts := float(r.get("timestamp", Time.get_unix_time_from_system()))
	if bool(r.get("history", false)) and (hold <= 0.0 or Time.get_unix_time_from_system() - ts > hold):
		return     # backlog from before we connected: only the ones still inside the hold time
	var who := String(r.get("reply_to_user", "")).strip_edges().trim_prefix("@")
	# name the chatter it answers, unless the reply already starts with "@name"
	var label := "Stream Core"
	if who != "" and not text.to_lower().begins_with("@" + who.to_lower()):
		label = "@" + who
	_add_card({"name": label, "hex": "", "parts": [text.left(MAX_TEXT)], "avatar": "",
		"urls": PackedStringArray(), "reply": true, "ts": ts, "platform": plat})


## Does this window take a reply to a chatter on this platform? ("<window>_replies_for")
func _reply_allowed(plat: String) -> bool:
	if _platforms.is_empty() or plat == "" or String(AppState.get_setting(_key + "_replies_for")) != "chat":
		return true
	return _platforms.has(AudienceManager.platform_group(plat))


func _expire_replies() -> void:
	var hold := float(AppState.get_setting("reply_screen_hold_s"))
	if hold <= 0.0 or _cards.is_empty():
		return
	var cutoff := Time.get_unix_time_from_system() - hold
	for c in _cards.duplicate():
		if bool(c.get("reply", false)) and not c.has("board") and float(c.get("ts", 0.0)) < cutoff:
			_cards.erase(c)
			(c["node"] as Control).queue_free()
			_dirty = true


# ── Chat games boards (polls, predictions, hype ...) ─────────
## Boards sit below the replies (the newest end), so they're always on the panel.
func _on_board(b: Dictionary) -> void:
	if not _showing_replies:
		return
	var id := String(b.get("id", ""))
	for c in _cards:
		if c.has("board") and String((c["board"] as Dictionary).get("id", "")) == id:
			c["board"] = b
			_fill(c)
			_dirty = true
			return
	_add_card({"name": String(b.get("title", "")), "hex": "", "parts": [], "avatar": "",
		"urls": PackedStringArray(), "reply": true, "board": b, "ts": Time.get_unix_time_from_system()})


func _on_board_cleared(id: String) -> void:
	for c in _cards.duplicate():
		if c.has("board") and String((c["board"] as Dictionary).get("id", "")) == id:
			_cards.erase(c)
			(c["node"] as Control).queue_free()
			_dirty = true


## A board as text: title (and time left), a bar per line, the footer.
func _fill_board(card: Dictionary) -> void:
	var b: Dictionary = card["board"]
	var rtl: RichTextLabel = card["rtl"]
	var size := _text_size()
	var closed := String(b.get("state", "")) == "closed"
	(card["bar"] as ColorRect).color = Color(1.0, 0.83, 0.0) if not closed else REPLY_COLOR
	rtl.clear()
	rtl.add_theme_font_size_override("normal_font_size", size)
	rtl.add_theme_font_size_override("bold_font_size", size)
	rtl.push_bold()
	rtl.add_text(SafeText.clean(String(b.get("title", ""))))
	rtl.pop()
	if b.get("ends_at") != null and String(b.get("state", "")) == "open":
		var left := maxi(0, ceili(float(b["ends_at"]) - Time.get_unix_time_from_system()))
		rtl.push_color(Color(1, 1, 1, 0.55))
		rtl.add_text("   %ds" % left)
		rtl.pop()
	var cells := 12
	for l: Variant in (b.get("lines", []) if b.get("lines") is Array else []):
		if not l is Dictionary:
			continue
		var line := l as Dictionary
		rtl.newline()
		var win := bool(line.get("win", false))
		if win:
			rtl.push_color(REPLY_COLOR)
		rtl.add_text(SafeText.clean(String(line.get("label", ""))))
		if String(b.get("kind", "")) != "question":
			var filled := clampi(roundi(clampf(float(line.get("pct", 0.0)), 0.0, 1.0) * cells), 0, cells)
			rtl.add_text("  " + "▰".repeat(filled) + "▱".repeat(cells - filled) + "  ")
		else:
			rtl.add_text("  ")
		rtl.push_color(Color(1, 1, 1, 0.7))
		rtl.add_text(SafeText.clean(String(line.get("note", "")) if line.get("note") != null else str(line.get("value", ""))))
		rtl.pop()
		if win:
			rtl.pop()
	var footer := String(b.get("footer", ""))
	if footer != "":
		rtl.newline()
		rtl.push_color(REPLY_COLOR if closed else Color(1, 1, 1, 0.6))
		rtl.add_text(SafeText.clean(footer))
		rtl.pop()


# ── Chat ─────────────────────────────────────────────────────
func _on_chat(msg: Dictionary) -> void:
	if bool(msg.get("system", false)) or _platforms.is_empty():
		return
	var plat := AudienceManager.platform_group(String(msg.get("platform", "")))
	if not _platforms.has(plat):
		return
	var who := String(msg.get("name", ""))
	if who == "" or AudienceManager.is_ignored(who):
		return
	var raw := String(msg.get("text", "")).strip_edges()
	if raw == "" or (raw.begins_with("!") and bool(AppState.get_setting("chat_screen_hide_commands"))):
		return
	var parts := AudienceManager.message_parts(raw, msg.get("emotes", []) as Array, MAX_TEXT)
	if parts.is_empty():
		return
	var urls := PackedStringArray()
	for p: Variant in parts:
		if p is Dictionary:
			urls.append(String(p["url"]))
	var avatar := String(msg.get("avatar", ""))
	if avatar != "":
		urls.append(avatar)
	_add_card({"name": who, "hex": String(msg.get("color", "")), "parts": parts, "avatar": avatar, "urls": urls,
		"platform": plat, "reply_to": String(msg.get("reply_to", "")), "reply_quote": String(msg.get("reply_quote", "")),
		"tint": String(msg.get("tint", "")) if bool(AppState.get_setting("audience_bubble_tints")) else ""})


func _add_card(card: Dictionary) -> void:
	var node := Control.new()
	var tint_bg := ColorRect.new()      # Super Chat / Twitch highlight: a coloured box behind the card
	tint_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tint_bg.visible = false
	node.add_child(tint_bg)
	var bar := ColorRect.new()
	node.add_child(bar)
	var rtl := RichTextLabel.new()
	rtl.bbcode_enabled = false
	rtl.fit_content = true
	rtl.scroll_active = false
	rtl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rtl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rtl.add_theme_font_override("normal_font", _shared_font())
	rtl.add_theme_font_override("bold_font", _bold_font())
	rtl.add_theme_color_override("default_color", TEXT_COLOR)
	rtl.position = Vector2(BAR_W + 10.0, 0)
	node.add_child(rtl)
	node.visible = false
	_bg.add_child(node)
	card["node"] = node
	card["rtl"] = rtl
	card["bar"] = bar
	card["tint_bg"] = tint_bg
	_cards.append(card)
	_fill(card)
	if _showing_replies:
		# boards stay at the newest end, below the replies
		var boards: Array[Dictionary] = []
		var rest: Array[Dictionary] = []
		for c in _cards:
			if c.has("board"):
				boards.append(c)
			else:
				rest.append(c)
		rest.append_array(boards)
		_cards = rest
	while _cards.size() > KEEP:
		(_cards.pop_front()["node"] as Control).queue_free()
	_dirty = true


func _fill(card: Dictionary) -> void:
	_apply_outline(card["rtl"] as RichTextLabel)
	if card.has("board"):
		_fill_board(card)
		return
	var rtl: RichTextLabel = card["rtl"]
	var size := _text_size()
	var color := REPLY_COLOR if bool(card.get("reply", false)) else AudienceManager.color_for(String(card["name"]), String(card["hex"]), String(card.get("platform", "")))
	(card["bar"] as ColorRect).color = color
	var tint := String(card.get("tint", ""))
	var tint_bg: ColorRect = card.get("tint_bg")
	if tint_bg:
		tint_bg.visible = TINT_COLORS.has(tint)
		if tint_bg.visible:
			tint_bg.color = TINT_COLORS[tint]
			(card["bar"] as ColorRect).color = (TINT_COLORS[tint] as Color).lightened(0.4)
	rtl.clear()
	rtl.add_theme_font_size_override("normal_font_size", size)
	rtl.add_theme_font_size_override("bold_font_size", size)
	var pic := String(card["avatar"])
	if pic != "" and bool(AppState.get_setting("chat_screen_pictures")) and bool(AppState.get_setting("audience_avatars")):
		var tex := EmoteCache.get_circle_texture(pic)
		if tex:
			var s := roundi(size * 1.25)
			rtl.add_image(tex, s, s, Color.WHITE, INLINE_ALIGNMENT_CENTER)
			rtl.add_text(" ")
	rtl.push_bold()
	rtl.push_color(color)
	rtl.add_text(SafeText.clean(String(card["name"])))
	rtl.pop()
	rtl.pop()
	var reply_to := String(card.get("reply_to", ""))
	if reply_to != "":
		# a reply made with the platform's reply button: who it answers, and a bit of what they said
		var quote := String(card.get("reply_quote", ""))
		rtl.add_text("  ")
		rtl.push_font_size(roundi(size * 0.8))
		rtl.push_color(Color(TEXT_COLOR, 0.7))
		rtl.add_text(SafeText.clean("↩ replying to " + reply_to + (": " + quote.left(60) + ("…" if quote.length() > 60 else "") if quote != "" else "")))
		rtl.pop()
		rtl.pop()
		rtl.newline()
	rtl.add_text("  ")
	var h := roundi(size * 1.35)
	card["animated"] = false
	for p: Variant in card["parts"]:
		if p is Dictionary:
			var tex: Texture2D = EmoteCache.get_texture(String(p["url"]))
			if tex:
				card["animated"] = bool(card["animated"]) or EmoteCache.is_animated(tex)
				var w := roundi(float(h) * tex.get_width() / maxf(tex.get_height(), 1.0))
				rtl.add_image(tex, w, h, Color.WHITE, INLINE_ALIGNMENT_CENTER, Rect2(), null, false, String(p["name"]))
			else:
				rtl.add_text(SafeText.clean(String(p["name"])))
		else:
			rtl.add_text(SafeText.clean(String(p)))


func _on_emote_ready(url: String) -> void:
	for c in _cards:
		if (c["urls"] as PackedStringArray).has(url):
			_fill(c)
			_dirty = true


func _on_status(_info: Dictionary) -> void:
	_dirty = true


# ── Layout ───────────────────────────────────────────────────
## Newspaper flow: fill column 1 top to bottom, then column 2 ... Shows as many of the
## newest messages as fit; the rest stay hidden (and are dropped after KEEP).
func _layout() -> void:
	_apply_header()
	var area := Vector2(_vp.size) - Vector2(PAD, PAD) * 2.0 - Vector2(0.0, _header_h)
	var cols := 1
	if not _platforms.is_empty() and AppState.DEFAULTS.has(_key + "_columns"):
		cols = clampi(int(AppState.get_setting(_key + "_columns")), 1, 4)
	var col_w := (area.x - GAP * (cols - 1)) / cols
	var heights: Array[float] = []
	for c in _cards:
		var rtl: RichTextLabel = c["rtl"]
		var w := col_w - BAR_W - 10.0
		rtl.custom_minimum_size = Vector2(w, 0)
		rtl.size = Vector2(w, 0)
		heights.append(float(rtl.get_content_height()))
	# the oldest message that still lets everything after it fit
	var start := _cards.size()
	while start > 0 and _fits(heights, start - 1, cols, area.y):
		start -= 1
	start = mini(start, maxi(_cards.size() - 1, 0))     # always show the newest, even if it's tall
	var col := 0
	var y := 0.0
	for i in _cards.size():
		var node: Control = _cards[i]["node"]
		if i < start:
			node.visible = false
			continue
		var h := heights[i]
		if y > 0.0 and y + h > area.y:
			col += 1
			y = 0.0
		node.visible = col < cols
		node.position = Vector2(PAD + col * (col_w + GAP), PAD + _header_h + y)
		node.size = Vector2(col_w, h)
		var bar: ColorRect = _cards[i]["bar"]
		bar.position = Vector2(0, 2)
		bar.size = Vector2(BAR_W, maxf(h - 4.0, 4.0))
		var tint_bg: ColorRect = _cards[i].get("tint_bg")
		if tint_bg:
			tint_bg.position = Vector2(0, -3)
			tint_bg.size = Vector2(col_w, h + 6.0)
		y += h + LINE_GAP
	if _platforms.is_empty():
		# replies only, nothing to show: no panel at all (it only appears while there's a reply)
		_status.visible = false
		_quad.visible = not _cards.is_empty()
		return
	_quad.visible = true      # (it may have been a replies-only window, hidden while empty)
	_status.visible = _cards.is_empty()
	if _status.visible:
		if not bool(AppState.get_setting("chat_enabled")):
			_status.text = "Chat is off (Chat tab > Connect)"
		elif not ChatFeed.is_connected_to_core():
			_status.text = "Waiting for Stream Core…"
		else:
			_status.text = "Waiting for chat…"


func _fits(heights: Array[float], start: int, cols: int, col_h: float) -> bool:
	var col := 0
	var y := 0.0
	for i in range(start, heights.size()):
		var h := heights[i]
		if y > 0.0 and y + h > col_h:
			col += 1
			y = 0.0
			if col >= cols:
				return false
		if h > col_h:
			return false
		y += h + LINE_GAP
	return true


# ── Settings ─────────────────────────────────────────────────
func _on_setting_changed(key: String, _value: Variant) -> void:
	if key in [_key + "_chat", _key + "_replies", _key + "_replies_for", "reply_screen"]:
		_read_sources()
		_refresh_visibility()
	elif key == _key:
		_refresh_visibility()
	elif key == _key + "_bg":
		_apply_style()
	elif key == _key + "_header" or key == _key + "_header_on":
		_dirty = true
	elif key in [_key + "_text", _key + "_outline", "chat_screen_pictures", "audience_avatars", "audience_color_by"] or key.begins_with("platform_color_"):
		for c in _cards:
			_fill(c)
		_dirty = true
	elif key in [_key + "_columns", "chat_enabled", "reply_screen_hold_s"]:
		_expire_replies()
		_dirty = true


## Reads what this window shows, and drops cards it no longer should.
func _read_sources() -> void:
	_platforms = PackedStringArray()
	for p in String(AppState.get_setting(_key + "_chat")).split(",", false):
		var g := AudienceManager.platform_group(p.strip_edges())
		if not _platforms.has(g) and p.strip_edges() != "":
			_platforms.append(g)
	_reply_mode = String(AppState.get_setting(_key + "_replies"))
	var was := _showing_replies
	_showing_replies = _reply_mode == "on" or (_reply_mode == "fallback" and not reply_screen_showing())
	for c in _cards.duplicate():
		var keep := true
		if bool(c.get("reply", false)):
			keep = _showing_replies and (c.has("board") or _reply_allowed(String(c.get("platform", ""))))
		elif not _platforms.has(String(c.get("platform", "other"))):
			keep = false
		if not keep:
			_cards.erase(c)
			(c["node"] as Control).queue_free()
	if _showing_replies and not was:
		for b: Dictionary in ChatFeed.get_boards():
			_on_board(b)
	_dirty = true


## Is the room's reply screen up (so "fallback" windows leave the replies to it)?
static func reply_screen_showing() -> bool:
	return AppState.room_has_reply_screen() and bool(AppState.get_setting("reply_screen"))


func _apply_style() -> void:
	_bg_style.bg_color = Color(0.03, 0.035, 0.05, clampf(float(AppState.get_setting(_key + "_bg")), 0.0, 1.0))
	_dirty = true


func _refresh_visibility() -> void:
	visible = bool(AppState.get_setting(_key))
	# the corner boards (BoardHud, "auto") stay away while a window shows the boards
	if visible and _showing_replies:
		add_to_group("reply_screen")
	elif is_in_group("reply_screen"):
		remove_from_group("reply_screen")
	_dirty = true


## The header line: the window's own text, or named after what it shows ("Twitch chat").
## Coloured like the platform when the window shows just one.
func _apply_header() -> void:
	var on := AppState.DEFAULTS.has(_key + "_header_on") and bool(AppState.get_setting(_key + "_header_on"))
	var text := String(AppState.get_setting(_key + "_header")).strip_edges() if on else ""
	if on and text == "":
		text = auto_header(_platforms, _showing_replies)
	_header.visible = on and text != ""
	_header_rule.visible = _header.visible
	if not _header.visible:
		_header_h = 0.0
		return
	var fs := roundi(_text_size() * 1.15)
	var c := Color(1, 1, 1, 0.95)
	if _platforms.size() == 1:
		c = AudienceManager.platform_color(_platforms[0]).lightened(0.25)
	_header.text = text
	_header.add_theme_font_size_override("font_size", fs)
	_header.add_theme_constant_override("outline_size", roundi(_outline_px() * 1.15))
	_header.add_theme_color_override("font_color", c)
	var h := fs * 1.5
	_header.position = Vector2(PAD, PAD * 0.5)
	_header.size = Vector2(float(_vp.size.x) - PAD * 2.0, h)
	_header_rule.color = Color(c, 0.7)
	_header_rule.position = Vector2(PAD, PAD * 0.5 + h + 2.0)
	_header_rule.size = Vector2(float(_vp.size.x) - PAD * 2.0, 3.0)
	_header_h = h + 10.0


## "Twitch chat", "Kick · YouTube chat", "Stream Core replies" ...
static func auto_header(platforms: PackedStringArray, replies: bool) -> String:
	if platforms.is_empty():
		return "Stream Core replies" if replies else ""
	if platforms.size() >= AudienceManager.PLATFORMS.size():
		return "Chat"
	var names := PackedStringArray()
	for g in AudienceManager.PLATFORMS:
		if platforms.has(g):
			names.append(String(AudienceManager.PLATFORM_LABELS[g]))
	return " · ".join(names) + " chat"


## Text outline ("<window>_outline", 0-1): a dark edge round every letter so chat stays readable
## over a busy room when the background is see-through.
func _outline_px() -> int:
	var o := clampf(float(AppState.get_setting(_key + "_outline")), 0.0, 1.0) if AppState.DEFAULTS.has(_key + "_outline") else 0.0
	return roundi(o * _text_size() * 0.35)


func _apply_outline(c: Control) -> void:
	var px := _outline_px()
	c.add_theme_constant_override("outline_size", px)
	c.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))


## About how tall a line of chat text is on a 1080p stream from the current camera (pixels), or
## -1 when the window is off screen / hidden. The Chat tab warns when it's too small to read.
func estimate_text_px(out_height: float = 1080.0) -> float:
	if not is_visible_in_tree() or not _quad.visible:
		return -1.0
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return -1.0
	var px_per_m := float(_vp.size.y) / maxf(_size.y, 0.01)
	var line_m := float(_text_size()) / px_per_m
	var c := _quad.global_position
	if cam.is_position_behind(c):
		return -1.0
	var up := global_basis.y.normalized()
	var a := cam.unproject_position(c)
	var b := cam.unproject_position(c + up * line_m)
	var vh := float(get_viewport().get_visible_rect().size.y)
	var on := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size).grow(-4.0).has_point(a)
	if not on:
		return -1.0
	return a.distance_to(b) * out_height / maxf(vh, 1.0)


func get_text_scale() -> float:
	return float(AppState.get_setting(_key + "_text"))


func _text_size() -> int:
	return roundi(BASE_TEXT * clampf(float(AppState.get_setting(_key + "_text")), 0.5, 3.0))


static func _shared_font() -> Font:
	if _font == null:
		var emoji := SystemFont.new()
		emoji.font_names = EMOJI_FONTS
		var f := FontVariation.new()
		f.base_font = ThemeDB.fallback_font
		f.fallbacks = [emoji]
		_font = f
	return _font


static func _bold_font() -> Font:
	if _bold == null:
		var f := FontVariation.new()
		f.base_font = _shared_font()
		f.variation_embolden = 0.8
		_bold = f
	return _bold
