class_name SpoutReceiver
extends Node
## Spout input through the optional godot-spout extension (addons/godot-spout). Spout shares a
## picture between programs on this PC straight on the graphics card (VTube Studio, OBS with the
## Spout plugin, games, TouchDesigner...): no copying, no compression, transparency kept.
## Everything is looked up by name (ClassDB), so the game still runs without the extension.
## Publishes EventBus.spout_senders_changed(names, available); the list is checked every
## POLL_S seconds (a quick read of Spout's shared list).

const TEXTURE_CLASS: String = "SpoutTexture"
const POLL_S: float = 2.0

var _names: PackedStringArray = []
var _wait: float = 0.0


static func is_available() -> bool:
	return ClassDB.class_exists(TEXTURE_CLASS) and ClassDB.class_has_method(TEXTURE_CLASS, "get_sender_names")


func _ready() -> void:
	if not is_available():
		set_process(false)
		EventBus.spout_senders_changed.emit(_names, false)
		return
	refresh()
	EventBus.spout_senders_changed.emit(_names, true)


func _process(delta: float) -> void:
	_wait -= delta
	if _wait <= 0.0:
		refresh()


## Reads the sender list now; emits spout_senders_changed when it changed.
func refresh() -> void:
	_wait = POLL_S
	if not is_available():
		return
	var names := PackedStringArray(ClassDB.class_call_static(TEXTURE_CLASS, "get_sender_names"))
	names.sort()
	if names == _names:
		return
	_names = names
	EventBus.spout_senders_changed.emit(_names, true)


func get_sender_names() -> PackedStringArray:
	return _names


func has_sender(sender_name: String) -> bool:
	return sender_name != "" and _names.has(sender_name)


## A texture that keeps showing this sender's latest picture by itself (it updates just before
## each frame is drawn), or null without the extension. Its size follows the sender's.
static func make_texture(sender_name: String) -> Texture2D:
	if not is_available():
		return null
	var tex := ClassDB.instantiate(TEXTURE_CLASS) as Texture2D
	if tex:
		tex.set("channel_name", sender_name)
	return tex
