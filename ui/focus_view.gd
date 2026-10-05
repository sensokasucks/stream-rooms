extends CanvasLayer
## "Screen focus" view: the video flat and full-frame, letterboxed, so viewers can
## read text and details. Fades in/out on EventBus.focus_view_changed.

@export var fade_time: float = 0.25

var _root: Control
var _picture: TextureRect
var _no_signal: Label
var _tween: Tween
var _curtain: ColorRect
var _curtain_text: Label


func _ready() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.modulate.a = 0.0
	_root.visible = false
	add_child(_root)
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bg)
	_picture = TextureRect.new()
	_picture.set_anchors_preset(Control.PRESET_FULL_RECT)
	_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_picture)
	_no_signal = Label.new()
	_no_signal.text = "No signal"
	_no_signal.set_anchors_preset(Control.PRESET_CENTER)
	_no_signal.add_theme_font_size_override("font_size", 28)
	_no_signal.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	_root.add_child(_no_signal)

	# while the stage curtain is closed, focus view shows the curtain, not the picture
	_curtain = ColorRect.new()
	_curtain.set_anchors_preset(Control.PRESET_FULL_RECT)
	_curtain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_curtain.visible = false
	_root.add_child(_curtain)
	_curtain_text = Label.new()
	_curtain_text.set_anchors_preset(Control.PRESET_FULL_RECT)
	_curtain_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_curtain_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_curtain_text.add_theme_font_size_override("font_size", 56)
	_curtain_text.add_theme_color_override("font_color", Color(1.0, 0.86, 0.5))
	_curtain.add_child(_curtain_text)

	EventBus.focus_view_changed.connect(_on_focus_view_changed)
	EventBus.screen_texture_changed.connect(_on_texture_changed)
	EventBus.curtain_covering_changed.connect(_on_curtain)
	EventBus.setting_changed.connect(func(k: String, _v: Variant) -> void:
		if k in ["curtain_sign", "curtain_color"]:
			_on_curtain(AppState.is_curtain_covering()))


func _on_curtain(covering: bool) -> void:
	_curtain.visible = covering
	_curtain.color = (AppState.get_setting("curtain_color") as Color).darkened(0.35)
	_curtain_text.text = String(AppState.get_setting("curtain_sign")).strip_edges()


func _on_texture_changed(tex: Texture2D) -> void:
	_picture.texture = tex
	_no_signal.visible = tex == null


func _on_focus_view_changed(on: bool) -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_root.visible = true
	_tween = create_tween()
	_tween.tween_property(_root, "modulate:a", 1.0 if on else 0.0, fade_time)
	if not on:
		_tween.tween_callback(func() -> void: _root.visible = false)
