extends CanvasLayer
## Always-on overlays: status toasts, the "reacting" badge, and the webcam
## corner picture (used when the room has no WEBCAM_Frame or the in-room frame
## is turned off). Clean feed hides toasts and the badge but keeps the webcam.
## Status toasts only show when "messages_on_picture" is on: this is the window OBS captures, so
## by default messages go to the control panel's message line instead (ControlPanel).

@export var toast_time: float = 4.0
@export var pip_width: float = 360.0

var _toast: Label
var _toast_timer: float = 0.0
var _badge: PanelContainer
var _pip: TextureRect
var _webcam_texture: Texture2D


func _ready() -> void:
	_toast = Label.new()
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_toast.offset_top = -64
	_toast.offset_bottom = -24
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.add_theme_font_size_override("font_size", 18)
	_toast.add_theme_constant_override("outline_size", 6)
	_toast.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_toast.visible = false
	add_child(_toast)

	_badge = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.85, 0.35, 0.1, 0.92)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(10)
	_badge.add_theme_stylebox_override("panel", sb)
	var bl := Label.new()
	bl.text = "PAUSED - REACTING"
	bl.add_theme_font_size_override("font_size", 18)
	_badge.add_child(bl)
	_badge.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_badge.offset_left = -240
	_badge.offset_top = 16
	_badge.offset_right = -16
	_badge.visible = false
	add_child(_badge)

	_pip = TextureRect.new()
	_pip.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_pip.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_pip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pip.visible = false
	add_child(_pip)

	EventBus.status_message.connect(_on_status)
	EventBus.react_pause_changed.connect(func(_p: bool) -> void: _refresh())
	EventBus.clean_feed_changed.connect(func(_c: bool) -> void: _refresh())
	EventBus.webcam_texture_changed.connect(_on_webcam)
	EventBus.room_changed.connect(func(_id: String) -> void: _refresh())
	EventBus.setting_changed.connect(func(k: String, v: Variant) -> void:
		if k == "webcam_in_room": _refresh()
		elif k == "messages_on_picture" and not bool(v): _toast.visible = false)


func _process(delta: float) -> void:
	if _toast.visible:
		_toast_timer -= delta
		_toast.modulate.a = clampf(_toast_timer / 0.5, 0.0, 1.0)
		if _toast_timer <= 0.0:
			_toast.visible = false


func _on_status(text: String, is_error: bool) -> void:
	_toast.text = text
	_toast.add_theme_color_override("font_color", Color(1, 0.55, 0.5) if is_error else Color(0.92, 0.94, 1))
	_toast_timer = toast_time * (1.5 if is_error else 1.0)
	_toast.visible = bool(AppState.get_setting("messages_on_picture")) and not AppState.is_clean_feed()


func _on_webcam(tex: Texture2D) -> void:
	_webcam_texture = tex
	_pip.texture = tex
	if tex and tex.get_width() > 0:
		var h := pip_width * float(tex.get_height()) / float(tex.get_width())
		_pip.offset_left = -pip_width - 16
		_pip.offset_right = -16
		_pip.offset_top = -h - 16
		_pip.offset_bottom = -16
	_refresh()


func _refresh() -> void:
	var clean := AppState.is_clean_feed()
	_badge.visible = AppState.is_react_paused() and not clean
	var in_room := AppState.room_has_webcam_frame() and bool(AppState.get_setting("webcam_in_room"))
	_pip.visible = _webcam_texture != null and not in_room
	if clean:
		_toast.visible = false
