extends RefCounted
## Route 81's land: the shapes of the ground beside the highway, the trees on it, the highway
## strips, the far ridges, and the materials for all of them.
## Used by r81_trip.gd (which strings the land together as the car drives) and r81_pieces.gd
## (tunnels, bridges, signs). Like Route 22's kit (rooms/route22/r22_geo.gd, which this borrows
## the mesh builder and the shared-uniform list from), nothing here keeps state, and everything
## is built from fixed seeds so every PC in a co-stream builds the same land.
##
## ── How the land is put together ──
## The road is cut into places of LENGTH (80 m), like Route 22's Cruise. Unlike the desert, the
## ground here is not flat, so each place gets a strip of land on its left and one on its right,
## out to REACH metres. A strip's cross-section is one of a few "edge profiles" (KINDS):
##   woods   a ditch, then forest on gently rising ground,
##   cut     a blasted rock wall close to the road, forest on the hill above it,
##   drop    a guardrail, then the ground falls away into the valley (the overlook side),
##   mount   the mountain a tunnel goes through: solid above the road,
##   field   farmland: a ditch, a wire fence (r81_places.gd), then flat crop fields in strips
##           with a hedgerow of trees and a woodlot far out,
##   lawn    flat mown ground where a town or a gas station stands (r81_places.gd), with lines
##           of street trees,
##   water   a river crossing: no ground at all beside the road (it is a bridge, r81_pieces.gd
##           bridge()); the land is the river's bed, far below.
## A strip has a profile where it starts and one where it ends, and blends between the two
## along its length (side_mesh(from, to)), so any strip can follow any strip that ends the way
## it starts. That is how a rock cut opens into an overlook, or the drop swaps sides.
## At a strip's two ends the shape depends on the profile alone (the random bumps fade to zero
## there), which is what makes the seams match.
##
## ── The valley and the mountainside ──
## Every corner of the land has a "depth" (0 = stays at road height .. 1 = the valley floor).
## The shaders lower it by depth * altitude (r81_common.gdshaderinc), and the altitude is the
## road's true height above the valley floor (r81_trip.gd HEIGHTS: about 25 m in a farm valley,
## 200 m and more in the Endless Mountains), so the same strip is a low bank down to the fields
## in a valley and a long forested fall on a mountain. Trees carry the depth of the ground they
## stand on. At REACH every falling side is exactly on the valley floor, where the far view
## (build_backdrop) carries on.
## Each side also has a `climb` (0..1, r81_trip.gd climb()): Route 81 mostly runs along the side
## of a mountain or at its foot, not on its top (Sen, round 5), so on a climbing side the land
## does not fall to the valley but rises behind the woods, the rock cut or the fields to a crest
## CLIMB_H above the road (mountain()). The other side falls away, and that is where the views
## are. In a valley country both sides may fall: the road runs a little above the valley floor.
## Only an overlook falls away right at the guardrail; woods, a rock cut or a tunnel's mountain
## stand between the road and the fall. Because all profiles agree far out (on the valley floor,
## or on the mountain), a place where one turns into another is a hillside, never a wall across
## the view.
##
## Across the road (X, metres; 0 = the dashed line between our two lanes, +X = our right):
##   our road ROAD_L..ROAD_R, the grass median to OPP_R, the other direction's road to OPP_L.
## Along it: Z from 0 (a place's start) to -LENGTH, the way the car drives.

const Geo := preload("res://rooms/route22/r22_geo.gd")
const TEX := "res://rooms/route81/textures/"
const TERRAIN_SHADER := preload("res://rooms/route81/r81_terrain.gdshader")
const TREE_SHADER := preload("res://rooms/route81/r81_tree.gdshader")
const ROAD_SHADER := preload("res://rooms/route81/r81_road.gdshader")
const TUNNEL_SHADER := preload("res://rooms/route81/r81_tunnel.gdshader")
const BACKDROP_SHADER := preload("res://rooms/route81/r81_backdrop.gdshader")
const FOLIAGE_SHADER := preload("res://rooms/route81/r81_foliage.gdshader")
const LAMP_SHADER := preload("res://rooms/route81/r81_lamp.gdshader")
const VISTA_SHADER := preload("res://rooms/route81/r81_vista.gdshader")
const BARK_SHADER := preload("res://rooms/route81/r81_bark.gdshader")
const IMPOSTOR_SHADER := preload("res://rooms/route81/r81_impostor.gdshader")
## The campfire's Blender trees (rooms/campfire/models/trees.glb, read through
## campfire_forest.gd): the detailed trees' meshes at two levels of detail, the far trees'
## pictures and the twig photos. Route 81 keeps no copy: a new export of trees.glb shows up
## here by itself. (Sen, 2026-11-26: these trees are the ones to use from now on.)
const CampForest := preload("res://rooms/campfire/campfire_forest.gd")
## The campfire's older code-built trees: only the stand-in when trees.glb does not load.
const CampTrees := preload("res://rooms/campfire/campfire_trees.gd")
const CAMP_TEX := "res://rooms/campfire/textures/"

## A place's length along the road, metres (the same as Route 22's pieces).
const LENGTH: float = 80.0
## Our road's paved edges: lanes are 3.6 m (lines at ±3.7), a narrow left shoulder, a wide right one.
const ROAD_L: float = -5.0
const ROAD_R: float = 6.8
## The other direction's road, across a 14 m grass median: its near edge, the dashed line
## between its lanes, and its far edge (it is our road turned round, so its wide shoulder is far left).
const OPP_R: float = -19.0
const OPP_C: float = -24.0
const OPP_L: float = -30.8
## How far the land reaches from the road's edge, metres.
const REACH: float = 900.0
## The edge profiles (see the top of the file).
const KINDS: PackedStringArray = ["woods", "cut", "drop", "mount", "field", "lawn", "lot", "water"]
## Fields and lawns are flat and stay at road height out to this far from the road (so farms,
## towns and gas stations can stand on them: r81_places.gd); beyond it they fall to the valley
## like everything else.
const FLAT_REACH: float = 230.0
## Under a bridge the ground is the river's bed: on the valley floor (depth 1, so the shader
## lowers it by the whole altitude; the mesh itself keeps it at road height).
const WATER_Y: float = 0.0
## Tunnels: the roof's height over the road, how much higher the mountain gets behind the
## tunnel mouth, and how far outside the paved edge the mountain's rock starts. The tunnel's
## walls stand 0.55 m outside the paved edge (r81_pieces.gd HALF_W): the rock keeps 0.65 m
## clear of them, because the road's bend moves the lining's corners (every 8 m) and the
## land's (every 5 m) along slightly different curves, and with only 5 cm between them the
## rock showed through the tiles on a curve (Sen, round 5).
const TUNNEL_H: float = 9.0
const MOUNT_RISE: float = 42.0
const TRENCH: float = 1.2
## A climbing side's mountain (mountain()): how high it gets above the road far out, metres,
## and how far from where it starts it takes to get most of the way (the slope eases off
## towards the crest).
const CLIMB_H: float = 250.0
const CLIMB_L: float = 300.0
## Distances from the paved edge (metres) where the land mesh has a line of corners: close
## together near the road, where the ditch, the rock face and the guardrail edge are, and
## further and further apart out to REACH. (1.15 and 1.2: the tunnel's rock face, TRENCH.)
const U_LIST: PackedFloat32Array = [0.0, 0.55, 1.15, 1.2, 1.5, 2.3, 3.0, 3.8, 4.5, 5.5, 6.5, 7.5, 8.5, 9.5, 11.0, 13.0, 15.0,
	18.0, 21.0, 25.0, 30.0, 36.0, 44.0, 54.0, 66.0, 80.0, 98.0, 120.0, 150.0, 190.0, 240.0, 300.0, 380.0, 480.0, 600.0, 740.0, 900.0]
## Rows of corners along a place: one every 5 m.
const ROW_STEP: float = 5.0
## The far land's coarse strips (side_strip(... coarse = true): the places past r81_trip.gd's
## AHEAD and BEHIND, out to FAR_AHEAD / FAR_BEHIND there, Sen round 6: draw the land further).
## Far fewer corners across and along: only the shapes that still show from a kilometre off.
## Keep 0, 1.15, 1.2 and REACH (the tunnel's rock face and the land's edge) and the median's
## TRENCH columns, so a far strip meets the next one and the road the same way a near one does.
const U_LIST_FAR: PackedFloat32Array = [0.0, 1.15, 1.2, 4.5, 12.0, 30.0, 60.0, 110.0, 180.0, 280.0, 420.0, 600.0, 900.0]
const ROW_STEP_FAR: float = 20.0
## The tree kinds, and how tall each stands at scale 1 (metres).
const TREES: PackedStringArray = ["oak", "maple", "pine"]
## Trees stand from the edge of the woods out to this far from the road; past it the land's
## shader paints the canopy (r81_terrain.gdshader).
const TREE_REACH: float = 300.0
## The Detailed look's trees (the campfire's Blender trees, card_mesh()): their kinds. Every
## tree on the Detailed look is one of these, out to TREE_REACH (Sen, round 5: the low-poly
## trees behind the first rows showed). They come in two groups: the ones nearer than
## CARD_REACH to the road's edge ("cards", all three levels of detail) and the ones further
## out ("cards2"), which no camera beside the road gets near enough for the full tree, so they
## only have the light level and the far picture.
const CARD_KINDS: PackedStringArray = ["oak", "maple", "birch", "fir", "pine"]
const CARD_REACH: float = 46.0
## Every detailed tree is drawn at one of three levels of detail, picked by its distance from
## the camera (the campfire's scheme, campfire_forest.gd): the full tree, a light one (no small
## branches, fewer and bigger leaf cards) and, far off, a picture of it that turns to the
## camera. Each level is its own MultiMesh per kind, named the kind plus one of these endings
## (card_names()); the shaders fold away the trees outside the level's band (CARD_BANDS).
const CARD_LEVELS: PackedStringArray = ["", "_light", "_far"]
## Each level's band, metres from the camera [from, to]. Further out than the campfire's
## (26 and 52 m there): the car passes trees at 20 to 30 m a second, and at the campfire's
## distances the changes came too often and too close to be missed (Sen, round 5). The
## first number of the far picture's band must stay above CARD_REACH plus the road's width,
## so a tree in "cards2" (no full level) is never near enough to want one. They travel in
## each tree's custom data (.b = from, .a = to; half floats in the OpenGL renderer, so keep
## them below 65000).
const CARD_BANDS: Array[Vector2] = [Vector2(0.0, 55.0), Vector2(55.0, 140.0), Vector2(140.0, 60000.0)]
## Metres over which two levels share a tree and dissolve into each other (the campfire's is 8;
## a little longer here, as everything is further out).
const CARD_FADE: float = 14.0
## How much wider than its band a level's node is shown (r81_trip.gd sets the nodes' visibility
## range with it, so the full and light meshes of far places are skipped outright): half the
## diagonal of the strip the group's trees stand on (80 m by CARD_REACH for "cards", by
## TREE_REACH - CARD_REACH for "cards2"), plus half the fade.
const CARD_RANGE_PAD: float = 52.0
const CARD2_RANGE_PAD: float = 142.0
## A power line's place (r81_trip.gd wires_at) uses this strip variant (the `salt` of
## side_strip; the left side's is 50 more, like every variant): a corridor WIRE_CUT metres wide
## is kept clear of trees across the middle of the place, where the line crosses the road.
const WIRE_SALT: int = 30
const WIRE_CUT: float = 34.0

static var _noise: FastNoiseLite
static var _tree_meshes: Dictionary = {}
# The detailed trees' meshes carry their materials, which belong to one room's kit: both are
# made anew by add_materials().
static var _card_meshes: Dictionary = {}
static var _card_mats: Dictionary = {}
# The Blender trees' meshes in this room's materials, {species: [full, light]} (CampForest.meshes);
# empty until first asked for, and when trees.glb is missing.
static var _card_kit: Dictionary = {}
static var _card_kit_read: bool = false
## Goes up by one every time add_materials() makes a new room's materials: r81_pieces.gd keeps
## its tunnel-top Blender trees under this number, so a room loaded again never gets trees that
## wear the last room's materials.
static var kit_serial: int = 0


static func _n() -> FastNoiseLite:
	if _noise == null:
		_noise = FastNoiseLite.new()
		_noise.seed = 8181
		_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_noise.frequency = 1.0
		_noise.fractal_octaves = 3
	return _noise


## Bumps that depend on the distance from the road only (the same along the whole road, so
## they are the same on both sides of a seam). -1..1.
static func _nx(u: float, salt: float) -> float:
	return _n().get_noise_2d(u * 0.012, salt * 7.3)


## Bumps that differ from strip to strip (salt) and along it (zt 0..1). -1..1. Callers fade
## them out at the strip's ends.
static func _nz(u: float, zt: float, salt: float) -> float:
	return _n().get_noise_3d(u * 0.02, zt * 2.2, salt * 3.7 + 11.0)


# ── The edge profiles ────────────────────────────────────────
## The overlook's depth at u metres from the paved edge: 0 at the guardrail (3 m) .. 1 at REACH,
## falling fastest near the road: about a seventh of the way down by the foot of the mown bank
## (43 m), so on a high road the trees start well below the guardrail and leave the view open.
static func _drop_depth(u: float) -> float:
	var t := clampf((u - 3.0) / (REACH - 3.0), 0.0, 1.0)
	return 1.0 - pow(1.0 - t, 3.5)


## The gentler fall every other profile ends on, far out (0 at the road .. 1 at REACH).
static func _fall_depth(u: float) -> float:
	var t := clampf((u - 3.0) / (REACH - 3.0), 0.0, 1.0)
	return 1.0 - pow(1.0 - t, 2.2)


## The depth of a profile at u on a side that falls to the valley: an overlook's from the
## guardrail on, a field's, a lawn's or a lot's from FLAT_REACH, any other's only from about
## 40 m out (their first 40 m stay at road height).
static func far_depth(kind: String, u: float) -> float:
	if kind == "drop":
		return _drop_depth(u)
	if kind == "water":
		return 1.0
	if kind == "field" or kind == "lawn" or kind == "lot":
		return _fall_depth(u) * smoothstep(FLAT_REACH, FLAT_REACH + 100.0, u)
	return _fall_depth(u) * smoothstep(40.0, 110.0, u)


## The ground's height on a field, a lawn or a lot at `u` from the paved edge, the same all along the
## strip out to FLAT_REACH (r81_places.gd stands its buildings and fences on this).
static func flat_height(kind: String, u: float) -> float:
	if kind != "field":
		# a gentle swale beside the shoulder, then level
		return -0.03 * minf(u, 3.0) - 0.25 * sin(PI * clampf((u - 3.0) / 8.0, 0.0, 1.0))
	if u < 3.0:
		return -0.03 * u
	if u < 6.0:
		return lerpf(-0.09, -0.6, (u - 3.0) / 3.0)
	if u < 12.0:
		return lerpf(-0.6, 0.3, (u - 6.0) / 6.0)
	# the fields roll a little, the same along the whole stretch
	return 0.3 + smoothstep(12.0, 60.0, u) * 0.9 * _nx(u * 0.6, 7.0)


## A climbing side's mountain: how far it has risen (metres above where it starts) at u, when
## it starts at `start` metres from the paved edge. Gentle where it starts (so the ditch and
## the edge of the woods stay as they are), steepest a little way up, then easing towards a
## crest about CLIMB_H up near REACH. Its own bumps (spurs and hollows) differ along the road
## by the strip's salt and fade out at the strip's ends (env), like every profile's.
static func mountain(u: float, start: float, zt: float, salt: float) -> float:
	var v := maxf(u - start, 0.0)
	var env := sin(PI * clampf(zt, 0.0, 1.0))
	var h := CLIMB_H * (1.0 - exp(-v / CLIMB_L)) * (v / (v + 30.0))
	return h * (1.0 + 0.12 * _nx(u, 6.0)) + smoothstep(0.0, 80.0, v) * (8.0 * _nx(u * 1.7, 8.0) + 10.0 * env * _nz(u * 0.6, zt, salt + 21.0))


## Where a profile's own shape is done and a climbing side's mountain starts (metres from the
## paved edge): behind the woods' ditch, on top of a rock cut, past the flat ground of a field,
## a lawn or a lot.
static func _climb_start(kind: String, zt: float, salt: float) -> float:
	match kind:
		"cut":
			return _cut_wall(zt, salt).y + 4.0
		"field", "lawn", "lot":
			return FLAT_REACH
	return 14.0


## A rock cut's wall at zt along a strip: [its height, where its top is (metres from the paved
## edge)]. The height varies along the strip (18 m at the seams); the wall leans back a little.
static func _cut_wall(zt: float, salt: float) -> Vector2:
	var env := sin(PI * clampf(zt, 0.0, 1.0))
	var h := 18.0 + 5.0 * env * _nz(0.0, zt * 1.5, salt)
	return Vector2(h, 4.5 + h * 0.32)


## One profile's cross-section at `u` metres out from the paved edge, `zt` (0..1) of the way
## along the strip. salt = the strip's own number (its bumps). climb = how much this side
## climbs (0 = falls to the valley far out, 1 = rises into the mountain; see the top of the
## file). Returns [height (m), depth (0..1), depth's slope per metre of u, rock, grass, forest,
## crop field (weights 0..1)].
static func edge(kind: String, u: float, zt: float, salt: float, climb: float = 0.0) -> PackedFloat32Array:
	var env := sin(PI * clampf(zt, 0.0, 1.0))        # 0 at both ends of the strip: seams match
	var y := 0.0
	var rock := 0.0
	var grass := 0.0
	var forest := 0.0
	var field := 0.0
	# (an overlook on a climbing side would look up a mountain: there it is woods)
	if kind == "drop" and climb > 0.5:
		kind = "woods"
	match kind:
		"field":
			# shoulder, a shallow ditch, the fence line at 13 m, then fields. No bumps of the
			# strip's own out to FLAT_REACH: the buildings on it are built from flat_height().
			y = flat_height(kind, u)
			y += smoothstep(FLAT_REACH, FLAT_REACH + 120.0, u) * (5.0 * _nx(u, 1.0) + 4.0 * env * _nz(u, zt, salt))
			grass = 1.0 - smoothstep(13.0, 16.0, u)
			# a hedgerow at about 150 m, a woodlot from 400 m
			forest = maxf(smoothstep(147.0, 150.0, u) * (1.0 - smoothstep(157.0, 160.0, u)), smoothstep(395.0, 420.0, u))
			field = (1.0 - grass) * (1.0 - forest)
		"lawn", "lot":
			y = flat_height(kind, u)
			y += smoothstep(FLAT_REACH, FLAT_REACH + 120.0, u) * (5.0 * _nx(u, 1.0) + 4.0 * env * _nz(u, zt, salt))
			if kind == "lawn":
				# a town: two lines of street trees, and the woods behind it
				forest = maxf(maxf(smoothstep(84.0, 86.0, u) * (1.0 - smoothstep(93.0, 95.0, u)), smoothstep(139.0, 141.0, u) * (1.0 - smoothstep(148.0, 150.0, u))),
					smoothstep(205.0, 225.0, u))
			else:
				# a lot (a gas station, a truck stop): open ground, the woods behind
				forest = smoothstep(140.0, 160.0, u)
			grass = 1.0 - forest
		"water":
			# no ground at road height at all, even right at the road's edge: the road is a
			# bridge here, and this is the river's bed under and beside it (depth 1: on the
			# valley floor)
			y = WATER_Y
		"cut":
			var wall := _cut_wall(zt, salt)
			var h := wall.x
			var w := h * 0.32
			var top := wall.y
			if u < 3.0:
				y = lerpf(0.0, -0.5, u / 3.0)
			elif u < 4.5:
				y = -0.5
			elif u < top:
				var f := (u - 4.5) / w
				y = -0.5 + (h + 0.5) * pow(f, 0.75) + 0.7 * env * _nz(u * 4.0, zt * 4.0, salt + 5.0) * sin(PI * f)
			elif u < top + 4.0:
				y = h
			else:
				var v := u - top - 4.0
				# (on a falling side the hill the road was cut through rises a little more, then
				# runs down to the valley; on a climbing side the mountain does the rising)
				y = h + 0.5 * minf(v, 140.0) * (1.0 - climb)
				y += smoothstep(0.0, 60.0, v) * (5.0 * _nx(u, 2.0) + 4.0 * env * _nz(u, zt, salt))
			grass = 1.0 - smoothstep(3.0, 4.2, u)
			rock = smoothstep(3.6, 4.5, u) * (1.0 - smoothstep(top + 0.5, top + 3.0, u))
			forest = smoothstep(top + 1.0, top + 4.0, u)
		"drop":
			# the shoulder, the guardrail's edge at 3 m, then the ground falls away: the fall
			# itself is the depth (_drop_depth), so it is as deep as the road is high
			y = -0.02 * minf(u, 3.0)
			y += smoothstep(20.0, 120.0, u) * (4.0 * _nx(u, 3.0) + 3.0 * env * _nz(u, zt, salt))
			grass = 1.0 - smoothstep(34.0, 44.0, u)
			forest = smoothstep(38.0, 46.0, u)
		_:
			# woods: shoulder, ditch, then forest on gently rising, rolling ground
			if u < 3.0:
				y = -0.03 * u
			elif u < 5.5:
				y = lerpf(-0.09, -0.7, (u - 3.0) / 2.5)
			elif u < 9.0:
				y = lerpf(-0.7, 0.4, (u - 5.5) / 3.5)
			else:
				y = 0.4 + 0.05 * minf(u - 9.0, 291.0) * (1.0 - climb)
				y += smoothstep(9.0, 70.0, u) * (5.0 * _nx(u, 1.0) + 4.0 * env * _nz(u, zt, salt))
			grass = 1.0 - smoothstep(7.5, 10.0, u)
			forest = 1.0 - grass
	var depth := far_depth(kind, u)
	var slope := (far_depth(kind, u + 1.0) - far_depth(kind, u - 1.0)) * 0.5
	if kind == "water":
		slope = 0.0
	if kind != "water":
		# a falling side: far out the profile's own shape fades to the valley floor's level
		# (the depth takes the land the rest of the way down)
		var fall := lerpf(y, 0.0, smoothstep(400.0, REACH, u))
		# a climbing side: the mountain rises behind the profile, all forest, never sinking
		var start := _climb_start(kind, zt, salt)
		var up := y + mountain(u, start, zt, salt)
		y = lerpf(fall, up, climb)
		depth *= 1.0 - climb
		slope *= 1.0 - climb
		if climb > 0.0:
			var wooded := smoothstep(start + 10.0, start + 40.0, u) * climb
			forest = maxf(forest, wooded)
			grass *= 1.0 - wooded
			field *= 1.0 - wooded
	return PackedFloat32Array([y, depth, slope, rock, grass, forest, field])


## The mountain over a tunnel at `u` out from the paved edge. rise 0..1 = how far the mountain
## has risen behind the tunnel mouth (0 = right at the mouth: just the roof's height, 1 = full
## height, which is what the strips inside the tunnel have end to end). Inside the tunnel's wall
## line (u < TRENCH) the ground stays at road height: that is the tunnel itself. climb: as in
## edge(); on a climbing side the tunnel goes into the mountainside, which rises on behind it.
static func mount(u: float, rise: float, climb: float = 0.0) -> PackedFloat32Array:
	var base := edge("cut", u, 0.0, 0.0, climb)
	if u < TRENCH - 0.02:
		return PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	# (base already runs into the valley or the mountain far out; the hump over the tunnel does
	# the same on a falling side)
	var m := lerpf(mount_height(rise, u), 0.0, smoothstep(400.0, REACH, u) * (1.0 - climb))
	return PackedFloat32Array([maxf(m, base[0]), base[1], base[2], 0.0, 0.0, 1.0, 0.0])


## The mountain's height straight over the tunnel (the roof slab over the road, r81_pieces.gd,
## uses this too so it meets the land beside it). x_or_u only moves the bumps.
static func mount_height(rise: float, x_or_u: float) -> float:
	return TUNNEL_H + rise * (MOUNT_RISE + 8.0 * _nx(x_or_u, 4.0))


## How far the mountain has risen at zt along a strip that goes from profile `from` to `to`:
## -1 = this spot is not mountain (it is the other profile). The mountain starts with a sheer
## step halfway along a strip (the tunnel mouth) and rises to full height by the strip's end.
static func mount_rise(from: String, to: String, zt: float) -> float:
	if from == "mount" and to == "mount":
		return 1.0
	if to == "mount":
		return -1.0 if zt < 0.5 else smoothstep(0.0, 1.0, (zt - 0.5) / 0.5)
	if from == "mount":
		return -1.0 if zt > 0.5 else smoothstep(0.0, 1.0, (0.5 - zt) / 0.5)
	return -1.0


## The land at `u` out from the paved edge, zt of the way along a strip that starts as profile
## `from` and ends as `to`. climb_a / climb_b = how much the side climbs at the strip's start
## and end (they differ only where the country changes). Same seven numbers as edge().
static func blend(from: String, to: String, u: float, zt: float, salt: float, climb_a: float = 0.0, climb_b: float = 0.0) -> PackedFloat32Array:
	var t := smoothstep(0.15, 0.85, zt)
	var climb := lerpf(climb_a, climb_b, t)
	if from == "mount" or to == "mount":
		var rise := mount_rise(from, to, zt)
		if rise >= 0.0:
			return mount(u, rise, climb)
		return edge(to if from == "mount" else from, u, zt, salt, climb)
	var a := edge(from, u, zt, salt, climb)
	if from == to:
		return a
	var b := edge(to, u, zt, salt, climb)
	var out := PackedFloat32Array()
	out.resize(a.size())
	for i in a.size():
		out[i] = lerpf(a[i], b[i], t)
	return out


## How much of a river crossing the spot zt along a strip from profile `from` to `to` is:
## 0 = solid ground, 1 = the bridge is over the river's bed (the same blend as blend()'s).
static func water_share(from: String, to: String, zt: float) -> float:
	var t := smoothstep(0.15, 0.85, zt)
	return (1.0 - t) * (1.0 if from == "water" else 0.0) + t * (1.0 if to == "water" else 0.0)


## The river beyond REACH: where the land strips end the valley floor is the far view's
## (build_backdrop), which knows nothing of the river, so it carried on as a pond with ruled
## edges (Sen, round 5). This is the rest of it: a ribbon of water on the valley floor out to
## RIVER_FAR on both sides, winding a little and changing width, starting where the strips' river
## ends (half of RIVER_HALF either side of `z` 0, the start of the crossing's middle place; see
## r81_trip.gd river_middle()). For the land material: depth 1 (it lies on the valley floor) and
## all river (UV2.y), a hand's breadth above the floor so the far view's ground does not show
## through. Built once.
const RIVER_HALF: float = 180.0
const RIVER_FAR: float = 2600.0
static var _ribbon: ArrayMesh
static func river_ribbon() -> ArrayMesh:
	if _ribbon:
		return _ribbon
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side: float in [-1.0, 1.0]:
		var edge_x := ROAD_R if side > 0.0 else OPP_L
		var rows: Array = []
		var n := 40
		for i in n + 1:
			var t := float(i) / float(n)
			# from a little inside the strips' end (so no gap shows at the seam) out to RIVER_FAR
			var u := lerpf(REACH - 30.0, RIVER_FAR, t)
			# (the bends and the width only start once the strips are left behind)
			var loose := smoothstep(0.0, 0.15, t)
			var wander := loose * (140.0 * _n().get_noise_2d(u * 0.0012, side * 31.0) + 40.0 * sin(u * 0.004 + side))
			var half := RIVER_HALF * (1.0 + loose * 0.3 * _n().get_noise_2d(u * 0.002, side * 17.0 + 5.0))
			rows.append([edge_x + side * u, wander, half])
		for i in n:
			var r0: Array = rows[i]
			var r1: Array = rows[i + 1]
			var quad: Array[Vector3] = [Vector3(r0[0], 0.3, r0[1] - r0[2]), Vector3(r0[0], 0.3, r0[1] + r0[2]),
				Vector3(r1[0], 0.3, r1[1] + r1[2]), Vector3(r1[0], 0.3, r1[1] - r1[2])]
			for k: int in [0, 1, 2, 0, 2, 3]:
				st.set_normal(Vector3.UP)
				st.set_color(Color(0.0, 0.0, 0.0, 1.0))
				st.set_uv(Vector2(1.0, 0.0))
				st.set_uv2(Vector2(0.0, 1.0))
				st.add_vertex(quad[k])
	_ribbon = st.commit()
	return _ribbon


## The median between the two roads at `m` metres from our road's edge (0..14): a grass swale;
## under a mountain, solid rock between the two tunnels. Same six numbers as edge().
static func median(from: String, to: String, m: float, zt: float) -> PackedFloat32Array:
	var rise := mount_rise(from, to, zt)
	var width := ROAD_L - OPP_R
	if rise >= 0.0 and m > TRENCH - 0.02 and m < width - TRENCH + 0.02:
		# (the same height as the top over the two roads, r81_pieces.gd lid(), so they join flush)
		return PackedFloat32Array([mount_height(rise, TRENCH), 0.0, 0.0, 0.0, 0.0, 1.0, 0.0])
	if rise >= 0.0:
		return PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	# over a river both roads are bridges and the gap between them is open air: the "median"
	# is the river's bed far below (see edge("water"))
	var wet := water_share(from, to, zt)
	if wet > 0.0:
		return PackedFloat32Array([lerpf(-0.9 * sin(PI * m / width), WATER_Y, wet), wet, 0.0, 0.0, 1.0 - wet, 0.0, 0.0])
	return PackedFloat32Array([-0.9 * sin(PI * m / width), 0.0, 0.0, 0.0, 1.0, 0.0, 0.0])


## The X of every line of corners of one side's strip, from the road outwards, and for each
## whether it is median (1), the other road's bed (2) or the side's own profile (0, with its
## distance u from the paved edge in the third number). side: +1 = our right, -1 = our left
## (which starts with the median and the other road).
## coarse = the far land's fewer columns (U_LIST_FAR).
static func _columns(side: int, coarse: bool = false) -> Array:
	var cols: Array = []
	var us := U_LIST_FAR if coarse else U_LIST
	if side > 0:
		for u in us:
			cols.append([ROAD_R + u, 0, u])
		return cols
	var width := ROAD_L - OPP_R
	var ms: Array = [0.0, TRENCH - 0.05, TRENCH, 7.0, width - TRENCH, width - TRENCH + 0.05, width] if coarse else 		[0.0, TRENCH - 0.05, TRENCH, 2.0, 4.0, 7.0, 10.0, 12.0, width - TRENCH, width - TRENCH + 0.05, width]
	for m: float in ms:
		cols.append([ROAD_L - m, 1, m])
	cols.append([OPP_L, 2, 0.0])
	for u in us:
		if u > 0.0:
			cols.append([OPP_L - u, 0, u])
	return cols


## The rows of corners along a strip, as zt (0..1). A strip with a tunnel mouth in it gets two
## rows a hair apart at the middle, which is what makes the mouth's face sheer.
## step = metres between rows (ROW_STEP, or ROW_STEP_FAR for the far land).
static func _rows(from: String, to: String, step: float = ROW_STEP) -> PackedFloat32Array:
	var rows := PackedFloat32Array()
	var n := roundi(LENGTH / step)
	var step_face := (from == "mount") != (to == "mount")
	for i in n + 1:
		var zt := float(i) / float(n)
		if step_face and absf(zt - 0.5) < 0.001:
			rows.append(0.4995)
			rows.append(0.5005)
		else:
			rows.append(zt)
	return rows


## One side's strip of land for a place: the mesh (for r81_terrain.gdshader) and its trees.
## side +1 / -1, from / to = its edge profiles at the start and the end, salt = its own number,
## climb_a / climb_b = how much the side climbs at the start and the end (see edge()).
## Returns {"mesh": ArrayMesh, "trees": the groups of tree batches, see _trees()}.
## coarse = a far strip (U_LIST_FAR, ROW_STEP_FAR) without trees: from a kilometre off the
## terrain shader's painted forest is all that shows.
static func side_strip(side: int, from: String, to: String, salt: int, climb_a: float = 0.0, climb_b: float = 0.0, coarse: bool = false) -> Dictionary:
	var cols := _columns(side, coarse)
	var rows := _rows(from, to, ROW_STEP_FAR if coarse else ROW_STEP)
	var nc := cols.size()
	var nr := rows.size()
	var pos := PackedVector3Array()
	var uv := PackedVector2Array()
	var weights := PackedColorArray()
	pos.resize(nc * nr)
	uv.resize(nc * nr)
	# x = how much crop field, y = how much river (r81_terrain.gdshader)
	var uv2 := PackedVector2Array()
	uv2.resize(nc * nr)
	weights.resize(nc * nr)
	var s := float(salt)
	for r in nr:
		var zt := rows[r]
		for c in nc:
			var col: Array = cols[c]
			var p: PackedFloat32Array
			match int(col[1]):
				1: p = median(from, to, float(col[2]), zt)
				2:
					# the other road's bed: just under it, or gone where it is a bridge
					var gone := water_share(from, to, zt)
					p = PackedFloat32Array([lerpf(-0.01, WATER_Y, gone), gone, 0.0, 0.0, 0.0, 0.0, 0.0])
				_: p = blend(from, to, float(col[2]), zt, s, climb_a, climb_b)
			var i := r * nc + c
			pos[i] = Vector3(float(col[0]), p[0], -zt * LENGTH)
			# the depth's slope is per metre of u; across X it runs the other way on the left
			uv[i] = Vector2(p[1], p[2] * float(side))
			weights[i] = Color(p[3], p[4], p[5], 1.0)
			uv2[i] = Vector2(p[6], water_share(from, to, zt))
	# normals from the grid; steep ground turns to bare rock whatever the profile said
	var normals := PackedVector3Array()
	normals.resize(nc * nr)
	for r in nr:
		for c in nc:
			var i := r * nc + c
			var ax := pos[r * nc + mini(c + 1, nc - 1)] - pos[r * nc + maxi(c - 1, 0)]
			var az := pos[mini(r + 1, nr - 1) * nc + c] - pos[maxi(r - 1, 0) * nc + c]
			var n := az.cross(ax)
			if n.y < 0.0:
				n = -n
			n = n.normalized() if n.length_squared() > 1e-10 else Vector3.UP
			normals[i] = n
			var steep := 1.0 - smoothstep(0.42, 0.62, n.y)
			# (a tunnel's mountain is bare rock round its mouth, but further out its steep sides
			# are wooded: a whole hillside of rock read as a grey hump, Sen round 5)
			if (from == "mount" or to == "mount") and int(cols[c][1]) == 0 and float(cols[c][2]) > 30.0:
				steep *= 0.3
			var w := weights[i]
			w.r = maxf(w.r, steep)
			w.g *= 1.0 - steep
			w.b *= 1.0 - steep
			weights[i] = w
	var idx := PackedInt32Array()
	for r in nr - 1:
		for c in nc - 1:
			var a := r * nc + c
			# (the columns run the other way on the right side: wind its triangles the other way
			# round, or the engine takes them for back faces and lights them from below)
			if side > 0:
				idx.append_array([a, a + nc + 1, a + 1, a, a + nc, a + nc + 1])
			else:
				idx.append_array([a, a + 1, a + nc + 1, a, a + nc + 1, a + nc])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = pos
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = weights
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return {"mesh": mesh, "trees": {} if coarse else _trees(side, from, to, salt, climb_a, climb_b)}


# ── Trees ────────────────────────────────────────────────────
## The trees of one strip: scattered where the profile says forest and the ground is not a
## cliff, thick near the road and thinner further out (out to TREE_REACH). One MultiMesh per
## tree kind; each tree's custom data = (its ground's depth, a number of its own, 0, 0) for
## r81_tree.gdshader. The trees are in random order, so drawing only the first part of each
## MultiMesh (the Forest density slider, r81_trip.gd) thins the forest evenly.
## Returns four groups, each {tree kind: MultiMesh}:
##   "far"    low-poly trees further than CARD_REACH from the road (the Low look),
##   "near"   low-poly trees nearer than that (the Low look),
##   "cards"  the near trees as detailed ones (the Detailed look): three MultiMeshes per
##            kind, one per level of detail (card_names()), all holding the same trees in the
##            same order; custom data = (depth, own number, the level's band from, to), and
##            the instance colour's alpha says which tree a far picture shows (impostor row),
##   "cards2" the far trees as detailed ones (the Detailed look): the light level and the far
##            picture only (card_names(1)).
## r81_trip.gd shows "near" and "far" on the Low look, "cards" and "cards2" on the Detailed one.
## climb_a / climb_b: how much the side climbs at the strip's two ends (see edge()).
static func _trees(side: int, from: String, to: String, salt: int, climb_a: float = 0.0, climb_b: float = 0.0) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5000 + salt * 131 + (7 if side > 0 else 0)
	var far := {}
	var near := {}
	var cards := {}
	var cards2 := {}
	for kind in TREES:
		far[kind] = []
		near[kind] = []
	for kind in CARD_KINDS:
		cards[kind] = []
		cards2[kind] = []
	var s := float(salt)
	# [from u, to u, trees per square metre]
	# (the first trees stand 9 m out: nearer, their crowns hung over the shoulder and hid the
	# green signs and the billboards in front of the woods, Sen round 7)
	for band: Array in [[9.0, 40.0, 0.03], [40.0, 120.0, 0.025], [120.0, TREE_REACH, 0.009]]:
		var count := roundi((float(band[1]) - float(band[0])) * LENGTH * float(band[2]))
		for i in count:
			var u := rng.randf_range(float(band[0]), float(band[1]))
			var zt := rng.randf()
			var size := rng.randf_range(1.2, 2.0)
			var turn := rng.randf() * TAU
			var pick := rng.randf()
			var p := blend(from, to, u, zt, s, climb_a, climb_b)
			if p[5] < 0.6:
				continue
			# the power line's corridor: no trees under the wires
			if salt % 50 == WIRE_SALT and absf(zt - 0.5) * LENGTH < WIRE_CUT * 0.5:
				continue
			# not on a rock face (the ground a metre either side is much higher or lower)
			var hi := blend(from, to, u + 1.0, zt, s, climb_a, climb_b)[0]
			var lo := blend(from, to, u - 1.0, zt, s, climb_a, climb_b)[0]
			if absf(hi - lo) > 2.6:
				continue
			var x := (ROAD_R + u) if side > 0 else (OPP_L - u)
			# conifers come in patches, about one tree in six
			var kind := "pine" if _n().get_noise_2d(u * 0.05 + s, zt * 3.0 + s * 0.7) > 0.32 else ("oak" if pick < 0.6 else "maple")
			var xf := Transform3D(Basis(Vector3.UP, turn).scaled(Vector3(size, size * rng.randf_range(0.9, 1.2), size)), Vector3(x, p[0] - 0.3, -zt * LENGTH))
			var data := Color(p[1], pick, 0.0, 0.0)
			if u > CARD_REACH:
				(far[kind] as Array).append([xf, data])
			else:
				(near[kind] as Array).append([xf, data])
			# The detailed tree on the same spot. Its mesh is 1 unit tall, so its scale is its
			# height in metres: 12 to 22 m, the low-poly tree's size and a little more, because
			# a real crown is airier than a lump and looks smaller at the same size.
			# Some oaks are birches and the conifers are firs (hemlock-like) or pines.
			var card_kind := kind
			var tall := size * rng.randf_range(10.0, 11.5)
			if kind == "pine":
				card_kind = "fir" if pick < 0.65 else "pine"
				tall *= 1.15
			elif kind == "oak" and pick > 0.48:
				card_kind = "birch"
				tall *= 0.85
			((cards2 if u > CARD_REACH else cards)[card_kind] as Array).append([Transform3D(Basis(Vector3.UP, turn).scaled(Vector3.ONE * tall), xf.origin), data])
	return {"far": tree_batches(far), "near": tree_batches(near), "cards": tree_batches(cards, true), "cards2": tree_batches(cards2, true, 1)}


## Turns lists of trees, {tree kind: [[Transform3D, custom data Color], ...]}, into one MultiMesh
## per kind that has any ({tree kind: MultiMesh}). r81_pieces.gd uses it for the trees on top of
## the tunnels. detailed = the lists hold CARD_KINDS, and each becomes one MultiMesh per level
## of detail (keys: card_names()), drawn with card_mesh(). first_level = the nearest level to
## make (1 = no full trees, for the "cards2" group); its band then starts at the camera, so a
## tree that comes nearer than the full level's band is still drawn whole.
static func tree_batches(lists: Dictionary, detailed: bool = false, first_level: int = 0) -> Dictionary:
	var out := {}
	for kind in (CARD_KINDS if detailed else TREES):
		var list: Array = lists.get(kind, [])
		if list.is_empty():
			continue
		# without trees.glb there is one level only: the stand-in tree at every distance (under
		# the first level's name, which is what r81_trip.gd's node for it is called)
		var ready := detailed and card_levels_ready()
		for level in range(first_level if detailed else 0, CARD_LEVELS.size() if ready else (first_level if detailed else 0) + 1):
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_custom_data = true
			# (without per-tree colours the OpenGL renderer hands the shader the custom data as
			# the colour and every tree comes out black)
			mm.use_colors = true
			var key := (kind + CARD_LEVELS[level]) if detailed else kind
			mm.mesh = (card_mesh(key) if ready else card_mesh(kind)) if detailed else tree_mesh(kind)
			mm.instance_count = list.size()
			var band := CARD_BANDS[level] if ready else Vector2(0.0, 60000.0)
			if level == first_level:
				band.x = 0.0
			# which row of the far-picture sheets this kind is, as a share of ROW_STEPS
			# (r81_impostor.gdshader reads it back from the colour's alpha)
			var row_alpha := (float(CampForest.SPECIES.find(kind)) + 0.5) / IMPOSTOR_ROW_STEPS
			for i in list.size():
				mm.set_instance_transform(i, list[i][0])
				var data: Color = list[i][1]
				if detailed:
					# (only the far pictures read the row: on the tree meshes the colour's alpha
					# scales how far the wind moves a corner, so it stays 1 there)
					mm.set_instance_color(i, Color(1.0, 1.0, 1.0, row_alpha if level == 2 else 1.0))
					mm.set_instance_custom_data(i, Color(data.r, data.g, band.x, band.y))
				else:
					mm.set_instance_color(i, Color.WHITE)
					mm.set_instance_custom_data(i, data)
			out[key] = mm
	return out


## The far pictures' row travels as (row + 0.5) / this in the instance colour's alpha; must be
## the same number in r81_impostor.gdshader (ROW_STEPS) and at least the number of species.
const IMPOSTOR_ROW_STEPS: float = 8.0


## The names of the detailed trees' MultiMeshes in a strip's "cards" group, and of r81_trip.gd's
## nodes for them: every kind at every level ("oak", "oak_light", "oak_far", "maple", ...).
## first_level = 1: the "cards2" group's names (no full level: "oak_light", "oak_far", ...).
static func card_names(first_level: int = 0) -> PackedStringArray:
	var out := PackedStringArray()
	for kind in CARD_KINDS:
		for level in range(first_level, CARD_LEVELS.size()):
			out.append(kind + CARD_LEVELS[level])
	return out


## Which level of detail (0 full, 1 light, 2 far picture) a card_names() name is.
static func card_level(card_name: String) -> int:
	return 2 if card_name.ends_with("_far") else (1 if card_name.ends_with("_light") else 0)


## True when the Blender trees loaded (trees.glb), so the detailed trees have their three
## levels. add_materials() must have run.
static func card_levels_ready() -> bool:
	if not _card_kit_read:
		_card_kit_read = true
		_card_kit = CampForest.meshes(_card_mats)
	return not _card_kit.is_empty()


## The mesh of one tree kind (built once): low-poly, about 10 m tall at scale 1, its foot at the
## origin. Corner colours, sway weights and UV.x as r81_tree.gdshader reads them.
static func tree_mesh(kind: String) -> ArrayMesh:
	if _tree_meshes.has(kind):
		return _tree_meshes[kind]
	var b := Geo.Buf.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 81 + kind.hash() % 1000
	var bark := Color(0.2, 0.16, 0.12)
	var height := 10.0
	match kind:
		"pine":
			b.mat = 0.0
			b.cyl(Transform3D.IDENTITY, 0.2, 0.1, 4.0, 5, bark)
			b.mat = 2.0
			# four skirts of needles, each a cone, narrowing to the tip
			for i in 4:
				var y := 2.2 + 2.1 * float(i)
				var r := 2.3 - 0.45 * float(i)
				b.cyl(Transform3D(Basis.IDENTITY, Vector3(0.0, y, 0.0)), r, 0.0, 3.4, 7, Color(0.05, 0.12, 0.06), Color(0.03, 0.07, 0.04))
			height = 12.0
		"maple":
			b.mat = 0.0
			b.cyl(Transform3D.IDENTITY, 0.22, 0.13, 5.5, 5, bark)
			b.mat = 1.0
			# a taller, egg-shaped crown
			b.blob(Vector3(0.0, 7.6, 0.0), Vector3(2.4, 3.4, 2.4), 7, 5, Color(0.2, 0.36, 0.1), Color(0.07, 0.15, 0.05), 0.35, rng)
			b.blob(Vector3(1.0, 6.0, 0.6), Vector3(1.7, 1.6, 1.7), 6, 4, Color(0.17, 0.32, 0.09), Color(0.06, 0.13, 0.04), 0.35, rng)
			height = 11.0
		_:
			b.mat = 0.0
			b.cyl(Transform3D.IDENTITY, 0.26, 0.16, 4.5, 5, bark)
			b.mat = 1.0
			# a broad crown out of three lumps
			b.blob(Vector3(0.0, 7.0, 0.0), Vector3(3.3, 2.5, 3.3), 7, 5, Color(0.16, 0.31, 0.08), Color(0.06, 0.13, 0.04), 0.4, rng)
			b.blob(Vector3(1.9, 5.8, 0.9), Vector3(2.1, 1.7, 2.1), 6, 4, Color(0.14, 0.28, 0.07), Color(0.05, 0.12, 0.04), 0.4, rng)
			b.blob(Vector3(-1.6, 6.2, -1.2), Vector3(2.2, 1.8, 2.2), 6, 4, Color(0.15, 0.3, 0.08), Color(0.05, 0.12, 0.04), 0.4, rng)
			height = 9.5
	b.alpha_by_height(1.5, height)
	var mesh := b.to_mesh()
	_tree_meshes[kind] = mesh
	return mesh


## The mesh of one kind of detailed tree at one level of detail (a card_names() name), 1 unit
## tall with its foot at the origin: the campfire's Blender tree (trees.glb through
## campfire_forest.gd meshes()) or, for the far level, the one square its picture is drawn on,
## wearing Route 81's own materials (add_materials() makes them, so it must have run first).
## The mesh has its materials on its surfaces: the MultiMeshInstance3D that draws it must not
## be given a material_override. Without trees.glb the full level is the campfire's older
## code-built tree (campfire_trees.gd kit()) and there are no other levels.
static func card_mesh(card_name: String) -> ArrayMesh:
	if _card_meshes.has(card_name):
		return _card_meshes[card_name]
	var level := card_level(card_name)
	var kind := card_name.trim_suffix(CARD_LEVELS[level]) if level > 0 else card_name
	var mesh: ArrayMesh
	if not card_levels_ready():
		mesh = CampTrees.kit(kind, _card_mats)
	elif level == 2:
		mesh = CampForest.impostor_mesh()
		mesh.surface_set_material(0, _card_mats["impostor"])
	else:
		mesh = (_card_kit[kind] as Array)[level]
	_card_meshes[card_name] = mesh
	return mesh


# ── Materials ────────────────────────────────────────────────
## Route 81's own materials, added to a Route 22 kit (Geo.new_kit()). Each goes through
## Geo._note, so r22_desert.gd writes it the shared uniforms (bend, travel, wet...), and into
## kit["r81"], the list r81_trip.gd writes the altitude and the season to.
##   kit["land"]    the ground (r81_terrain.gdshader)
##   kit["trees"]   the low-poly trees (r81_tree.gdshader)
##   the detailed trees' bark, leaves and far pictures (r81_bark / r81_foliage /
##   r81_impostor.gdshader) are not in the kit by name: card_mesh() puts them on the tree
##   meshes. kit["r81_lod"] lists them: r81_trip.gd writes the camera's place (lod_eye) to those.
##   kit["tunnel"]  the tunnels' lining (r81_tunnel.gdshader)
##   kit["road81"]  our road, kit["road81_opp"] the other direction's (r81_road.gdshader)
##   kit["street_a"] / kit["street_b"] the streetlights' lamp heads (r81_lamp.gdshader)
##   kit["backdrop"] the far ridges (r81_backdrop.gdshader), kit["vista"] the distant views
##                  standing on them (r81_vista.gdshader); both are lit by r22_desert.gd
static func add_materials(kit: Dictionary) -> void:
	var own: Array[ShaderMaterial] = []
	kit["r81"] = own
	var land := ShaderMaterial.new()
	land.shader = TERRAIN_SHADER
	land.set_shader_parameter("tex_rock", load(TEX + "rock_cut.jpg"))
	land.set_shader_parameter("tex_grass", load(TEX + "ground_verge.jpg"))
	land.set_shader_parameter("tex_leaves", load(TEX + "ground_leaves.jpg"))
	kit["land"] = Geo._note(kit, land)
	own.append(land)
	var trees := ShaderMaterial.new()
	trees.shader = TREE_SHADER
	kit["trees"] = Geo._note(kit, trees)
	own.append(trees)
	# The detailed trees. The names are the ones campfire_forest.gd meshes() (and the stand-in
	# campfire_trees.gd kit()) look up: "trunk", and a leaf material per species.
	# [name, leaf card photo, tint, evergreen]. The Blender trees' leafy cards are small twigs
	# with their own photos (CampForest.TWIG_PICTURE), as in the campfire.
	_card_meshes = {}
	_card_mats = {}
	_card_kit = {}
	_card_kit_read = false
	kit_serial += 1
	var lod: Array[ShaderMaterial] = []
	kit["r81_lod"] = lod
	var bark := ShaderMaterial.new()
	bark.shader = BARK_SHADER
	bark.set_shader_parameter("tex_bark", load(CAMP_TEX + "detail_bark_pine.jpg"))
	bark.set_shader_parameter("tex_bark_oak", load(CAMP_TEX + "detail_bark_oak.jpg"))
	bark.set_shader_parameter("tex_bark_birch", load(CAMP_TEX + "detail_bark_birch.jpg"))
	_card_mats["trunk"] = Geo._note(kit, bark)
	own.append(bark)
	lod.append(bark)
	for k: Array in [["fir", "card_fir.png", Color(0.82, 0.95, 0.85), 1.0], ["pine", "card_pine.png", Color(0.9, 1.0, 0.85), 1.0],
			["leaves", "card_oak.png", Color.WHITE, 0.0], ["leaves_birch", "card_birch.png", Color.WHITE, 0.0],
			["leaves_maple", "card_maple.png", Color.WHITE, 0.0]]:
		var leaves := ShaderMaterial.new()
		leaves.shader = FOLIAGE_SHADER
		var photo := String(CampForest.TWIG_PICTURE.get(String(k[0]), k[1]))
		if not ResourceLoader.exists(CAMP_TEX + photo):
			photo = String(k[1])        # (no Blender trees here: the older trees' own leaf cards)
		leaves.set_shader_parameter("card", load(CAMP_TEX + photo))
		leaves.set_shader_parameter("tint", k[2])
		leaves.set_shader_parameter("evergreen", k[3])
		leaves.set_shader_parameter("lod_fade", CARD_FADE)
		_card_mats[String(k[0])] = Geo._note(kit, leaves)
		own.append(leaves)
		lod.append(leaves)
	# the far trees: a picture of each tree from eight sides (made by the campfire's
	# models/make_trees.py), on one square that turns to the camera
	var far := ShaderMaterial.new()
	far.shader = IMPOSTOR_SHADER
	if ResourceLoader.exists(CAMP_TEX + "impostor_color.png"):
		far.set_shader_parameter("color_sheet", load(CAMP_TEX + "impostor_color.png"))
		far.set_shader_parameter("normal_sheet", load(CAMP_TEX + "impostor_normal.png"))
	far.set_shader_parameter("frames", float(CampForest.IMPOSTOR_FRAMES))
	far.set_shader_parameter("rows", float(CampForest.SPECIES.size()))
	far.set_shader_parameter("half_size", CampForest.IMPOSTOR_HALF)
	far.set_shader_parameter("lod_fade", CARD_FADE)
	var leafy := PackedFloat32Array()
	for sp in CampForest.SPECIES:
		leafy.append(1.0 if sp in ["oak", "maple", "birch"] else 0.0)
	far.set_shader_parameter("leafy", leafy)
	_card_mats["impostor"] = Geo._note(kit, far)
	own.append(far)
	lod.append(far)
	var tunnel := ShaderMaterial.new()
	tunnel.shader = TUNNEL_SHADER
	tunnel.set_shader_parameter("tex_concrete", load(TEX + "tunnel_concrete.jpg"))
	kit["tunnel"] = Geo._note(kit, tunnel)
	for key: String in ["road81", "road81_opp"]:
		var road := ShaderMaterial.new()
		road.shader = ROAD_SHADER
		road.set_shader_parameter("tex_asphalt", load(TEX + "road_highway.jpg"))
		road.set_shader_parameter("tex_asphalt_nor", load(TEX + "road_highway_nor.jpg"))
		road.set_shader_parameter("flow", 1.0 if key == "road81" else -1.0)
		# (kit["roads"]: r22_desert.gd writes those `night`)
		(kit["roads"] as Array[ShaderMaterial]).append(road)
		kit[key] = Geo._note(kit, road)
	# the streetlights' lamp heads: one material for even-numbered places' poles, one for odd
	for key: String in ["street_a", "street_b"]:
		var lamp := ShaderMaterial.new()
		lamp.shader = LAMP_SHADER
		kit[key] = Geo._note(kit, lamp)
	var back := ShaderMaterial.new()
	back.shader = BACKDROP_SHADER
	back.set_shader_parameter("rock_noise", Geo.ROCK_NOISE)
	kit["backdrop"] = back
	own.append(back)
	# the distant views (r81_vistas.gd); r22_desert.gd lights it together with the backdrop
	var vista := ShaderMaterial.new()
	vista.shader = VISTA_SHADER
	vista.set_shader_parameter("rock_noise", Geo.ROCK_NOISE)
	kit["vista"] = vista
	own.append(vista)


## A flat strip of road from x0 to x1 (its own X) and z0 to z1, cut every `step` metres along
## so the bend can curve it. For r81_road.gdshader.
static func road_strip(x0: float, x1: float, z0: float, z1: float, step: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	var n := maxi(1, int(absf(z1 - z0) / step))
	var mid := (x0 + x1) * 0.5
	for i in n:
		var za := lerpf(z0, z1, float(i) / float(n))
		var zb := lerpf(z0, z1, float(i + 1) / float(n))
		for xs: Array in [[x0, mid], [mid, x1]]:
			var xa := float(xs[0])
			var xb := float(xs[1])
			st.add_vertex(Vector3(xa, 0.0, za))
			st.add_vertex(Vector3(xb, 0.0, za))
			st.add_vertex(Vector3(xb, 0.0, zb))
			st.add_vertex(Vector3(xa, 0.0, za))
			st.add_vertex(Vector3(xb, 0.0, zb))
			st.add_vertex(Vector3(xa, 0.0, zb))
	return st.commit()


# ── The far view ─────────────────────────────────────────────
## How far out each row of ridges stands (metres from the road, on both sides) and how high its
## crest is above the valley floor.
const RIDGES: Array = [[3300.0, 280.0], [4900.0, 350.0], [6900.0, 430.0], [9600.0, 530.0], [13500.0, 650.0]]
## Half the length of a ridge along the road, metres.
const RIDGE_HALF: float = 16000.0
## A ridge's foot lies this many times its height from its crest line.
const RIDGE_SPREAD: float = 2.3


## A point on ridge `i` (0 = the nearest) on one side (-1 left, +1 right) of the far view, in
## the far view's own metres: `z` along the ridge, `across` from -1 (one foot) through 0 (the
## crest) to +1 (the other foot); the foot on the road's side is across = -side.
## Each ridge is a long tent shape whose crest wanders, rises and falls, and now and then dips
## into a gap (where a river would cut through). build_backdrop() makes the ridges from this,
## and r81_vistas.gd stands its towers, ski trails and quarries on them with it.
static func ridge_point(side: float, i: int, z: float, across: float) -> Vector3:
	var n := _n()
	var out := float(RIDGES[i][0])
	var high := float(RIDGES[i][1])
	var salt := float(i) * 13.0 + side * 5.0
	var h := high * (0.72 + 0.28 * n.get_noise_2d(z * 0.0004, salt))
	h *= 1.0 + 0.06 * n.get_noise_2d(z * 0.004, salt + 3.0)
	# a gap: the crest dips most of the way down
	h *= 1.0 - 0.75 * smoothstep(0.42, 0.5, n.get_noise_2d(z * 0.00025 + 40.0, salt + 9.0))
	var wander := 260.0 * n.get_noise_2d(z * 0.0002, salt + 20.0)
	# the tent's cross-section: foot 0, shoulder 0.72 of the way up at 0.4, crest 1
	var a := absf(across)
	var share := lerpf(1.0, 0.72, a / 0.4) if a < 0.4 else lerpf(0.72, 0.0, (a - 0.4) / 0.6)
	return Vector3(side * (out + wander) + across * high * RIDGE_SPREAD, h * share, z)


## The far view: a valley floor and five rows of long parallel ridges on each side, the
## Pennsylvania "ridge and valley" look. Its origin is on the valley floor; the ridges run
## along its own Z, the nearest 3 km off, which leaves a broad valley for the distant views
## (r81_vistas.gd). r81_trip.gd lowers it by the altitude and turns it round the car with the
## road's heading, so the view swings as the road curves.
static func build_backdrop(kit: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Backdrop"
	var b := Geo.Buf.new()
	var floor_col := Color(1.0, 0.0, 0.0)
	var ridge_col := Color(0.0, 0.0, 0.0)
	var far := RIDGE_HALF * 1.2
	b.quad(Vector3(-far, 0.0, -far), Vector3(far, 0.0, -far), Vector3(far, 0.0, far), Vector3(-far, 0.0, far), floor_col)
	var steps := 80
	for side: float in [-1.0, 1.0]:
		for i in RIDGES.size():
			var grid: Array = []
			# five lines of corners across the ridge: foot, shoulder, crest, shoulder, foot
			for across: float in [-1.0, -0.4, 0.0, 0.4, 1.0]:
				var row := PackedVector3Array()
				for j in steps + 1:
					row.append(ridge_point(side, i, lerpf(-RIDGE_HALF, RIDGE_HALF, float(j) / float(steps)), across))
				grid.append(row)
			b.surface(grid, false, [ridge_col, ridge_col, ridge_col, ridge_col, ridge_col])
	var mi := Geo.add_mesh(root, "Ridges", b, kit["backdrop"], false)
	# always drawn: it is far bigger than any culling box makes sense for
	mi.extra_cull_margin = 16000.0
	return root
