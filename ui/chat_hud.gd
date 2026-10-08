extends CanvasLayer
## ChatHud: a chat box on the picture, in a corner, like the chat games boards (BoardHud).
## "chat_hud": auto = only while no chat window in the room shows chat, on = always, off = never.
## The box is a "flat" ChatScreen (window key "chat_hud"), so it has every chat window's options:
## platforms, Stream Core replies, header, text size, background, outline, columns. It stays up
## in clean feed (F10): it's part of the show.

const MARGIN: float = 16.0     # pixels from the picture's edge on a 1080p stream

var _win: ChatScreen
var _rect: TextureRect
var _tick: float = 0.0


func _ready() -> void:
	layer = 6
	_win = ChatScreen.new()
	_win.name = "ChatHudWindow"
	_win.setup(Vector2(_box_px()), "chat_hud", true)
	add_child(_win)
	_rect = TextureRect.new()
	_rect.texture = _win.get_texture()
	_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rect)
	EventBus.setting_changed.connect(func(k: String, _v: Variant) -> void:
		if k.begins_with("chat_hud") or k in ["chat_left", "chat_right", "chat_screen", "reply_screen"] or k.ends_with("_chat"):
			_tick = 0.0)
	EventBus.room_changed.connect(func(_id: String) -> void: _tick = 0.0)
	get_viewport().size_changed.connect(func() -> void: _tick = 0.0)
	_refresh()


func _process(delta: float) -> void:
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 0.5
	_refresh()


## The chat box's window (for tests).
func get_chat_window() -> ChatScreen:
	return _win


## Is the box on the picture right now (for tests)?
func is_box_visible() -> bool:
	return visible and _rect.visible


## Does a chat window in the room show chat? ("auto" leaves the chat to it then.)
func room_shows_chat() -> bool:
	for n in get_tree().get_nodes_in_group("chat_windows"):
		var w := n as ChatScreen
		if w != null and is_instance_valid(w) and not w.is_flat() and w.shows_chat():
			return true
	return false


## The box's size in pixels of a 1080p picture.
func _box_px() -> Vector2i:
	var s := get_viewport().get_visible_rect().size
	var k := 1080.0 / maxf(s.y, 1.0)
	var w := clampf(float(AppState.get_setting("chat_hud_width")), 0.1, 0.9) * s.x * k
	var h := clampf(float(AppState.get_setting("chat_hud_height")), 0.1, 0.95) * 1080.0
	return Vector2i(maxi(roundi(w), 64), maxi(roundi(h), 64))


func _refresh() -> void:
	var mode := String(AppState.get_setting("chat_hud"))
	var on := mode == "on" or (mode == "auto" and not room_shows_chat())
	_win.set_flat_on(on)
	var px := _box_px()
	_win.set_pixel_size(px)
	var s := get_viewport().get_visible_rect().size
	var k := s.y / 1080.0        # 1080p pixels -> this picture's pixels
	_rect.size = Vector2(px) * k
	var m := MARGIN * k
	var corner := String(AppState.get_setting("chat_hud_corner"))
	var x := m if corner.ends_with("left") else s.x - _rect.size.x - m
	var y := m if corner.begins_with("top") else s.y - _rect.size.y - m
	_rect.position = Vector2(x, y)
	_rect.visible = _win.is_shown()
	visible = on
