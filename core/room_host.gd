class_name RoomHost
extends Node3D
## Loads and swaps rooms. Listens for EventBus.room_requested, loads the room
## scene on a background thread, fades to black, swaps, attaches the screen
## lights / webcam frame, applies the room's environment and audio, fades back in.

signal room_ready(room: Room, info: RoomInfo)

@export var screen_feed: ScreenFeed
@export var world_environment: WorldEnvironment
@export var fade_rect: ColorRect
@export var fade_time: float = 0.35
## Extra time black after the swap, so GI can settle before fading in.
@export var settle_time: float = 0.25

var _room: Room
var _room_id: String = ""
var _loading_id: String = ""
var _queued_id: String = ""
var _faded_out: bool = false
var _default_env: Environment
var _room_env: Environment         # the room's own Environment (before graphics quality)
var _gfx_syncing: bool = false


func _ready() -> void:
	_default_env = world_environment.environment
	fade_rect.color = Color(0, 0, 0, 1)
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	EventBus.room_requested.connect(load_room)
	EventBus.setting_changed.connect(_on_setting_changed)
	GraphicsQuality.apply_fps()
	GraphicsQuality.apply_viewport(get_viewport())


func _process(_delta: float) -> void:
	if _loading_id == "" or not _faded_out:
		return
	var info := RoomCatalog.get_info(_loading_id)
	match ResourceLoader.load_threaded_get_status(info.scene_path):
		ResourceLoader.THREAD_LOAD_LOADED:
			var packed := ResourceLoader.load_threaded_get(info.scene_path) as PackedScene
			_swap_to(packed, info)
		ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			EventBus.status_message.emit("Couldn't load room '%s'." % info.display_name, true)
			_loading_id = ""
			_fade_in()


# ── Public API ───────────────────────────────────────────────
func load_room(room_id: String) -> void:
	if room_id == _room_id and _loading_id == "":
		return
	if _loading_id != "":
		_queued_id = room_id
		return
	var info := RoomCatalog.get_info(room_id)
	if info == null:
		return
	if ResourceLoader.load_threaded_request(info.scene_path) != OK:
		EventBus.status_message.emit("Couldn't start loading room '%s'." % info.display_name, true)
		return
	_loading_id = room_id
	_faded_out = false
	var tw := create_tween()
	tw.tween_property(fade_rect, "color:a", 1.0, fade_time if _room else 0.0)
	tw.tween_callback(func() -> void: _faded_out = true)


func get_current_room() -> Room:
	return _room


## The room's own Environment, before the graphics quality switches.
func get_room_environment() -> Environment:
	return _room_env if _room_env else _default_env


func _on_setting_changed(key: String, _value: Variant) -> void:
	if key == "fps_cap" or key == "vsync":
		GraphicsQuality.apply_fps()
		return
	if key != "graphics_quality" and not GraphicsQuality.KEYS.has(key):
		return
	if not _gfx_syncing:
		_gfx_syncing = true
		if key == "graphics_quality":
			GraphicsQuality.set_level(String(AppState.get_setting(key)))   # a preset writes its switches
		else:
			AppState.set_setting("graphics_quality", GraphicsQuality.detect_level())   # a switch moved
		_gfx_syncing = false
	_apply_graphics()


func _apply_graphics() -> void:
	world_environment.environment = GraphicsQuality.environment_for(get_room_environment())
	GraphicsQuality.apply_viewport(get_viewport())


# ── Private ──────────────────────────────────────────────────
func _swap_to(packed: PackedScene, info: RoomInfo) -> void:
	_loading_id = ""
	if _room:
		_room.queue_free()
		_room = null
	var inst := packed.instantiate()
	if not inst is Room:
		push_error("Room scene %s must use rooms/room.gd on its root." % info.scene_path)
		inst.queue_free()
		_fade_in()
		return
	_room = inst as Room
	_room_id = info.id
	add_child(_room)

	_room_env = info.environment if info.environment else _default_env
	world_environment.environment = GraphicsQuality.environment_for(_room_env)
	AudioManager.apply_room(info)

	var screen := _room.find_screen()
	var curtain_front := 0.0
	if screen:
		var lights := ScreenLights.new()
		lights.name = "ScreenLights"
		_room.add_child(lights)
		lights.setup(screen, info, screen_feed.get_texture(), _room.get_projector_marker(), _room.get_mirror_screens())
		# stage curtain in front of the screen (B / Shift+B, Room tab)
		var curtain := StageCurtain.new()
		curtain.name = "StageCurtain"
		_room.add_child(curtain)
		curtain.setup(_room, screen)
		# how far in front of the screen the curtain hangs (the side chat windows go in front of it)
		var sbox := screen.global_transform * screen.get_aabb()
		curtain_front = absf((curtain.global_position - sbox.get_center()).dot(curtain.global_basis.z.normalized()))
	else:
		EventBus.status_message.emit("Room '%s' has no TVScreen mesh." % info.display_name, true)

	var marker := _room.get_webcam_marker()
	AppState.set_room_has_webcam_frame(marker != null)
	if marker:
		var cam := WebcamDisplay.new()
		cam.name = "WebcamDisplay"
		marker.add_child(cam)

	var chat_marker := _room.get_chat_screen_marker()
	if chat_marker:
		var chat := ChatScreen.new()
		chat.name = "ChatScreen"
		chat.setup(_room.chat_screen_size, "chat_screen")
		chat_marker.add_child(chat)

	var reply_marker := _room.get_reply_screen_marker()
	AppState.set_room_has_reply_screen(reply_marker != null)
	if reply_marker:
		var replies := ChatScreen.new()
		replies.name = "ReplyScreen"
		var raise := maxf(_room.reply_screen_raise, 0.0)
		replies.setup(_room.reply_screen_size + Vector2(0.0, raise), "reply_screen")
		reply_marker.add_child(replies)
		replies.position.y += raise     # taller upward: the bottom edge stays put

	# tall chat windows either side of the main screen (Chat tab: what each one shows)
	if screen:
		var cams := _room.get_camera_markers()
		var side := SideChats.new()
		side.name = "SideChats"
		_room.add_child(side)
		side.setup(screen, cams[0].global_position if not cams.is_empty() else screen.global_position + Vector3.BACK * 8.0,
			_room.side_chat_extra_gap, _room.side_chat_height_scale,
			maxf(_room.side_chat_forward, curtain_front + SideChats.CURTAIN_CLEARANCE))

	var presenters := _room.get_presenter_setups()
	var presenter_nodes: Dictionary = {}
	if presenters.is_empty():
		EventBus.room_presenters_changed.emit(0)
	else:
		var stage := PresenterStage.new()
		stage.name = "Presenters"
		_room.add_child(stage)
		stage.setup(presenters, _room.presenter_size)
		presenter_nodes = stage.get_presenter_map()

	# the chat audience: main seats, the room's crowd seats, and a spot on each podium for
	# the presenter's linked chat name
	var seats := _room.get_audience_seats()
	var crowd_info := _room.get_crowd_seat_info()
	var crowd: Array[Transform3D] = []
	for e in crowd_info:
		crowd.append(e["xf"])
	var audience: AudienceView = null
	if seats.is_empty() and crowd.is_empty() and presenters.is_empty():
		AudienceManager.set_slot_kinds(PackedByteArray(), {})
		AudienceManager.set_capacity(0)
	else:
		audience = AudienceView.new()
		audience.name = "Audience"
		_room.add_child(audience)
		audience.setup(seats, _stage_point(screen), crowd, presenters, _room.presenter_size, presenter_nodes, crowd_info)

	# chat reactions (🍅 ...) play here; it finds its targets in the room
	var reactions := ReactionLayer.new()
	reactions.name = "Reactions"
	_room.add_child(reactions)
	reactions.setup(_room, audience, presenters, _room.presenter_size)

	var labels := PackedStringArray()
	for m in _room.get_camera_markers():
		labels.append(_room.get_camera_label(m))
	room_ready.emit(_room, info)
	EventBus.camera_presets_changed.emit(labels)
	EventBus.room_controls_changed.emit(_room.get_controls() + _screen_controls(info))
	EventBus.room_changed.emit(info.id)

	get_tree().create_timer(settle_time).timeout.connect(_fade_in)


## Middle of the main screen (global), or null if the room has none.
func _stage_point(screen: MeshInstance3D) -> Variant:
	if screen == null or screen.mesh == null:
		return null
	return screen.global_transform * screen.mesh.get_aabb().get_center()


## Controls for the screen looks this room uses (see RoomInfo).
func _screen_controls(info: RoomInfo) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if info.screen_film_amount > 0.0:
		out.append({"heading": "Film"})
		out.append({"key": "film_look", "label": "Film look", "min": 0.0, "max": 2.0, "step": 0.01,
			"format": "%d%%", "scale": 100.0,
			"tooltip": "How much old-film dirt and fading the picture gets. 0% = clean, 100% = the room's look, 200% = extra dirty."})
	if info.screen_hologram:
		out.append({"heading": "Hologram screen"})
		out.append({"key": "holo_amount", "label": "Hologram", "min": 0.0, "max": 1.0, "step": 0.01, "format": "%d%%", "scale": 100.0})
		out.append({"key": "holo_transparency", "label": "Transparency", "min": 0.0, "max": 1.0, "step": 0.01, "format": "%d%%", "scale": 100.0})
		out.append({"key": "holo_glitch", "label": "Glitch", "min": 0.0, "max": 1.0, "step": 0.01, "format": "%d%%", "scale": 100.0})
		out.append({"key": "holo_lines", "label": "Scan lines", "min": 10.0, "max": 400.0, "step": 1.0, "format": "%d"})
		out.append({"key": "holo_speed", "label": "Scroll speed", "min": 0.0, "max": 2.0, "step": 0.01, "format": "%.2f"})
		out.append({"key": "holo_noise", "label": "Noise", "min": 0.0, "max": 1.0, "step": 0.01, "format": "%d%%", "scale": 100.0})
		out.append({"key": "holo_color1", "label": "Line colour 1", "type": "color"})
		out.append({"key": "holo_color2", "label": "Line colour 2", "type": "color"})
	return out


func _fade_in() -> void:
	var tw := create_tween()
	tw.tween_property(fade_rect, "color:a", 0.0, fade_time)
	if _queued_id != "":
		var next := _queued_id
		_queued_id = ""
		tw.tween_callback(func() -> void: load_room(next))
