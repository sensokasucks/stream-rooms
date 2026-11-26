extends Node3D
## The Route 81 Cruise's endless highway: strings places of land together as the car drives,
## and works out everything that depends on how far it has driven.
## Like Route 22's trip (rooms/route22/r22_trip.gd) the car never moves: `travel` (metres driven)
## grows with the speed, place number k covers the road from k * 80 m to (k + 1) * 80 m, and its
## node sits at world z = travel - k * 80, sliding back past the car. Unlike Route 22 there is no
## bag of ready-made pieces. Each place is dressed when it comes into view, from parts that are
## built once and shared (r81_land.gd strips of land and trees, r81_pieces.gd rails, tunnels and
## signs), by rules that depend only on k and the shared settings. So two PCs in a co-stream that
## agree on travel see the same road; the host sends its travel every few seconds (room event
## "r81_travel") and guests ease onto it.
##
## ── What a place looks like (boundary(), part_at()) ──
## Each side of the highway has an edge profile (r81_land.gd KINDS: woods, cut, drop, mount) at
## every boundary between two places. A side keeps its profile for eight boundaries (640 m,
## long enough to take a view in), then rolls
## again: an overlook ("drop") with a chance set by the "How often views open up" slider
## (r81_views), a rock cut, or woods. The right side rolls at boundaries 0, 8, 16.. and the left at
## 4, 12, 20.., so the two sides never change in the same place. A place whose side starts and
## ends differently is a transition (the land blends from one to the other).
## Tunnels come every `period()` places (the Tunnels choice, r81_tunnels): the road runs into a
## rock cut, the mountain closes over it for 400 m, and it comes out the far side in a new
## region (see `region`): another stretch of the far view, another height. That is how this room
## will change between very different kinds of country in the later regions.
##
## ── What else is worked out here, all from travel ──
##   bend / hill   the road's curve and roll ahead (for r22_common.gdshaderinc), three times
##                 stronger than the desert's,
##   heading       how far the road has turned in all (the curve added up): the far ridges and
##                 the sun swing round by it,
##   altitude      how high above the valley floor the road is (40 to 240 m): how far the
##                 overlook side falls away (r81_common.gdshaderinc alt_drop) and how low the far
##                 view lies,
##   tunnel_a / tunnel_b, cover   where the nearest tunnel is and how deep in it the car is.
## Settings: r22_speed and r22_curves (shared with the desert Cruise), r81_tunnels, r81_views,
## r81_forest (how much of the trees is drawn), r81_season, r22_detail.
## route81_room.gd makes it (setup) and calls tick() every frame.

const Geo := preload("res://rooms/route22/r22_geo.gd")
const Desert := preload("res://rooms/route22/r22_desert.gd")
const Land := preload("res://rooms/route81/r81_land.gd")
const Pieces := preload("res://rooms/route81/r81_pieces.gd")

## How far behind and ahead of the car places are kept (metres). Further ahead than the desert's:
## there is no flat ground to hide where the land ends, only distance, haze and the curve.
const BEHIND: float = 640.0
const AHEAD: float = 960.0
## Trees are only drawn on places whose start is nearer than this (metres; past it the land's
## shader paints tree tops instead). The second number is for the Low look.
const TREES_NEAR: float = 480.0
const TREES_NEAR_LOW: float = 240.0
## Where the trip starts (metres), so place numbers in view are never negative.
const START: float = 1000.0
## The road's curve and roll at full Curves: largest sideways and up shift factor (m / m²).
const MAX_BEND: float = 0.00096
const MAX_HILL: float = 0.00018
## How much of the road's true turning the far view and the sun swing by. Less than all of it:
## the far view never comes closer, so a ridge must not end up standing across the road.
const HEADING_SHARE: float = 0.5
## Places between tunnel mouths for each Tunnels choice ("never" = no tunnels): about 4, 7 and 13 km.
const PERIODS: Dictionary = {"short": 50, "medium": 88, "long": 163}
## A tunnel: the mouth is halfway along its first place, the way out halfway along its sixth.
const TUNNEL_LENGTH: float = Land.LENGTH * 5.0
## Metres from a tunnel mouth to where the daylight is gone (cover reaches 1).
const COVER_FADE: float = 25.0
## The valley floor lies this far below the overlook side's outer edge when the altitude is 0
## (r81_land.gd edge("drop") at REACH); the far view is set down by the altitude plus this.
const FLOOR_BELOW: float = 94.0
## Seconds between the host's travel messages to its guests.
const SYNC_EVERY: float = 4.0
## The tunnel lamps' colour (sodium orange; the Streetlights choice will set it in a later round).
const LAMP := Color(1.0, 0.62, 0.25)

## Metres driven (from START). Read by the room for the shaders and the sound.
var travel: float = START
## Metres a second the scenery moves now (eases towards r22_speed).
var speed: float = 0.0
var bend: float = 0.0
var hill: float = 0.0
## Radians the far view and the sun have swung round (the room hands it to r22_desert.gd).
var heading: float = 0.0
## Metres the road is above the valley floor now.
var altitude: float = 140.0
## 0 = under the open sky .. 1 = deep in a tunnel.
var cover: float = 0.0
## Which stretch of country this is: goes up by one in the middle of every tunnel.
var region: int = 0
## The nearest tunnel covers the road from world z = tunnel_a to tunnel_b (a > b; both 0 = none).
var tunnel_a: float = 0.0
var tunnel_b: float = 0.0

var _kit: Dictionary
var _backdrop: Node3D
var _slots: Array[Dictionary] = []      # the place nodes, made as needed (see _make_slot)
var _free: Array[int] = []              # indexes into _slots of the ones not in use
var _placed: Dictionary = {}            # k -> {"slot": index, "look": what it was dressed as}
var _strips: Dictionary = {}            # "side|from|to|salt" -> Land.side_strip() result
var _forest_drawn: float = -1.0         # the Forest density share last applied to the tree batches
var _lights: Array[OmniLight3D] = []    # the tunnel lamps' light on the car
var _sync_in: float = SYNC_EVERY


## kit: r22_geo.gd new_kit() with r81_land.gd add_materials() done. backdrop: the far view
## (Land.build_backdrop), which this node lowers and turns.
func setup(kit: Dictionary, backdrop: Node3D) -> void:
	_kit = kit
	_backdrop = backdrop
	name = "Trip"
	for z: float in [-5.0, 6.0]:
		var l := OmniLight3D.new()
		l.name = "TunnelLamp"
		l.light_color = LAMP
		l.omni_range = 14.0
		l.shadow_enabled = false
		l.visible = false
		add_child(l)
		l.position = Vector3(1.8, 6.0, z)
		_lights.append(l)
	speed = _target_speed()
	EventBus.net_room_event.connect(_on_net_room_event)
	_work_out()
	_place()


func _exit_tree() -> void:
	if EventBus.net_room_event.is_connected(_on_net_room_event):
		EventBus.net_room_event.disconnect(_on_net_room_event)


## r22_speed in metres a second (the setting is km/h, 0..120).
static func _target_speed() -> float:
	return clampf(float(AppState.get_setting("r22_speed")), 0.0, 120.0) / 3.6


## Places from one tunnel mouth to the next (0 = no tunnels), from the Tunnels choice.
static func period() -> int:
	return int(PERIODS.get(String(AppState.get_setting("r81_tunnels")), 0))


## The "How often views open up" slider as a share 0..1, in hundredths (so every PC rounds it
## the same way).
static func views() -> float:
	return clampf(roundf(float(AppState.get_setting("r81_views")) * 100.0), 0.0, 100.0) / 100.0


## A number 0..1 that depends only on n (the same on every PC).
static func _dice(n: int) -> float:
	var x := (n * 374761393 + 668265263) & 0x7fffffff
	x = ((x ^ (x >> 13)) * 1274126177) & 0x7fffffff
	x = x ^ (x >> 16)
	return float(x % 10000) / 10000.0


## The edge profile of one side (+1 = our right, -1 = the left, beyond the other road) at
## boundary b, the line between places b - 1 and b. See the top of the file.
static func boundary(side: int, b: int) -> String:
	var p := period()
	if p > 0:
		var j := posmod(b, p)
		if j >= 1 and j <= 5:
			return "mount"
		# rock cuts lead into and out of every tunnel (the land only knows cut <-> mountain)
		if j == 0 or j == 6 or j == 7 or j == p - 1:
			return "cut"
	var group := floori(float(b + (0 if side > 0 else 4)) / 8.0)
	var roll := _dice(group * 2 + (1 if side > 0 else 0))
	var open := views() * 0.5
	if roll < open:
		return "drop"
	if roll < open + 0.28:
		return "cut"
	return "woods"


## Which part of a tunnel place k is ("in", "tube", "out", r81_pieces.gd), or "" for open road.
static func part_at(k: int) -> String:
	var p := period()
	if p <= 0:
		return ""
	var j := posmod(k, p)
	if j == 0:
		return "in"
	if j <= 4:
		return "tube"
	return "out" if j == 5 else ""


## Called every frame by the room. night = 0..1 from r22_desert.gd (unused for now: the
## streetlights of a later round will need it).
func tick(delta: float, _night: float) -> void:
	speed = move_toward(speed, _target_speed(), delta * 3.0)       # about 3 m/s² either way
	travel += speed * delta
	_work_out()
	_place()
	_apply()
	_bend_words()
	_sync(delta)


## Everything that follows from travel alone: the curve, the heading, the height, the tunnel.
func _work_out() -> void:
	var curves := clampf(float(AppState.get_setting("r22_curves")), 0.0, 1.0)
	# slow waves along the road (the same on every PC for the same travel)
	bend = curves * MAX_BEND * (0.7 * sin(travel / 900.0) + 0.3 * sin(travel / 370.0 + 1.3))
	hill = curves * MAX_HILL * (0.6 * sin(travel / 640.0 + 0.4) + 0.4 * sin(travel / 290.0 + 2.1))
	# A shift of bend * d² means the road ahead curves at 2 * bend radians a metre. Adding that
	# up over the distance driven (the waves above, integrated) gives how far it has turned.
	heading = HEADING_SHARE * curves * MAX_BEND * 2.0 * (-0.7 * 900.0 * cos(travel / 900.0) - 0.3 * 370.0 * cos(travel / 370.0 + 1.3))
	var here := travel / Land.LENGTH
	var p := period()
	tunnel_a = 0.0
	tunnel_b = 0.0
	cover = 0.0
	region = 0
	if p > 0:
		# the tunnel whose middle (3 places past its first) is nearest
		var first := roundi((here - 3.0) / float(p)) * p
		tunnel_a = travel - float(first) * Land.LENGTH - Land.LENGTH * 0.5
		tunnel_b = tunnel_a - TUNNEL_LENGTH
		if tunnel_a > 0.0 and tunnel_b < 0.0:
			cover = clampf(minf(tunnel_a, -tunnel_b) / COVER_FADE, 0.0, 1.0)
		region = floori((here - 3.0) / float(p))
	# the height: two slow waves, starting somewhere else in every region (the jump happens in
	# the dark, in the middle of the tunnel)
	altitude = 140.0 + 70.0 * sin(travel / 1900.0 + float(region) * 2.0) + 30.0 * sin(travel / 730.0 + 1.0)


## The places' numbers in view now.
func in_view() -> Vector2i:
	return Vector2i(floori((travel - BEHIND) / Land.LENGTH), floori((travel + AHEAD) / Land.LENGTH))


## What the places in view are, as "left from>to / right from>to / part" (for tests).
func looks_in_view() -> Array[String]:
	var out: Array[String] = []
	for k: int in _placed:
		out.append(String(_placed[k]["look"]))
	return out


## Jumps to a spot on the road (tests, and a guest far behind its host).
func set_travel(metres: float) -> void:
	travel = maxf(metres, START)
	_work_out()
	_place()


## Puts every place in view where it belongs, dressing the ones that have just come into view
## (or whose rules changed: the Tunnels or views setting moved) and freeing the ones that left.
func _place() -> void:
	var span := in_view()
	for k: int in _placed.keys():
		if k < span.x or k > span.y:
			var gone: int = _placed[k]["slot"]
			(_slots[gone]["root"] as Node3D).visible = false
			_free.append(gone)
			_placed.erase(k)
	var tree_reach := TREES_NEAR_LOW if Desert.detail_level() == "low" else TREES_NEAR
	for k in range(span.x, span.y + 1):
		var look := _look(k)
		if not _placed.has(k):
			if _free.is_empty():
				_make_slot()
			_placed[k] = {"slot": _free.pop_back(), "look": ""}
		var entry: Dictionary = _placed[k]
		var slot: Dictionary = _slots[entry["slot"]]
		if String(entry["look"]) != look:
			entry["look"] = look
			_dress(slot, k)
		var root := slot["root"] as Node3D
		root.visible = true
		root.position = Vector3(0.0, 0.0, travel - float(k) * Land.LENGTH)
		var near := root.position.z > -tree_reach and root.position.z < tree_reach
		for t: MultiMeshInstance3D in slot["trees"]:
			t.visible = near and t.multimesh != null
	_apply_forest()


## What place k is, in one line: both sides' profiles, the tunnel part, which variant of the land.
func _look(k: int) -> String:
	return "%s>%s / %s>%s / %s / %d" % [boundary(-1, k), boundary(-1, k + 1), boundary(1, k), boundary(1, k + 1), part_at(k), posmod(k, 3)]


## One side's land and trees for a place (built the first time it is needed, then kept).
## Steady stretches come in three variants (their bumps and trees differ), picked by k.
func _strip(side: int, from: String, to: String, k: int) -> Dictionary:
	var salt := 0
	if from != "mount" and to != "mount":
		salt = (10 + posmod(k, 3)) if from == to else 1
	if side < 0:
		salt += 50
	var key := "%d|%s|%s|%d" % [side, from, to, salt]
	if not _strips.has(key):
		_strips[key] = Land.side_strip(side, from, to, salt)
		_forest_drawn = -1.0          # (the new trees need the Forest density applied)
	return _strips[key]


## A new place node, hidden and free: the land, trees and props of both sides, and the parts
## only some places have (tunnel lining, mountain top, portal, a sign), which _dress() fills.
func _make_slot() -> void:
	var root := Node3D.new()
	root.name = "Place_%d" % _slots.size()
	root.visible = false
	add_child(root)
	var slot := {"root": root, "trees": [] as Array[MultiMeshInstance3D], "land": {}, "props": {}, "tree_of": {}}
	for side: int in [1, -1]:
		var tag := "R" if side > 0 else "L"
		slot["land"][side] = _mesh_node(root, "Land" + tag, _kit["land"], true)
		slot["props"][side] = _mesh_node(root, "Props" + tag, _kit["prop"], true)
		for kind in Land.TREES:
			var t := MultiMeshInstance3D.new()
			t.name = "Trees%s_%s" % [tag, kind]
			t.material_override = _kit["trees"]
			# the shaders move things a long way (the bend, the valley): never cull early
			t.extra_cull_margin = 700.0
			root.add_child(t)
			(slot["trees"] as Array[MultiMeshInstance3D]).append(t)
			slot["tree_of"]["%d|%s" % [side, kind]] = t
	slot["lid"] = _mesh_node(root, "MountainTop", _kit["land"], true)
	for kind in Land.TREES:
		var t := MultiMeshInstance3D.new()
		t.name = "TreesTop_" + kind
		t.material_override = _kit["trees"]
		t.extra_cull_margin = 700.0
		root.add_child(t)
		(slot["trees"] as Array[MultiMeshInstance3D]).append(t)
		slot["tree_of"]["0|" + kind] = t
	slot["lining"] = _mesh_node(root, "TunnelLining", _kit["tunnel"], false)
	slot["frame"] = _mesh_node(root, "Portal", _kit["prop"], true)
	var board := _mesh_node(root, "Sign", _kit["prop"], true)
	board.mesh = Pieces.sign_board()
	slot["sign"] = board
	slot["sign_words"] = Geo.add_words(root, "", Pieces.SIGN_AT + Vector3(0.0, 0.0, 0.05), 0.0, 0.42, Color(0.95, 0.95, 0.92))
	slot["tunnel_words"] = Geo.add_words(root, "", Vector3(Pieces.ROAD_MIDS[0], Land.TUNNEL_H + 0.3, -Land.LENGTH * 0.5 + 0.45), 0.0, 0.6, Color(0.16, 0.16, 0.17))
	for l: Label3D in [slot["sign_words"], slot["tunnel_words"]]:
		l.set_meta("base", l.position)
	_slots.append(slot)
	_free.append(_slots.size() - 1)


func _mesh_node(parent: Node3D, node_name: String, mat: Material, shadows: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 700.0
	parent.add_child(mi)
	return mi


## Gives a place node the parts place k needs.
func _dress(slot: Dictionary, k: int) -> void:
	var part := part_at(k)
	for side: int in [1, -1]:
		var from := boundary(side, k)
		var to := boundary(side, k + 1)
		var strip := _strip(side, from, to, k)
		(slot["land"][side] as MeshInstance3D).mesh = strip["mesh"]
		(slot["props"][side] as MeshInstance3D).mesh = Pieces.props(side, from, to)
		for kind in Land.TREES:
			(slot["tree_of"]["%d|%s" % [side, kind]] as MultiMeshInstance3D).multimesh = (strip["trees"] as Dictionary).get(kind)
	(slot["lid"] as MeshInstance3D).mesh = Pieces.lid(part) if part != "" else null
	var top_trees: Dictionary = Pieces.lid_trees(part) if part != "" else {}
	for kind in Land.TREES:
		(slot["tree_of"]["0|" + kind] as MultiMeshInstance3D).multimesh = top_trees.get(kind)
	(slot["lining"] as MeshInstance3D).mesh = Pieces.lining(part) if part != "" else null
	(slot["frame"] as MeshInstance3D).mesh = Pieces.frame(part) if part == "in" or part == "out" else null
	var tunnel_words := slot["tunnel_words"] as Label3D
	tunnel_words.visible = part == "in"
	if part == "in":
		tunnel_words.text = "%s TUNNEL" % Pieces.TUNNELS[posmod(floori(float(k) / float(maxi(period(), 1))), Pieces.TUNNELS.size())].to_upper()
	# a green sign about every 700 m of open road, never in or right at a tunnel
	var signed := part == "" and posmod(k, 9) == 4 and boundary(1, k) != "mount" and boundary(1, k + 1) != "mount"
	(slot["sign"] as MeshInstance3D).visible = signed
	var sign_words := slot["sign_words"] as Label3D
	sign_words.visible = signed
	if signed:
		sign_words.text = Pieces.sign_words(k)


## Forest density (r81_forest, 0..100): how much of every batch of trees is drawn. The trees in
## a batch are in random order (r81_land.gd _trees), so drawing the first part thins evenly.
func _apply_forest() -> void:
	var share := clampf(float(AppState.get_setting("r81_forest")) / 100.0, 0.0, 1.0)
	if share == _forest_drawn:
		return
	_forest_drawn = share
	for key: String in _strips:
		for kind: String in _strips[key]["trees"]:
			var mm := _strips[key]["trees"][kind] as MultiMesh
			mm.visible_instance_count = -1 if share >= 1.0 else roundi(float(mm.instance_count) * share)


## Hands the numbers to the things that show them: the valley's depth and the season to Route
## 81's materials, the tunnel to the two roads, the far view's place and turn, the tunnel lamps'
## light on the car.
func _apply() -> void:
	var season := 1.0 if String(AppState.get_setting("r81_season")) == "fall" else 0.0
	for m: ShaderMaterial in _kit["r81"]:
		m.set_shader_parameter("alt_drop", altitude)
		m.set_shader_parameter("season", season)
	# photosensitive-safe mode: the lamps' light slides by evenly instead of in pools
	var safe := bool(AppState.get_setting("photosensitive_safe"))
	var pulse := 0.25 if safe else clampf(float(AppState.get_setting("flash_strength")), 0.25, 1.0)
	for key: String in ["road81", "road81_opp"]:
		var road := _kit[key] as ShaderMaterial
		road.set_shader_parameter("tunnel_a", tunnel_a)
		road.set_shader_parameter("tunnel_b", tunnel_b)
		road.set_shader_parameter("pulse", pulse)
	(_kit["tunnel"] as ShaderMaterial).set_shader_parameter("pulse", pulse)
	if _backdrop:
		# every region looks at another stretch of the ridges, a little turned
		var r := float(region)
		_backdrop.position = Vector3(400.0 * sin(r * 2.3), -(altitude + FLOOR_BELOW), fposmod(r * 3100.0, 9000.0) - 4500.0)
		_backdrop.rotation = Vector3(0.0, heading + 0.35 * sin(r * 1.9), 0.0)
	# the lamps' light on the car and the riders: a gentle swell as each lamp goes over (one every
	# 8 m, the same spacing as the lining's), steady in photosensitive-safe mode
	var swell := 0.0 if safe else 0.35 * pulse * sin(TAU * travel / Pieces.STEP)
	for l in _lights:
		l.visible = cover > 0.01
		l.light_energy = cover * (1.5 + swell)


## The signs' words follow the bend like the signs (Label3D is not drawn by our shaders, so
## r22_common.gdshaderinc's r22_bend is done here).
func _bend_words() -> void:
	for k: int in _placed:
		var slot: Dictionary = _slots[_placed[k]["slot"]]
		var root := slot["root"] as Node3D
		for l: Label3D in [slot["sign_words"], slot["tunnel_words"]]:
			if not l.visible:
				continue
			var base: Vector3 = l.get_meta("base")
			var d := maxf(absf(root.position.z + base.z) - 18.0, 0.0)
			l.position = base + Vector3(bend * d * d, hill * d * d, 0.0)


## Co-stream: the host tells its guests how far it has driven every few seconds; a guest eases
## onto it (or jumps, if it is far off).
func _sync(delta: float) -> void:
	if NetSession.get_role() != "host":
		return
	_sync_in -= delta
	if _sync_in <= 0.0:
		_sync_in = SYNC_EVERY
		NetSession.send_room_event("r81_travel", [travel, speed])


func _on_net_room_event(_peer_id: int, _peer_name: String, kind: String, data: Array) -> void:
	if kind != "r81_travel" or NetSession.get_role() != "guest" or data.size() < 1:
		return
	var host_travel := float(data[0])
	if not is_finite(host_travel):
		return
	if absf(host_travel - travel) > 60.0:
		travel = maxf(host_travel, START)
	else:
		travel = lerpf(travel, host_travel, 0.5)
