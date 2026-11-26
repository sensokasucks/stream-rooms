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
## Each side of the highway has an edge profile (r81_land.gd KINDS: woods, cut, drop, mount,
## field, lawn, lot, water) at every boundary between two places. A side keeps its profile for eight boundaries (640 m,
## long enough to take a view in), then rolls
## again: an overlook ("drop") with a chance set by the "How often views open up" slider
## (r81_views), a rock cut, or woods. The right side rolls at boundaries 0, 8, 16.. and the left at
## 4, 12, 20.., so the two sides never change in the same place. A place whose side starts and
## ends differently is a transition (the land blends from one to the other).
## Tunnels come every `period()` places (the Tunnels choice, r81_tunnels): the road runs into a
## rock cut, the mountain closes over it for 400 m, and it comes out the far side in a new
## region (see `region`): another stretch of the far view, another height. That is how this room
## changes between very different kinds of country.
##
## ── Countries (country(), region_of()) ──
## Every region is one kind of country (COUNTRIES), in turn, or always the one the Country
## choice names (r81_country):
##   ridge    woods, rock cuts and overlooks high on a ridge (round 1's road),
##   farm     low in a valley: crop fields with farms (r81_places.gd), small towns, gas stations,
##   river    low down too; halfway through, the road crosses a wide river on a long bridge
##            (crossing(): both sides are "water" for eight places),
##   endless  the Endless Mountains: the highest road, most of it overlook,
##   coal     the coal plateau: high and scrubby, with patch towns (some dead, one over a mine
##            fire with smoke coming out of the ground), a breaker and culm banks,
##   city     the city valley: low, an old industrial city along much of the road.
## A side that stays field, lawn or lot for all eight boundaries of its stretch gets a
## "feature" from r81_places.gd on its seven whole places (feature_at()).
## With Tunnels = Never the country by the road still changes, every NO_TUNNEL_COUNTRY places,
## through a stretch of woods; the far view stays the first region's.
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
## r81_country,
## r81_forest (how much of the trees is drawn), r81_season, r22_detail.
## route81_room.gd makes it (setup) and calls tick() every frame.

const Geo := preload("res://rooms/route22/r22_geo.gd")
const Desert := preload("res://rooms/route22/r22_desert.gd")
const Land := preload("res://rooms/route81/r81_land.gd")
const Pieces := preload("res://rooms/route81/r81_pieces.gd")
## (the desert Cruise's trip: the Speed slider's units are its, MAX_KMH)
const DesertTrip := preload("res://rooms/route22/r22_trip.gd")
const Vistas := preload("res://rooms/route81/r81_vistas.gd")
const Places := preload("res://rooms/route81/r81_places.gd")
const Billboards := preload("res://rooms/route22/r22_billboards.gd")

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
## The lamps' colours for the Streetlights choice (r81_lights): old orange sodium, cool white LED.
const LAMP := Color(1.0, 0.62, 0.25)
const LAMP_LED := Color(0.8, 0.9, 1.0)
## Places with a streetlight: the 8 before a tunnel's first place and the 8 after its last
## (LIT_BEFORE, LIT_FROM..LIT_TO, counted from the tunnel's first place). r81_road.gdshader
## draws the light on the road by the same numbers. With Tunnels = Never the same pattern
## repeats every NO_TUNNEL_PERIOD places, so the road still has lit stretches.
const LIT_BEFORE: int = 8
const LIT_FROM: int = 6
const LIT_TO: int = 13
const NO_TUNNEL_PERIOD: int = 60

## The kinds of country, in the order the tour (r81_country = "tour") drives through them.
const COUNTRIES: PackedStringArray = ["ridge", "farm", "river", "endless", "coal", "city"]
## Each country's height above the valley floor (metres): [middle, slow swing, quick swing].
## The river country is low so its bridge is not absurdly high (the river lies on the valley
## floor, FLOOR_BELOW under the lowest road); the bridge piers (r81_pieces.gd PIER_MAX_ALT)
## allow up to 320.
## (Sen, 2026-11-26: the real road is benched into the mountainsides, not on the peaks, so
## these are well below the far ridges' crests, r81_land.gd RIDGES: 280 m and up. The far
## ridges then stand at eye level and above across the valley.)
const HEIGHTS: Dictionary = {"ridge": Vector3(85.0, 40.0, 15.0), "farm": Vector3(40.0, 16.0, 7.0),
	"river": Vector3(30.0, 10.0, 4.0), "endless": Vector3(150.0, 45.0, 18.0),
	"coal": Vector3(115.0, 30.0, 14.0), "city": Vector3(40.0, 14.0, 6.0)}
## With Tunnels = Never: places per country.
const NO_TUNNEL_COUNTRY: int = 120
## A river crossing: both sides are water for boundaries mid - CROSS_HALF .. mid + CROSS_HALF
## (see crossing()), 640 m of bridge, with an overlook's falling ground before and after.
const CROSS_HALF: int = 4

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
## Valley fog 0..1 from the weather (r22_desert.gd mist; the room hands it over every frame).
var mist: float = 0.0
## 0 = under the open sky .. 1 = deep in a tunnel.
var cover: float = 0.0
## Which stretch of country this is: goes up by one in the middle of every tunnel.
var region: int = 0
## The nearest tunnel covers the road from world z = tunnel_a to tunnel_b (a > b; both 0 = none).
var tunnel_a: float = 0.0
var tunnel_b: float = 0.0

var _kit: Dictionary
var _backdrop: Node3D
var _vistas: Vistas
var _boards: Billboards                 # Route 81's own billboard set (may be null: none)
var _slots: Array[Dictionary] = []      # the place nodes, made as needed (see _make_slot)
var _free: Array[int] = []              # indexes into _slots of the ones not in use
var _placed: Dictionary = {}            # k -> {"slot": index, "look": what it was dressed as}
var _strips: Dictionary = {}            # "side|from|to|salt" -> Land.side_strip() result
## The camera's place last written to the detailed trees' materials (lod_eye; _apply()).
var _lod_eye: Vector3 = Vector3.INF
var _forest_drawn: float = -1.0         # the Forest density share last applied to the tree batches
var _lights: Array[OmniLight3D] = []    # the tunnel lamps' light on the car
var _sync_in: float = SYNC_EVERY
var _night: float = 0.0                 # 0 day .. 1 night, from the room every frame (tick)


## kit: r22_geo.gd new_kit() with r81_land.gd add_materials() done. backdrop: the far view
## (Land.build_backdrop), which this node lowers and turns. vistas: the distant views standing
## on it (r81_vistas.gd), which this node tells the region.
## boards: Route 81's billboards (r22_billboards.gd set up with the "r81_bb_" settings).
func setup(kit: Dictionary, backdrop: Node3D, vistas: Vistas = null, boards: Billboards = null) -> void:
	_kit = kit
	_backdrop = backdrop
	_vistas = vistas
	_boards = boards
	if _boards:
		_boards.pictures_changed.connect(_refill_boards)
		EventBus.setting_changed.connect(_on_board_setting_changed)
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


## How common or a shape tick changed (Room tab > Billboards): the boards in view follow at
## once. (A new folder, order or filler choice reloads the set, which ends up in
## _refill_boards by pictures_changed.)
func _on_board_setting_changed(key: String, _value: Variant) -> void:
	if key == "r81_bb_amount" or Billboards.SHAPES_81.has(key.trim_prefix("r81_bb_")):
		_refill_boards()


func _exit_tree() -> void:
	if EventBus.setting_changed.is_connected(_on_board_setting_changed):
		EventBus.setting_changed.disconnect(_on_board_setting_changed)
	if EventBus.net_room_event.is_connected(_on_net_room_event):
		EventBus.net_room_event.disconnect(_on_net_room_event)


## r22_speed in metres a second (the setting is kept in km/h, 0..MAX_KMH; the Room tab shows
## it in miles an hour).
static func _target_speed() -> float:
	return clampf(float(AppState.get_setting("r22_speed")), 0.0, DesertTrip.MAX_KMH) / 3.6


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


## The kind of country region r is: the Country choice (r81_country), or on the "tour" each
## of COUNTRIES in turn.
static func country(r: int) -> String:
	var c := String(AppState.get_setting("r81_country"))
	return c if COUNTRIES.has(c) else COUNTRIES[posmod(r, COUNTRIES.size())]


## How many places one country lasts: from the middle of one tunnel to the middle of the next,
## or NO_TUNNEL_COUNTRY without tunnels.
static func country_span() -> int:
	var p := period()
	return p if p > 0 else NO_TUNNEL_COUNTRY


## Which region boundary (or place) b lies in. With tunnels a region starts in the middle of a
## tunnel (3 places past its first), the same count as `region`.
static func region_of(b: int) -> int:
	var p := period()
	return floori(float(b - 3) / float(p)) if p > 0 else floori(float(b) / float(NO_TUNNEL_COUNTRY))


## The river crossing's part at boundary b: "water" on the bridge, "drop" on the boundary
## before and after it (the valley side falling to the river), "" anywhere else. Only river
## country has one, in the middle of its stretch (a little before the middle without tunnels,
## clear of the streetlights' places, lit_at()).
static func crossing(b: int) -> String:
	if country(region_of(b)) != "river":
		return ""
	var span := country_span()
	var mid := roundi(float(span) * 0.5) if period() > 0 else 37
	var off := absi(posmod(b, span) - mid)
	if off <= CROSS_HALF:
		return "water"
	return "drop" if off == CROSS_HALF + 1 else ""


## Which side of the highway the mountain is on in region r: +1 = our right, -1 = the left.
## The road is benched into a mountainside (r81_land.gd, "slope"): that side climbs, the other
## is the valley side with the overlooks. It swaps now and then from region to region (the
## road has gone through the mountain in the tunnel between them).
static func uphill(r: int) -> int:
	return 1 if _dice(r * 31 + 17) < 0.55 else -1


## The eight boundaries a side keeps one profile for: [the group's number, its first boundary].
## The right side's groups start at boundaries 0, 8, 16.., the left's at 4, 12, 20..
static func _group(side: int, b: int) -> Vector2i:
	var off := 0 if side > 0 else 4
	var group := floori(float(b + off) / 8.0)
	return Vector2i(group, group * 8 - off)


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
	var on_hill := side == uphill(region_of(b))
	if p <= 0 and posmod(b, NO_TUNNEL_COUNTRY) <= 1:
		# without tunnels, one kind of country hands over to the next in the woods
		return "slope" if on_hill else "woods"
	var cross := crossing(b)
	if cross != "":
		return cross
	var group := _group(side, b).x
	var roll := _dice(group * 2 + (1 if side > 0 else 0))
	var v := views()
	# each country's shares of the roll, in the order they are tried; what is left is woods
	var shares: Array = []
	match country(region_of(b)):
		"farm":
			shares = [["field", 0.46], ["lawn", 0.22], ["lot", 0.1], ["drop", v * 0.12]]
		"river":
			shares = [["drop", v * 0.6], ["field", 0.14], ["lot", 0.06], ["cut", 0.1]]
		"endless":
			shares = [["drop", v * 0.75], ["cut", 0.2], ["lot", 0.04]]
		"coal":
			shares = [["lot", 0.36], ["drop", v * 0.35], ["cut", 0.16]]
		"city":
			shares = [["lot", 0.62], ["lawn", 0.1], ["drop", v * 0.1]]
		_:
			shares = [["drop", v * 0.5], ["cut", 0.28], ["lot", 0.05]]
	# The mountain side has no overlooks: where the roll says one, and wherever nothing else
	# stands, it is the wooded mountainside. The valley side has no rock cuts (there is no
	# on_hill to cut into), and gets the overlooks of both sides, so "How often views open up"
	# still means about what it says.
	for share: Array in shares:
		var kind := String(share[0])
		var part := float(share[1])
		if kind == "drop" and not on_hill:
			part = minf(part * 1.7, 0.9)
		if kind == "cut" and not on_hill:
			continue
		roll -= part
		if roll < 0.0:
			return "slope" if kind == "drop" and on_hill else kind
	return "slope" if on_hill else "woods"


## What people built on `side` of place k: [a r81_places.gd feature, which of its places this
## is (0..6)], or [] for none. A stretch has one when the side is field, lawn or lot at all
## eight of its boundaries (so no tunnel, river or country's end cuts into it).
static func feature_at(side: int, k: int) -> Array:
	var g := _group(side, k)
	var i := k - g.y
	var kind := boundary(side, g.y)
	if i > 6 or not (kind == "field" or kind == "lawn" or kind == "lot"):
		return []
	for b in range(g.y + 1, g.y + 8):
		if boundary(side, b) != kind:
			return []
	var roll := _dice(g.x * 2 + (1 if side > 0 else 0) + 7919)
	match kind:
		"field":
			# (one stretch of fields in four is only fields)
			if roll > 0.75:
				return []
			return ["farm" if roll < 0.45 else "amish", i]
		"lawn":
			return ["town_cozy" if roll < 0.5 else "town_historic", i]
	# a lot: what stands on it depends on the country
	match country(region_of(g.y)):
		"coal":
			if roll < 0.3:
				return ["coal_town", i]
			if roll < 0.52:
				return ["dead_town", i]
			if roll < 0.72:
				return ["mine_fire", i]
			return ["breaker" if roll < 0.9 else "old_station", i]
		"city":
			return ["city" if roll < 0.8 else "truck_stop", i]
	return ["gas" if roll < 0.45 else ("truck_stop" if roll < 0.75 else "old_station"), i]


## Whether place k is (or is turning into) the river bridge.
static func bridge_at(k: int) -> bool:
	return boundary(1, k) == "water" or boundary(1, k + 1) == "water"


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
func tick(delta: float, night: float) -> void:
	_night = night
	if _boards:
		_boards.tick(night)
	speed = move_toward(speed, _target_speed(), delta * 3.0)       # about 3 m/s² either way
	travel += speed * delta
	_work_out()
	_place()
	_apply()
	_bend_words()
	_sync(delta)


## Everything that follows from travel alone: the curve, the heading, the height, the tunnel.
func _work_out() -> void:
	# (Curves = the sideways bends, r22_curves; Hills = the rises and dips, r22_hills)
	var curves := clampf(float(AppState.get_setting("r22_curves")), 0.0, 1.0)
	var hills := clampf(float(AppState.get_setting("r22_hills")), 0.0, 1.0)
	# slow waves along the road (the same on every PC for the same travel)
	bend = curves * MAX_BEND * (0.7 * sin(travel / 900.0) + 0.3 * sin(travel / 370.0 + 1.3))
	hill = hills * MAX_HILL * (0.6 * sin(travel / 640.0 + 0.4) + 0.4 * sin(travel / 290.0 + 2.1))
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
	# the height: this country's (HEIGHTS), in two slow waves that start somewhere else in every
	# region (the jump happens in the dark, in the middle of the tunnel)
	var h: Vector3 = HEIGHTS[country(region)]
	if p <= 0:
		# no tunnel to hide a jump: ease to the next country's height over its last fifth
		var at := here / float(NO_TUNNEL_COUNTRY)
		var r0 := floori(at)
		h = (HEIGHTS[country(r0)] as Vector3).lerp(HEIGHTS[country(r0 + 1)], smoothstep(0.8, 1.0, at - float(r0)))
	altitude = h.x + h.y * sin(travel / 1900.0 + float(region) * 2.0) + h.z * sin(travel / 730.0 + 1.0)


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
			if _boards:
				_boards.clear(_slots[gone]["boards"])
			_free.append(gone)
			_placed.erase(k)
	var low := Desert.detail_level() == "low"
	var tree_reach := TREES_NEAR_LOW if low else TREES_NEAR
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
		# The Low look draws the low-poly trees ("near", "far") and the Detailed look the
		# Blender ones (the "cards" groups); the tunnels' tops (no group) show on both. A
		# strip without the Blender trees (trees.glb missing) keeps its low-poly "far" trees.
		for t: MultiMeshInstance3D in slot["trees"]:
			var group := String(t.get_meta("group", ""))
			var shown := true
			if group != "":
				shown = bool(t.get_meta("detailed", false)) != low
				if group == "far" and not low and not Land.card_levels_ready():
					shown = true
			t.visible = near and t.multimesh != null and shown
	_apply_forest()


## How many places the streetlights' pattern repeats after (the tunnels' period when there are
## tunnels), and whether place k has a streetlight.
static func street_period() -> int:
	var p := period()
	return p if p > 0 else NO_TUNNEL_PERIOD


static func lit_at(k: int) -> bool:
	var sp := street_period()
	var j := posmod(k, sp)
	return j >= sp - LIT_BEFORE or (j >= LIT_FROM and j <= LIT_TO)


## Whether a power line crosses the road at place k: now and then, where both sides are plain
## woods from end to end and there is no tunnel.
static func wires_at(k: int) -> bool:
	if posmod(k, 11) != 5 or part_at(k) != "":
		return false
	for side: int in [-1, 1]:
		var kind := boundary(side, k)
		if (kind != "woods" and kind != "slope") or boundary(side, k + 1) != kind:
			return false
	return true


## What place k is, in one line: both sides' profiles, the tunnel part, which variant of the land.
func _look(k: int) -> String:
	var built := ""
	for side: int in [-1, 1]:
		var f := feature_at(side, k)
		if not f.is_empty():
			built += " %s%d%s" % [f[0], f[1], "R" if side > 0 else "L"]
	return "%s>%s / %s>%s / %s / %d%s" % [boundary(-1, k), boundary(-1, k + 1), boundary(1, k), boundary(1, k + 1), part_at(k), posmod(k, 3), (" lit" if lit_at(k) else "") + (" wires" if wires_at(k) else "") + built]


## One side's land and trees for a place (built the first time it is needed, then kept).
## Steady stretches come in three variants (their bumps and trees differ), picked by k.
func _strip(side: int, from: String, to: String, k: int) -> Dictionary:
	var salt := 0
	if from != "mount" and to != "mount":
		salt = (10 + posmod(k, 3)) if from == to else 1
	# (a power line's place: the variant with the corridor cut through its trees)
	if wires_at(k):
		salt = Land.WIRE_SALT
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
	var slot := {"root": root, "trees": [] as Array[MultiMeshInstance3D], "land": {}, "props": {}, "built": {}, "tree_of": {}}
	for side: int in [1, -1]:
		var tag := "R" if side > 0 else "L"
		slot["land"][side] = _mesh_node(root, "Land" + tag, _kit["land"], true)
		slot["props"][side] = _mesh_node(root, "Props" + tag, _kit["prop"], true)
		slot["built"][side] = _mesh_node(root, "Places" + tag, _kit["prop"], true)
		# one node per group of trees (Land._trees) and kind; "cards" meshes bring their own
		# materials, the low-poly ones all wear kit["trees"]
		# (a detailed group has a node per kind and level of detail: Land.group_names())
		for group: String in Land.tree_groups():
			var detailed := not Land.group_levels(group).is_empty()
			for kind in Land.group_names(group):
				var t := MultiMeshInstance3D.new()
				t.name = "Trees%s_%s_%s" % [tag, group, kind]
				if not detailed:
					t.material_override = _kit["trees"]
				else:
					# Each tree picks its level in the shaders by its own distance; this only
					# lets Redot skip a whole place's full or light trees when the place is far
					# outside the level's band. The range is measured to the strip's middle,
					# and the tunnel cameras never get near a strip, so the pad is generous.
					var band := Land.group_band(group, Land.card_level(kind))
					t.visibility_range_begin = maxf(0.0, band.x - Land.CARD_RANGE_PAD)
					t.visibility_range_end = band.y + Land.CARD_RANGE_PAD
					t.set_meta("detailed", true)
				t.set_meta("group", group)
				# the shaders move things a long way (the bend, the valley): never cull early
				t.extra_cull_margin = 700.0
				root.add_child(t)
				(slot["trees"] as Array[MultiMeshInstance3D]).append(t)
				slot["tree_of"]["%d|%s|%s" % [side, group, kind]] = t
	# the mine fire's smoke: up to four plumes a place (two a side), parked until needed
	slot["smoke"] = [] as Array[CPUParticles3D]
	for n in 4:
		var plume := _smoke_plume()
		plume.name = "Smoke%d" % n
		root.add_child(plume)
		(slot["smoke"] as Array[CPUParticles3D]).append(plume)
	var boards := Node3D.new()
	boards.name = "Boards"
	root.add_child(boards)
	slot["boards"] = boards
	slot["lid"] = _mesh_node(root, "MountainTop", _kit["land"], true)
	for kind in Land.TREES:
		var t := MultiMeshInstance3D.new()
		t.name = "TreesTop_" + kind
		t.material_override = _kit["trees"]
		t.extra_cull_margin = 700.0
		root.add_child(t)
		(slot["trees"] as Array[MultiMeshInstance3D]).append(t)
		slot["tree_of"]["0|" + kind] = t
	# (the power line wears the tree material: see Pieces.power_line)
	var wires := _mesh_node(root, "PowerLine", _kit["trees"], true)
	wires.mesh = Pieces.power_line("woods", "woods")
	slot["wires"] = wires
	# the river bridge: parapets and girders, and the piers, which wear the tree material for
	# the same reason as the power line (they reach down into the valley)
	slot["bridge"] = _mesh_node(root, "Bridge", _kit["prop"], true)
	slot["piers"] = _mesh_node(root, "BridgePiers", _kit["trees"], true)
	var pole := _mesh_node(root, "LightPole", _kit["prop"], true)
	pole.mesh = Pieces.light_pole()
	slot["pole"] = pole
	var heads := _mesh_node(root, "LightHeads", _kit["street_a"], false)
	heads.mesh = Pieces.light_heads()
	slot["heads"] = heads
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


## One plume of the mine fire's smoke: slow grey-white puffs rising and leaning with the
## wind, drawn with Route 22's dust wisp (r22_dust.gdshader). Its particles live in the
## plume's own space so they slide past with their place (the land moves, not the car).
func _smoke_plume() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.local_coords = true
	p.amount = 26
	p.lifetime = 11.0
	p.preprocess = 11.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 1.2
	p.direction = Vector3(0.25, 1.0, 0.1)
	p.spread = 9.0
	p.gravity = Vector3(0.12, 0.05, 0.0)
	p.initial_velocity_min = 1.6
	p.initial_velocity_max = 2.6
	p.angle_min = 0.0
	p.angle_max = 360.0
	p.scale_amount_min = 3.5
	p.scale_amount_max = 6.0
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.25))
	grow.add_point(Vector2(1.0, 1.0))
	p.scale_amount_curve = grow
	var fade := Gradient.new()
	fade.set_color(0, Color(0.78, 0.78, 0.76, 0.0))
	fade.add_point(0.12, Color(0.78, 0.78, 0.76, 0.5))
	fade.set_color(fade.get_point_count() - 1, Color(0.85, 0.85, 0.85, 0.0))
	p.color_ramp = fade
	var quad := QuadMesh.new()
	quad.material = Geo.dust_material(Vector2.ONE, 0.7)
	p.mesh = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.extra_cull_margin = 700.0
	p.visible = false
	p.emitting = false
	return p


## Gives a place node the parts place k needs.
func _dress(slot: Dictionary, k: int) -> void:
	var part := part_at(k)
	for side: int in [1, -1]:
		var from := boundary(side, k)
		var to := boundary(side, k + 1)
		var strip := _strip(side, from, to, k)
		(slot["land"][side] as MeshInstance3D).mesh = strip["mesh"]
		(slot["props"][side] as MeshInstance3D).mesh = Pieces.props(side, from, to)
		var f := feature_at(side, k)
		(slot["built"][side] as MeshInstance3D).mesh = null if f.is_empty() else Places.build(String(f[0]), int(f[1]), side)
		for group: String in strip["trees"]:
			for kind in Land.group_names(group):
				(slot["tree_of"]["%d|%s|%s" % [side, group, kind]] as MultiMeshInstance3D).multimesh = (strip["trees"][group] as Dictionary).get(kind)
	(slot["wires"] as MeshInstance3D).visible = wires_at(k)
	if wires_at(k):
		# (the pylons stand on the land's own profiles: mountainside on one side)
		(slot["wires"] as MeshInstance3D).mesh = Pieces.power_line(boundary(-1, k), boundary(1, k))
	if _boards:
		_boards.fill(slot["boards"], k, board_slots(k))
	var vents: Array[Vector3] = []
	for side: int in [1, -1]:
		var f := feature_at(side, k)
		if not f.is_empty():
			vents.append_array(Places.smoke_spots(String(f[0]), int(f[1]), side))
	var plumes: Array[CPUParticles3D] = slot["smoke"]
	for n in plumes.size():
		plumes[n].visible = n < vents.size()
		plumes[n].emitting = n < vents.size()
		if n < vents.size():
			plumes[n].set_meta("base", vents[n])
			plumes[n].position = vents[n]
	var over := bridge_at(k)
	(slot["bridge"] as MeshInstance3D).mesh = Pieces.bridge(boundary(1, k), boundary(1, k + 1)) if over else null
	(slot["piers"] as MeshInstance3D).mesh = Pieces.bridge_piers(boundary(1, k), boundary(1, k + 1)) if over else null
	# a streetlight (every other one wears the second lamp material, for the "Mixed" choice)
	var lit := lit_at(k)
	(slot["pole"] as MeshInstance3D).visible = lit
	(slot["heads"] as MeshInstance3D).visible = lit
	(slot["heads"] as MeshInstance3D).material_override = _kit["street_a" if posmod(k, 2) == 0 else "street_b"]
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
	# (nor on the bridge: it stands on the ground beside the shoulder)
	var signed := part == "" and posmod(k, 9) == 4 and boundary(1, k) != "mount" and boundary(1, k + 1) != "mount" and not over
	(slot["sign"] as MeshInstance3D).visible = signed
	var sign_words := slot["sign_words"] as Label3D
	sign_words.visible = signed
	if signed:
		sign_words.text = Pieces.sign_words(k)


## Where billboards can stand at place k, for r22_billboards.gd fill(): [[foot (the place's
## own metres), side, the shapes that fit there], ...]. A tall board in the grass in front of
## woods on our side; any shape out in a field, or at the quiet end of a town or a lot, on
## either side (never where r81_places.gd has built something: see the place numbers there).
static func board_slots(k: int) -> Array:
	var out: Array = []
	if part_at(k) != "" or wires_at(k):
		return out
	for side: int in [1, -1]:
		var kind := boundary(side, k)
		if kind != boundary(side, k + 1):
			continue
		var u := 0.0
		var fit: Array = []
		var f := feature_at(side, k)
		var i := -1 if f.is_empty() else int(f[1])
		match kind:
			"woods", "slope":
				if side > 0:
					u = 8.5
					fit = ["monopole", "classic"]
			"field":
				if i == -1 or i == 0 or i == 3 or i == 6:
					u = 27.0
					fit = ["classic", "monopole", "wooden", "trailer", "barn"]
			"lawn", "lot":
				if i == -1 or i == 0 or i == 6:
					u = 17.0
					fit = ["classic", "monopole", "wooden", "trailer"]
		if fit.is_empty():
			continue
		var x := (Land.ROAD_R + u) if side > 0 else (Land.OPP_L - u)
		out.append([Vector3(x, Land.edge(kind, u, 0.5, 0.0)[0], -Land.LENGTH * 0.55), float(side), fit])
	return out


## The billboard pictures changed: put boards on the places in view again.
func _refill_boards() -> void:
	for k: int in _placed:
		_boards.fill(_slots[_placed[k]["slot"]]["boards"], k, board_slots(k))


## The car's spot in the far view (r81_land.gd build_backdrop), in the far view's own metres,
## when region r starts: midway between the two nearest ridges, somewhere else along them in
## every region so each looks at other crests and gaps. r81_vistas.gd lays its views out
## round this spot.
static func region_spot(r: int) -> Vector3:
	return Vector3(0.0, 0.0, fposmod(float(r) * 3100.0, 9000.0) - 4500.0)


## Forest density (r81_forest, 0..100): how much of every batch of trees is drawn. The trees in
## a batch are in random order (r81_land.gd _trees), so drawing the first part thins evenly.
func _apply_forest() -> void:
	var share := clampf(float(AppState.get_setting("r81_forest")) / 100.0, 0.0, 1.0)
	if share == _forest_drawn:
		return
	_forest_drawn = share
	for key: String in _strips:
		for group: String in _strips[key]["trees"]:
			for kind: String in _strips[key]["trees"][group]:
				var mm := _strips[key]["trees"][group][kind] as MultiMesh
				mm.visible_instance_count = -1 if share >= 1.0 else roundi(float(mm.instance_count) * share)


## Hands the numbers to the things that show them: the valley's depth and the season to Route
## 81's materials, the tunnel to the two roads, the far view's place and turn, the tunnel lamps'
## light on the car.
func _apply() -> void:
	var season := 1.0 if String(AppState.get_setting("r81_season")) == "fall" else 0.0
	# (the trees' sway: the same number r22_desert.gd gives its own plants from the Wind slider)
	var wind := 0.4 + 2.2 * clampf(float(AppState.get_setting("r22_wind")), 0.0, 1.0)
	for m: ShaderMaterial in _kit["r81"]:
		m.set_shader_parameter("alt_drop", altitude)
		m.set_shader_parameter("season", season)
		m.set_shader_parameter("wind", wind)
	# the detailed trees' levels of detail follow the camera in use (only written when it moved)
	var cam := get_viewport().get_camera_3d()
	if cam and not cam.global_position.is_equal_approx(_lod_eye):
		_lod_eye = cam.global_position
		for m: ShaderMaterial in _kit["r81_lod"]:
			m.set_shader_parameter("lod_eye", _lod_eye)
	# photosensitive-safe mode: the lamps' light slides by evenly instead of in pools
	var safe := bool(AppState.get_setting("photosensitive_safe"))
	var pulse := 0.25 if safe else clampf(float(AppState.get_setting("flash_strength")), 0.25, 1.0)
	# The Streetlights choice: colour A is the even-numbered poles' and the tunnels', colour B
	# the odd poles' (only "Mixed" makes them differ). "Off" darkens the poles, not the tunnels.
	var lights := String(AppState.get_setting("r81_lights"))
	var col_a := LAMP_LED if lights == "led" else LAMP
	var col_b := LAMP_LED if lights == "led" or lights == "mixed" else LAMP
	var street_on := 0.0 if lights == "off" else _night
	# The road shader only gets the wrapped travel (r22_desert.gd). What the wrapping took
	# off, kept small by wrapping it at two rounds of the streetlights' pattern (two, because
	# "Mixed" goes by even and odd places), lets it work out the place it is drawing.
	var route_base := fposmod(travel - fposmod(travel, Desert.TRAVEL_WRAP), Land.LENGTH * 2.0 * float(street_period()))
	for key: String in ["road81", "road81_opp"]:
		var road := _kit[key] as ShaderMaterial
		road.set_shader_parameter("tunnel_a", tunnel_a)
		road.set_shader_parameter("tunnel_b", tunnel_b)
		road.set_shader_parameter("pulse", pulse)
		road.set_shader_parameter("lamp_color", col_a)
		road.set_shader_parameter("street_period", float(street_period()))
		road.set_shader_parameter("street_a", col_a)
		road.set_shader_parameter("street_b", col_b)
		road.set_shader_parameter("street_on", street_on)
		road.set_shader_parameter("route_base", route_base)
	(_kit["street_a"] as ShaderMaterial).set_shader_parameter("lamp_color", col_a)
	(_kit["street_b"] as ShaderMaterial).set_shader_parameter("lamp_color", col_b)
	(_kit["street_a"] as ShaderMaterial).set_shader_parameter("glow", street_on)
	(_kit["street_b"] as ShaderMaterial).set_shader_parameter("glow", street_on)
	(_kit["tunnel"] as ShaderMaterial).set_shader_parameter("lamp_color", col_a)
	(_kit["tunnel"] as ShaderMaterial).set_shader_parameter("pulse", pulse)
	(_kit["vista"] as ShaderMaterial).set_shader_parameter("steady", 1.0 if safe else 0.0)
	if _backdrop:
		# The far view is turned round the car (not round its own middle, which would swing
		# the ridges sideways by kilometres): the car's spot in it stays under the car.
		var spot := region_spot(region)
		var turned := Basis(Vector3.UP, heading)
		# It creeps back a tenth as fast as the road goes by, along the ridges, so a town in
		# the valley is ahead when a region starts and behind when it ends. (Without tunnels
		# there are no regions to start anew in: it sways slowly to and fro instead.)
		var p := period()
		var crept := 0.1 * (travel - (float(region * p) + 3.0) * Land.LENGTH) if p > 0 else 900.0 * sin(travel / 7000.0)
		var here := spot + Vector3(0.0, 0.0, -crept)
		_backdrop.transform = Transform3D(turned, Vector3(0.0, -(altitude + FLOOR_BELOW), 0.0) - turned * here)
		# morning mist lies in the hollows of some regions (r81_backdrop.gdshader)
		(_kit["backdrop"] as ShaderMaterial).set_shader_parameter("mist", maxf(0.6 if posmod(region, 3) == 1 else 0.12, mist))
		if _vistas:
			_vistas.show_region(region, spot)
	# the lamps' light on the car and the riders: a gentle swell as each lamp goes over (one every
	# 8 m, the same spacing as the lining's), steady in photosensitive-safe mode
	var swell := 0.0 if safe else 0.35 * pulse * sin(TAU * travel / Pieces.STEP)
	# ...and outside at night, a streetlight's as the car passes under it (the pole stands
	# halfway along its place; steady at half strength in photosensitive-safe mode)
	var here := floori(travel / Land.LENGTH)
	var from_pole := fposmod(travel, Land.LENGTH) - Land.LENGTH * 0.5
	var under := 0.0
	if lit_at(here) and cover < 0.01:
		under = street_on * (0.5 if safe else exp(-from_pole * from_pole / 900.0))
	for l in _lights:
		l.visible = cover > 0.01 or under > 0.01
		l.light_color = col_a if cover > 0.01 or posmod(here, 2) == 0 else col_b
		l.light_energy = cover * (1.5 + swell) + under * 1.2


## The signs' words and the mine fire's smoke follow the bend like the land (neither is drawn
## by our shaders, so r22_common.gdshaderinc's r22_bend is done here).
func _bend_words() -> void:
	for k: int in _placed:
		var slot: Dictionary = _slots[_placed[k]["slot"]]
		var root := slot["root"] as Node3D
		var movers: Array = [slot["sign_words"], slot["tunnel_words"]]
		movers.append_array(slot["smoke"])
		for l: Node3D in movers:
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
