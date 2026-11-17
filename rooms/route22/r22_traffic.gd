extends Node3D
## Route 22's other traffic: pickups, classic sedans, semis, motorhomes, motorcycles and the odd
## tour bus (r22_vehicles.gd), with their headlights' and tail lights' glare at night.
## How many: the "How busy" slider (r22_traffic, 0..100; 100 = about one every 10 seconds,
## 0 = an empty road). Shared in a co-stream, though which vehicle comes when is each PC's own.
## On the Detailed look (Set detail, each PC's own) a new vehicle is one of the Blender models
## (Vehicles.build_model), on the Low look the plain built-in-code shape; ones already on the
## road keep the look they came with.
##
## This node is laid along a road: its own Z runs along the road, X across it (lanes at ±1.8 m).
##   The Cruise: the road under the car. Almost everything is oncoming (the left lane, rushing
##     past at its speed plus ours); now and then, with the road clear, a faster car comes up
##     behind in the left lane, overtakes and pulls in ahead.
##   The Drive-In: Route 22 running past the lot. Traffic goes both ways; own_speed is 0.
## The room calls setup() once and tick() every frame.

const Geo := preload("res://rooms/route22/r22_geo.gd")
const Vehicles := preload("res://rooms/route22/r22_vehicles.gd")
const Desert := preload("res://rooms/route22/r22_desert.gd")

## Most vehicles about at once.
const MAX_ALIVE: int = 8
## Body colours they come in.
const PAINTS: Array[Color] = [Color(0.75, 0.73, 0.68), Color(0.12, 0.25, 0.45), Color(0.55, 0.1, 0.08), Color(0.15, 0.35, 0.25),
	Color(0.85, 0.65, 0.2), Color(0.1, 0.1, 0.11), Color(0.85, 0.85, 0.83), Color(0.4, 0.55, 0.65), Color(0.6, 0.35, 0.2)]

var _kit: Dictionary
var _desert: Node                       # r22_desert.gd (whoosh for the sound)
var _two_way: bool = false              # the Drive-In: both directions, nothing overtakes
var _z_far: float = -420.0              # where vehicles appear ahead (own Z)
var _z_near: float = 320.0              # where they appear behind / leave
var _rng := RandomNumberGenerator.new()
var _alive: Array[Dictionary] = []      # {node, vz, x, kind, length, passed, merge}
var _spare: Dictionary = {}             # pool (kind + look, a node's "pool" meta) -> Array of hidden vehicle nodes to reuse
var _next_in: float = 3.0               # seconds to the next vehicle


## two_way: the Drive-In's road (both ways). reach: [far, near] own-Z ends of the road.
func setup(kit: Dictionary, desert: Node, two_way: bool, reach: Vector2) -> void:
	_kit = kit
	_desert = desert
	_two_way = two_way
	_z_far = reach.x
	_z_near = reach.y
	_rng.randomize()
	name = "Traffic"


## Called every frame. own_speed = metres a second the scenery slides back (+Z; the Cruise's speed).
func tick(delta: float, own_speed: float) -> void:
	var busy := clampf(float(AppState.get_setting("r22_traffic")), 0.0, 100.0)
	_next_in -= delta
	if _next_in <= 0.0:
		if busy > 0.5 and _alive.size() < MAX_ALIVE:
			_spawn(own_speed)
		# 100 = one every 10 s on average; less busy = longer gaps
		var mean := 10.0 * 100.0 / maxf(busy, 1.0)
		_next_in = mean * _rng.randf_range(0.5, 1.5)
	var i := 0
	while i < _alive.size():
		var v := _alive[i]
		var n := v["node"] as Node3D
		var vz := float(v["vz"])
		n.position.z += vz * delta
		# an overtaking car pulls back into our lane once it is well ahead
		if bool(v.get("merge", false)) and n.position.z < -28.0:
			n.position.x = move_toward(n.position.x, 1.8, delta * 1.2)
		# the rush of air as it goes by the car (or the lot)
		if not bool(v["passed"]) and absf(n.position.z) < 6.0:
			v["passed"] = true
			if _desert and _desert.has_method("whoosh"):
				_desert.call("whoosh", clampf(absf(vz) / 40.0, 0.2, 1.0) * (1.6 if float(v["length"]) > 8.0 else 1.0))
		if n.position.z > _z_near + 20.0 or n.position.z < _z_far - 40.0:
			_retire(i)
			continue
		i += 1


## How many vehicles are on the road right now (for tests).
func count() -> int:
	return _alive.size()


func _spawn(own_speed: float) -> void:
	var kind := _pick_kind()
	var n := _take(kind)
	var their := _rng.randf_range(20.0, 29.0) if kind != "semi" and kind != "bus" else _rng.randf_range(19.0, 25.0)
	var x := -1.8
	var vz := 0.0
	var merge := false
	var start_z := _z_far
	if _two_way:
		if _rng.randf() < 0.5:
			x = -1.8
			vz = their
			start_z = _z_far
		else:
			x = 1.8
			vz = -their
			start_z = _z_near
	else:
		# (only with the road empty, so it never meets an oncoming one while it passes)
		if own_speed > 5.0 and _alive.is_empty() and _rng.randf() < 0.18 and kind != "semi" and kind != "bus" and kind != "rv":
			# an overtaker: from behind, a little faster than us
			x = -1.8
			vz = -_rng.randf_range(4.0, 8.0)
			start_z = _z_near
			merge = true
		else:
			x = -1.8
			vz = their + own_speed
			start_z = _z_far
	n.position = Vector3(x, 0.0, start_z)
	# the front (-Z in its own space) faces the way it goes
	n.rotation = Vector3(0.0, PI if vz > 0.0 else 0.0, 0.0)
	n.visible = true
	_alive.append({"node": n, "vz": vz, "x": x, "kind": kind, "length": float(n.get_meta("length", 5.0)), "passed": false, "merge": merge})


func _retire(i: int) -> void:
	var v := _alive[i]
	var n := v["node"] as Node3D
	n.visible = false
	var pool := String(n.get_meta("pool", v["kind"]))
	if not _spare.has(pool):
		_spare[pool] = []
	(_spare[pool] as Array).append(n)
	_alive.remove_at(i)


func _pick_kind() -> String:
	var total := 0.0
	for k: String in Vehicles.TRAFFIC_KINDS:
		total += float(Vehicles.TRAFFIC_KINDS[k])
	var roll := _rng.randf() * total
	for k: String in Vehicles.TRAFFIC_KINDS:
		roll -= float(Vehicles.TRAFFIC_KINDS[k])
		if roll <= 0.0:
			return k
	return "pickup"


## A vehicle node of a kind: a spare one if there is one, else a new one built now (its mesh,
## and glare squares on its head and tail lights).
func _take(kind: String) -> Node3D:
	var full := Desert.detail_level() == "full"
	var pool := kind + ("_model" if full else "")
	if _spare.has(pool) and not (_spare[pool] as Array).is_empty():
		return (_spare[pool] as Array).pop_back()
	var root := Node3D.new()
	root.name = "Vehicle_" + pool
	root.set_meta("pool", pool)
	add_child(root)
	var b := Geo.Buf.new()
	var paint := PAINTS[_rng.randi() % PAINTS.size()]
	var info := Vehicles.build_model(kind, b, paint, {}, _rng) if full else Vehicles.build(kind, {"all": b}, paint, {}, _rng)
	Geo.add_mesh(root, "Body", b, _kit["prop"], true)
	for p: Vector3 in info.get("front_lights", []):
		Geo.add_glow(_kit, root, p, Color(1.6, 1.5, 1.25), 1.4)
	for p: Vector3 in info.get("tail_lights", []):
		Geo.add_glow(_kit, root, p, Color(1.4, 0.12, 0.08), 0.7)
	root.set_meta("length", float(info.get("length", 5.0)))
	return root
