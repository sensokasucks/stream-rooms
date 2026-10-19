extends Node
## Stands in for godot-ndi's NDIFinder in tests.
## test_ndi.gd puts this script in NdiReceiver.mock_finder, so the app finds these sources.
signal sources_changed
var sources: Array = []
func get_sources() -> Array:
	return sources
## Replaces the source list with one mock stream per name, as if they appeared on the network.
func set_sources(names: Array, alpha: bool = false) -> void:
	sources.clear()
	for n in names:
		var s = load("res://_tests/mock_ndi/mock_stream.gd").new()
		s.name = n
		s.alpha = alpha
		sources.append(s)
	sources_changed.emit()
