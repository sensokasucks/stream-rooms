extends VideoStreamPlayback
var alpha: bool = false
var _t: float = 0.0
var _playing: bool = false
var _tex: ImageTexture
var _img: Image
func _play() -> void:
	_playing = true
	_img = Image.create(640, 360, false, Image.FORMAT_RGBA8)
	_draw()
	_tex = ImageTexture.create_from_image(_img)
func _stop() -> void:
	_playing = false
func _is_playing() -> bool:
	return _playing
func _get_texture() -> Texture2D:
	return _tex
func _update(delta: float) -> void:
	_t += delta
	_draw()
	if _tex:
		_tex.update(_img)
func _get_channels() -> int:
	return 2
func _get_mix_rate() -> int:
	return 48000
func _draw() -> void:
	var bg := Color(0, 0, 0, 0) if alpha else Color(0.9, 0.1, 0.5).lerp(Color(0.1, 0.4, 0.9), 0.5 + 0.5 * sin(_t * 2.0))
	_img.fill(bg)
	var x := int(320 + 200 * sin(_t * 3.0))
	_img.fill_rect(Rect2i(x - 60, 120, 120, 120), Color(1, 0.85, 0.2, 1))
