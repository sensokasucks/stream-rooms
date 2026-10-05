class_name NdiReceiver
extends Node
## NDI input through the optional godot-ndi extension (addons/godot-ndi, needs the NDI Runtime).
## Finds NDI sources on the network and makes VideoStreamPlayers for them.
## Everything is looked up by name (ClassDB), so the game still runs, without NDI, when the
## extension or the runtime is missing.
## Publishes EventBus.ndi_sources_changed(names, available).

const FINDER_CLASS: String = "NDIFinder"
const STREAM_CLASS: String = "VideoStreamNDI"

## Tests only: a script standing in for NDIFinder (get_sources(), sources_changed signal).
static var mock_finder: GDScript = null

var _finder: Node
var _names: PackedStringArray = []


static func is_available() -> bool:
	return mock_finder != null or (ClassDB.class_exists(FINDER_CLASS) and ClassDB.class_exists(STREAM_CLASS))


func _ready() -> void:
	if not is_available():
		EventBus.ndi_sources_changed.emit(_names, false)
		return
	_finder = mock_finder.new() as Node if mock_finder else ClassDB.instantiate(FINDER_CLASS) as Node
	if _finder == null:
		EventBus.ndi_sources_changed.emit(_names, false)
		return
	_finder.name = "NDIFinder"
	add_child(_finder)
	_finder.connect("sources_changed", _on_sources_changed)
	EventBus.ndi_sources_changed.emit(_names, true)


func get_source_names() -> PackedStringArray:
	return _names


## True with the patched plugin (addons/godot-ndi/STREAM_ROOMS_PATCH.md): the game can pull the
## NDI sound itself at the sound card's pace instead of the plugin pushing it once per frame.
static func supports_pull_audio() -> bool:
	if mock_finder != null:
		return false
	return ClassDB.class_exists(STREAM_CLASS) and ClassDB.class_has_method(STREAM_CLASS, "pull_audio")


func has_source(source_name: String) -> bool:
	return source_name != "" and _names.has(source_name)


## A new, hidden player for this source (not playing yet), or null if the source isn't
## on the network. The player is added under `parent`; it sends its sound to `bus`.
## external_audio (patched plugin only): the player plays no sound; pull it with
## player.stream.pull_audio(frames, mix_rate) instead.
## The finder's own stream objects are used because they start much faster.
func make_player(source_name: String, parent: Node, bus: StringName, external_audio: bool = false) -> VideoStreamPlayer:
	var stream := _find_stream(source_name)
	if stream == null:
		return null
	if supports_pull_audio():
		stream.set("external_audio", external_audio)
	var p := VideoStreamPlayer.new()
	p.name = "NDI_" + source_name.validate_node_name()
	p.self_modulate = Color(1, 1, 1, 0)     # only its texture is used
	p.size = Vector2(2, 2)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.expand = true
	p.bus = bus
	p.stream = stream
	parent.add_child(p)
	return p


func _find_stream(source_name: String) -> VideoStream:
	if _finder == null or source_name == "":
		return null
	for s: Variant in _finder.call("get_sources"):
		if s is VideoStream and _stream_name(s) == source_name:
			return s as VideoStream
	return null


## VideoStreamNDI's "name" property is the NDI source name.
static func _stream_name(s: Variant) -> String:
	var n: Variant = (s as Object).get("name")
	if n == null:
		n = (s as Object).call("get_name")
	return String(n)


func _on_sources_changed() -> void:
	var names := PackedStringArray()
	for s: Variant in _finder.call("get_sources"):
		if s is Object:
			names.append(_stream_name(s))
	names.sort()
	if names == _names:
		return
	_names = names
	EventBus.ndi_sources_changed.emit(_names, true)
