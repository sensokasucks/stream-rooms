extends Node
## Stands in for godot-ndi's NDIFinder in tests.
signal sources_changed
var sources: Array = []
func get_sources() -> Array:
	return sources
func set_sources(names: Array, alpha: bool = false) -> void:
	sources.clear()
	for n in names:
		var s = load("res://_tests/mock_ndi/mock_stream.gd").new()
		s.name = n
		s.alpha = alpha
		sources.append(s)
	sources_changed.emit()
