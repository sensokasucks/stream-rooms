class_name PeoplePicker
extends Node
## Click on people in the room: Shift + left click (or P, then a left click) on a chatter's
## silhouette, a presenter or the big screen opens a small menu in its own window (a native
## popup, so an OBS Window Capture of the room never shows it):
##   Throw ▸ a few reactions at them (through Reactions, so a co-stream plays it on every PC),
##   Highlight / glow (the same seat glow as Stream Core's Highlighted message), Show their last
##   message (on the panel's message line), Seat ▸ reserve / free / move to the front row,
##   Read aloud ▸ block them in Stream Core's read-aloud, and Copy name.
## Plain left clicks do nothing, so moving the camera (right drag) never fires it by accident.
## Made by main.gd, which hands it the camera and each new room (set_room). What's under the
## mouse comes from the room's ReactionLayer (pick_at).

## Emitted when something was picked (and its menu opened): ReactionLayer.pick_at's result. For tests.
signal picked(info: Dictionary)

## The Throw ▸ entries: [effect id, label, params]. Each is a ReactionLayer effect that takes a target.
const THROWS: Array = [
	["throw", "🍅 Tomato", {"object": "🍅"}],
	["confetti", "🎉 Confetti", {}],
	["spotlight", "🔦 Spotlight", {}],
	["fall_down", "🎈 Balloons", {"object": "🎈"}],
	["highfive", "✋ High five", {}],
]
## Menu item ids (THROWS use THROW_ID + index).
const THROW_ID: int = 100
const ID_GLOW: int = 10
const ID_SAID: int = 11
const ID_RESERVE: int = 20
const ID_FRONT: int = 21
const ID_BLOCK_STREAM: int = 30
const ID_BLOCK_DAY: int = 31
const ID_BLOCK_FOREVER: int = 32
const ID_COPY: int = 40

var camera: Camera3D
var _room: Room
var _armed: bool = false               # P was pressed: the next left click picks
var _menu: PopupMenu
var _info: Dictionary = {}             # what the open menu is about (pick_at's result)
var _glow_name: String = ""            # whose seat glows from this menu ("" = nobody)


## main.gd: a new room is ready.
func set_room(room: Room) -> void:
	_room = room


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and key.keycode == KEY_P and not key.ctrl_pressed and not key.alt_pressed:
		_armed = true
		EventBus.status_message.emit("Click someone in the room (or the big screen) for their menu.", false)
		get_viewport().set_input_as_handled()
		return
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if not (mb.shift_pressed or _armed):
		return
	_armed = false
	if not pick(mb.position).is_empty():
		get_viewport().set_input_as_handled()


## What's at a point of the room's window, and opens its menu. Returns {} for nothing.
func pick(at: Vector2) -> Dictionary:
	if _room == null or camera == null or not is_instance_valid(_room):
		return {}
	var layer := _room.find_child("Reactions", true, false) as ReactionLayer
	if layer == null:
		return {}
	var info := layer.pick_at(camera, at)
	if String(info.get("kind", "")) == "":
		return {}
	_open_menu(info, at)
	picked.emit(info)
	return info


func _open_menu(info: Dictionary, at: Vector2) -> void:
	_info = info
	if _menu:
		_menu.queue_free()
	_menu = PopupMenu.new()
	_menu.force_native = true            # its own OS window: never in the room's capture
	add_child(_menu)
	_menu.add_item(String(info["name"]))
	_menu.set_item_disabled(0, true)
	_menu.add_separator()
	var throws := PopupMenu.new()
	throws.force_native = true
	for i in THROWS.size():
		throws.add_item(String(THROWS[i][1]), THROW_ID + i)
	throws.id_pressed.connect(_on_item)
	_menu.add_submenu_node_item("Throw", throws)
	var user := String(info["kind"]) == "user"
	if user:
		_menu.add_item("Stop the glow" if _glow_name == String(info["name"]) else "Highlight / glow", ID_GLOW)
		_menu.add_item("Show their last message", ID_SAID)
		var seat := PopupMenu.new()
		seat.force_native = true
		var reserved := not AudienceManager.get_reservation(int(info["slot"])).is_empty()
		seat.add_item("Free this reserved seat" if reserved else "Reserve this seat for them", ID_RESERVE)
		seat.add_item("Move to the front row", ID_FRONT)
		seat.set_item_disabled(1, AudienceManager.is_mirror())     # (the host does the seating)
		seat.id_pressed.connect(_on_item)
		_menu.add_submenu_node_item("Seat", seat)
		var tts := PopupMenu.new()
		tts.force_native = true
		tts.add_item("Don't read them aloud this stream", ID_BLOCK_STREAM)
		tts.add_item("... for 24 hours", ID_BLOCK_DAY)
		tts.add_item("... for good", ID_BLOCK_FOREVER)
		tts.id_pressed.connect(_on_item)
		_menu.add_submenu_node_item("Read aloud", tts)
	_menu.add_item("Copy name", ID_COPY)
	_menu.id_pressed.connect(_on_item)
	_menu.position = DisplayServer.window_get_position() + Vector2i(at)
	_menu.popup()


## A menu item (also callable from tests with the ids above).
func _on_item(id: int) -> void:
	var who := String(_info.get("name", ""))
	if id >= THROW_ID and id < THROW_ID + THROWS.size():
		var t: Array = THROWS[id - THROW_ID]
		Reactions.play_from_menu(String(t[0]), _info.get("target", {}), t[2] as Dictionary)
		return
	match id:
		ID_GLOW:
			if _glow_name == who:
				_glow_name = ""
				EventBus.chat_highlight_changed.emit({})
			else:
				_glow_name = who
				EventBus.chat_highlight_changed.emit({"platform": "", "user_id": "", "names": PackedStringArray([who.to_lower()])})
		ID_SAID:
			var said := String(AudienceManager.get_seat_member(int(_info.get("slot", -1))).get("said", ""))
			EventBus.status_message.emit("%s said: %s" % [who, SafeText.clean(said)] if said != "" else "%s hasn't said anything yet." % who, false)
		ID_RESERVE:
			var slot := int(_info.get("slot", -1))
			var on := AudienceManager.get_reservation(slot).is_empty()
			if AudienceManager.is_mirror():
				NetSession.ask_reserve(slot, on)
			elif on and AudienceManager.reserve_seat(slot) != "":
				EventBus.status_message.emit("Seat reserved for %s." % who, false)
			elif not on and AudienceManager.unreserve_seat(slot) != "":
				EventBus.status_message.emit("%s's seat is free again." % who, false)
		ID_FRONT:
			if AudienceManager.move_to_row(int(_info.get("slot", -1)), "front") < 0:
				EventBus.status_message.emit("No free seat nearer the front for %s." % who, false)
		ID_BLOCK_STREAM, ID_BLOCK_DAY, ID_BLOCK_FOREVER:
			var span := {ID_BLOCK_STREAM: "stream", ID_BLOCK_DAY: "day", ID_BLOCK_FOREVER: "forever"}[id] as String
			var m := AudienceManager.get_seat_member(int(_info.get("slot", -1)))
			# Stream Core keeps the list (Setup > Read aloud > Blocked); see its tts_block handler
			ChatFeed.send_message({"type": "tts_block", "data": {"platform": String(m.get("platform", "")), "name": who, "for": span}})
			EventBus.status_message.emit("%s won't be read aloud (%s)." % [who, {"stream": "this stream", "day": "24 hours", "forever": "for good"}[span]], false)
		ID_COPY:
			DisplayServer.clipboard_set(who)
			EventBus.status_message.emit("Copied %s." % who, false)
