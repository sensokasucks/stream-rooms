extends "res://rooms/route22/r22_traffic.gd"
## Route 81's other traffic. The vehicles, their looks and their lights are Route 22's
## (rooms/route22/r22_traffic.gd, which this extends: _take, _retire, count); what differs is
## the road. An interstate is two separate roads, so nothing ever comes towards us in our lanes:
##   - the other direction's traffic runs on its own road across the median (lanes at
##     OPP_LANES), rushing past at its speed plus ours,
##   - on our road, faster vehicles come up from behind in the left lane (x = -1.8), pass and
##     pull away ahead. We drive in the right lane and never catch anything up.
## About four in ten are semis: Route 81 is a truck road.
## How many: the same "How busy" slider as the desert (r22_traffic, 0..100; 100 = about one
## every 6 seconds over both roads). Which vehicle comes when is each PC's own.
## route81_room.gd calls setup() once and tick() every frame.

const Land := preload("res://rooms/route81/r81_land.gd")

## The other road's two lanes (X, metres), 1.8 m either side of its dashed line (Land.OPP_C):
## first its right-hand lane as its drivers see it (the far one from us, where most of them
## and all the trucks drive), then its passing lane (next to the median).
const OPP_LANES: Array[float] = [Land.OPP_C - 1.8, Land.OPP_C + 1.8]
## Our passing lane.
const PASS_LANE: float = -1.8
## Seconds between vehicles at "How busy" 100, on average.
const BUSIEST_GAP: float = 6.0
## The share of semis.
const SEMIS: float = 0.4


## Called every frame. own_speed = metres a second the scenery slides back (+Z).
func tick(delta: float, own_speed: float) -> void:
	var busy := clampf(float(AppState.get_setting("r22_traffic")), 0.0, 100.0)
	_next_in -= delta
	if _next_in <= 0.0:
		if busy > 0.5 and _alive.size() < MAX_ALIVE:
			_spawn(own_speed)
		var mean := BUSIEST_GAP * 100.0 / maxf(busy, 1.0)
		_next_in = mean * _rng.randf_range(0.5, 1.5)
	var i := 0
	while i < _alive.size():
		var v := _alive[i]
		var n := v["node"] as Node3D
		var vz := float(v["vz"])
		n.position.z += vz * delta
		# the rush of air as one passes close by (only our own road's traffic is near enough)
		if not bool(v["passed"]) and absf(n.position.z) < 6.0 and absf(n.position.x) < 6.0:
			v["passed"] = true
			if _desert and _desert.has_method("whoosh"):
				_desert.call("whoosh", clampf(absf(vz) / 40.0, 0.2, 1.0) * (1.6 if float(v["length"]) > 8.0 else 1.0))
		if n.position.z > _z_near + 20.0 or n.position.z < _z_far - 40.0:
			_retire(i)
			continue
		i += 1


## Puts one more vehicle on the road: usually on the other road coming towards us, about one
## in three on ours, passing us from behind (only while nothing else is coming up behind).
func _spawn(own_speed: float) -> void:
	var kind := "semi" if _rng.randf() < SEMIS else _pick_kind()
	var heavy := kind == "semi" or kind == "bus" or kind == "rv"
	# what it does on its own road, metres a second (about 95 to 125 km/h; trucks 90 to 105)
	var their := _rng.randf_range(25.0, 29.0) if heavy else _rng.randf_range(27.0, 35.0)
	var behind_busy := false
	for v in _alive:
		if float(v["x"]) == PASS_LANE and (v["node"] as Node3D).position.z > _z_near - 90.0:
			behind_busy = true
	var x := OPP_LANES[0] if heavy or _rng.randf() < 0.7 else OPP_LANES[1]
	var vz := their + own_speed
	var start_z := _z_far
	if not behind_busy and _rng.randf() < 0.33:
		# passing us: at least a brisk walk faster than we go, whatever our speed
		x = PASS_LANE
		vz = -maxf(their - own_speed, 3.0)
		start_z = _z_near
	var n := _take(kind)
	n.position = Vector3(x, 0.0, start_z)
	# the front (-Z in its own space) faces the way it goes
	n.rotation = Vector3(0.0, PI if vz > 0.0 else 0.0, 0.0)
	n.visible = true
	_alive.append({"node": n, "vz": vz, "x": x, "kind": kind, "length": float(n.get_meta("length", 5.0)), "passed": false, "merge": false})
