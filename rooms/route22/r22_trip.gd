extends Node3D
## The Route 22 Cruise's endless road: the conveyor that slides the desert past the car.
## The car never moves. `travel` (metres driven) grows with the speed, and every road piece
## (r22_pieces.gd, 80 m each) sits at a place worked out from it alone: piece number k covers
## the road from k * 80 m to (k + 1) * 80 m, so its origin is at world z = travel - k * 80, and
## it slides back past the car (+Z) as travel grows. The pieces in view are those from BEHIND
## metres behind the car to AHEAD metres ahead (about ten at a time). Which of the 24 piece
## types number k is comes from a shuffled bag (type_at): every type once per round of 24,
## never the same one twice in view.
## Because everything depends only on travel, two PCs in a co-stream that agree on travel see
## the same road: the host sends its travel every few seconds (room event "r22_travel") and
## guests ease onto it. Billboards are placed by the same dice, though their pictures are each
## PC's own set.
## Also here: the road's slow curves and hills (bend / hill, for r22_common.gdshaderinc, also
## from travel), bending the signs' words (Label3D is not drawn by our shaders, so the bend is
## applied to them here), turning the windmills, and the mile markers.
## Settings: r22_speed (km/h; 0 = parked), r22_curves (how much the road winds and rolls).
## route22_cruise_room.gd makes it (setup) and calls tick() every frame.

const Pieces := preload("res://rooms/route22/r22_pieces.gd")
const Billboards := preload("res://rooms/route22/r22_billboards.gd")
## How far behind and ahead of the car pieces are kept in place (metres; pieces fade out over
## their last 50 m: r22_pieces.gd _finish).
const BEHIND: float = 330.0
const AHEAD: float = 420.0
## Two pieces of one type are never closer than this many places in the order (more than are in
## view at once: (BEHIND + AHEAD) / LENGTH + 1).
const SPACING: int = 11
## Where the trip starts (metres), so piece numbers in view are never negative.
const START: float = 1000.0
## The road's curve and roll at full Curves: largest sideways and up shift factor (m / m²).
const MAX_BEND: float = 0.00032
const MAX_HILL: float = 0.00009
## Seconds between the host's travel messages to its guests.
const SYNC_EVERY: float = 4.0

## Metres driven (from START). Read by the room for the shaders and the sound.
var travel: float = START
## Metres a second the scenery moves now (eases towards r22_speed).
var speed: float = 0.0
var bend: float = 0.0
var hill: float = 0.0

var _kit: Dictionary
var _boards: Billboards
var _pieces: Array[Node3D] = []         # one of each type, built once (index = type)
var _placed: Dictionary = {}            # k -> type, the pieces in place now
var _cycles: Dictionary = {}            # round number -> PackedInt32Array of types (type_at)
var _sync_in: float = SYNC_EVERY
var _labels: Dictionary = {}            # type -> Array[Label3D] (their straight positions in meta "base")


## Builds the 24 pieces (hidden until their turn) and the billboards. kit: r22_geo.gd new_kit().
func setup(kit: Dictionary, boards: Billboards) -> void:
	_kit = kit
	_boards = boards
	name = "Trip"
	for t in Pieces.TYPES.size():
		var piece := Pieces.build(t, kit)
		piece.visible = false
		add_child(piece)
		_pieces.append(piece)
		var words: Array[Label3D] = []
		for l in piece.get_node("Labels").get_children():
			if l is Label3D:
				l.set_meta("base", (l as Label3D).position)
				words.append(l)
		_labels[t] = words
	boards.pictures_changed.connect(_refill_boards)
	speed = _target_speed()
	EventBus.net_room_event.connect(_on_net_room_event)


func _exit_tree() -> void:
	if EventBus.net_room_event.is_connected(_on_net_room_event):
		EventBus.net_room_event.disconnect(_on_net_room_event)


## r22_speed in metres a second (the setting is km/h, 0..120).
static func _target_speed() -> float:
	return clampf(float(AppState.get_setting("r22_speed")), 0.0, 120.0) / 3.6


## Which piece type comes at place k: round k / 24 of the bag, shuffled with that round's own
## seed, then rearranged so its first SPACING types were not among the last SPACING of the round
## before (so no type is ever in view twice).
func type_at(k: int) -> int:
	var n := Pieces.TYPES.size()
	var c := floori(float(k) / float(n))
	return _cycle(c)[posmod(k, n)]


func _cycle(c: int) -> PackedInt32Array:
	if _cycles.has(c):
		return _cycles[c]
	var n := Pieces.TYPES.size()
	var order := PackedInt32Array()
	for i in n:
		order.append(i)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 * c + 22
	for i in range(n - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var keep := order[i]
		order[i] = order[j]
		order[j] = keep
	if c > 0:
		var prev := _cycle(c - 1)
		var tail := prev.slice(n - SPACING)
		var front := PackedInt32Array()
		var back := PackedInt32Array()
		for t in order:
			if front.size() < SPACING and not tail.has(t):
				front.append(t)
			else:
				back.append(t)
		order = front + back
	_cycles[c] = order
	# forget rounds long past
	if _cycles.size() > 6:
		for old: int in _cycles.keys():
			if old < c - 3:
				_cycles.erase(old)
	return order


## Called every frame by the room. wind (0..1) turns the windmills; night lights the boards.
func tick(delta: float, wind: float, night: float) -> void:
	speed = move_toward(speed, _target_speed(), delta * 3.0)       # about 3 m/s² either way
	travel += speed * delta
	# the curves and hills: slow waves along the road (the same on every PC for the same travel)
	var curves := clampf(float(AppState.get_setting("r22_curves")), 0.0, 1.0)
	bend = curves * MAX_BEND * (0.7 * sin(travel / 900.0) + 0.3 * sin(travel / 370.0 + 1.3))
	hill = curves * MAX_HILL * (0.6 * sin(travel / 640.0 + 0.4) + 0.4 * sin(travel / 290.0 + 2.1))
	_place()
	_bend_words()
	for k: int in _placed:
		for s: Node3D in _pieces[_placed[k]].get_meta("spinners", []):
			s.rotate_object_local(Vector3.FORWARD, delta * (1.0 + 4.0 * wind))
	_boards.tick(night)
	_sync(delta)


## The pieces' numbers in view now.
func in_view() -> Vector2i:
	var l := Pieces.LENGTH
	return Vector2i(floori((travel - BEHIND) / l), floori((travel + AHEAD) / l))


## The piece types in view now (for tests).
func types_in_view() -> Array[String]:
	var out: Array[String] = []
	for k: int in _placed:
		out.append(Pieces.TYPES[_placed[k]])
	return out


## Puts every piece in view in its place, takes the ones that have left away, and gives a piece
## that has just come into view its billboards and its mile number.
func _place() -> void:
	var span := in_view()
	for k: int in _placed.keys():
		if k < span.x or k > span.y:
			var gone: Node3D = _pieces[_placed[k]]
			gone.visible = false
			_boards.clear(gone.get_node("Boards"))
			_placed.erase(k)
	for k in range(span.x, span.y + 1):
		var t := type_at(k)
		var piece := _pieces[t]
		if not _placed.has(k):
			if piece.visible:
				continue          # (can't happen with SPACING; never show one piece in two places)
			_placed[k] = t
			piece.visible = true
			_boards.fill(piece.get_node("Boards"), k, piece.get_meta("slots", []))
			# (only pieces with a mile marker have one)
			if piece.has_meta("mile"):
				var mile := piece.get_meta("mile") as Label3D
				mile.text = "MILE\n%d" % (22 + int(float(k) * Pieces.LENGTH / 1609.34))
		piece.position = Vector3(0.0, 0.0, travel - float(k) * Pieces.LENGTH)


## Signs' words follow the bend like the signs (r22_common.gdshaderinc r22_bend, done here).
func _bend_words() -> void:
	for k: int in _placed:
		var t: int = _placed[k]
		var piece := _pieces[t]
		for l: Label3D in _labels[t]:
			var base: Vector3 = l.get_meta("base")
			var w := piece.position + base
			var d := maxf(absf(w.z) - 18.0, 0.0)
			l.position = base + Vector3(bend * d * d, hill * d * d, 0.0)


## Co-stream: the host tells its guests how far it has driven every few seconds; a guest eases
## onto it (or jumps, if it is far off).
func _sync(delta: float) -> void:
	if NetSession.get_role() != "host":
		return
	_sync_in -= delta
	if _sync_in <= 0.0:
		_sync_in = SYNC_EVERY
		NetSession.send_room_event("r22_travel", [travel, speed])


func _on_net_room_event(_peer_id: int, _peer_name: String, kind: String, data: Array) -> void:
	if kind != "r22_travel" or NetSession.get_role() != "guest" or data.size() < 1:
		return
	var host_travel := float(data[0])
	if not is_finite(host_travel):
		return
	if absf(host_travel - travel) > 60.0:
		travel = host_travel
	else:
		travel = lerpf(travel, host_travel, 0.5)


## The billboard pictures changed: re-dress the pieces in view.
func _refill_boards() -> void:
	for k: int in _placed:
		var piece := _pieces[_placed[k]]
		_boards.fill(piece.get_node("Boards"), k, piece.get_meta("slots", []))
