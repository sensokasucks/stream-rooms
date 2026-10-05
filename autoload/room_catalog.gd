extends Node
## RoomCatalog: static list of rooms, discovered from res://rooms/<folder>/room_info.tres.
## Read-only at runtime. Add a room by adding a folder - no code changes needed.

const ROOMS_DIR: String = "res://rooms"
const INFO_FILE: String = "room_info.tres"

var _rooms: Dictionary = {}          # id -> RoomInfo
var _order: PackedStringArray = []


func _ready() -> void:
	_scan()


func get_ids() -> PackedStringArray:
	return _order


func get_info(room_id: String) -> RoomInfo:
	return _rooms.get(room_id) as RoomInfo


func _scan() -> void:
	var dir := DirAccess.open(ROOMS_DIR)
	if dir == null:
		push_error("No rooms folder at %s" % ROOMS_DIR)
		return
	var found: Array[RoomInfo] = []
	for sub in dir.get_directories():
		var path := ROOMS_DIR.path_join(sub).path_join(INFO_FILE)
		# Exported builds may only contain the .remap entry; ResourceLoader handles both.
		if not ResourceLoader.exists(path):
			continue
		var info := load(path) as RoomInfo
		if info == null or info.id == "":
			push_warning("Skipping %s: not a RoomInfo with an id" % path)
			continue
		found.append(info)
	found.sort_custom(func(a: RoomInfo, b: RoomInfo) -> bool:
		return a.sort_order < b.sort_order if a.sort_order != b.sort_order else a.display_name < b.display_name)
	for info in found:
		_rooms[info.id] = info
		_order.append(info.id)
