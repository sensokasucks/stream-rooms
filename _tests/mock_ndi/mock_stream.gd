extends VideoStream
## Stands in for VideoStreamNDI: a moving test picture (optionally with a transparent background).
var name: String = ""
var alpha: bool = false
func _instantiate_playback() -> VideoStreamPlayback:
	var p = load("res://_tests/mock_ndi/mock_playback.gd").new()
	p.alpha = alpha
	return p
