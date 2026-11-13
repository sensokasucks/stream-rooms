extends Node3D
## The Lakeside Campfire's fire games, for the streamer and every co-stream guest.
##   - Roasting: hold M in the room window. A stick pokes out of your avatar (your podium's
##     picture on its camp chair) with a marshmallow over the fire. It browns while you hold:
##     white, golden, brown, black, and if you leave it too long it catches fire. Let go and a
##     word over your avatar says how it came out; let go while it is golden and it becomes a
##     s'more (they are counted).
##   - Tossing: press T. A stick flies from your avatar onto the fire, which flares up
##     (the room's flare()).
## Made by rooms/campfire/campfire_room.gd, which calls setup(). Switched by the "camp_games"
## setting (Room tab). Whose avatar is "yours" follows the laser pointer's rule
## (core/laser_pointers.gd, _my_presenter): a guest's claimed podium, otherwise the first podium
## on set no guest has claimed; with no podium on set the stick comes from chair 1's place.
## In a co-stream each PC sends what it does through NetSession.send_room_event and draws the
## others' from EventBus.net_room_event:
##   "roast" [podium n, held, toast, flaming]   several times a second while held, once on letting go
##   "stick" [podium n]                          a stick was tossed
## The same on every PC, so nothing here is decided by the network: each PC browns its own
## marshmallow and the others only show it.

const FIRE_SHADER := preload("res://rooms/forge_hall/fire.gdshader")
## Seconds over a 100% fire for a marshmallow to go from white to golden-done (toast 1.0).
const ROAST_SECONDS: float = 11.0
## Toast levels: below GOLDEN_FROM it is underdone, up to GOLDEN_TO it is golden (a s'more),
## above that burnt, and from FLAME_AT it is on fire.
const GOLDEN_FROM: float = 0.6
const GOLDEN_TO: float = 1.0
const FLAME_AT: float = 1.3
## The marshmallow's colour by toast (a gradient: toast / 1.5 along it).
const TOAST_COLORS: Array[Color] = [Color(0.97, 0.96, 0.93), Color(0.96, 0.88, 0.7), Color(0.85, 0.6, 0.25), Color(0.4, 0.22, 0.08), Color(0.05, 0.04, 0.03)]
## Updates go out at most this often while roasting (seconds); one is also the keep-alive.
const SEND_GAP: float = 0.2
## Someone else's stick is pulled back if nothing has been heard from them for this long.
const STALE_S: float = 2.0
## Seconds between your own stick tosses.
const TOSS_GAP: float = 1.0
## How far the fire leaps for one stick (the room's flare(), 0..1).
const STICK_FLARE: float = 0.6
## Where the hand is on an avatar's picture: across and up as shares of its size from its
## middle, and metres in front of it (the same idea as LaserPointers.PODIUM_HAND).
const HAND: Vector3 = Vector3(0.32, -0.18, 0.08)
## Where the marshmallow hangs: metres from the fire's middle towards the roaster, and metres up.
const ROAST_SPOT: Vector2 = Vector2(0.42, 0.85)
## Seconds a result ("Golden!") stays over an avatar.
const WORD_SECONDS: float = 3.0

var _room: Room
## Everyone roasting or seen roasting: person id -> their rig. id 0 = this PC, otherwise the
## co-stream peer id. A rig: {n: podium, held: bool, out: 0..1 how far the stick is out,
## toast: float, flaming: bool, smores: int, quiet: seconds since their last update,
## root: Node3D, stick: MeshInstance3D, mallow: MeshInstance3D, mat: StandardMaterial3D,
## flame: MeshInstance3D, word: Label3D, word_left: seconds}.
var _people: Dictionary = {}
var _send_wait: float = 0.0
var _toss_wait: float = 0.0


## Called by the room right after it made this node.
func setup(room: Room) -> void:
	_room = room


func _ready() -> void:
	EventBus.net_room_event.connect(_on_net_event)
	EventBus.net_peer_left.connect(_on_peer_left)


func _exit_tree() -> void:
	if EventBus.net_room_event.is_connected(_on_net_event):
		EventBus.net_room_event.disconnect(_on_net_event)
		EventBus.net_peer_left.disconnect(_on_peer_left)


## RoomHost: another room is taking over (see Room / campfire_room.gd retire()).
func retire() -> void:
	_exit_tree()
	set_process(false)
	set_process_unhandled_input(false)


# ── Public (keys, tests) ─────────────────────────────────────
## Start or stop roasting on this PC (the M key; tests call it too).
func set_roasting(on: bool) -> void:
	if not _enabled():
		on = false
	var me := _person(0)
	if bool(me["held"]) == on:
		return
	me["n"] = _my_podium()
	if on and float(me["out"]) < 0.05:
		me["toast"] = 0.0                # a fresh marshmallow
		me["flaming"] = false
	me["held"] = on
	if not on:
		_finish(me)
	_send_roast(me)


## Toss a stick on the fire from this PC's avatar (the T key; tests call it too).
func toss_stick() -> void:
	if not _enabled() or _toss_wait > 0.0:
		return
	_toss_wait = TOSS_GAP
	var n := _my_podium()
	_throw_stick(n)
	NetSession.send_room_event("stick", [n])


## A person's rig as described at _people, or {} (id 0 = this PC). For tests.
func get_person(id: int = 0) -> Dictionary:
	return _people.get(id, {})


## Sets this PC's marshmallow's toast directly (tests, to skip the waiting).
func set_toast(toast: float) -> void:
	_person(0)["toast"] = toast


# ── Input ────────────────────────────────────────────────────
## M (hold) and T, without Ctrl / Alt. _unhandled_input, so typing in a text box never fires them.
func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or key.echo or key.ctrl_pressed or key.alt_pressed or not _enabled():
		return
	if key.keycode == KEY_M:
		set_roasting(key.pressed)
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_T and key.pressed:
		toss_stick()
		get_viewport().set_input_as_handled()


## Clicking away to another window while holding M never sends the key-up: let go for them.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and _people.has(0) and bool(_people[0]["held"]):
		set_roasting(false)


func _enabled() -> bool:
	return _room != null and is_instance_valid(_room) and bool(AppState.get_setting("camp_games"))


# ── Every frame ──────────────────────────────────────────────
func _process(delta: float) -> void:
	_toss_wait = maxf(_toss_wait - delta, 0.0)
	if _people.is_empty():
		return
	var heat: float = clampf(float(_room.call("get_fire_amount")), 0.0, 2.0) if _room and is_instance_valid(_room) else 0.0
	for id: int in _people:
		var p: Dictionary = _people[id]
		if id == 0:
			if bool(p["held"]):
				# this PC's own marshmallow browns: faster over a bigger fire, not at all over none
				p["toast"] = minf(float(p["toast"]) + delta / ROAST_SECONDS * heat, 1.6)
				p["flaming"] = float(p["toast"]) >= FLAME_AT
				_send_wait -= delta
				if _send_wait <= 0.0:
					_send_roast(p)
		elif bool(p["held"]):
			p["quiet"] = float(p["quiet"]) + delta
			if float(p["quiet"]) > STALE_S:
				p["held"] = false        # they dropped out mid-roast: no result, the stick just goes
		p["out"] = move_toward(float(p["out"]), 1.0 if bool(p["held"]) else 0.0, delta * 2.4)
		if float(p["word_left"]) > 0.0:
			p["word_left"] = float(p["word_left"]) - delta
			(p["word"] as Label3D).visible = float(p["word_left"]) > 0.0
		_place(p)


## Draws one person's stick where it is now: from their hand towards the spot over the fire, as
## far as `out` says, with the marshmallow on its tip in the colour of its toast.
func _place(p: Dictionary) -> void:
	var root := p["root"] as Node3D
	var out := float(p["out"])
	root.visible = out > 0.02
	var hand := _hand_of(int(p["n"]))
	(p["word"] as Label3D).global_position = hand + Vector3(0.0, 1.15, 0.0)
	if not root.visible:
		return
	var fire := _fire_pos()
	var flat := Vector3(hand.x - fire.x, 0.0, hand.z - fire.z)
	var spot := fire + flat.normalized() * ROAST_SPOT.x + Vector3(0.0, ROAST_SPOT.y, 0.0)
	var eased := out * out * (3.0 - 2.0 * out)
	var tip := hand.lerp(spot, eased)
	var along := tip - hand
	var length := maxf(along.length(), 0.01)
	var up := along / length
	var side := up.cross(Vector3.UP if absf(up.y) < 0.95 else Vector3.RIGHT).normalized()
	var basis_now := Basis(side, up, side.cross(up))
	# the stick is a 1 m rod along Y, stretched to the length it shows
	(p["stick"] as MeshInstance3D).global_transform = Transform3D(basis_now.scaled(Vector3(1.0, length, 1.0)), hand + along * 0.5)
	(p["mallow"] as MeshInstance3D).global_transform = Transform3D(basis_now, tip)
	var toast := float(p["toast"])
	var mat := p["mat"] as StandardMaterial3D
	mat.albedo_color = toast_color(toast)
	# a burning marshmallow glows
	mat.emission_energy_multiplier = 1.5 if bool(p["flaming"]) else 0.0
	var flame := p["flame"] as MeshInstance3D
	flame.visible = bool(p["flaming"]) and out > 0.5
	flame.global_position = tip + Vector3(0.0, 0.13, 0.0)


## The marshmallow's colour at a toast level (0 = white ... 1.5 = black).
static func toast_color(toast: float) -> Color:
	var x := clampf(toast / 1.5, 0.0, 0.999) * float(TOAST_COLORS.size() - 1)
	var i := int(x)
	return TOAST_COLORS[i].lerp(TOAST_COLORS[i + 1], x - float(i))


## What letting go at a toast level gives: the word shown over the avatar.
static func result_word(toast: float) -> String:
	if toast < 0.25:
		return "Still cold"
	if toast < GOLDEN_FROM:
		return "Barely warm"
	if toast <= GOLDEN_TO:
		return "Golden! S'more time"
	if toast < FLAME_AT:
		return "A bit burnt..."
	return "Burnt to a crisp!"


## Someone let go: show how it came out, and make the s'more if it was golden.
func _finish(p: Dictionary) -> void:
	var toast := float(p["toast"])
	if float(p["out"]) < 0.3:
		return                          # a tap: the marshmallow never reached the fire
	var word := p["word"] as Label3D
	var text := result_word(toast)
	if toast >= GOLDEN_FROM and toast <= GOLDEN_TO:
		p["smores"] = int(p["smores"]) + 1
		text += "  (%d)" % int(p["smores"])
		_show_smore(_hand_of(int(p["n"])) + Vector3(0.0, 0.75, 0.0))
	word.text = text
	word.modulate = Color(1.0, 0.85, 0.45) if toast >= GOLDEN_FROM and toast <= GOLDEN_TO else Color(0.9, 0.9, 0.9)
	word.visible = true
	p["word_left"] = WORD_SECONDS
	p["flaming"] = false


# ── Whose avatar, and where ──────────────────────────────────
## This PC's podium, 1..4, or 0 when there is none on set. The same rule as the laser pointer's
## "my podium" (core/laser_pointers.gd, _my_presenter): keep the two alike.
func _my_podium() -> int:
	if NetSession.get_role() == "guest":
		return NetSession.my_podium()
	var owners: Dictionary = {}
	for e: Dictionary in NetSession.podium_list():
		owners[int(e["n"])] = String(e["owner"])
	for i in range(1, AppState.PRESENTER_COUNT + 1):
		if bool(AppState.get_setting(AppState.presenter_key(i, "on"))) and String(owners.get(i, "")) == "":
			return i
	return 0


## Where podium n's hand is (world space): on the avatar's picture when that presenter is on
## set, otherwise at the same place over the empty chair. n = 0 uses chair 1.
func _hand_of(n: int) -> Vector3:
	n = clampi(n, 1, AppState.PRESENTER_COUNT) if n > 0 else 1
	var stage := _room.get_node_or_null("Presenters") as PresenterStage
	var presenter := stage.get_presenter(n) if stage else null
	if presenter != null and presenter.visible:
		var pic := presenter.get_picture()
		var size := (pic.mesh as QuadMesh).size if pic.mesh is QuadMesh else Vector2.ONE
		return pic.global_transform * Vector3(size.x * HAND.x, size.y * HAND.y, HAND.z)
	var marker := _room.find_child("PRESENTER_%d" % n, true, false) as Node3D
	if marker == null:
		return _fire_pos() + Vector3(0.0, 1.0, -2.5)
	var size2 := _room.presenter_size
	return marker.global_transform * Vector3(size2.x * HAND.x, size2.y * (0.5 + HAND.y), HAND.z)


func _fire_pos() -> Vector3:
	var fire := _room.find_child("FIRE_Camp", true, false) as Node3D
	return fire.global_position if fire else _room.global_position


# ── Tossing a stick ──────────────────────────────────────────
## A stick tumbles from podium n's hand onto the fire in an arc, and the fire flares as it lands.
func _throw_stick(n: int) -> void:
	var from := _hand_of(n)
	var to := _fire_pos() + Vector3(0.0, 0.25, 0.0)
	var rod := CylinderMesh.new()
	rod.top_radius = 0.02
	rod.bottom_radius = 0.028
	rod.height = 0.55
	rod.radial_segments = 6
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.2, 0.12)
	mat.roughness = 0.9
	var stick := MeshInstance3D.new()
	stick.name = "TossedStick"
	stick.mesh = rod
	stick.material_override = mat
	add_child(stick)
	stick.global_position = from
	var spin := Vector3(randf_range(4.0, 9.0), randf_range(-3.0, 3.0), randf_range(4.0, 9.0))
	# a straight line from hand to fire, lifted in the middle, tumbling as it goes
	var move := func(t: float) -> void:
		stick.global_position = from.lerp(to, t) + Vector3(0.0, 1.5 * 4.0 * t * (1.0 - t), 0.0)
		stick.rotation = spin * t
	var land := func() -> void:
		stick.queue_free()
		if _room and is_instance_valid(_room):
			_room.call("flare", STICK_FLARE)
	var fly := create_tween()
	fly.tween_method(move, 0.0, 1.0, 0.75)
	fly.tween_callback(land)


# ── The s'more ───────────────────────────────────────────────
## A s'more (cracker, chocolate, squashed marshmallow, cracker) pops up at `at`, turns slowly,
## and shrinks away after a few seconds.
func _show_smore(at: Vector3) -> void:
	var smore := Node3D.new()
	smore.name = "Smore"
	add_child(smore)
	smore.global_position = at
	var layers: Array = [[0.0, 0.025, Vector2(0.2, 0.2), Color(0.72, 0.5, 0.24)], [0.03, 0.02, Vector2(0.17, 0.17), Color(0.22, 0.11, 0.06)],
		[0.065, 0.045, Vector2(0.19, 0.19), Color(0.93, 0.84, 0.62)], [0.105, 0.025, Vector2(0.2, 0.2), Color(0.72, 0.5, 0.24)]]
	for l: Array in layers:
		var box := BoxMesh.new()
		box.size = Vector3((l[2] as Vector2).x, float(l[1]), (l[2] as Vector2).y)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = l[3]
		mat.roughness = 0.8
		var mi := MeshInstance3D.new()
		mi.mesh = box
		mi.material_override = mat
		mi.position = Vector3(0.0, float(l[0]), 0.0)
		smore.add_child(mi)
	smore.rotation = Vector3(0.35, 0.0, 0.0)
	smore.scale = Vector3.ONE * 0.01
	var pop := create_tween()
	pop.tween_property(smore, "scale", Vector3.ONE * 1.6, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pop.parallel().tween_property(smore, "rotation:y", TAU, 2.6)
	pop.tween_property(smore, "scale", Vector3.ONE * 0.01, 0.3)
	pop.tween_callback(smore.queue_free)


# ── Rigs ─────────────────────────────────────────────────────
## The rig for person id, made on first use.
func _person(id: int) -> Dictionary:
	if _people.has(id):
		return _people[id]
	var root := Node3D.new()
	root.name = "Roaster_%d" % id
	add_child(root)
	var rod := CylinderMesh.new()
	rod.top_radius = 0.009
	rod.bottom_radius = 0.013
	rod.height = 1.0
	rod.radial_segments = 5
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.28, 0.19, 0.11)
	wood.roughness = 0.9
	var stick := MeshInstance3D.new()
	stick.mesh = rod
	stick.material_override = wood
	root.add_child(stick)
	var puff := CylinderMesh.new()
	puff.top_radius = 0.045
	puff.bottom_radius = 0.045
	puff.height = 0.075
	puff.radial_segments = 10
	var mat := StandardMaterial3D.new()
	mat.roughness = 0.7
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.45, 0.1)
	mat.emission_energy_multiplier = 0.0
	var mallow := MeshInstance3D.new()
	mallow.mesh = puff
	mallow.material_override = mat
	root.add_child(mallow)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.2, 0.3)
	var flame_mat := ShaderMaterial.new()
	flame_mat.shader = FIRE_SHADER
	flame_mat.set_shader_parameter("seed", float(id % 17) + 0.5)
	flame_mat.set_shader_parameter("amount", 1.2)
	var flame := MeshInstance3D.new()
	flame.mesh = quad
	flame.material_override = flame_mat
	flame.extra_cull_margin = 0.5
	flame.visible = false
	root.add_child(flame)
	var word := Label3D.new()
	word.name = "RoastWord_%d" % id
	word.font_size = 64
	word.pixel_size = 0.0026
	word.outline_size = 14
	word.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	word.no_depth_test = true
	word.visible = false
	add_child(word)
	root.visible = false
	var p := {"n": 0, "held": false, "out": 0.0, "toast": 0.0, "flaming": false, "smores": 0, "quiet": 0.0,
		"root": root, "stick": stick, "mallow": mallow, "mat": mat, "flame": flame, "word": word, "word_left": 0.0}
	_people[id] = p
	return p


# ── The network ──────────────────────────────────────────────
func _send_roast(p: Dictionary) -> void:
	_send_wait = SEND_GAP
	NetSession.send_room_event("roast", [int(p["n"]), bool(p["held"]), float(p["toast"]), bool(p["flaming"])])


## EventBus.net_room_event: what someone else in the co-stream did (already checked for size and
## types by NetSession; the values are checked again here).
func _on_net_event(peer_id: int, _peer_name: String, kind: String, data: Array) -> void:
	if not _enabled() or peer_id == 0:
		return
	if kind == "stick" and data.size() == 1 and data[0] is int:
		_throw_stick(clampi(int(data[0]), 0, AppState.PRESENTER_COUNT))
	elif kind == "roast" and data.size() == 4 and data[0] is int and data[1] is bool and data[2] is float and data[3] is bool:
		var p := _person(peer_id)
		var was_held := bool(p["held"])
		p["n"] = clampi(int(data[0]), 0, AppState.PRESENTER_COUNT)
		p["held"] = bool(data[1])
		p["toast"] = clampf(float(data[2]), 0.0, 1.6) if is_finite(float(data[2])) else 0.0
		p["flaming"] = bool(data[3])
		p["quiet"] = 0.0
		if was_held and not bool(p["held"]):
			_finish(p)


## Someone left the session: their stick goes with them.
func _on_peer_left(peer_id: int) -> void:
	if _people.has(peer_id):
		var p: Dictionary = _people[peer_id]
		(p["root"] as Node3D).queue_free()
		(p["word"] as Label3D).queue_free()
		_people.erase(peer_id)
