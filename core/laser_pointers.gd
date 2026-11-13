class_name LaserPointers
extends Node3D
## Laser pointers: hold L in the room window and a coloured dot appears where the mouse points in
## the room (on a wall, the big screen, the floor), with a thin beam from your camera or from your
## podium's avatar. In a co-stream everyone has their own, and everyone sees everyone's.
##
## Each person sets their own in the Co-stream tab > Laser pointer (Stream Core shows the same
## settings): laser_color, laser_beam (beam or dot only), laser_from ("camera" | "podium"),
## laser_podium (which podium, 0 = mine) and laser_toggle (L turns it on and off instead of holding).
##
## main.gd adds it at start-up and hands it each new room (set_room), so "podium" can find the
## presenters. This PC's laser is drawn straight away; NetSession.send_laser sends it to the others
## (at most every SEND_GAP while it moves, a keep-alive every KEEP_ALIVE_S while it's still, and once
## when it goes off). The others' arrive as EventBus.net_laser_changed and glide toward their latest
## spot like the camera markers (core/net_markers.gd). EventBus.net_peer_left removes one, and one
## that hears nothing for STALE_S goes away by itself (a lost "off").
## Work only happens while a laser is on: _process switches itself off when none is.

## Seconds between two updates sent while this PC's laser moves (20 a second).
const SEND_GAP: float = 0.05
## Seconds between updates while it's on but still, so the others know it's still on.
const KEEP_ALIVE_S: float = 0.5
## Someone else's laser with no news for this long (seconds) is hidden. Several keep-alives long,
## so a busy PC or a slow connection doesn't make a still laser blink.
const STALE_S: float = 3.0
## How far the aiming ray looks for a wall, in metres. Nothing hit = the dot floats this far out.
const RAY_M: float = 60.0
## The beam starts here when it comes from your camera: metres right, down and forward of the
## camera, like a pointer held in the right hand (a beam straight from the lens would be a point).
const CAMERA_OFFSET := Vector3(0.14, -0.16, -0.35)
## When it comes from a podium: the spot on the avatar picture, as fractions of its width and
## height from its centre (+x = the picture's right), plus metres in front of it.
const PODIUM_HAND := Vector3(0.3, 0.05, 0.06)
## Beam thickness (radius, metres) at the dot end and at the start (thinner, or a beam starting
## right beside your own camera looks like a thick rod), and how see-through it is (0..1).
const BEAM_RADIUS: float = 0.005
const BEAM_START_RADIUS: float = 0.0015
const BEAM_ALPHA: float = 0.6
## The dot: radius in metres, how far it sits out from the surface it hits (so it never sinks into
## the wall), how much brighter than the colour its core is (so the room's glow picks it up), and
## its small light on the surface around it (energy and range in metres).
const DOT_RADIUS: float = 0.04
const DOT_LIFT: float = 0.015
const DOT_BRIGHT: float = 2.5
const DOT_LIGHT_ENERGY: float = 1.2
const DOT_LIGHT_RANGE: float = 0.5
## Remote lasers glide this fast toward their latest spot (fraction per second, like NetMarkers).
const GLIDE: float = 18.0

## Tests: aim at this point of the window instead of the mouse (a Vector2), or null for the mouse.
var aim_override: Variant = null

var _room: Room
var _on: bool = false                 # this PC's laser is on (L held, or toggled on)
var _local: Dictionary = {}           # this PC's laser: {node, from, to} (see _make)
var _remote: Dictionary = {}          # peer id -> {node, from, to, target_from, target_to, seen (ms)}
var _send_wait: float = 0.0           # seconds until the next update may go out
var _alive_wait: float = 0.0          # seconds until the next keep-alive
var _last_sent_from: Vector3
var _last_sent_to: Vector3
var _settings_dirty: bool = false     # colour / beam changed while on: send it now


func _ready() -> void:
	name = "LaserPointers"
	EventBus.net_laser_changed.connect(_on_net_laser)
	EventBus.net_peer_left.connect(_drop_remote)
	EventBus.net_state_changed.connect(func(info: Dictionary) -> void:
		# the session ended (or never started): nobody else's laser stays behind
		if String(info.get("role", "off")) == "off":
			for id: int in _remote.keys():
				_drop_remote(id))
	EventBus.setting_changed.connect(_on_setting_changed)
	set_process(false)


## main.gd: a new room is ready (its Presenters node is where the podium lasers start).
func set_room(room: Room) -> void:
	_room = room


# ── Public API ───────────────────────────────────────────────
## Turns this PC's laser on or off (L does this; tests and the toggle mode call it too).
func set_on(on: bool) -> void:
	if on == _on:
		return
	_on = on
	if on:
		if _local.is_empty():
			_local = _make()
		_send_wait = 0.0
		_alive_wait = 0.0
		_update_local()
		set_process(true)
	else:
		if not _local.is_empty():
			(_local["node"] as Node3D).visible = false
		NetSession.send_laser(false, Vector3.ZERO, Vector3.ZERO, Color.BLACK, false)


func is_on() -> bool:
	return _on


## A laser for tests: peer id 0 = this PC's. {} when there's none. Otherwise {visible, from, to,
## color, beam}: positions are where it's drawn now (a remote one may still be gliding).
func get_laser(peer_id: int = 0) -> Dictionary:
	var l: Dictionary = _local if peer_id == 0 else _remote.get(peer_id, {})
	if l.is_empty():
		return {}
	var node := l["node"] as Node3D
	return {"visible": node.visible, "from": l["from"], "to": l["to"], "color": l["color"],
		"beam": (node.get_node("Beam") as Node3D).visible}


## Number of other people's lasers showing now. Used by tests.
func remote_count() -> int:
	var n := 0
	for id: int in _remote:
		if (_remote[id]["node"] as Node3D).visible:
			n += 1
	return n


# ── Input ────────────────────────────────────────────────────
## L (without Ctrl / Alt): hold for the laser, or press to turn it on and off with laser_toggle.
## _unhandled_input, so typing an L in a text box never fires it.
func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or key.keycode != KEY_L or key.echo or key.ctrl_pressed or key.alt_pressed:
		return
	if bool(AppState.get_setting("laser_toggle")):
		if key.pressed:
			set_on(not _on)
	else:
		set_on(key.pressed)
	get_viewport().set_input_as_handled()


## Clicking away to another window while holding L never sends the key-up, so a held laser goes off.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and _on and not bool(AppState.get_setting("laser_toggle")):
		set_on(false)


# ── Every frame (only while a laser is on) ───────────────────
func _process(delta: float) -> void:
	if _on:
		_update_local()
		_send_wait -= delta
		_alive_wait -= delta
		var moved := not (_local["from"] as Vector3).is_equal_approx(_last_sent_from) or not (_local["to"] as Vector3).is_equal_approx(_last_sent_to)
		if _send_wait <= 0.0 and (moved or _settings_dirty or _alive_wait <= 0.0):
			_send_wait = SEND_GAP
			_alive_wait = KEEP_ALIVE_S
			_settings_dirty = false
			_last_sent_from = _local["from"]
			_last_sent_to = _local["to"]
			NetSession.send_laser(true, _local["from"], _local["to"], AppState.get_setting("laser_color"), bool(AppState.get_setting("laser_beam")))
	var now := Time.get_ticks_msec()
	var t := clampf(delta * GLIDE, 0.0, 1.0)
	var any_remote := false
	for id: int in _remote:
		var r: Dictionary = _remote[id]
		var node := r["node"] as Node3D
		if not node.visible:
			continue
		if now - int(r["seen"]) > int(STALE_S * 1000.0):
			node.visible = false
			continue
		any_remote = true
		r["from"] = (r["from"] as Vector3).lerp(r["target_from"], t)
		r["to"] = (r["to"] as Vector3).lerp(r["target_to"], t)
		_place(r)
	set_process(_on or any_remote)


## Works out where this PC's laser starts and where it points, and draws it there.
func _update_local() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var at: Vector2 = aim_override if aim_override is Vector2 else get_viewport().get_mouse_position()
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not aim_override is Vector2:
		at = get_viewport().get_visible_rect().size * 0.5     # (free look: the middle of the view)
	var ray_from := cam.project_ray_origin(at)
	var dir := cam.project_ray_normal(at)
	var to := ray_from + dir * RAY_M
	var q := PhysicsRayQueryParameters3D.create(ray_from, to, CameraRig.WALL_LAYER)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		to = (hit["position"] as Vector3) + (hit["normal"] as Vector3) * DOT_LIFT
	_local["from"] = _origin(cam)
	_local["to"] = to
	_local["color"] = AppState.get_setting("laser_color")
	_style(_local, _local["color"], bool(AppState.get_setting("laser_beam")))
	(_local["node"] as Node3D).visible = true
	_place(_local)


## Where this PC's beam starts: the podium's avatar for laser_from = "podium" (when there is one on
## set), otherwise just beside the camera.
func _origin(cam: Camera3D) -> Vector3:
	if String(AppState.get_setting("laser_from")) == "podium":
		var p := _my_presenter()
		if p != null:
			var pic := p.get_picture()
			var size := (pic.mesh as QuadMesh).size if pic.mesh is QuadMesh else Vector2.ONE
			return pic.global_transform * Vector3(size.x * PODIUM_HAND.x, size.y * PODIUM_HAND.y, PODIUM_HAND.z)
	return cam.global_transform * CAMERA_OFFSET


## The presenter this PC's laser comes from with laser_from = "podium", or null (no podiums in this
## room, or that podium is off set). laser_podium 1..4 picks one; 0 = mine: a guest's claimed
## podium, otherwise the first podium on set that no guest has claimed.
func _my_presenter() -> Presenter:
	if _room == null or not is_instance_valid(_room):
		return null
	var stage := _room.get_node_or_null("Presenters") as PresenterStage
	if stage == null:
		return null
	var n := int(AppState.get_setting("laser_podium"))
	if n == 0:
		if NetSession.get_role() == "guest":
			n = NetSession.my_podium()
		else:
			var owners: Dictionary = {}       # podium n -> guest's name (in a session)
			for e: Dictionary in NetSession.podium_list():
				owners[int(e["n"])] = String(e["owner"])
			for i in range(1, AppState.PRESENTER_COUNT + 1):
				if bool(AppState.get_setting(AppState.presenter_key(i, "on"))) and String(owners.get(i, "")) == "":
					n = i
					break
	var p := stage.get_presenter(n) if n > 0 else null
	return p if p != null and p.visible else null


# ── The others' lasers ───────────────────────────────────────
## EventBus.net_laser_changed: someone else's laser moved, changed or went off.
func _on_net_laser(peer_id: int, _peer_name: String, state: Dictionary) -> void:
	if not bool(state.get("on", false)):
		if _remote.has(peer_id):
			(_remote[peer_id]["node"] as Node3D).visible = false
		return
	var from: Vector3 = state["from"]
	var to: Vector3 = state["to"]
	if not _remote.has(peer_id):
		_remote[peer_id] = _make()
	var r: Dictionary = _remote[peer_id]
	var node := r["node"] as Node3D
	if not node.visible:
		# (turning on: jump straight to the spot instead of gliding in from the last one)
		r["from"] = from
		r["to"] = to
	r["target_from"] = from
	r["target_to"] = to
	r["seen"] = Time.get_ticks_msec()
	r["color"] = state["color"]
	_style(r, state["color"], bool(state["beam"]))
	node.visible = true
	_place(r)
	set_process(true)


## Someone left (EventBus.net_peer_left), or the session ended: their laser goes.
func _drop_remote(peer_id: int) -> void:
	if _remote.has(peer_id):
		(_remote[peer_id]["node"] as Node3D).queue_free()
		_remote.erase(peer_id)


func _on_setting_changed(key: String, _value: Variant) -> void:
	if key.begins_with("laser_") and _on:
		_settings_dirty = true        # (_process redraws and sends it on the next frame)


# ── Drawing ──────────────────────────────────────────────────
## Builds one laser (hidden): a beam (child "Beam", a thin see-through cylinder stretched from the
## start to the dot) and the dot (child "Dot", a bright little sphere with a small light).
## Returns the laser's record: {node, beam_mat, dot_mat, light, from, to, color, style}.
func _make() -> Dictionary:
	var root := Node3D.new()
	root.visible = false
	add_child(root)
	var beam_pivot := Node3D.new()
	beam_pivot.name = "Beam"
	root.add_child(beam_pivot)
	var beam := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = BEAM_RADIUS              # (top = the dot end once it's turned below)
	cyl.bottom_radius = BEAM_START_RADIUS
	cyl.height = 1.0
	cyl.radial_segments = 8
	cyl.rings = 1
	beam.mesh = cyl
	# the cylinder stands along +Y; lying along -Z from the pivot, scaled to the length in _place
	beam.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	beam.position = Vector3(0.0, 0.0, -0.5)
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var beam_mat := StandardMaterial3D.new()
	beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	beam.material_override = beam_mat
	beam_pivot.add_child(beam)
	var dot := MeshInstance3D.new()
	dot.name = "Dot"
	var sphere := SphereMesh.new()
	sphere.radius = DOT_RADIUS
	sphere.height = DOT_RADIUS * 2.0
	sphere.radial_segments = 12
	sphere.rings = 6
	dot.mesh = sphere
	dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var dot_mat := StandardMaterial3D.new()
	dot_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dot.material_override = dot_mat
	root.add_child(dot)
	var light := OmniLight3D.new()
	light.omni_range = DOT_LIGHT_RANGE
	light.light_energy = DOT_LIGHT_ENERGY
	light.shadow_enabled = false
	dot.add_child(light)
	return {"node": root, "beam_mat": beam_mat, "dot_mat": dot_mat, "light": light,
		"from": Vector3.ZERO, "to": Vector3.ZERO, "color": Color.RED, "style": ""}


## Colours a laser and shows or hides its beam. Cheap when nothing changed (the style is remembered).
func _style(l: Dictionary, color: Color, beam: bool) -> void:
	var style := "%s|%s" % [color.to_html(false), beam]
	if String(l["style"]) == style:
		return
	l["style"] = style
	(l["beam_mat"] as StandardMaterial3D).albedo_color = Color(color.r, color.g, color.b, BEAM_ALPHA)
	(l["dot_mat"] as StandardMaterial3D).albedo_color = Color(color.r * DOT_BRIGHT, color.g * DOT_BRIGHT, color.b * DOT_BRIGHT)
	(l["light"] as OmniLight3D).light_color = color
	((l["node"] as Node3D).get_node("Beam") as Node3D).visible = beam


## Puts a laser's beam between its "from" and "to" and the dot on "to".
func _place(l: Dictionary) -> void:
	var node := l["node"] as Node3D
	var from: Vector3 = l["from"]
	var to: Vector3 = l["to"]
	(node.get_node("Dot") as Node3D).global_position = to
	var pivot := node.get_node("Beam") as Node3D
	var length := from.distance_to(to)
	if length < 0.01:
		pivot.scale = Vector3(1.0, 1.0, 0.001)
		pivot.global_position = from
		return
	# (looking_at needs an up that isn't along the beam: straight up or down uses +Z instead)
	var dir := (to - from) / length
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.99 else Vector3.BACK
	pivot.global_transform = Transform3D(Basis.looking_at(dir, up), from).scaled_local(Vector3(1.0, 1.0, length))
