extends RefCounted
## Builds the Log Cabin out of plain coloured shapes, in code: the log walls, the glass gable
## wall with the stone chimney in the middle, the roof and its beams, the loft and its stairs,
## the furniture, the deck, the back stoop, and every marker the app looks for (rooms/room.gd
## lists them: TVScreen, CAM_*, PRESENTER_n, PODIUM_n, AUDIENCE_*, TARGET_*, LIGHTS_House with
## LAMP_* inside).
##
## FIRST PASS (2026-11-17): this is the layout only, from Sen's plan "Log Cabin room plan"
## (layout mockup v2). Everything is flat colour, the shapes are simple, and the outside is a
## placeholder clearing (_build_clearing). Shaders, better models, CC0 textures and the real
## outdoor scenes come later. The cabin itself is meant to be shared: the later scene rooms
## (Appalachian forest, lakeside, ocean, frozen north) will call build_cabin() and add their own
## outside instead of the clearing.
##
## The den (added the same day, from Sen's den picture): a small, low-beamed room off the great
## room's left wall, through a doorway, with its own stone fireplace, a leather sofa and an
## armchair. "Gather in" (cabin_view, the room script's reload key) picks where the guests sit:
## "great_room" puts the presenters on the four armchairs by the big fireplace and the big screen
## on the tall chimney; "den" sits them on the den's sofa and armchair, makes the den's screen
## the main one (TVScreen), puts the den's cameras first, and the other screen shows the same
## picture (SCREEN_Mirror_). Everything else is built the same either way.
##
## Called once by rooms/log_cabin/log_cabin_room.gd (_ready, before anything reads the room),
## which keeps the Dictionary build() returns: the materials and nodes it animates afterwards.
## There is no Blender model: to move or resize something, change the numbers in the "Layout"
## block below.
##
## Axes (metres): the floor inside is y = 0. The glass gable wall that faces the view is at
## z = 0, the back wall (entrance) at z = BACK_Z; -Z is the view (deck, then the outside), +Z is
## the back. x = 0 is the middle of the cabin (the chimney and the ridge), +X is the stairs' side.
## Markers that "face" something follow the app's rule: +Z points at what they face, except
## cameras, which look along -Z.

# ── Layout ───────────────────────────────────────────────────
## Half the cabin's width (outside of the logs) and how deep it is, front glass to back wall.
const HALF_W: float = 6.5
const BACK_Z: float = 9.0
## Height of the log walls (the eaves) and of the ridge, inside.
const EAVE_Y: float = 3.6
const RIDGE_Y: float = 8.6
## Logs: radius, and the metres between one log's middle and the next one's. The ends stick out
## past the corners by LOG_OVERHANG (the notched-corner look).
const LOG_R: float = 0.17
const LOG_STEP: float = 0.3
const LOG_OVERHANG: float = 0.32
## The roof reaches this far past the side walls (sideways) and past the front and back walls.
const ROOF_SIDE: float = 0.7
const ROOF_FRONT: float = 1.2
const ROOF_BACK: float = 0.8
## The ground outside: this far below the floor (the cabin stands on a stone footing).
const GROUND_Y: float = -0.9
## The deck in front of the glass: half its width, how far out it reaches (z), its top.
const DECK_HALF: float = 8.1
const DECK_DEPTH: float = 3.9
const DECK_Y: float = -0.1
## The deck's steps down to the ground (x from, x to) in its front railing.
const DECK_STEPS: Vector2 = Vector2(6.1, 7.5)
## The chimney: the wide lower part (half width, top), the narrower stack above it (half width),
## its top, and how far it reaches out the front (z) and in (z, its face in the room).
const CHIM_HALF: float = 2.1
const CHIM_WIDE_TOP: float = 4.6
const CHIM_STACK_HALF: float = 1.0
const CHIM_TOP: float = 10.0
const CHIM_OUT_Z: float = -0.9
const CHIM_IN_Z: float = 0.8
## The firebox opening in the chimney's face: half width, bottom, top, depth into the stone.
const FIREBOX_HALF: float = 0.7
const FIREBOX_Y: Vector2 = Vector2(0.4, 1.3)
const FIREBOX_DEPTH: float = 0.5
## The raised hearth in front of the chimney: half width, how far it sticks out, height.
const HEARTH_HALF: float = 2.6
const HEARTH_OUT: float = 0.5
const HEARTH_H: float = 0.4
## The mantel shelf: height of its top.
const MANTEL_Y: float = 1.78
## The big screen on the chimney above the mantel: width x height, bottom edge height.
const SCREEN_SIZE: Vector2 = Vector2(3.8, 2.14)
const SCREEN_BOTTOM: float = 1.95
## The loft across the back: its floor's top, and where its front edge (with the railing) is.
const LOFT_Y: float = 2.8
const LOFT_FRONT_Z: float = 5.4
## The stairs up to the loft along the right wall: x from, x to; z where they start; steps.
const STAIR_X: Vector2 = Vector2(5.25, 6.45)
const STAIR_START_Z: float = 1.7
const STAIR_STEPS: int = 14
## Windows in the side and back log walls: [wall ("left" x = -HALF_W, "right" x = +HALF_W,
## "back" z = BACK_Z), from, to (z for the side walls, x for the back wall), sill, top].
const WINDOWS: Array = [
	["left", 5.8, 8.0, 0.9, 2.2], ["left", 2.2, 4.4, 0.9, 2.3], ["right", 6.2, 8.2, 0.9, 2.2],
	["back", -5.6, -4.3, 1.2, 2.2], ["back", 3.4, 4.6, 1.2, 2.2],
]
## The doorway from the great room into the den, in the left wall: z from, z to, top.
const DEN_DOOR: Vector3 = Vector3(4.6, 5.6, 2.15)
## The back door (the entrance from the stoop): x from, x to, top.
const BACK_DOOR: Vector3 = Vector3(-0.5, 0.5, 2.1)
## The glass doors in the two front corners: x from, x to (left one; the right one is mirrored).
const GLASS_DOOR: Vector2 = Vector2(-6.2, -5.0)
## The front window wall's mullions (upright timbers) at these x (and mirrored).
const MULLIONS: Array[float] = [-6.5, -5.0, -3.55, -2.1]
## The collar ties across the roof (z) and their height.
const COLLARS_Z: Array[float] = [2.4, 4.4, 7.0]
const COLLAR_Y: float = 5.6
## The den: its far wall (x), the walls either side (z from, z to), the height of its log walls,
## its flat beamed ceiling and its roof's ridge (running along x, over DEN_MID_Z).
const DEN_FAR_X: float = -12.5
const DEN_Z: Vector2 = Vector2(2.0, 8.6)
const DEN_EAVE_Y: float = 3.3
const DEN_CEIL_Y: float = 3.15
const DEN_RIDGE_Y: float = 4.9
const DEN_MID_Z: float = 5.3
## The den's windows: [the z of the wall they are in, x from, x to, sill, top].
const DEN_WINDOWS: Array = [[8.6, -10.9, -8.7, 0.9, 2.4], [2.0, -11.3, -9.4, 0.9, 2.4]]
## The den's chimney on its far wall: how far it sticks into the room (x of its face), its z
## from / to, and the firebox in its face (z from, z to, bottom, top).
const DEN_CHIM_FACE_X: float = -11.85
const DEN_CHIM_Z: Vector2 = Vector2(4.15, 6.45)
const DEN_FIREBOX: Vector4 = Vector4(4.8, 5.8, 0.35, 1.2)
const DEN_MANTEL_Y: float = 1.62
## The den's screen above its mantel: width x height, bottom edge height.
const DEN_SCREEN_SIZE: Vector2 = Vector2(2.0, 1.125)
const DEN_SCREEN_BOTTOM: float = 1.8
## The den's sofa (three seats, 1.1 m apart) and armchair: where each stands (x, z) and the point
## (x, z) it is turned towards, so both open towards the den's main camera like in the picture.
const DEN_SOFA: Vector4 = Vector4(-9.4, 7.2, -8.0, 3.7)
const DEN_ARMCHAIR: Vector4 = Vector4(-10.0, 3.1, -8.0, 6.0)
const DEN_SEAT_Y: float = 0.45
## In "Gather in: Den" these cameras come first, then the great room's (CAMERAS, renumbered).
const DEN_CAMERAS: Array = [
	["01_Den_Fireside", Vector3(-6.95, 1.55, 5.15), Vector3(-12.0, 1.45, 5.3)],
	["02_Reaction_Den_Sofa", Vector3(-7.4, 1.35, 3.6), Vector3(-9.4, 0.95, 7.0)],
	["03_Den_Armchair", Vector3(-7.2, 1.4, 6.6), Vector3(-10.0, 0.95, 3.1)],
	["04_Den_Hearth", Vector3(-11.2, 1.75, 5.3), Vector3(-7.0, 1.1, 5.3)],
]

## Chat seats: [name, x, seat height, z, what it faces ("screen" or a Vector3 point)].
## 18 on the main floor, 5 at the loft railing, 7 on the deck = 30 (plan v2). Seats along a row
## are 1 m apart or more, so all stay at the default Seat spacing (audience_seat_gap 1.0).
const SEATS: Array = [
	# sheepskins and cushions on the hearth rug
	["Hearth_1", -1.5, 0.12, 1.85, "screen"], ["Hearth_2", -0.5, 0.12, 1.85, "screen"],
	["Hearth_3", 0.5, 0.12, 1.85, "screen"], ["Hearth_4", 1.5, 0.12, 1.85, "screen"],
	# the two leather sofas
	["SofaL_1", -3.1, 0.45, 3.85, "screen"], ["SofaL_2", -2.1, 0.45, 3.85, "screen"], ["SofaL_3", -1.1, 0.45, 3.85, "screen"],
	["SofaR_1", 1.1, 0.45, 3.85, "screen"], ["SofaR_2", 2.1, 0.45, 3.85, "screen"], ["SofaR_3", 3.1, 0.45, 3.85, "screen"],
	# four armchairs
	["Arm_1", -4.5, 0.45, 1.9, "screen"], ["Arm_2", -5.3, 0.45, 3.7, "screen"],
	["Arm_3", 4.4, 0.45, 1.9, "screen"], ["Arm_4", 4.3, 0.45, 4.75, "screen"],
	# the dining bench, its back to the table, facing the view
	["Dining_1", -4.8, 0.45, 6.2, "screen"], ["Dining_2", -3.8, 0.45, 6.2, "screen"],
	["Dining_3", -2.8, 0.45, 6.2, "screen"], ["Dining_4", -1.8, 0.45, 6.2, "screen"],
	# the bench at the loft railing
	["Loft_1", -4.2, 3.22, 5.75, "screen"], ["Loft_2", -2.8, 3.22, 5.75, "screen"], ["Loft_3", -1.4, 3.22, 5.75, "screen"],
	["Loft_4", 1.4, 3.22, 5.75, "screen"], ["Loft_5", 2.8, 3.22, 5.75, "screen"],
	# the deck: Adirondack chairs facing the view, and three round the fire table
	["Deck_1", -6.0, 0.25, -2.9, Vector3(-6.0, 0.0, -30.0)], ["Deck_2", -4.2, 0.25, -2.9, Vector3(-4.2, 0.0, -30.0)],
	["Deck_3", 4.2, 0.25, -2.9, Vector3(4.2, 0.0, -30.0)], ["Deck_4", 6.0, 0.25, -2.9, Vector3(6.0, 0.0, -30.0)],
	["Deck_5", -1.2, 0.35, -2.3, Vector3(0.0, 0.0, -2.95)], ["Deck_6", 1.2, 0.35, -2.3, Vector3(0.0, 0.0, -2.95)],
	["Deck_7", 0.0, 0.35, -3.55, Vector3(0.0, 0.0, -2.95)],
]
## The podiums are leather armchairs with the presenter's picture standing on the seat:
## [x, z]; they face the audience (+Z). P1 and P2 by the hearth, P3 and P4 by the corner doors.
const PODIUMS: Array[Vector2] = [Vector2(-3.2, 0.95), Vector2(3.2, 0.95), Vector2(-5.6, 0.9), Vector2(5.6, 0.9)]
## Height of a podium chair's seat (where the presenter's picture stands).
const PODIUM_SEAT_Y: float = 0.45
## Camera views: [name (after "CAM_"; the leading number sets the order), where it stands, what
## it looks at]. The one with "Reaction" in its name is used for react pauses.
const CAMERAS: Array = [
	["01_Loft", Vector3(0.0, 4.7, 7.6), Vector3(0.0, 2.4, 0.8)],
	["02_Reaction_Hearth", Vector3(0.0, 1.6, 1.25), Vector3(0.0, 1.5, 8.0)],
	["03_Sofa", Vector3(-3.4, 1.3, 5.2), Vector3(0.6, 2.2, 0.8)],
	["04_Stair_Corner", Vector3(4.9, 2.5, 5.0), Vector3(-1.2, 1.7, 1.0)],
	["05_Deck_Looking_In", Vector3(-5.2, 1.6, -3.3), Vector3(-2.6, 1.8, 4.5)],
	["06_Deck_Looking_Out", Vector3(3.6, 1.7, -1.0), Vector3(1.0, 1.0, -30.0)],
	["07_Outside_Gable", Vector3(0.0, 2.6, -17.0), Vector3(0.0, 3.6, 3.0)],
	["08_Front_Door", Vector3(5.5, 1.6, 16.5), Vector3(0.0, 1.4, 9.0)],
	["09_Dining_Table", Vector3(-6.0, 1.7, 7.9), Vector3(0.4, 1.7, 1.0)],
	["10_Screen_Close", Vector3(0.0, 2.2, 4.9), Vector3(0.0, 2.95, 0.8)],
]

# ── Colours (flat for now; textures come later) ──────────────
const C_LOG := Color(0.55, 0.36, 0.2)
const C_LOG_END := Color(0.74, 0.56, 0.36)
const C_PINE := Color(0.8, 0.6, 0.38)
const C_FLOOR := Color(0.58, 0.38, 0.21)
const C_TIMBER := Color(0.45, 0.29, 0.16)
const C_STONE := Color(0.5, 0.48, 0.44)
const C_STONE_DARK := Color(0.33, 0.31, 0.29)
const C_SOOT := Color(0.06, 0.05, 0.05)
const C_ROOF := Color(0.24, 0.22, 0.21)
const C_LEATHER := Color(0.36, 0.2, 0.11)
const C_FABRIC := Color(0.72, 0.64, 0.52)
const C_WOOL := Color(0.86, 0.83, 0.76)
const C_RUG := Color(0.5, 0.17, 0.11)
const C_IRON := Color(0.09, 0.09, 0.09)
const C_DECK := Color(0.5, 0.37, 0.24)
const C_FRAME := Color(0.4, 0.26, 0.14)
const C_GRASS := Color(0.29, 0.4, 0.21)
const C_CHINK := Color(0.78, 0.72, 0.62)
const C_BARK := Color(0.42, 0.3, 0.22)
const C_RUG_MEAN := Color(0.55, 0.35, 0.24)    # the average colour of textures/rug.jpg's drawing
const C_THROW_GREEN := Color(0.3, 0.42, 0.3)
const C_MUG := Color(0.82, 0.8, 0.74)


# ── Surfaces (Set detail: Detailed lays photo textures on them) ──
## Which kind of surface the shapes added to a Buf from now on are (Buf.mat): each kind becomes
## its own part (surface) of the mesh with its own material (cabin_surface.gdshader). The
## textures come from textures/make_textures.py (CC0 photos from Poly Haven).
const S_PLAIN := 0       # no texture: iron, lamp bases, books...
const S_LOG := 1         # the log walls, posts, rafters, collar ties and beams
const S_LOG_END := 2     # the cut ends of logs (growth rings); cyl() / rod() caps with a cap colour
const S_CHINK := 3       # the plaster between the logs
const S_FLOOR := 4
const S_CEILING := 5     # the pine boards under the roof and the den's ceiling
const S_STONE := 6       # chimneys, hearths, footing
const S_ROOF := 7
const S_DECK := 8        # deck, stoop, steps, railings
const S_LEATHER := 9
const S_WOOL := 10       # upholstery, cushions
const S_FLEECE := 11     # throws, sheepskins
const S_BARK := 12       # firewood
const S_RUG := 13        # the rugs: the picture laid once over each (Buf.rug_quad)
const S_TIMBER := 14     # sawn timber: frames, furniture, shelves, mantels
const S_IRON := 15
const S_GRASS := 16      # the ground outside (a colour photo, the campfire's)
const S_DIRT := 17       # the trodden paths (a colour photo, the campfire's)
const S_LITTER := 18     # the forest floor (a colour photo, the campfire's; Cabin: Appalachian Forest)
const S_SAND := 19       # a lake beach (a colour photo, the campfire's; Cabin: Lakeside)
## Per kind: [texture in textures/ ("" = none; a path starting "res://" is a colour photo used
## as it is, see cabin_surface.gdshader `photo`), metres per copy, the world axis the
## picture's up follows (-1 = none, 0 = x, 1 = y, 2 = z), mapping (see cabin_surface.gdshader),
## bump strength, roughness, specular, metallic].
const SURFACES: Dictionary = {
	S_PLAIN: ["", 1.0, -1, 0, 0.0, 0.8, 0.5, 0.0],
	S_LOG: ["logs", 1.6, -1, 0, 1.0, 0.7, 0.45, 0.0],
	S_LOG_END: ["logs", 1.0, -1, 2, 0.0, 0.8, 0.4, 0.0],
	S_CHINK: ["chinking", 0.8, -1, 0, 0.8, 0.95, 0.3, 0.0],
	S_FLOOR: ["floor", 2.4, -1, 0, 0.8, 0.55, 0.5, 0.0],
	S_CEILING: ["ceiling", 1.8, 2, 0, 0.7, 0.75, 0.4, 0.0],
	S_STONE: ["stone", 1.6, -1, 0, 1.2, 0.9, 0.4, 0.0],
	S_ROOF: ["roof", 3.0, 0, 0, 1.0, 0.9, 0.3, 0.0],
	S_DECK: ["deck", 2.0, -1, 0, 0.9, 0.85, 0.35, 0.0],
	S_LEATHER: ["leather", 0.7, -1, 0, 0.8, 0.45, 0.55, 0.0],
	S_WOOL: ["wool", 0.35, -1, 0, 0.7, 0.95, 0.25, 0.0],
	S_FLEECE: ["fleece", 0.3, -1, 0, 1.0, 1.0, 0.2, 0.0],
	S_BARK: ["bark", 0.6, -1, 0, 1.0, 0.95, 0.3, 0.0],
	S_RUG: ["rug", 1.0, -1, 1, 0.0, 1.0, 0.2, 0.0],
	S_TIMBER: ["logs", 0.9, -1, 0, 0.6, 0.6, 0.45, 0.0],
	S_IRON: ["", 1.0, -1, 0, 0.0, 0.45, 0.5, 0.6],
	S_GRASS: ["res://rooms/campfire/textures/ground_grass.jpg", 4.0, -1, 0, 0.0, 0.95, 0.3, 0.0],
	S_DIRT: ["res://rooms/campfire/textures/ground_dirt.jpg", 3.0, -1, 0, 0.0, 0.95, 0.3, 0.0],
	S_LITTER: ["res://rooms/campfire/textures/ground_forest.jpg", 3.5, -1, 0, 0.0, 0.95, 0.3, 0.0],
	S_SAND: ["res://rooms/campfire/textures/ground_sand.jpg", 3.0, -1, 0, 0.0, 0.95, 0.3, 0.0],
}
## Colour photos (the ground) are tinted by this (cabin_surface.gdshader `photo_tint`): the
## campfire's grass photo is a dry summer meadow, greened here to suit the forest.
const PHOTO_TINTS: Dictionary = {S_GRASS: Color(0.6, 0.74, 0.48), S_DIRT: Color(0.82, 0.78, 0.72), S_SAND: Color(0.86, 0.82, 0.74)}
## How strongly the photo's light and dark show (cabin_surface.gdshader `grain_strength`; 1 = as
## in the photo). The stone photo's pale mortar was harsh in full sun.
const GRAIN_STRENGTH: Dictionary = {S_STONE: 0.65}
const TEX := "res://rooms/log_cabin/textures/"
const SURFACE_SHADER := preload("res://rooms/log_cabin/cabin_surface.gdshader")
const EMBER_SHADER := preload("res://rooms/log_cabin/cabin_embers.gdshader")
const SHADE_SHADER := preload("res://rooms/log_cabin/cabin_shade.gdshader")
const Weather := preload("res://rooms/weather/room_weather.gd")
## The indoors, for the weather (rooms/weather/room_weather.gd): the two roofed parts, each a box
## [x from, x to, z from, z to] with a gable roof [eave height, ridge height, 0 = the ridge runs
## along Z (height follows x) / 1 = along X (height follows z), the ridge's x or z]. Surfaces
## under these stay dry and free of snow (cabin_surface.gdshader shelter_*). Keep in step with
## the walls and roofs (HALF_W, BACK_Z, EAVE_Y, RIDGE_Y and the DEN_ sizes).
const SHELTER_GREAT_BOX := Vector4(-HALF_W - 0.05, HALF_W + 0.05, -0.05, BACK_Z + 0.05)
const SHELTER_GREAT_ROOF := Vector4(EAVE_Y, RIDGE_Y, 0.0, 0.0)
const SHELTER_DEN_BOX := Vector4(DEN_FAR_X - 0.05, -HALF_W, DEN_Z.x - 0.05, DEN_Z.y + 0.05)
const SHELTER_DEN_ROOF := Vector4(DEN_EAVE_Y, DEN_RIDGE_Y, 1.0, DEN_MID_Z)
## Where the smoke leaves each chimney (just above its cap): the great room's stack (see
## _build_chimney: centred on x = 0, between CHIM_OUT_Z + 0.25 and CHIM_IN_Z - 0.35) and the den's
## (_build_den_chimney). Keep in step with those two if a chimney moves.
const SMOKE_SPOTS: Array[Vector3] = [Vector3(0.0, CHIM_TOP + 0.3, -0.1), Vector3(-12.57, DEN_RIDGE_Y + 1.45, 5.3)]
const Trees := preload("res://rooms/campfire/campfire_trees.gd")


## One material per kind of surface (SURFACES). They start in the Simple look (detail 0); the room
## script's _apply_detail sets `detail` on every one of them (out["detail_mats"]).
static func _surface_materials(out: Dictionary) -> Dictionary:
	var mats: Dictionary = {}
	var list: Array[ShaderMaterial] = []
	for id: int in SURFACES:
		var s: Array = SURFACES[id]
		var m := ShaderMaterial.new()
		m.shader = SURFACE_SHADER
		var tex := String(s[0])
		if tex.begins_with("res://"):
			m.set_shader_parameter("tex_grain", load(tex))
			m.set_shader_parameter("photo", 1.0)
			m.set_shader_parameter("photo_tint", PHOTO_TINTS.get(id, Color.WHITE))
		elif tex != "":
			m.set_shader_parameter("tex_grain", load(TEX + tex + ".jpg"))
			if float(s[4]) > 0.0:
				m.set_shader_parameter("tex_nor", load(TEX + tex + "_nor.jpg"))
		m.set_shader_parameter("grain_strength", float(GRAIN_STRENGTH.get(id, 1.0)))
		m.set_shader_parameter("shelter_a_box", SHELTER_GREAT_BOX)
		m.set_shader_parameter("shelter_a_roof", SHELTER_GREAT_ROOF)
		m.set_shader_parameter("shelter_b_box", SHELTER_DEN_BOX)
		m.set_shader_parameter("shelter_b_roof", SHELTER_DEN_ROOF)
		m.set_shader_parameter("tile", float(s[1]))
		m.set_shader_parameter("vertical_axis", int(s[2]))
		m.set_shader_parameter("mapping", int(s[3]))
		m.set_shader_parameter("bump", float(s[4]))
		m.set_shader_parameter("roughness", float(s[5]))
		m.set_shader_parameter("specular", float(s[6]))
		m.set_shader_parameter("metallic", float(s[7]))
		# no texture: nothing to switch on (detail would only multiply by a missing picture)
		m.set_shader_parameter("detail", 0.0)
		mats[id] = m
		if tex != "":
			list.append(m)
	out["detail_mats"] = list
	out["surface_mats"] = mats
	return mats


# ── A mesh being put together ────────────────────────────────
## Collects shaded, coloured triangles and turns them into one mesh with a part (surface) per
## kind of surface (the same idea as the campfire room's builder). Every shape below adds to one
## of these, so a whole group of objects is a single mesh: cheap to draw.
class Buf:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uv2s := PackedVector2Array()
	var kinds := PackedInt32Array()     # the S_ kind of each corner
	## The kind of surface (an S_ constant) the shapes added from now on are. Set it before
	## adding shapes.
	var mat: int = 0

	## One triangle. The normal comes from the corner order; the material draws both sides,
	## so the order never makes a face vanish.
	func tri(a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
		var n := (c - a).cross(b - a)
		if n.length_squared() < 1e-12:
			return
		n = n.normalized()
		tri_round(a, b, c, n, n, n, col)

	## One triangle with a normal per corner (round things, such as a log's side, shade smoothly)
	## and, if given, a UV2 per corner (the rug's picture, a log end's rings).
	func tri_round(a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3, col: Color,
			ua: Vector2 = Vector2.ZERO, ub: Vector2 = Vector2.ZERO, uc: Vector2 = Vector2.ZERO) -> void:
		# the side drawn as the front is the one (c - a) x (b - a) points out of: turn the
		# triangle round if that isn't the side the given normals are on
		if (c - a).cross(b - a).dot(na + nb + nc) < 0.0:
			var keep := b
			b = c
			c = keep
			var keep_n := nb
			nb = nc
			nc = keep_n
			var keep_u := ub
			ub = uc
			uc = keep_u
		verts.append_array([a, b, c])
		normals.append_array([na, nb, nc])
		colors.append_array([col, col, col])
		uv2s.append_array([ua, ub, uc])
		kinds.append_array([mat, mat, mat])

	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
		tri(a, c, b, col)
		tri(a, d, c, col)

	## A flat rectangle lying on the floor from lo to hi (x, z) at height y, showing the rug
	## picture once (S_RUG, UV2 0..1).
	func rug_quad(lo: Vector2, hi: Vector2, y: float, col: Color) -> void:
		var keep := mat
		mat = S_RUG
		var a := Vector3(lo.x, y, lo.y)
		var b := Vector3(hi.x, y, lo.y)
		var c := Vector3(hi.x, y, hi.y)
		var d := Vector3(lo.x, y, hi.y)
		tri_round(a, c, b, Vector3.UP, Vector3.UP, Vector3.UP, col, Vector2(0, 0), Vector2(1, 1), Vector2(1, 0))
		tri_round(a, d, c, Vector3.UP, Vector3.UP, Vector3.UP, col, Vector2(0, 0), Vector2(0, 1), Vector2(1, 1))
		mat = keep

	## A box: xf places its centre and turns it; size is its full width, height and depth.
	func box(xf: Transform3D, size: Vector3, col: Color) -> void:
		var h := size * 0.5
		var p: Array[Vector3] = []
		for sx: float in [-1.0, 1.0]:
			for sy: float in [-1.0, 1.0]:
				for sz: float in [-1.0, 1.0]:
					p.append(xf * Vector3(h.x * sx, h.y * sy, h.z * sz))
		# corners: index = 4 * (x side) + 2 * (y side) + (z side)
		quad(p[0], p[1], p[3], p[2], col)
		quad(p[4], p[6], p[7], p[5], col)
		quad(p[0], p[4], p[5], p[1], col)
		quad(p[2], p[3], p[7], p[6], col)
		quad(p[0], p[2], p[6], p[4], col)
		quad(p[1], p[5], p[7], p[3], col)

	## An upright box between two corners (min and max), no turning: the quick way to place most
	## of the furniture.
	func block(lo: Vector3, hi: Vector3, col: Color) -> void:
		box(Transform3D(Basis.IDENTITY, (lo + hi) * 0.5), (hi - lo).abs(), col)

	## A soft box with its edges and corners cut off by `r` metres (cushions, sofa arms, a
	## mattress). soft = 0 shades it with flat faces and bevels; soft = 1 shades it like a pillow
	## (each corner's normal leans out from the middle), which looks stuffed.
	func soft_box(xf: Transform3D, size: Vector3, r: float, col: Color, soft: float = 1.0) -> void:
		var h := size * 0.5
		r = minf(r, minf(h.x, minf(h.y, h.z)) * 0.95)
		# for each of the 8 corners, a point on each of its three faces, r in from the edges
		var pts := {}
		for sx: int in [-1, 1]:
			for sy: int in [-1, 1]:
				for sz: int in [-1, 1]:
					pts[Vector3i(sx, sy, sz) * 10 + Vector3i(1, 0, 0)] = Vector3(sx * h.x, sy * (h.y - r), sz * (h.z - r))
					pts[Vector3i(sx, sy, sz) * 10 + Vector3i(0, 1, 0)] = Vector3(sx * (h.x - r), sy * h.y, sz * (h.z - r))
					pts[Vector3i(sx, sy, sz) * 10 + Vector3i(0, 0, 1)] = Vector3(sx * (h.x - r), sy * (h.y - r), sz * h.z)
		var faces: Array = []
		# the six faces
		for axis in 3:
			for s: int in [-1, 1]:
				var e := Vector3i.ZERO
				e[axis] = 1
				var cs: Array[Vector3] = []
				for u: int in [-1, 1]:
					for v: int in [-1, 1]:
						var k := Vector3i.ZERO
						k[axis] = s
						k[(axis + 1) % 3] = u
						k[(axis + 2) % 3] = v * u
						cs.append(pts[k * 10 + e])
				# (u, v * u) runs (-1, 1), (-1, -1), (1, -1), (1, 1): already round the face in order
				faces.append([cs[0], cs[1], cs[2], cs[3]])
		# the twelve bevelled edges
		for axis in 3:
			var a1 := (axis + 1) % 3
			var a2 := (axis + 2) % 3
			for s1: int in [-1, 1]:
				for s2: int in [-1, 1]:
					var k0 := Vector3i.ZERO
					k0[a1] = s1
					k0[a2] = s2
					k0[axis] = -1
					var k1 := k0
					k1[axis] = 1
					var e1 := Vector3i.ZERO
					e1[a1] = 1
					var e2 := Vector3i.ZERO
					e2[a2] = 1
					faces.append([pts[k0 * 10 + e1], pts[k1 * 10 + e1], pts[k1 * 10 + e2], pts[k0 * 10 + e2]])
		# the eight corners
		for sx: int in [-1, 1]:
			for sy: int in [-1, 1]:
				for sz: int in [-1, 1]:
					var k := Vector3i(sx, sy, sz) * 10
					faces.append([pts[k + Vector3i(1, 0, 0)], pts[k + Vector3i(0, 1, 0)], pts[k + Vector3i(0, 0, 1)]])
		var inv := Vector3(1.0 / maxf(h.x, 0.001), 1.0 / maxf(h.y, 0.001), 1.0 / maxf(h.z, 0.001))
		for f: Array in faces:
			var flat_n := Vector3.ZERO
			var mid := Vector3.ZERO
			for q: Vector3 in f:
				mid += q
			mid /= float(f.size())
			flat_n = mid.normalized()
			var ns: Array[Vector3] = []
			for q: Vector3 in f:
				# outward: flat (the face's own direction) or pillowy (away from the middle)
				var pn := (q * inv * inv).normalized().lerp(_axis_of(mid, h), 1.0 - soft)
				ns.append((xf.basis * pn).normalized())
			var w: Array[Vector3] = []
			for q: Vector3 in f:
				w.append(xf * q)
			tri_round(w[0], w[1], w[2], ns[0], ns[1], ns[2], col)
			if f.size() == 4:
				tri_round(w[0], w[2], w[3], ns[0], ns[2], ns[3], col)

	## The flat direction of the face a point in a soft_box's surface lies on (the box's own
	## axis it is closest to, or the bevel's slant).
	static func _axis_of(mid: Vector3, h: Vector3) -> Vector3:
		var d := Vector3(absf(mid.x) / maxf(h.x, 0.001), absf(mid.y) / maxf(h.y, 0.001), absf(mid.z) / maxf(h.z, 0.001))
		var n := Vector3(signf(mid.x) if d.x > 0.98 else 0.0, signf(mid.y) if d.y > 0.98 else 0.0, signf(mid.z) if d.z > 0.98 else 0.0)
		return n.normalized() if n.length() > 0.0 else mid.normalized()

	## A cylinder or cone standing on xf's origin along its Y axis: r0 at the bottom, r1 at the
	## top, h tall. cap = the colour of the flat ends (a log's cut end): ends given a colour are
	## drawn as end grain (S_LOG_END, with their rings' UV2).
	func cyl(xf: Transform3D, r0: float, r1: float, h: float, segs: int, col: Color, cap: Color = Color(0, 0, 0, 0)) -> void:
		var end := col if cap.a == 0.0 else cap
		var side_mat := mat
		for i in segs:
			var a0 := TAU * float(i) / float(segs)
			var a1 := TAU * float(i + 1) / float(segs)
			var b0 := xf * Vector3(cos(a0) * r0, 0.0, sin(a0) * r0)
			var b1 := xf * Vector3(cos(a1) * r0, 0.0, sin(a1) * r0)
			var t0 := xf * Vector3(cos(a0) * r1, h, sin(a0) * r1)
			var t1 := xf * Vector3(cos(a1) * r1, h, sin(a1) * r1)
			if segs > 5:
				var tilt := (r0 - r1) / maxf(h, 0.001)
				var n0 := (xf.basis * Vector3(cos(a0), tilt, sin(a0))).normalized()
				var n1 := (xf.basis * Vector3(cos(a1), tilt, sin(a1))).normalized()
				tri_round(b0, t1, t0, n0, n1, n0, col)
				tri_round(b0, b1, t1, n0, n1, n1, col)
			else:
				quad(b0, t0, t1, b1, col)
			if cap.a != 0.0:
				mat = S_LOG_END
			var u0 := Vector2(cos(a0), sin(a0))
			var u1 := Vector2(cos(a1), sin(a1))
			if r0 > 0.0:
				var nb := -(xf.basis.y).normalized()
				tri_round(xf * Vector3.ZERO, b0, b1, nb, nb, nb, end, Vector2.ZERO, u0, u1)
			if r1 > 0.0:
				var nt := (xf.basis.y).normalized()
				tri_round(xf * Vector3(0.0, h, 0.0), t1, t0, nt, nt, nt, end, Vector2.ZERO, u1, u0)
			mat = side_mat

	## A cylinder from one point to another (a log, a pole, a rail).
	func rod(from: Vector3, to: Vector3, radius: float, segs: int, col: Color, cap: Color = Color(0, 0, 0, 0)) -> void:
		var axis := to - from
		if axis.length() < 0.001:
			return
		var up := axis.normalized()
		var side := up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
		cyl(Transform3D(Basis(side, up, side.cross(up)), from), radius, radius, axis.length(), segs, col, cap)

	## A board lying along a line in the x-y plane (from p0 to p1), reaching from z0 to z1, with
	## its bottom face on that line and `thick` metres of it above (for the roof and ceiling).
	func slab(p0: Vector2, p1: Vector2, z0: float, z1: float, thick: float, col: Color) -> void:
		var d := (p1 - p0).normalized()
		var n := Vector2(-d.y, d.x)
		if n.y < 0.0:
			n = -n
		var mid := (p0 + p1) * 0.5 + n * thick * 0.5
		var basis := Basis(Vector3(d.x, d.y, 0.0), Vector3(n.x, n.y, 0.0), Vector3(0.0, 0.0, 1.0))
		box(Transform3D(basis, Vector3(mid.x, mid.y, (z0 + z1) * 0.5)), Vector3(p0.distance_to(p1), thick, absf(z1 - z0)), col)

	## The mesh: one surface per kind of surface used, each with its material from `materials`
	## (an S_ kind -> Material). Without materials everything is one surface (the caller puts a
	## material_override on it).
	func to_mesh(materials: Dictionary = {}) -> ArrayMesh:
		var mesh := ArrayMesh.new()
		if verts.is_empty():
			return mesh
		var groups: Array = [-1] if materials.is_empty() else materials.keys()
		for g: int in groups:
			var v := PackedVector3Array()
			var n := PackedVector3Array()
			var c := PackedColorArray()
			var u := PackedVector2Array()
			for i in verts.size():
				if g == -1 or kinds[i] == g:
					v.append(verts[i])
					n.append(normals[i])
					c.append(colors[i])
					u.append(uv2s[i])
			if v.is_empty():
				continue
			var arrays: Array = []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = v
			arrays[Mesh.ARRAY_NORMAL] = n
			arrays[Mesh.ARRAY_COLOR] = c
			arrays[Mesh.ARRAY_TEX_UV2] = u
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			if g != -1:
				mesh.surface_set_material(mesh.get_surface_count() - 1, materials[g])
		return mesh


## The height of the ceiling (the underside of the roof) at x: EAVE_Y at the side walls, rising
## in a straight line to RIDGE_Y over the middle.
static func roof_y(x: float) -> float:
	return EAVE_Y + (RIDGE_Y - EAVE_Y) * (1.0 - absf(x) / HALF_W)


## The plain material every flat-coloured part uses: the colour comes from the mesh's corners.
static func _flat_material(rough: float = 0.85) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = rough
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


static func _add_mesh(parent: Node3D, node_name: String, mesh: Mesh, mat: Material, shadows: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## A marker node at `at` whose +Z axis points (level) at `toward`.
static func _marker_facing(parent: Node3D, node_name: String, at: Vector3, toward: Vector3) -> Marker3D:
	var m := Marker3D.new()
	m.name = node_name
	parent.add_child(m)
	var dir := toward - at
	dir.y = 0.0
	if dir.length() < 0.001:
		dir = Vector3.BACK
	m.transform = Transform3D(Basis.looking_at(-dir.normalized(), Vector3.UP), at)
	return m


# ── The whole room ───────────────────────────────────────────
## Builds the cabin and the placeholder clearing under `room`. Returns what the room script
## goes on using:
##   screen (MeshInstance3D "TVScreen"): the main screen for this view (see the den note above),
##   fires (Array[Marker3D] "FIRE_Hearth", "FIRE_Den"): bottom centre of each fire's flames,
##   ember_mat (ShaderMaterial, cabin_embers.gdshader): the glowing coals under both fires,
##   glow_mat (ShaderMaterial, cabin_shade.gdshader): lampshades, the chandelier's candles and
##     the lantern, which glow with the house lights (the room script sets its `level`),
##   smoke_spots (Array[Vector3]): the tops of the two chimneys, where the room script lets the
##     smoke rise (the great room's first),
##   glass_mat (ShaderMaterial, rooms/weather/weather_glass.gdshader): every window pane,
##   shelters, eaves: the indoors and the dripping roof edges, for the weather (see shelters()),
##   tree_mats (Array): the detailed trees' materials (the weather sets their wind and frost).
static func build(room: Node3D, view: String = "great_room") -> Dictionary:
	var out := build_cabin(room, view)
	out["smoke_spots"] = SMOKE_SPOTS
	out["shelters"] = shelters()
	out["eaves"] = eaves()
	_build_clearing(room.get_node("Set") as Node3D, out)
	return out


## The indoors as boxes (world space when the room sits at the origin, as it does): rain and snow
## vanish inside them (room_weather.gd). They take in the roofs' overhangs, so nothing falls on
## the cabin's own roof eaves from inside the shot.
static func shelters() -> Array:
	return [
		AABB(Vector3(-HALF_W - ROOF_SIDE, -1.0, -ROOF_FRONT), Vector3(2.0 * (HALF_W + ROOF_SIDE), RIDGE_Y + 1.5, BACK_Z + ROOF_FRONT + ROOF_BACK)),
		AABB(Vector3(DEN_FAR_X - 0.6, -1.0, DEN_Z.x - 0.6), Vector3(-HALF_W - DEN_FAR_X + 0.6, DEN_RIDGE_Y + 1.0, DEN_Z.y - DEN_Z.x + 1.2)),
	]


## The roof edges water drips off in the rain (room_weather.gd), as [from, to]: the great room's
## right eave (over the deck's side) and back eave line, and the den's two long eaves. The great
## room's left eave sits over the den's roof, so it has none.
static func eaves() -> Array:
	var ye := EAVE_Y - ROOF_SIDE * (RIDGE_Y - EAVE_Y) / HALF_W
	var x := HALF_W + ROOF_SIDE
	var dye := DEN_EAVE_Y - 0.5 * (DEN_RIDGE_Y - DEN_EAVE_Y) / (DEN_MID_Z - DEN_Z.x)
	return [
		[Vector3(x, ye - 0.05, -ROOF_FRONT), Vector3(x, ye - 0.05, BACK_Z + ROOF_BACK)],
		[Vector3(DEN_FAR_X - 0.5, dye - 0.05, DEN_Z.x - 0.5), Vector3(-HALF_W - 0.1, dye - 0.05, DEN_Z.x - 0.5)],
		[Vector3(DEN_FAR_X - 0.5, dye - 0.05, DEN_Z.y + 0.5), Vector3(-HALF_W - 0.1, dye - 0.05, DEN_Z.y + 0.5)],
	]


## Just the cabin (with the den), its deck and stoop, its furniture and its markers (no outside).
## The scene rooms planned for later call this and add their own scenery. view = "great_room" or
## "den" (cabin_view, "Gather in"): where the presenters sit and which screen is the main one.
static func build_cabin(room: Node3D, view: String = "great_room") -> Dictionary:
	var out: Dictionary = {}
	var fires: Array[Marker3D] = []
	out["fires"] = fires
	var set_root := Node3D.new()
	set_root.name = "Set"
	room.add_child(set_root)
	var markers := Node3D.new()
	markers.name = "Markers"
	room.add_child(markers)
	var surf := _surface_materials(out)

	var logs := Buf.new()             # the log walls
	_build_walls(logs)
	_add_mesh(set_root, "LogWalls", logs.to_mesh(surf), null)
	var shell := Buf.new()            # floor, footing, roof, beams, gable boards, frames, loft, stairs
	_build_shell(shell)
	_build_loft(shell)
	_add_mesh(set_root, "Shell", shell.to_mesh(surf), null)
	var stone := Buf.new()            # the chimney and the hearth
	_build_chimney(stone, markers, out)
	_add_mesh(set_root, "Chimney", stone.to_mesh(surf), null)
	var stuff := Buf.new()            # furniture and things
	_build_great_room(stuff)
	_build_back_rooms(stuff)
	_build_outside_bits(stuff)
	_add_mesh(set_root, "Furniture", stuff.to_mesh(surf), null)
	var den := Buf.new()              # the den: walls, ceiling, roof, chimney, sofa, armchair
	_build_den(den, markers, out)
	_add_mesh(set_root, "Den", den.to_mesh(surf), null)
	_build_glass(set_root, out)
	_build_screens(set_root, out, view)
	if view == "den":
		_den_presenters(markers)
	else:
		_build_podiums(set_root, markers, surf)
	_build_lamps(set_root, room, out)
	_build_markers(markers, view)
	return out


# ── Walls ────────────────────────────────────────────────────
## The three log walls (left, right, back). Each log row runs the wall's length, broken where a
## window or door is; the end logs stick out past the corners.
static func _build_walls(b: Buf) -> void:
	var rows := int(floor((EAVE_Y - LOG_R) / LOG_STEP)) + 1
	for r in rows:
		var y := LOG_R + float(r) * LOG_STEP
		# the two side walls run from the glass wall (z = 0) to the back wall
		for side: String in ["left", "right"]:
			var x := -HALF_W if side == "left" else HALF_W
			for span in _spans(side, -LOG_OVERHANG, BACK_Z + LOG_OVERHANG, y):
				b.mat = S_LOG
				b.rod(Vector3(x, y, span.x), Vector3(x, y, span.y), _log_r(r, span.x), 14, _log_col(r, span.x), C_LOG_END)
				if r > 0:
					_chinking(b, Vector3(x, y - LOG_STEP * 0.5, span.x), Vector3(x, y - LOG_STEP * 0.5, span.y))
		# the back wall runs across, half a log higher (the corners interlock)
		var yb := y + LOG_STEP * 0.5
		for span in _spans("back", -HALF_W - LOG_OVERHANG, HALF_W + LOG_OVERHANG, yb):
			b.mat = S_LOG
			b.rod(Vector3(span.x, yb, BACK_Z), Vector3(span.y, yb, BACK_Z), _log_r(r + 7, span.x), 14, _log_col(r + 1, span.x), C_LOG_END)
			if r > 0:
				_chinking(b, Vector3(span.x, yb - LOG_STEP * 0.5, BACK_Z), Vector3(span.y, yb - LOG_STEP * 0.5, BACK_Z))
	# the back gable above the logs: upright boards up to the ridge
	b.mat = S_CEILING
	var top := EAVE_Y + LOG_STEP * 0.5
	b.tri(Vector3(-HALF_W, top, BACK_Z), Vector3(HALF_W, top, BACK_Z), Vector3(0.0, RIDGE_Y + 0.1, BACK_Z), C_PINE.darkened(0.2))
	# window frames and the back door's frame and door
	b.mat = S_TIMBER
	for w: Array in WINDOWS:
		_window_frame(b, String(w[0]), float(w[1]), float(w[2]), float(w[3]), float(w[4]))
	_window_frame(b, "left", DEN_DOOR.x, DEN_DOOR.y, 0.0, DEN_DOOR.z)
	b.block(Vector3(BACK_DOOR.x, 0.0, BACK_Z - 0.06), Vector3(BACK_DOOR.y, BACK_DOOR.z, BACK_Z + 0.06), C_TIMBER.darkened(0.2))
	b.block(Vector3(BACK_DOOR.x - 0.1, 0.0, BACK_Z - 0.2), Vector3(BACK_DOOR.x, BACK_DOOR.z + 0.1, BACK_Z + 0.2), C_FRAME)
	b.block(Vector3(BACK_DOOR.y, 0.0, BACK_Z - 0.2), Vector3(BACK_DOOR.y + 0.1, BACK_DOOR.z + 0.1, BACK_Z + 0.2), C_FRAME)
	b.block(Vector3(BACK_DOOR.x - 0.1, BACK_DOOR.z, BACK_Z - 0.2), Vector3(BACK_DOOR.y + 0.1, BACK_DOOR.z + 0.12, BACK_Z + 0.2), C_FRAME)


## A log's radius: LOG_R, a little thicker or thinner from log to log (row, and where it starts),
## so the wall doesn't look machined.
static func _log_r(row: int, start: float) -> float:
	return LOG_R * (1.0 + 0.06 * sin(float(row) * 2.7 + start * 1.3))


## A log's colour: C_LOG, a shade lighter or darker from log to log.
static func _log_col(row: int, start: float) -> Color:
	var k := sin(float(row) * 1.9 + start * 0.7)
	return C_LOG.darkened(0.08 * k) if k > 0.0 else C_LOG.lightened(-0.06 * k)


## The chinking along the joint between two stacked logs (from `a` to `b`, the joint's line in
## the middle of the wall): a strip of light plaster set back in the groove on both faces.
static func _chinking(b: Buf, a: Vector3, c: Vector3) -> void:
	var keep := b.mat
	b.mat = S_CHINK
	var along_x := absf(c.x - a.x) > absf(c.z - a.z)
	var half := Vector3(0.0, 0.04, 0.13) if along_x else Vector3(0.13, 0.04, 0.0)
	b.block(Vector3(minf(a.x, c.x), a.y, minf(a.z, c.z)) - half, Vector3(maxf(a.x, c.x), a.y, maxf(a.z, c.z)) + half, C_CHINK)
	b.mat = keep


## The pieces of one log row along a wall at height y: [from, to] spans between the wall's ends,
## skipping each window or door the row passes through.
static func _spans(wall: String, from: float, to: float, y: float) -> Array[Vector2]:
	var cuts: Array[Vector2] = []
	for w: Array in WINDOWS:
		if String(w[0]) == wall and y > float(w[3]) - LOG_R * 0.5 and y < float(w[4]) + LOG_R * 0.5:
			cuts.append(Vector2(float(w[1]), float(w[2])))
	if wall == "back" and y < BACK_DOOR.z + LOG_R * 0.5:
		cuts.append(Vector2(BACK_DOOR.x, BACK_DOOR.y))
	if wall == "left" and y < DEN_DOOR.z + LOG_R * 0.5:
		cuts.append(Vector2(DEN_DOOR.x, DEN_DOOR.y))
	cuts.sort_custom(func(a: Vector2, c: Vector2) -> bool: return a.x < c.x)
	var out: Array[Vector2] = []
	var at := from
	for c in cuts:
		if c.x > at:
			out.append(Vector2(at, c.x))
		at = maxf(at, c.y)
	if to > at:
		out.append(Vector2(at, to))
	return out


## A timber frame round a window opening, with a sill.
static func _window_frame(b: Buf, wall: String, from: float, to: float, sill: float, top: float) -> void:
	var t := 0.08
	if wall == "back":
		b.block(Vector3(from - t, sill - t, BACK_Z - 0.22), Vector3(to + t, sill, BACK_Z + 0.22), C_FRAME)
		b.block(Vector3(from - t, top, BACK_Z - 0.2), Vector3(to + t, top + t, BACK_Z + 0.2), C_FRAME)
		b.block(Vector3(from - t, sill, BACK_Z - 0.2), Vector3(from, top, BACK_Z + 0.2), C_FRAME)
		b.block(Vector3(to, sill, BACK_Z - 0.2), Vector3(to + t, top, BACK_Z + 0.2), C_FRAME)
		return
	var x := -HALF_W if wall == "left" else HALF_W
	b.block(Vector3(x - 0.22, sill - t, from - t), Vector3(x + 0.22, sill, to + t), C_FRAME)
	b.block(Vector3(x - 0.2, top, from - t), Vector3(x + 0.2, top + t, to + t), C_FRAME)
	b.block(Vector3(x - 0.2, sill, from - t), Vector3(x + 0.2, top, from), C_FRAME)
	b.block(Vector3(x - 0.2, sill, to), Vector3(x + 0.2, top, to + t), C_FRAME)


# ── Floor, roof, beams, the front frame ──────────────────────
static func _build_shell(b: Buf) -> void:
	# the floor and the stone footing under the cabin
	b.mat = S_FLOOR
	b.block(Vector3(-HALF_W, -0.2, 0.0), Vector3(HALF_W, 0.0, BACK_Z), C_FLOOR)
	b.mat = S_STONE
	b.block(Vector3(-HALF_W - 0.15, GROUND_Y - 0.1, -0.1), Vector3(HALF_W + 0.15, -0.2, BACK_Z + 0.15), C_STONE_DARK)
	# the roof: a thin pine ceiling right on the roof line, the roofing on top of it
	var eave := Vector2(HALF_W + ROOF_SIDE, roof_y(HALF_W + ROOF_SIDE))
	for sx: float in [-1.0, 1.0]:
		var e := Vector2(eave.x * sx, eave.y)
		b.mat = S_CEILING
		b.slab(e, Vector2(0.0, RIDGE_Y), -ROOF_FRONT, BACK_Z + ROOF_BACK, 0.06, C_PINE)
		b.mat = S_ROOF
		b.slab(Vector2(e.x, e.y + 0.07), Vector2(0.0, RIDGE_Y + 0.07), -ROOF_FRONT - 0.05, BACK_Z + ROOF_BACK + 0.05, 0.22, C_ROOF)
	# the ridge beam, and the log rafters and collar ties across the great room
	b.mat = S_LOG
	b.block(Vector3(-0.18, RIDGE_Y - 0.42, -ROOF_FRONT), Vector3(0.18, RIDGE_Y, BACK_Z + ROOF_BACK), C_TIMBER)
	for z in COLLARS_Z:
		var cx := HALF_W * (1.0 - (COLLAR_Y - EAVE_Y) / (RIDGE_Y - EAVE_Y))
		b.rod(Vector3(-cx, COLLAR_Y, z), Vector3(cx, COLLAR_Y, z), 0.15, 10, C_TIMBER, C_LOG_END)
		b.rod(Vector3(0.0, COLLAR_Y, z), Vector3(0.0, RIDGE_Y - 0.4, z), 0.12, 10, C_TIMBER)
		for sx: float in [-1.0, 1.0]:
			b.rod(Vector3(sx * HALF_W, EAVE_Y - 0.1, z), Vector3(0.0, RIDGE_Y - 0.25, z), 0.15, 10, C_TIMBER)
	# the front window wall's timber frame: posts, the beam at eave height, and beams under the
	# roof line (the glass itself is _build_glass)
	b.mat = S_TIMBER
	for i in MULLIONS.size():
		for sx: float in [-1.0, 1.0]:
			var x := MULLIONS[i] * sx
			b.block(Vector3(x - 0.09, 0.0, -0.1), Vector3(x + 0.09, roof_y(x), 0.1), C_FRAME)
	for sx: float in [-1.0, 1.0]:
		b.block(Vector3(minf(sx * HALF_W, sx * CHIM_HALF), EAVE_Y - 0.08, -0.1), Vector3(maxf(sx * HALF_W, sx * CHIM_HALF), EAVE_Y + 0.08, 0.1), C_FRAME)
		b.block(Vector3(minf(sx * HALF_W, sx * CHIM_HALF), 0.0, -0.12), Vector3(maxf(sx * HALF_W, sx * CHIM_HALF), 0.12, 0.12), C_FRAME)
		b.slab(Vector2(sx * HALF_W, EAVE_Y - 0.12), Vector2(0.0, RIDGE_Y - 0.12), -0.12, 0.12, 0.12, C_FRAME)
	# the glass doors' frames in the two front corners (thicker, with a handle)
	for sx: float in [-1.0, 1.0]:
		var x0 := minf(GLASS_DOOR.x * sx, GLASS_DOOR.y * sx)
		var x1 := maxf(GLASS_DOOR.x * sx, GLASS_DOOR.y * sx)
		b.block(Vector3(x0, 2.2, -0.12), Vector3(x1, 2.32, 0.12), C_FRAME)
		var hx := x1 - 0.12 if sx < 0.0 else x0 + 0.12
		b.mat = S_IRON
		b.block(Vector3(hx - 0.02, 0.95, -0.14), Vector3(hx + 0.02, 1.15, 0.14), C_IRON)
		b.mat = S_TIMBER


## The loft across the back: its floor, two log posts holding its front edge, the railing (with
## the gap where the stairs arrive) and the stairs up the right wall.
static func _build_loft(b: Buf) -> void:
	b.mat = S_FLOOR
	b.block(Vector3(-HALF_W, LOFT_Y - 0.25, LOFT_FRONT_Z), Vector3(HALF_W, LOFT_Y, BACK_Z), C_FLOOR)
	b.mat = S_TIMBER
	b.block(Vector3(-HALF_W, LOFT_Y - 0.45, LOFT_FRONT_Z - 0.05), Vector3(HALF_W, LOFT_Y - 0.25, LOFT_FRONT_Z + 0.25), C_TIMBER)
	b.mat = S_LOG
	for x: float in [-2.4, 2.4]:
		b.rod(Vector3(x, 0.0, LOFT_FRONT_Z + 0.1), Vector3(x, LOFT_Y - 0.25, LOFT_FRONT_Z + 0.1), 0.16, 14, C_LOG, C_LOG_END)
	b.mat = S_TIMBER
	var rail_y := LOFT_Y + 1.0
	var rail_end := STAIR_X.x
	b.rod(Vector3(-HALF_W, rail_y, LOFT_FRONT_Z + 0.05), Vector3(rail_end, rail_y, LOFT_FRONT_Z + 0.05), 0.05, 8, C_TIMBER)
	b.rod(Vector3(-HALF_W, LOFT_Y + 0.12, LOFT_FRONT_Z + 0.05), Vector3(rail_end, LOFT_Y + 0.12, LOFT_FRONT_Z + 0.05), 0.04, 6, C_TIMBER)
	var x := -HALF_W + 0.2
	while x < rail_end:
		b.rod(Vector3(x, LOFT_Y, LOFT_FRONT_Z + 0.05), Vector3(x, rail_y, LOFT_FRONT_Z + 0.05), 0.022 if fmod(x + HALF_W, 1.3) > 0.2 else 0.06, 5, C_TIMBER)
		x += 0.22
	# the stairs: solid wooden steps, rising towards the back
	b.mat = S_FLOOR
	var run := (LOFT_FRONT_Z - STAIR_START_Z) / float(STAIR_STEPS)
	var rise := LOFT_Y / float(STAIR_STEPS)
	for i in STAIR_STEPS:
		var z0 := STAIR_START_Z + float(i) * run
		b.block(Vector3(STAIR_X.x, 0.0, z0), Vector3(STAIR_X.y, rise * float(i + 1), z0 + run), C_FLOOR.darkened(0.05 * float(i % 2)))
	b.mat = S_TIMBER
	b.rod(Vector3(STAIR_X.x, 1.0, STAIR_START_Z), Vector3(STAIR_X.x, LOFT_Y + 1.0, LOFT_FRONT_Z), 0.045, 8, C_TIMBER)
	for i in range(0, STAIR_STEPS, 2):
		var z := STAIR_START_Z + (float(i) + 0.5) * run
		var y := rise * float(i + 1)
		b.rod(Vector3(STAIR_X.x, y, z), Vector3(STAIR_X.x, y + 0.95, z), 0.03, 5, C_TIMBER)


# ── The chimney ──────────────────────────────────────────────
## The stone chimney standing in the middle of the glass wall: a wide lower part (the fireplace,
## with the screen above the mantel on its room side), a narrower stack up through the roof, the
## raised hearth in front with a niche of split logs, and the mantel shelf on two corbels.
static func _build_chimney(b: Buf, markers: Node3D, out: Dictionary) -> void:
	var fb_back := CHIM_IN_Z - FIREBOX_DEPTH
	b.mat = S_STONE
	# behind the firebox, full width and height of the wide part
	b.block(Vector3(-CHIM_HALF, 0.0, CHIM_OUT_Z), Vector3(CHIM_HALF, CHIM_WIDE_TOP, fb_back), C_STONE)
	# either side of the firebox, under it and over it
	b.block(Vector3(-CHIM_HALF, 0.0, fb_back), Vector3(-FIREBOX_HALF, CHIM_WIDE_TOP, CHIM_IN_Z), C_STONE)
	b.block(Vector3(FIREBOX_HALF, 0.0, fb_back), Vector3(CHIM_HALF, CHIM_WIDE_TOP, CHIM_IN_Z), C_STONE)
	b.block(Vector3(-FIREBOX_HALF, 0.0, fb_back), Vector3(FIREBOX_HALF, FIREBOX_Y.x, CHIM_IN_Z), C_STONE_DARK)
	b.block(Vector3(-FIREBOX_HALF, FIREBOX_Y.y, fb_back), Vector3(FIREBOX_HALF, CHIM_WIDE_TOP, CHIM_IN_Z), C_STONE)
	# the sooty inside of the firebox
	b.mat = S_PLAIN
	b.block(Vector3(-FIREBOX_HALF, FIREBOX_Y.x, fb_back - 0.01), Vector3(FIREBOX_HALF, FIREBOX_Y.y, fb_back + 0.02), C_SOOT)
	b.mat = S_STONE
	# the shoulders slope in to the stack, and the stack goes up through the roof
	var stack_z := Vector2(CHIM_OUT_Z + 0.25, CHIM_IN_Z - 0.35)
	for sx: float in [-1.0, 1.0]:
		b.quad(Vector3(sx * CHIM_HALF, CHIM_WIDE_TOP, CHIM_OUT_Z), Vector3(sx * CHIM_STACK_HALF, CHIM_WIDE_TOP + 0.9, stack_z.x),
			Vector3(sx * CHIM_STACK_HALF, CHIM_WIDE_TOP + 0.9, stack_z.y), Vector3(sx * CHIM_HALF, CHIM_WIDE_TOP, CHIM_IN_Z), C_STONE)
	b.quad(Vector3(-CHIM_HALF, CHIM_WIDE_TOP, CHIM_IN_Z), Vector3(CHIM_HALF, CHIM_WIDE_TOP, CHIM_IN_Z),
		Vector3(CHIM_STACK_HALF, CHIM_WIDE_TOP + 0.9, stack_z.y), Vector3(-CHIM_STACK_HALF, CHIM_WIDE_TOP + 0.9, stack_z.y), C_STONE)
	b.quad(Vector3(-CHIM_HALF, CHIM_WIDE_TOP, CHIM_OUT_Z), Vector3(CHIM_HALF, CHIM_WIDE_TOP, CHIM_OUT_Z),
		Vector3(CHIM_STACK_HALF, CHIM_WIDE_TOP + 0.9, stack_z.x), Vector3(-CHIM_STACK_HALF, CHIM_WIDE_TOP + 0.9, stack_z.x), C_STONE)
	b.block(Vector3(-CHIM_STACK_HALF, CHIM_WIDE_TOP + 0.9, stack_z.x), Vector3(CHIM_STACK_HALF, CHIM_TOP, stack_z.y), C_STONE)
	b.block(Vector3(-CHIM_STACK_HALF - 0.1, CHIM_TOP, stack_z.x - 0.1), Vector3(CHIM_STACK_HALF + 0.1, CHIM_TOP + 0.18, stack_z.y + 0.1), C_STONE_DARK)
	# fieldstones standing a little proud of the face, so it reads as stone even in the Simple look
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261117
	for i in 60:
		var x := rng.randf_range(-CHIM_HALF + 0.2, CHIM_HALF - 0.2)
		var y := rng.randf_range(0.2, CHIM_WIDE_TOP - 0.2)
		var fire_hole := absf(x) < FIREBOX_HALF + 0.15 and y < FIREBOX_Y.y + 0.15
		var behind_screen := absf(x) < SCREEN_SIZE.x * 0.5 + 0.05 and y > SCREEN_BOTTOM - 0.05 and y < SCREEN_BOTTOM + SCREEN_SIZE.y + 0.05
		if fire_hole or behind_screen:
			continue
		var s := Vector3(rng.randf_range(0.25, 0.5), rng.randf_range(0.18, 0.3), 0.08)
		b.soft_box(Transform3D(Basis.IDENTITY, Vector3(x, y, CHIM_IN_Z + 0.01)), s, 0.035, C_STONE.darkened(rng.randf_range(0.0, 0.2)), 0.7)
	# the raised hearth, with a niche of split logs in its front
	b.block(Vector3(-HEARTH_HALF, 0.0, CHIM_IN_Z), Vector3(HEARTH_HALF, HEARTH_H, CHIM_IN_Z + HEARTH_OUT), C_STONE.lightened(0.1))
	b.block(Vector3(-HEARTH_HALF + 0.3, 0.05, CHIM_IN_Z + HEARTH_OUT - 0.02), Vector3(-0.9, HEARTH_H - 0.06, CHIM_IN_Z + HEARTH_OUT + 0.005), C_SOOT)
	b.mat = S_BARK
	for r in 3:
		for c in 4:
			var at := Vector3(-HEARTH_HALF + 0.42 + float(c) * 0.32 + (0.16 if r % 2 == 1 else 0.0), 0.12 + float(r) * 0.1, CHIM_IN_Z + 0.08)
			if at.x < -1.0:
				b.rod(at, at + Vector3(0.0, 0.0, HEARTH_OUT - 0.07), 0.055, 8, C_BARK, C_LOG_END)
	# the mantel: a heavy hand-hewn beam on two corbels
	b.mat = S_TIMBER
	b.block(Vector3(-1.95, MANTEL_Y - 0.2, CHIM_IN_Z), Vector3(1.95, MANTEL_Y, CHIM_IN_Z + 0.3), C_TIMBER)
	for sx: float in [-1.0, 1.0]:
		b.block(Vector3(sx * 1.6 - 0.08, MANTEL_Y - 0.48, CHIM_IN_Z), Vector3(sx * 1.6 + 0.08, MANTEL_Y - 0.2, CHIM_IN_Z + 0.22), C_TIMBER)
	# andirons and logs in the firebox
	var fire_at := Vector3(0.0, FIREBOX_Y.x + 0.02, CHIM_IN_Z - FIREBOX_DEPTH * 0.45)
	_fire_logs(b, Transform3D(Basis.IDENTITY, fire_at), 1.0)
	var fire := Marker3D.new()
	fire.name = "FIRE_Hearth"
	markers.add_child(fire)
	fire.position = fire_at
	(out["fires"] as Array[Marker3D]).append(fire)
	# the glowing coals under the logs (cabin_embers.gdshader: they pulse slowly; how bright
	# follows the Fire setting, the room script sets `amount`)
	var ember_mat := ShaderMaterial.new()
	ember_mat.shader = EMBER_SHADER
	ember_mat.set_shader_parameter("noise", load("res://rooms/campfire/textures/sky_noise.png"))
	var coals := BoxMesh.new()
	coals.size = Vector3(0.9, 0.05, 0.35)
	var coal_mi := MeshInstance3D.new()
	coal_mi.name = "Embers"
	coal_mi.mesh = coals
	coal_mi.material_override = ember_mat
	coal_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	markers.get_parent().get_node("Set").add_child(coal_mi)
	coal_mi.position = fire_at
	out["ember_mat"] = ember_mat


## The andirons and the logs burning on them, in the fire's own axes (xf; +Z = out into the
## room), `k` = their size (the den's fire is a little smaller).
static func _fire_logs(b: Buf, xf: Transform3D, k: float) -> void:
	var keep := b.mat
	b.mat = S_IRON
	for sx: float in [-0.35, 0.35]:
		b.rod(xf * (Vector3(sx, 0.0, -0.15) * k), xf * (Vector3(sx, 0.0, 0.2) * k), 0.025, 5, C_IRON)
		b.rod(xf * (Vector3(sx, 0.0, 0.2) * k), xf * (Vector3(sx, 0.16, 0.24) * k), 0.022, 5, C_IRON)
	b.mat = S_BARK
	var charred := C_BARK.darkened(0.55)
	b.rod(xf * (Vector3(-0.45, 0.08, -0.05) * k), xf * (Vector3(0.45, 0.1, -0.08) * k), 0.07 * k, 10, charred, C_SOOT)
	b.rod(xf * (Vector3(-0.4, 0.08, 0.1) * k), xf * (Vector3(0.4, 0.14, 0.05) * k), 0.06 * k, 10, charred, C_SOOT)
	b.rod(xf * (Vector3(-0.25, 0.16, -0.12) * k), xf * (Vector3(0.2, 0.26, 0.08) * k), 0.05 * k, 10, charred, C_SOOT)
	b.mat = keep


# ── The great room ───────────────────────────────────────────
## Everything in the tall part of the room: rug, coffee table, cushions, the two leather sofas,
## the armchairs with their side tables, and the chandelier.
static func _build_great_room(b: Buf) -> void:
	b.rug_quad(Vector2(-3.4, 1.45), Vector2(3.4, 4.65), 0.012, C_RUG_MEAN)
	# a live-edge coffee table: a thick slab with soft, uneven edges on two stout legs
	b.mat = S_TIMBER
	b.soft_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.4, 2.75)), Vector3(2.0, 0.09, 0.64), 0.04, C_TIMBER.lightened(0.12), 0.4)
	for sx: float in [-0.75, 0.75]:
		b.soft_box(Transform3D(Basis.IDENTITY, Vector3(sx, 0.18, 2.75)), Vector3(0.14, 0.36, 0.46), 0.03, C_TIMBER, 0.3)
	_table_things(b, Vector3(0.0, 0.445, 2.75), 1)
	# sheepskins and cushions by the hearth (under the Hearth_ seats)
	b.mat = S_FLEECE
	for s: Array in SEATS:
		if String(s[0]).begins_with("Hearth"):
			var x := float(s[1])
			var z := float(s[3])
			var wool := int(x * 2.0) % 2 == 0
			b.soft_box(Transform3D(Basis(Vector3.UP, x * 0.4), Vector3(x, 0.05, z)), Vector3(0.68, 0.1, 0.58), 0.05, C_WOOL if wool else C_FABRIC, 1.0)
			b.soft_box(Transform3D(Basis(Vector3.UP, x * 0.4 + 0.3), Vector3(x + 0.05, 0.13, z + 0.02)), Vector3(0.5, 0.12, 0.45), 0.06, C_WOOL.darkened(0.08) if wool else C_RUG.lightened(0.2), 1.0)
	# the sofas: each seats three, facing the screen (-Z)
	for sx: float in [-1.0, 1.0]:
		var xf := Transform3D(Basis.IDENTITY, Vector3(sx * 2.1, 0.0, 3.92))
		_sofa(b, xf, 3, 1.0, C_LEATHER)
		# a knitted throw over one end of the back
		b.mat = S_FLEECE
		b.soft_box(xf * Transform3D(Basis(Vector3.RIGHT, -0.25), Vector3(-sx * 0.9, 0.85, 0.43)), Vector3(0.75, 0.42, 0.1), 0.04, C_FABRIC if sx < 0.0 else C_THROW_GREEN, 1.0)
	# the four armchairs (under the Arm_ seats), turned to face the screen
	for s: Array in SEATS:
		if String(s[0]).begins_with("Arm"):
			_armchair(b, Vector3(float(s[1]), 0.0, float(s[3])), C_LEATHER.lightened(0.08))
	# side tables beside the left armchairs and by the stairs (the table lamps stand on them)
	for at: Vector3 in [Vector3(-5.6, 0.0, 2.6), Vector3(4.95, 0.0, 2.9)]:
		_side_table(b, at)
	# the chandelier: an iron ring of candles hanging from the ridge on a chain
	b.mat = S_IRON
	var ch := Vector3(0.0, 5.0, 3.0)
	b.rod(ch, Vector3(0.0, RIDGE_Y - 0.4, 3.0), 0.02, 4, C_IRON)
	for i in 12:
		var a0 := TAU * float(i) / 12.0
		var a1 := TAU * float(i + 1) / 12.0
		b.rod(ch + Vector3(cos(a0), 0.0, sin(a0)) * 0.65, ch + Vector3(cos(a1), 0.0, sin(a1)) * 0.65, 0.025, 5, C_IRON)
		b.cyl(Transform3D(Basis.IDENTITY, ch + Vector3(cos(a0), 0.0, sin(a0)) * 0.65 - Vector3(0.0, 0.01, 0.0)), 0.045, 0.045, 0.02, 6, C_IRON)
	for i in 4:
		var a := TAU * float(i) / 4.0 + 0.4
		b.rod(ch + Vector3(cos(a), 0.0, sin(a)) * 0.65, ch + Vector3(0.0, 0.8, 0.0), 0.012, 4, C_IRON)


## A leather armchair standing at `at`, facing the screen (-Z, where the chimney is).
static func _armchair(b: Buf, at: Vector3, col: Color) -> void:
	var to_screen := Vector3(0.0, 0.0, CHIM_IN_Z) - at
	to_screen.y = 0.0
	var basis := Basis.looking_at(to_screen.normalized(), Vector3.UP)      # -Z = towards the screen
	_sofa(b, Transform3D(basis, at), 1, 0.72, col)


## A leather sofa (or, with one seat, an armchair) standing on xf's origin, facing its -Z:
## `seats` seat cushions of `seat_w` metres side by side, back cushions, rolled arms and short
## wooden feet. Seat height 0.45 to 0.5 (the AUDIENCE_ and PRESENTER_ markers sit at 0.45).
static func _sofa(b: Buf, xf: Transform3D, seats: int, seat_w: float, col: Color) -> void:
	var keep := b.mat
	var w := float(seats) * seat_w
	b.mat = S_LEATHER
	# the frame: base, and the back rising behind the cushions
	b.soft_box(xf * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.24, 0.02)), Vector3(w + 0.04, 0.3, 0.86), 0.04, col.darkened(0.12), 0.3)
	b.soft_box(xf * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.55, 0.38)), Vector3(w + 0.04, 0.9, 0.16), 0.05, col.darkened(0.1), 0.4)
	for i in seats:
		var x := (float(i) - float(seats - 1) * 0.5) * seat_w
		# seat cushion and back cushion, plump
		b.soft_box(xf * Transform3D(Basis.IDENTITY, Vector3(x, 0.44, -0.04)), Vector3(seat_w - 0.03, 0.14, 0.76), 0.06, col.lightened(0.04), 1.0)
		b.soft_box(xf * Transform3D(Basis(Vector3.RIGHT, -0.18), Vector3(x, 0.75, 0.22)), Vector3(seat_w - 0.05, 0.48, 0.2), 0.08, col.lightened(0.02), 1.0)
	# rolled arms
	for sd: float in [-1.0, 1.0]:
		var ax := sd * (w * 0.5 + 0.11)
		b.soft_box(xf * Transform3D(Basis.IDENTITY, Vector3(ax, 0.3, 0.0)), Vector3(0.2, 0.56, 0.88), 0.06, col.darkened(0.06), 0.6)
		b.rod(xf * Vector3(ax, 0.6, -0.45), xf * Vector3(ax, 0.6, 0.44), 0.115, 12, col.darkened(0.04))
	# short turned wooden feet
	b.mat = S_TIMBER
	for sd: float in [-1.0, 1.0]:
		for fz: float in [-0.36, 0.38]:
			b.cyl(xf * Transform3D(Basis.IDENTITY, Vector3(sd * (w * 0.5 + 0.12), 0.0, fz)), 0.035, 0.045, 0.09, 8, C_TIMBER.darkened(0.2))
	b.mat = keep


## A small side table at `at` (on the floor) with a stone lamp base on it (the lamp's shade is
## _build_lamps') and a book and a mug beside it.
static func _side_table(b: Buf, at: Vector3) -> void:
	b.mat = S_TIMBER
	b.soft_box(Transform3D(Basis.IDENTITY, at + Vector3(0.0, 0.57, 0.0)), Vector3(0.56, 0.06, 0.56), 0.015, C_TIMBER.lightened(0.05), 0.2)
	b.block(at + Vector3(-0.22, 0.12, -0.22), at + Vector3(0.22, 0.15, 0.22), C_TIMBER)
	for lx: float in [-0.22, 0.22]:
		for lz: float in [-0.22, 0.22]:
			b.block(at + Vector3(lx - 0.025, 0.0, lz - 0.025), at + Vector3(lx + 0.025, 0.54, lz + 0.025), C_TIMBER.darkened(0.1))
	b.mat = S_STONE
	b.cyl(Transform3D(Basis.IDENTITY, at + Vector3(0.0, 0.6, 0.0)), 0.09, 0.06, 0.3, 10, C_STONE.darkened(0.1))
	b.mat = S_IRON
	b.rod(at + Vector3(0.0, 0.9, 0.0), at + Vector3(0.0, 1.0, 0.0), 0.012, 4, C_IRON)
	_table_things(b, at + Vector3(0.12, 0.6, 0.14), 0)


## Small things lying on a table top at `top` (its surface's middle): kind 0 = a book and a mug,
## 1 = a stack of books, two mugs and a candle in a jar (the coffee table).
static func _table_things(b: Buf, top: Vector3, kind: int) -> void:
	var keep := b.mat
	b.mat = S_PLAIN
	var books: Array = [[Vector3(0.0, 0.0, 0.0), Vector3(0.22, 0.035, 0.16), Color(0.35, 0.16, 0.12), 0.2]]
	if kind == 1:
		books = [[Vector3(-0.55, 0.0, 0.05), Vector3(0.28, 0.04, 0.2), Color(0.2, 0.28, 0.22), 0.1],
			[Vector3(-0.55, 0.04, 0.05), Vector3(0.25, 0.035, 0.18), Color(0.45, 0.2, 0.13), -0.15],
			[Vector3(-0.55, 0.075, 0.05), Vector3(0.21, 0.03, 0.15), Color(0.62, 0.52, 0.35), 0.3]]
	for bk: Array in books:
		var size: Vector3 = bk[1]
		b.box(Transform3D(Basis(Vector3.UP, float(bk[3])), top + (bk[0] as Vector3) + Vector3(0.0, size.y * 0.5, 0.0)), size, bk[2])
	# (an if rather than a ternary: a ternary of two array literals loses the Array[Vector3] type)
	var mugs: Array[Vector3] = [Vector3(0.14, 0.0, -0.1)]
	if kind != 0:
		mugs = [Vector3(0.35, 0.0, -0.08), Vector3(0.55, 0.0, 0.1)]
	for m in mugs:
		b.cyl(Transform3D(Basis.IDENTITY, top + m), 0.04, 0.042, 0.095, 10, C_MUG)
		b.rod(top + m + Vector3(0.042, 0.03, 0.0), top + m + Vector3(0.075, 0.06, 0.0), 0.01, 4, C_MUG)
	if kind == 1:
		b.cyl(Transform3D(Basis.IDENTITY, top + Vector3(0.05, 0.0, 0.12)), 0.05, 0.05, 0.1, 10, Color(0.75, 0.6, 0.35))
	b.mat = keep


# ── Under the loft ───────────────────────────────────────────
## The kitchen in the back left corner, the dining table with its bench, the mudroom bench and
## coat pegs by the back door, and the bookshelves; plus a bench and a bed up in the loft.
static func _build_back_rooms(b: Buf) -> void:
	# kitchen: an L of base cupboards (doors marked out) with a stone worktop, open shelves with
	# enamel mugs, and a cast iron stove with a kettle
	var cup := C_TIMBER.lightened(0.15)
	b.mat = S_TIMBER
	b.block(Vector3(-HALF_W + 0.15, 0.0, 8.35), Vector3(-2.1, 0.88, BACK_Z - 0.15), cup)
	b.block(Vector3(-HALF_W + 0.15, 0.0, 7.35), Vector3(-5.85, 0.88, 8.35), cup)
	var dx := -HALF_W + 0.25
	while dx < -2.3:
		b.block(Vector3(dx, 0.1, 8.33), Vector3(dx + 0.5, 0.8, 8.36), cup.darkened(0.12))
		b.block(Vector3(dx + 0.42, 0.62, 8.31), Vector3(dx + 0.45, 0.7, 8.33), C_IRON)
		dx += 0.6
	b.mat = S_STONE
	b.block(Vector3(-HALF_W + 0.15, 0.88, 8.3), Vector3(-2.05, 0.94, BACK_Z - 0.15), C_STONE_DARK)
	b.block(Vector3(-HALF_W + 0.15, 0.88, 7.3), Vector3(-5.8, 0.94, 8.35), C_STONE_DARK)
	b.mat = S_TIMBER
	for sy: float in [1.45, 1.85]:
		b.block(Vector3(-HALF_W + 0.15, sy, 8.6), Vector3(-3.6, sy + 0.04, BACK_Z - 0.15), C_TIMBER.lightened(0.2))
	b.mat = S_PLAIN
	for i in 6:
		var mx := -6.1 + float(i) * 0.4
		b.cyl(Transform3D(Basis.IDENTITY, Vector3(mx, 1.49, 8.75)), 0.045, 0.045, 0.1, 10, C_MUG if i % 2 == 0 else Color(0.2, 0.3, 0.45))
		b.block(Vector3(mx - 0.08, 1.89, 8.65), Vector3(mx + 0.08, 1.93, 8.8), Color(0.75, 0.72, 0.66))
	b.mat = S_IRON
	b.block(Vector3(-3.5, 0.0, 8.35), Vector3(-2.55, 0.94, BACK_Z - 0.18), C_IRON.lightened(0.05))
	b.block(Vector3(-3.45, 0.94, 8.4), Vector3(-2.6, 0.97, 8.85), C_IRON)
	b.cyl(Transform3D(Basis.IDENTITY, Vector3(-3.15, 0.97, 8.6)), 0.12, 0.08, 0.16, 12, Color(0.55, 0.12, 0.08))
	b.rod(Vector3(-3.15, 1.13, 8.6), Vector3(-3.15, 1.17, 8.6), 0.03, 6, C_IRON)
	b.rod(Vector3(-3.05, 0.99, 8.6), Vector3(-2.93, 1.1, 8.6), 0.015, 5, Color(0.55, 0.12, 0.08))
	b.rod(Vector3(-3.0, 3.6, 8.75), Vector3(-3.0, 0.97, 8.75), 0.07, 10, C_IRON)        # the stove pipe
	# dining: a long live-edge table under the pendant lamp, the bench facing the view, chairs
	b.mat = S_TIMBER
	b.soft_box(Transform3D(Basis.IDENTITY, Vector3(-3.4, 0.76, 7.02)), Vector3(3.6, 0.08, 0.86), 0.035, C_TIMBER.lightened(0.08), 0.3)
	for x: float in [-4.9, -1.9]:
		b.block(Vector3(x - 0.06, 0.0, 6.7), Vector3(x + 0.06, 0.72, 7.34), C_TIMBER)
	b.block(Vector3(-4.9, 0.12, 6.98), Vector3(-1.9, 0.18, 7.06), C_TIMBER)
	b.soft_box(Transform3D(Basis.IDENTITY, Vector3(-3.35, 0.415, 6.2)), Vector3(3.8, 0.07, 0.4), 0.025, C_TIMBER.lightened(0.05), 0.3)
	for x: float in [-5.1, -1.6]:
		b.block(Vector3(x - 0.05, 0.0, 6.05), Vector3(x + 0.05, 0.38, 6.35), C_TIMBER)
	for x: float in [-4.6, -3.4, -2.2]:      # spindle-back chairs on the far side of the table
		b.block(Vector3(x - 0.22, 0.42, 7.6), Vector3(x + 0.22, 0.47, 8.0), C_TIMBER)
		for lx: float in [-0.19, 0.19]:
			for lz: float in [7.63, 7.97]:
				b.rod(Vector3(x + lx, 0.0, lz), Vector3(x + lx, 0.42, lz), 0.02, 6, C_TIMBER.darkened(0.1))
		for sp in 5:
			var px := x - 0.18 + float(sp) * 0.09
			b.rod(Vector3(px, 0.47, 7.98), Vector3(px, 0.98, 8.0), 0.012 if sp % 4 != 0 else 0.02, 5, C_TIMBER)
		b.block(Vector3(x - 0.22, 0.95, 7.96), Vector3(x + 0.22, 1.02, 8.04), C_TIMBER)
	_table_things(b, Vector3(-3.1, 0.8, 7.0), 1)
	# the pendant lamp's cord down from the loft's underside
	b.mat = S_IRON
	b.rod(Vector3(-3.4, 1.9, 7.0), Vector3(-3.4, LOFT_Y - 0.25, 7.0), 0.01, 4, C_IRON)
	# mudroom: a bench, coat pegs with coats and a hat, boots, a log basket
	b.mat = S_TIMBER
	b.block(Vector3(0.8, 0.38, 8.45), Vector3(2.2, 0.45, 8.85), C_TIMBER)
	for x: float in [0.9, 2.1]:
		b.block(Vector3(x - 0.04, 0.0, 8.5), Vector3(x + 0.04, 0.38, 8.8), C_TIMBER)
	b.block(Vector3(0.8, 1.55, 8.78), Vector3(2.2, 1.65, 8.84), C_TIMBER)
	b.mat = S_IRON
	for i in 4:
		b.rod(Vector3(0.95 + float(i) * 0.38, 1.6, 8.8), Vector3(0.95 + float(i) * 0.38, 1.62, 8.66), 0.015, 4, C_IRON)
	b.mat = S_WOOL
	for i: int in [0, 2]:
		var cx := 0.95 + float(i) * 0.38
		b.soft_box(Transform3D(Basis.IDENTITY, Vector3(cx, 1.2, 8.72)), Vector3(0.42, 0.78, 0.12), 0.05, Color(0.45, 0.15, 0.12) if i == 0 else Color(0.25, 0.3, 0.24), 1.0)
	b.cyl(Transform3D(Basis.IDENTITY, Vector3(2.09, 1.55, 8.68)), 0.15, 0.1, 0.12, 12, Color(0.3, 0.22, 0.16))
	b.mat = S_LEATHER
	for bx: float in [1.05, 1.3]:
		b.soft_box(Transform3D(Basis.IDENTITY, Vector3(bx, 0.15, 8.65)), Vector3(0.12, 0.3, 0.14), 0.03, Color(0.24, 0.16, 0.1), 0.6)
		b.soft_box(Transform3D(Basis.IDENTITY, Vector3(bx, 0.04, 8.55)), Vector3(0.12, 0.08, 0.32), 0.03, Color(0.2, 0.13, 0.08), 0.6)
	# bookshelves along the back wall, with rows of books
	b.mat = S_TIMBER
	b.block(Vector3(2.7, 0.0, 8.8), Vector3(4.9, 2.4, BACK_Z - 0.15), C_TIMBER.darkened(0.1))
	for x: float in [2.7, 4.85]:
		b.block(Vector3(x, 0.0, 8.45), Vector3(x + 0.05, 2.4, 8.85), C_TIMBER.darkened(0.05))
	b.mat = S_PLAIN
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for shelf in 5:
		var y := 0.1 + float(shelf) * 0.46
		b.mat = S_TIMBER
		b.block(Vector3(2.75, y - 0.03, 8.45), Vector3(4.85, y, 8.85), C_TIMBER.darkened(0.05))
		b.mat = S_PLAIN
		var x := 2.8
		while x < 4.75:
			var w := rng.randf_range(0.03, 0.08)
			var col := Color.from_hsv(rng.randf_range(0.0, 0.15) if rng.randf() < 0.6 else rng.randf_range(0.25, 0.6), rng.randf_range(0.3, 0.6), rng.randf_range(0.25, 0.55))
			var h := rng.randf_range(0.24, 0.36)
			var lean := rng.randf_range(-0.12, 0.12) if rng.randf() < 0.15 else 0.0
			b.box(Transform3D(Basis(Vector3.FORWARD, lean), Vector3(x + w * 0.5, y + h * 0.5, 8.63)), Vector3(w, h, rng.randf_range(0.18, 0.25)), col)
			x += w + 0.008
			if rng.randf() < 0.06:
				x += 0.2
	# loft: the bench at the railing (the Loft_ seats) with cushions, a bed with a quilt
	b.mat = S_TIMBER
	b.block(Vector3(-4.8, LOFT_Y + 0.35, 5.6), Vector3(3.4, LOFT_Y + 0.42, 6.0), C_TIMBER.lightened(0.05))
	for x: float in [-4.6, -2.1, 0.0, 2.1, 3.2]:
		b.block(Vector3(x - 0.05, LOFT_Y, 5.65), Vector3(x + 0.05, LOFT_Y + 0.35, 5.95), C_TIMBER)
	b.mat = S_WOOL
	for s: Array in SEATS:
		if String(s[0]).begins_with("Loft"):
			b.soft_box(Transform3D(Basis.IDENTITY, Vector3(float(s[1]), LOFT_Y + 0.45, 5.8)), Vector3(0.7, 0.07, 0.38), 0.03, C_FABRIC.darkened(0.1), 1.0)
	b.mat = S_TIMBER
	b.block(Vector3(-3.05, LOFT_Y, 7.0), Vector3(-0.75, LOFT_Y + 0.35, BACK_Z - 0.2), C_TIMBER.darkened(0.1))
	b.block(Vector3(-3.05, LOFT_Y, 8.65), Vector3(-0.75, LOFT_Y + 1.1, BACK_Z - 0.18), C_TIMBER.darkened(0.15))
	b.mat = S_WOOL
	b.soft_box(Transform3D(Basis.IDENTITY, Vector3(-1.9, LOFT_Y + 0.45, 7.8)), Vector3(2.2, 0.2, 1.6), 0.08, C_WOOL, 1.0)
	b.soft_box(Transform3D(Basis.IDENTITY, Vector3(-1.9, LOFT_Y + 0.58, 7.55)), Vector3(2.28, 0.08, 1.15), 0.04, C_RUG.lightened(0.1), 1.0)
	for px: float in [-2.45, -1.35]:
		b.soft_box(Transform3D(Basis.IDENTITY, Vector3(px, LOFT_Y + 0.62, 8.4)), Vector3(0.7, 0.16, 0.36), 0.07, C_WOOL.lightened(0.05), 1.0)
	b.rug_quad(Vector2(-2.0, 6.3), Vector2(2.0, 6.9), LOFT_Y + 0.01, C_RUG_MEAN.darkened(0.1))


# ── The den ──────────────────────────────────────────────────
## The den off the great room's left wall (Sen's den picture): log walls with a window behind the
## sofa and one behind the armchair, a flat pine ceiling with heavy log beams, its own small gable
## roof (which tucks under the great room's roof), a stone chimney on the far wall with a raised
## hearth, a heavy mantel on corbels and a fire (FIRE_Den), a rug, a coffee table, the leather sofa
## and armchair the presenters sit on in "Gather in: Den", a side table, a floor lamp's stand and a
## stack of firewood. Called by build_cabin after _build_chimney (which makes out["ember_mat"]).
static func _build_den(b: Buf, markers: Node3D, out: Dictionary) -> void:
	var near_x := -HALF_W          # the great room's left wall, which the den leans on
	var in_lo := DEN_FAR_X + LOG_R  # the inside faces of the den's walls
	var in_hi := near_x - LOG_R
	var z_lo := DEN_Z.x + LOG_R
	var z_hi := DEN_Z.y - LOG_R
	# floor and footing
	b.mat = S_FLOOR
	b.block(Vector3(DEN_FAR_X, -0.2, DEN_Z.x), Vector3(near_x, 0.0, DEN_Z.y), C_FLOOR.darkened(0.04))
	b.mat = S_STONE
	b.block(Vector3(DEN_FAR_X - 0.15, GROUND_Y - 0.1, DEN_Z.x - 0.15), Vector3(near_x, -0.2, DEN_Z.y + 0.15), C_STONE_DARK)
	# log walls: the two long walls (z = DEN_Z.x, DEN_Z.y) and the far wall (x = DEN_FAR_X), a half
	# log higher so the corners interlock like the great room's
	var rows := int(floor((DEN_EAVE_Y - LOG_R) / LOG_STEP)) + 1
	for r in rows:
		var y := LOG_R + float(r) * LOG_STEP
		for z: float in [DEN_Z.x, DEN_Z.y]:
			for span in _den_spans(z, DEN_FAR_X - LOG_OVERHANG, in_hi, y):
				b.mat = S_LOG
				b.rod(Vector3(span.x, y, z), Vector3(span.y, y, z), _log_r(r + 3, span.x), 14, _log_col(r + 2, span.x + z), C_LOG_END)
				if r > 0:
					_chinking(b, Vector3(span.x, y - LOG_STEP * 0.5, z), Vector3(span.y, y - LOG_STEP * 0.5, z))
		var yf := y + LOG_STEP * 0.5
		if yf < DEN_EAVE_Y:
			b.mat = S_LOG
			b.rod(Vector3(DEN_FAR_X, yf, DEN_Z.x - LOG_OVERHANG), Vector3(DEN_FAR_X, yf, DEN_Z.y + LOG_OVERHANG), _log_r(r + 5, 1.0), 14, _log_col(r + 4, 1.0), C_LOG_END)
			if r > 0:
				_chinking(b, Vector3(DEN_FAR_X, yf - LOG_STEP * 0.5, DEN_Z.x), Vector3(DEN_FAR_X, yf - LOG_STEP * 0.5, DEN_Z.y))
	b.mat = S_TIMBER
	for w: Array in DEN_WINDOWS:
		var z := float(w[0])
		var t := 0.08
		b.block(Vector3(float(w[1]) - t, float(w[3]) - t, z - 0.22), Vector3(float(w[2]) + t, float(w[3]), z + 0.22), C_FRAME)
		b.block(Vector3(float(w[1]) - t, float(w[4]), z - 0.2), Vector3(float(w[2]) + t, float(w[4]) + t, z + 0.2), C_FRAME)
		b.block(Vector3(float(w[1]) - t, float(w[3]), z - 0.2), Vector3(float(w[1]), float(w[4]), z + 0.2), C_FRAME)
		b.block(Vector3(float(w[2]), float(w[3]), z - 0.2), Vector3(float(w[2]) + t, float(w[4]), z + 0.2), C_FRAME)
	# the gable over the far wall, up to the den's ridge
	var top := rows * LOG_STEP
	b.mat = S_CEILING
	b.tri(Vector3(DEN_FAR_X, top, DEN_Z.x), Vector3(DEN_FAR_X, top, DEN_Z.y), Vector3(DEN_FAR_X, DEN_RIDGE_Y + 0.1, DEN_MID_Z), C_PINE.darkened(0.2))
	# the low flat ceiling of pine boards, with heavy log beams across it (none along the middle:
	# it would hang right across the Den Fireside camera's view)
	b.block(Vector3(in_lo, DEN_CEIL_Y, z_lo), Vector3(in_hi, DEN_CEIL_Y + 0.05, z_hi), C_PINE)
	b.mat = S_LOG
	for x: float in [-7.5, -8.9, -10.3]:
		b.rod(Vector3(x, DEN_CEIL_Y - 0.14, z_lo), Vector3(x, DEN_CEIL_Y - 0.14, z_hi), 0.14, 10, C_TIMBER, C_LOG_END)
	# the roof: two slopes from the eaves up to a ridge along x, ending where they meet the great
	# room's roof (_great_roof_x), so nothing pokes through into the great room
	var overhang := 0.5
	var slope := (DEN_RIDGE_Y - DEN_EAVE_Y) / (DEN_MID_Z - DEN_Z.x)
	var far := DEN_FAR_X - overhang
	for side: float in [-1.0, 1.0]:
		var ze := DEN_Z.x - overhang if side < 0.0 else DEN_Z.y + overhang
		var ye := DEN_EAVE_Y - overhang * slope
		for layer: Array in [[0.0, C_PINE, S_CEILING], [0.2, C_ROOF, S_ROOF]]:
			var lift := float(layer[0])
			b.mat = int(layer[2])
			b.quad(Vector3(far, ye + lift, ze), Vector3(_great_roof_x(ye + lift), ye + lift, ze),
				Vector3(_great_roof_x(DEN_RIDGE_Y + lift), DEN_RIDGE_Y + lift, DEN_MID_Z), Vector3(far, DEN_RIDGE_Y + lift, DEN_MID_Z), layer[1])
		# the roof's edge at the far end
		b.quad(Vector3(far, ye, ze), Vector3(far, ye + 0.2, ze), Vector3(far, DEN_RIDGE_Y + 0.2, DEN_MID_Z), Vector3(far, DEN_RIDGE_Y, DEN_MID_Z), C_ROOF.darkened(0.2))
	_build_den_chimney(b, markers, out)
	_build_den_furniture(b)


## Where the great room's roof (its pine underside) is at height y, on the den's (left) side.
static func _great_roof_x(y: float) -> float:
	return -HALF_W * (1.0 - (y - EAVE_Y) / (RIDGE_Y - EAVE_Y))


## The pieces of one log row along a den wall (at z) at height y, skipping its windows.
static func _den_spans(z: float, from: float, to: float, y: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var at := from
	for w: Array in DEN_WINDOWS:
		if is_equal_approx(float(w[0]), z) and y > float(w[3]) - LOG_R * 0.5 and y < float(w[4]) + LOG_R * 0.5:
			out.append(Vector2(at, float(w[1])))
			at = float(w[2])
	out.append(Vector2(at, to))
	return out


## The den's chimney on its far wall: stone from the floor up through the roof (sticking out
## behind the wall too, like an outside chimney), the firebox, raised hearth, the heavy mantel on
## two corbels, andirons and logs, the FIRE_Den marker and its glowing coals. The fire faces +X
## (into the den), so its marker is turned a quarter round: the room script places the flames and
## the light in the marker's own axes, the same way for both fires.
static func _build_den_chimney(b: Buf, markers: Node3D, out: Dictionary) -> void:
	var back_x := DEN_FAR_X - 0.4
	var fb := DEN_FIREBOX       # z from, z to, bottom, top
	var fb_back := DEN_CHIM_FACE_X - 0.45
	var stone := C_STONE.lightened(0.04)
	b.mat = S_STONE
	b.block(Vector3(back_x, 0.0, DEN_CHIM_Z.x), Vector3(fb_back, DEN_CEIL_Y, DEN_CHIM_Z.y), stone)
	b.block(Vector3(fb_back, 0.0, DEN_CHIM_Z.x), Vector3(DEN_CHIM_FACE_X, DEN_CEIL_Y, fb.x), stone)
	b.block(Vector3(fb_back, 0.0, fb.y), Vector3(DEN_CHIM_FACE_X, DEN_CEIL_Y, DEN_CHIM_Z.y), stone)
	b.block(Vector3(fb_back, 0.0, fb.x), Vector3(DEN_CHIM_FACE_X, fb.z, fb.y), C_STONE_DARK)
	b.block(Vector3(fb_back, fb.w, fb.x), Vector3(DEN_CHIM_FACE_X, DEN_CEIL_Y, fb.y), stone)
	b.mat = S_PLAIN
	b.block(Vector3(fb_back - 0.02, fb.z, fb.x), Vector3(fb_back + 0.01, fb.w, fb.y), C_SOOT)
	b.mat = S_STONE
	# the stack through the roof
	b.block(Vector3(back_x, DEN_CEIL_Y, 4.75), Vector3(DEN_FAR_X + 0.25, DEN_RIDGE_Y + 1.2, 5.85), stone)
	b.block(Vector3(back_x - 0.08, DEN_RIDGE_Y + 1.2, 4.67), Vector3(DEN_FAR_X + 0.33, DEN_RIDGE_Y + 1.36, 5.93), C_STONE_DARK)
	# darker stones over the face, kept off the firebox and the screen
	var rng := RandomNumberGenerator.new()
	rng.seed = 1117
	var screen_z := Vector2(DEN_MID_Z - DEN_SCREEN_SIZE.x * 0.5 - 0.05, DEN_MID_Z + DEN_SCREEN_SIZE.x * 0.5 + 0.05)
	for i in 40:
		var z := rng.randf_range(DEN_CHIM_Z.x + 0.15, DEN_CHIM_Z.y - 0.15)
		var y := rng.randf_range(0.2, DEN_CEIL_Y - 0.2)
		var fire_hole := z > fb.x - 0.12 and z < fb.y + 0.12 and y < fb.w + 0.12
		var behind_screen := z > screen_z.x and z < screen_z.y and y > DEN_SCREEN_BOTTOM - 0.05 and y < DEN_SCREEN_BOTTOM + DEN_SCREEN_SIZE.y + 0.05
		if fire_hole or behind_screen:
			continue
		var s := Vector3(0.08, rng.randf_range(0.16, 0.28), rng.randf_range(0.22, 0.42))
		b.soft_box(Transform3D(Basis.IDENTITY, Vector3(DEN_CHIM_FACE_X + 0.01, y, z)), s, 0.035, stone.darkened(rng.randf_range(0.0, 0.2)), 0.7)
	# raised hearth, and the heavy mantel beam on two corbels (wider than the chimney, as in the picture)
	b.block(Vector3(DEN_CHIM_FACE_X, 0.0, DEN_CHIM_Z.x - 0.25), Vector3(DEN_CHIM_FACE_X + 0.5, 0.3, DEN_CHIM_Z.y + 0.25), C_STONE.lightened(0.12))
	b.mat = S_TIMBER
	b.block(Vector3(DEN_CHIM_FACE_X, DEN_MANTEL_Y - 0.24, DEN_CHIM_Z.x - 0.15), Vector3(DEN_CHIM_FACE_X + 0.32, DEN_MANTEL_Y, DEN_CHIM_Z.y + 0.15), C_TIMBER.darkened(0.1))
	for z: float in [DEN_CHIM_Z.x + 0.2, DEN_CHIM_Z.y - 0.2]:
		b.block(Vector3(DEN_CHIM_FACE_X, DEN_MANTEL_Y - 0.55, z - 0.08), Vector3(DEN_CHIM_FACE_X + 0.24, DEN_MANTEL_Y - 0.24, z + 0.08), C_TIMBER.darkened(0.1))
	# andirons and logs, placed in the fire marker's axes (+Z = out into the den)
	var fire_at := Vector3(DEN_CHIM_FACE_X - 0.45 * 0.5, fb.z + 0.02, DEN_MID_Z)
	var xf := Transform3D(Basis(Vector3.UP, PI * 0.5), fire_at)
	_fire_logs(b, xf, 0.85)
	# candles and a small carving on the mantel (an original whittled bear, not a trophy)
	b.mat = S_PLAIN
	for cz: float in [4.25, 4.45, 6.3]:
		b.cyl(Transform3D(Basis.IDENTITY, Vector3(DEN_CHIM_FACE_X + 0.16, DEN_MANTEL_Y, cz)), 0.035, 0.035, 0.12 + 0.05 * sin(cz * 9.0), 8, C_WOOL)
	b.mat = S_TIMBER
	var bear := Vector3(DEN_CHIM_FACE_X + 0.16, DEN_MANTEL_Y, 6.05)
	b.soft_box(Transform3D(Basis.IDENTITY, bear + Vector3(0.0, 0.07, 0.0)), Vector3(0.09, 0.09, 0.2), 0.035, C_TIMBER.lightened(0.2), 1.0)
	b.soft_box(Transform3D(Basis.IDENTITY, bear + Vector3(0.0, 0.13, -0.11)), Vector3(0.07, 0.07, 0.08), 0.03, C_TIMBER.lightened(0.2), 1.0)
	var fire := Marker3D.new()
	fire.name = "FIRE_Den"
	markers.add_child(fire)
	fire.transform = xf
	(out["fires"] as Array[Marker3D]).append(fire)
	var coals := BoxMesh.new()
	coals.size = Vector3(0.75, 0.05, 0.3)
	var coal_mi := MeshInstance3D.new()
	coal_mi.name = "Embers_Den"
	coal_mi.mesh = coals
	coal_mi.material_override = out["ember_mat"]
	coal_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	markers.get_parent().get_node("Set").add_child(coal_mi)
	coal_mi.transform = xf


## The den's furniture: rug, coffee table (with a few books), the three-seat leather sofa with
## cushions and throws, the armchair, a side table under LAMP_Den_Table, the floor lamp's stand
## under LAMP_Den_Floor, and firewood stacked by the hearth.
static func _build_den_furniture(b: Buf) -> void:
	b.rug_quad(Vector2(-11.0, 3.6), Vector2(-7.6, 7.3), 0.012, C_RUG_MEAN.lerp(Color(0.42, 0.3, 0.18), 0.3))
	# a chunky wooden coffee table with a shelf, books and mugs
	b.mat = S_TIMBER
	b.soft_box(Transform3D(Basis.IDENTITY, Vector3(-9.3, 0.41, 5.6)), Vector3(1.3, 0.1, 0.8), 0.03, C_TIMBER.lightened(0.12), 0.4)
	b.block(Vector3(-9.85, 0.08, 5.3), Vector3(-8.75, 0.12, 5.9), C_TIMBER)
	for x: float in [-9.85, -8.81]:
		for z: float in [5.26, 5.88]:
			b.block(Vector3(x, 0.0, z), Vector3(x + 0.06, 0.36, z + 0.06), C_TIMBER.darkened(0.1))
	_table_things(b, Vector3(-9.15, 0.46, 5.55), 1)
	# the sofa: three seats 1.1 m apart, turned towards the doorway like in the picture
	var sofa := _den_seat_xf(DEN_SOFA)
	_sofa(b, sofa, 3, 1.1, C_LEATHER.darkened(0.05))
	# throws: a wool one over the far arm, a red one over the back; two little pillows
	b.mat = S_FLEECE
	b.soft_box(sofa * Transform3D(Basis.IDENTITY, Vector3(-1.76, 0.55, 0.0)), Vector3(0.3, 0.32, 0.95), 0.06, C_WOOL, 1.0)
	b.soft_box(sofa * Transform3D(Basis(Vector3.RIGHT, -0.25), Vector3(0.7, 0.9, 0.42)), Vector3(0.9, 0.32, 0.12), 0.05, C_RUG, 1.0)
	b.mat = S_WOOL
	for sx: float in [-1.45, 1.45]:
		b.soft_box(sofa * Transform3D(Basis(Vector3.FORWARD, 0.3 * signf(sx)), Vector3(sx, 0.68, 0.08)), Vector3(0.4, 0.38, 0.14), 0.07, C_FABRIC, 1.0)
	# the armchair, with a plaid throw over its back
	var arm := _den_seat_xf(DEN_ARMCHAIR)
	_sofa(b, arm, 1, 0.72, C_LEATHER.lightened(0.05))
	b.mat = S_FLEECE
	b.soft_box(arm * Transform3D(Basis(Vector3.RIGHT, -0.2), Vector3(0.0, 0.92, 0.42)), Vector3(0.7, 0.32, 0.1), 0.04, C_THROW_GREEN, 1.0)
	# side table by the armchair (the table lamp stands on it)
	_side_table(b, Vector3(-11.35, 0.0, 3.0))
	# the floor lamp's stand behind the sofa's far end
	b.mat = S_IRON
	var fl := Vector3(-11.75, 0.0, 7.95)
	b.cyl(Transform3D(Basis.IDENTITY, fl), 0.18, 0.16, 0.04, 12, C_IRON)
	b.rod(fl, fl + Vector3(0.0, 1.42, 0.0), 0.018, 6, C_IRON)
	# split firewood stacked by the hearth
	b.mat = S_BARK
	for r in 4:
		for i in 3:
			var at := Vector3(-12.05 + float(i) * 0.2 + (0.1 if r % 2 == 1 else 0.0), 0.07 + float(r) * 0.13, 7.0)
			b.rod(at, at + Vector3(0.0, 0.0, 0.5), 0.065, 8, C_BARK, C_LOG_END)


## A transform for a den seat from its Vector4 (x, z, the x and z it is turned towards): origin
## on the floor at (x, z), -Z towards that point (so +Z is the backrest's side).
static func _den_seat_xf(v: Vector4) -> Transform3D:
	var dir := Vector3(v.z - v.x, 0.0, v.w - v.y).normalized()
	return Transform3D(Basis.looking_at(dir, Vector3.UP), Vector3(v.x, 0.0, v.y))


## "Gather in: Den": the four presenters sit in the den instead of on the podium chairs.
## PRESENTER_1..3 are the sofa's seats (from the fireplace end to the door end) and PRESENTER_4
## is the armchair; each faces the way its seat faces. There are no PODIUM_ meshes in this view
## (the sofa and armchair are always there), so the Presenters tab's on-set switch only shows or
## hides the person.
static func _den_presenters(markers: Node3D) -> void:
	var sofa := _den_seat_xf(DEN_SOFA)
	var seats: Array[Transform3D] = []
	for sx: float in [-1.1, 0.0, 1.1]:
		seats.append(sofa * Transform3D(Basis.IDENTITY, Vector3(sx, DEN_SEAT_Y, -0.05)))
	seats.append(_den_seat_xf(DEN_ARMCHAIR) * Transform3D(Basis.IDENTITY, Vector3(0.0, DEN_SEAT_Y, -0.05)))
	for i in seats.size():
		var at := seats[i].origin
		_marker_facing(markers, "PRESENTER_%d" % (i + 1), at, at - seats[i].basis.z)


# ── Outside the walls ────────────────────────────────────────
## The deck in front of the glass (on posts, with railing, steps, Adirondack chairs and a fire
## table), the covered stoop at the back door, and the woodpile against the left wall.
static func _build_outside_bits(b: Buf) -> void:
	b.mat = S_DECK
	b.block(Vector3(-DECK_HALF, DECK_Y - 0.15, -DECK_DEPTH), Vector3(DECK_HALF, DECK_Y, 0.0), C_DECK)
	for x in [-DECK_HALF + 0.1, -4.0, 0.0, 4.0, DECK_HALF - 0.1]:
		b.block(Vector3(float(x) - 0.1, GROUND_Y, -DECK_DEPTH + 0.05), Vector3(float(x) + 0.1, DECK_Y - 0.15, -DECK_DEPTH + 0.25), C_TIMBER)
	var rail_y := DECK_Y + 1.0
	var front := -DECK_DEPTH + 0.05
	# front railing (with the gap for the steps) and the two side railings
	var runs: Array = [[Vector3(-DECK_HALF, 0, front), Vector3(DECK_STEPS.x, 0, front)], [Vector3(DECK_STEPS.y, 0, front), Vector3(DECK_HALF, 0, front)],
		[Vector3(-DECK_HALF, 0, front), Vector3(-DECK_HALF, 0, -0.1)], [Vector3(DECK_HALF, 0, front), Vector3(DECK_HALF, 0, -0.1)]]
	for r: Array in runs:
		var a: Vector3 = r[0]
		var c: Vector3 = r[1]
		b.rod(Vector3(a.x, rail_y, a.z), Vector3(c.x, rail_y, c.z), 0.05, 6, C_TIMBER)
		var n := maxi(int(a.distance_to(c) / 0.16), 1)
		for i in n + 1:
			var p := a.lerp(c, float(i) / float(n))
			var post := i % 8 == 0 or i == n
			b.block(Vector3(p.x - (0.06 if post else 0.02), DECK_Y, p.z - (0.06 if post else 0.02)), Vector3(p.x + (0.06 if post else 0.02), rail_y, p.z + (0.06 if post else 0.02)), C_TIMBER)
	var steps := 4
	for i in steps:
		var y := DECK_Y - (DECK_Y - GROUND_Y) * float(i + 1) / float(steps + 1)
		b.block(Vector3(DECK_STEPS.x, GROUND_Y, -DECK_DEPTH - 0.28 * float(i + 1)), Vector3(DECK_STEPS.y, y, -DECK_DEPTH - 0.28 * float(i)), C_DECK.darkened(0.05))
	# Adirondack chairs (under the deck seats that face the view) and the fire table's chairs
	for s: Array in SEATS:
		if not String(s[0]).begins_with("Deck"):
			continue
		var at := Vector3(float(s[1]), DECK_Y, float(s[3]))
		var look: Vector3 = s[4]
		var dir := Vector3(look.x - at.x, 0.0, look.z - at.z).normalized()
		var xf := Transform3D(Basis.looking_at(dir, Vector3.UP), at)      # -Z = the way it faces
		var seat_h := float(s[2]) - DECK_Y
		b.box(xf * Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-8.0)), Vector3(0.0, seat_h - 0.05, 0.0)), Vector3(0.7, 0.06, 0.6), C_FRAME.lightened(0.2))
		b.box(xf * Transform3D(Basis(Vector3.RIGHT, deg_to_rad(20.0)), Vector3(0.0, seat_h + 0.35, 0.35)), Vector3(0.7, 0.8, 0.06), C_FRAME.lightened(0.2))
		for sx: float in [-0.37, 0.37]:
			b.box(xf * Transform3D(Basis.IDENTITY, Vector3(sx, (seat_h + 0.25) * 0.5, 0.0)), Vector3(0.06, seat_h + 0.25, 0.7), C_FRAME)
	b.mat = S_STONE
	b.block(Vector3(-0.5, DECK_Y, -3.2), Vector3(0.5, DECK_Y + 0.42, -2.7), C_STONE_DARK)
	b.mat = S_DECK
	# the back stoop: a small deck and steps under its own little roof
	b.block(Vector3(-1.1, DECK_Y - 0.15, BACK_Z), Vector3(1.1, DECK_Y, BACK_Z + 1.3), C_DECK)
	for i in 3:
		var y := DECK_Y - (DECK_Y - GROUND_Y) * float(i + 1) / 4.0
		b.block(Vector3(-0.8, GROUND_Y, BACK_Z + 1.3 + 0.28 * float(i)), Vector3(0.8, y, BACK_Z + 1.3 + 0.28 * float(i + 1)), C_DECK.darkened(0.05))
	for sx: float in [-1.0, 1.0]:
		b.mat = S_LOG
		b.rod(Vector3(sx * 1.0, DECK_Y, BACK_Z + 1.2), Vector3(sx * 1.0, 2.5, BACK_Z + 1.2), 0.07, 10, C_LOG, C_LOG_END)
		b.mat = S_ROOF
		b.slab(Vector2(sx * 1.4, 2.45), Vector2(0.0, 3.1), BACK_Z + 0.2, BACK_Z + 1.5, 0.12, C_ROOF)
	# the woodpile against the back wall (outside), right of the stoop
	b.mat = S_BARK
	for r in 5:
		for i in 8:
			var x := 2.9 + float(i) * 0.3 + (0.15 if r % 2 == 1 else 0.0)
			if x > 5.3:
				continue
			var y := GROUND_Y + 0.12 + float(r) * 0.22
			b.rod(Vector3(x, y, BACK_Z + 0.3), Vector3(x, y, BACK_Z + 0.85), 0.11, 9, C_BARK, C_LOG_END)


## The see-through glass: the two big gable windows either side of the chimney (following the roof
## line), the corner glass doors, and the side and back windows. One mesh with the weather's
## glass material (rooms/weather/weather_glass.gdshader: rain drops, wet blur, frost; out
## "glass_mat"), which casts no shadow (so sunlight comes in).
static func _build_glass(parent: Node3D, out: Dictionary) -> void:
	var g := Buf.new()
	var tint := Color(0.78, 0.86, 0.9, 0.12)
	for sx: float in [-1.0, 1.0]:
		var xo := sx * HALF_W
		var xi := sx * CHIM_HALF
		g.quad(Vector3(xo, 0.0, 0.0), Vector3(xi, 0.0, 0.0), Vector3(xi, roof_y(xi), 0.0), Vector3(xo, roof_y(xo), 0.0), tint)
	for w: Array in WINDOWS:
		var from := float(w[1])
		var to := float(w[2])
		var sill := float(w[3])
		var top := float(w[4])
		match String(w[0]):
			"back":
				g.quad(Vector3(from, sill, BACK_Z), Vector3(to, sill, BACK_Z), Vector3(to, top, BACK_Z), Vector3(from, top, BACK_Z), tint)
			_:
				var x := -HALF_W if String(w[0]) == "left" else HALF_W
				g.quad(Vector3(x, sill, from), Vector3(x, sill, to), Vector3(x, top, to), Vector3(x, top, from), tint)
	for w: Array in DEN_WINDOWS:
		var z := float(w[0])
		g.quad(Vector3(float(w[1]), float(w[3]), z), Vector3(float(w[2]), float(w[3]), z), Vector3(float(w[2]), float(w[4]), z), Vector3(float(w[1]), float(w[4]), z), tint)
	var m := Weather.glass_material(Color(0.78, 0.86, 0.9, 0.12))
	out["glass_mat"] = m
	_add_mesh(parent, "Glass", g.to_mesh(), m, false)


## The two screens: the big one on the tall chimney above the mantel, and the den's above its
## mantel. The one for the current view is TVScreen (the app puts the picture and the screen
## lights on it); the other is SCREEN_Mirror_<n>, which shows the same picture.
static func _build_screens(parent: Node3D, out: Dictionary, view: String) -> void:
	var great := _screen_quad(parent, "TVScreen" if view != "den" else "SCREEN_Mirror_Great_Room", SCREEN_SIZE,
		Transform3D(Basis.IDENTITY, Vector3(0.0, SCREEN_BOTTOM + SCREEN_SIZE.y * 0.5, CHIM_IN_Z + 0.06)))
	# the den's screen faces into the den (+X)
	var den := _screen_quad(parent, "TVScreen" if view == "den" else "SCREEN_Mirror_Den", DEN_SCREEN_SIZE,
		Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(DEN_CHIM_FACE_X + 0.06, DEN_SCREEN_BOTTOM + DEN_SCREEN_SIZE.y * 0.5, DEN_MID_Z)))
	out["screen"] = den if view == "den" else great


## One screen (a QuadMesh facing its +Z) with a thin dark bezel behind it.
static func _screen_quad(parent: Node3D, node_name: String, size: Vector2, xf: Transform3D) -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = size
	var screen := MeshInstance3D.new()
	screen.name = node_name
	screen.mesh = quad
	screen.transform = xf
	parent.add_child(screen)
	var bezel := BoxMesh.new()
	bezel.size = Vector3(size.x + 0.08, size.y + 0.08, 0.05)
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.03, 0.03, 0.035)
	bm.roughness = 0.4
	var bezel_mi := _add_mesh(parent, "Bezel_" + node_name, bezel, bm)
	bezel_mi.transform = xf * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, -0.03))
	return screen


## The four podiums: high-backed leather armchairs, each its own mesh named PODIUM_n so the app
## shows it only while that presenter is on set, with PRESENTER_n on its seat (the bottom centre
## of the presenter's picture), facing the audience.
static func _build_podiums(parent: Node3D, markers: Node3D, surf: Dictionary) -> void:
	for i in PODIUMS.size():
		var p := PODIUMS[i]
		var at := Vector3(p.x, 0.0, p.y)
		var b := Buf.new()
		# a wingback leather armchair. Local axes: +Z = the way the chair faces (towards the
		# audience); _sofa builds facing its own -Z, so it is turned round
		var col := C_LEATHER.darkened(0.1)
		var xf := Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
		_sofa(b, xf, 1, 0.72, col)
		b.mat = S_LEATHER
		b.soft_box(xf * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.95, 0.4)), Vector3(0.95, 0.65, 0.16), 0.07, col.darkened(0.06), 0.8)
		for sd: float in [-1.0, 1.0]:
			b.soft_box(xf * Transform3D(Basis(Vector3.UP, sd * 0.25), Vector3(sd * 0.46, 1.0, 0.2)), Vector3(0.1, 0.6, 0.4), 0.04, col.darkened(0.04), 0.8)
		var chair := _add_mesh(parent, "PODIUM_%d" % (i + 1), b.to_mesh(surf), null)
		var marker := _marker_facing(markers, "PRESENTER_%d" % (i + 1), at + Vector3(0.0, PODIUM_SEAT_Y, 0.0), at + Vector3(0.0, 0.0, 5.0))
		chair.transform = Transform3D(marker.transform.basis, at)


## The lamps: two table lamps, the chandelier, the pendant over the dining table and the lantern
## by the back door. Each is a LAMP_ marker under LIGHTS_House (Room turns it into a light and
## dims it with the house lights) plus a glowing shade or candle flames (glow_mat, whose glow the
## room script sets from the house light level).
static func _build_lamps(parent: Node3D, room: Node3D, out: Dictionary) -> void:
	var house := Node3D.new()
	house.name = "LIGHTS_House"
	room.add_child(house)
	# cabin_shade.gdshader: the cloth glows brightest where you look straight through it and
	# fades to the rim; the room script sets its `level` from the house lights
	var glow := ShaderMaterial.new()
	glow.shader = SHADE_SHADER
	glow.set_shader_parameter("weave", load(TEX + "wool.jpg"))
	out["glow_mat"] = glow
	(out["detail_mats"] as Array[ShaderMaterial]).append(glow)   # the weave shows on Detailed
	var shades := Buf.new()
	var lamps: Array = [
		["LAMP_Table_Left", Vector3(-5.6, 1.15, 2.6), "shade"],
		["LAMP_Table_Right", Vector3(4.95, 1.15, 2.9), "shade"],
		["LAMP_Chandelier", Vector3(0.0, 5.05, 3.0), "candles"],
		["LAMP_Dining", Vector3(-3.4, 1.8, 7.0), "pendant"],
		["LAMP_Back_Door", Vector3(0.8, 2.15, BACK_Z + 0.25), "lantern"],
		["LAMP_Den_Table", Vector3(-11.35, 1.2, 3.0), "shade"],
		["LAMP_Den_Floor", Vector3(-11.75, 1.6, 7.95), "shade"],
	]
	for l: Array in lamps:
		var at: Vector3 = l[1]
		var lamp := Marker3D.new()
		lamp.name = String(l[0])
		house.add_child(lamp)
		lamp.position = at
		match String(l[2]):
			"shade":
				shades.cyl(Transform3D(Basis.IDENTITY, at - Vector3(0.0, 0.2, 0.0)), 0.24, 0.14, 0.28, 12, C_WOOL)
			"pendant":
				shades.cyl(Transform3D(Basis.IDENTITY, at - Vector3(0.0, 0.05, 0.0)), 0.32, 0.08, 0.15, 14, C_FABRIC.lightened(0.2))
			"lantern":
				shades.block(at - Vector3(0.1, 0.15, 0.1), at + Vector3(0.1, 0.15, 0.1), C_WOOL)
			"candles":
				for i in 12:
					var a := TAU * float(i) / 12.0
					shades.cyl(Transform3D(Basis.IDENTITY, at + Vector3(cos(a) * 0.65, 0.0, sin(a) * 0.65)), 0.025, 0.02, 0.14, 6, C_WOOL)
	_add_mesh(parent, "LampGlow", shades.to_mesh(), glow, false)


## The camera views, and the reaction targets (things chat can throw at: "fireplace", "chandelier",
## "deck"). In the den view the den's cameras come first and "fireplace" is the den's fire.
static func _build_markers(markers: Node3D, view: String) -> void:
	var cams: Array = []
	if view == "den":
		cams.append_array(DEN_CAMERAS)
		for c: Array in CAMERAS:
			# renumber the great room's after the den's ("01_Loft" -> "05_Loft"); only the den's
			# own Reaction camera keeps "Reaction" in its name
			var parts := String(c[0]).split("_", false, 1)
			var label := String(parts[1]).replace("Reaction_", "")
			cams.append(["%02d_%s" % [int(parts[0]) + DEN_CAMERAS.size(), label], c[1], c[2]])
	else:
		cams.append_array(CAMERAS)
	for c: Array in cams:
		var cam := Marker3D.new()
		cam.name = "CAM_" + String(c[0])
		markers.add_child(cam)
		cam.transform = Transform3D(Basis.IDENTITY, c[1]).looking_at(c[2], Vector3.UP)
	for s: Array in SEATS:
		var at := Vector3(float(s[1]), float(s[2]), float(s[3]))
		var toward: Vector3 = Vector3(0.0, 0.0, CHIM_IN_Z) if s[4] is String else s[4]
		_marker_facing(markers, "AUDIENCE_" + String(s[0]), at, toward)
	if view == "den":
		_marker_facing(markers, "TARGET_Fireplace", Vector3(DEN_CHIM_FACE_X + 0.2, 0.75, DEN_MID_Z), Vector3(-7.0, 0.0, DEN_MID_Z))
	else:
		_marker_facing(markers, "TARGET_Fireplace", Vector3(0.0, 0.8, CHIM_IN_Z + 0.2), Vector3(0.0, 0.0, 8.0))
	_marker_facing(markers, "TARGET_Chandelier", Vector3(0.0, 5.0, 3.0), Vector3(0.0, 0.0, 8.0))
	_marker_facing(markers, "TARGET_Deck", Vector3(0.0, 0.4, -2.9), Vector3(0.0, 0.0, 8.0))


# ── The placeholder outside ──────────────────────────────────
## Stands in for the real scenery until the scene rooms are built: a grassy clearing with trodden
## paths, a ring of trees that leaves the view in front open, and a few far hills. Two sets of
## trees are built and the room script shows one (Set detail, _apply_detail):
##   out["simple_trees"]     plain cone trees (the Simple look)
##   out["detailed_plants"]  the Lakeside Campfire's leaf-card trees (campfire_trees.gd: firs,
##                           pines, oaks, maples, birches) as MultiMeshes, with grass tufts round
##                           the cabin and ferns at the trees' feet (the Detailed look)
## Both stand on the same spots (fixed random seed), so switching looks never moves a tree.
static func _build_clearing(parent: Node3D, out: Dictionary) -> void:
	var surf: Dictionary = out["surface_mats"]
	var g := Buf.new()
	var size := 600.0               # far enough that its edge hides in the haze below the sky's mountains
	g.mat = S_GRASS
	g.quad(Vector3(-size, GROUND_Y, -size), Vector3(size, GROUND_Y, -size), Vector3(size, GROUND_Y, size), Vector3(-size, GROUND_Y, size), C_GRASS)
	# trodden paths from the deck steps out towards the view, and from the back stoop
	g.mat = S_DIRT
	var dirt := C_GRASS.darkened(0.25).lerp(Color(0.45, 0.38, 0.28), 0.6)
	g.quad(Vector3(6.2, GROUND_Y + 0.01, -5.0), Vector3(7.4, GROUND_Y + 0.01, -5.0), Vector3(7.0, GROUND_Y + 0.01, -16.0), Vector3(5.8, GROUND_Y + 0.01, -16.0), dirt)
	g.quad(Vector3(-0.7, GROUND_Y + 0.01, 11.2), Vector3(0.7, GROUND_Y + 0.01, 11.2), Vector3(1.6, GROUND_Y + 0.01, 22.0), Vector3(0.2, GROUND_Y + 0.01, 22.0), dirt)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var trees: Array = []           # [foot, height, kind]
	var tries := 0
	while trees.size() < 170 and tries < 3000:
		tries += 1
		var r := rng.randf_range(15.0, 70.0)
		var a := rng.randf() * TAU
		var p := Vector2(cos(a) * r, sin(a) * r)
		# keep the view in front of the deck open (a wedge towards -Z)
		if p.y < -10.0 and absf(p.x) < -p.y * 0.9:
			continue
		trees.append([Vector3(p.x, GROUND_Y, p.y), rng.randf_range(7.0, 15.0), _pick_kind(rng.randf(), r)])
	# (no hills of our own: the sky, camp_sky.gdshader, draws mountains along the horizon)
	_add_mesh(parent, "Clearing", g.to_mesh(surf), null, true)
	# the Simple look's cone trees
	var t := Buf.new()
	for one: Array in trees:
		var foot: Vector3 = one[0]
		var h := float(one[1])
		t.cyl(Transform3D(Basis.IDENTITY, foot), 0.22, 0.16, h * 0.35, 6, C_TIMBER.darkened(0.3))
		var green := Color(0.13, 0.26, 0.15).lightened(fmod(absf(foot.x * 0.37 + foot.z * 0.21), 0.12))
		t.cyl(Transform3D(Basis.IDENTITY, foot + Vector3(0.0, h * 0.2, 0.0)), h * 0.22, 0.0, h * 0.55, 8, green)
		t.cyl(Transform3D(Basis.IDENTITY, foot + Vector3(0.0, h * 0.5, 0.0)), h * 0.16, 0.0, h * 0.5, 8, green.lightened(0.05))
	out["simple_trees"] = _add_mesh(parent, "SimpleTrees", t.to_mesh(surf), null, true)
	out["detailed_plants"] = _build_detailed_plants(parent, trees, rng)
	out["tree_mats"] = ((out["detailed_plants"] as Node3D).get_meta("mats") as Dictionary).values()


## The kind of tree for a spot: mostly firs and pines, with oaks, maples and birches between
## (more of them nearer the cabin, where they frame the views), `roll` 0..1, `r` metres out.
static func _pick_kind(roll: float, r: float) -> String:
	var leafy := 0.45 if r < 35.0 else 0.25
	if roll < leafy * 0.4:
		return "oak"
	if roll < leafy * 0.75:
		return "maple"
	if roll < leafy:
		return "birch"
	return "fir" if roll < leafy + (1.0 - leafy) * 0.65 else "pine"


## The Detailed look's plants (hidden until the room script shows them): the campfire's
## leaf-card trees on the clearing's tree spots, young firs between them, grass tufts round the
## cabin (not under the deck, the cabin or on the paths) and ferns at the trees' feet. One
## MultiMesh per kind (campfire_trees.gd kit(), which brings its own materials).
static func _build_detailed_plants(parent: Node3D, trees: Array, rng: RandomNumberGenerator) -> Node3D:
	var holder := Node3D.new()
	holder.name = "DetailedPlants"
	holder.visible = false
	parent.add_child(holder)
	var mats := Trees.materials(0.05)
	holder.set_meta("mats", mats)    # _build_clearing hands them on (out["tree_mats"]) for the weather
	var spots: Dictionary = {}      # kind -> Array[Transform3D]
	for one: Array in trees:
		var foot: Vector3 = one[0]
		var kind := String(one[2])
		var tall := float(one[1]) * (1.4 if kind == "fir" or kind == "pine" else 1.1)
		var wide := tall * (0.38 if kind == "fir" else 0.5 if kind == "pine" else 0.75 if kind != "birch" else 0.55)
		_spot(spots, kind, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(wide, tall, wide)), foot + Vector3(0.0, -0.05, 0.0)))
		# a young fir or two at the foot of the big ones, and ferns
		if rng.randf() < 0.5:
			var off := Vector3(rng.randf_range(-3.0, 3.0), 0.0, rng.randf_range(-3.0, 3.0))
			var yt := rng.randf_range(2.5, 5.5)
			_spot(spots, "young_fir", Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(yt * 0.45, yt, yt * 0.45)), foot + off))
		for f in 3:
			var off := Vector3(rng.randf_range(-2.5, 2.5), 0.0, rng.randf_range(-2.5, 2.5))
			var fs := rng.randf_range(0.7, 1.3)
			_spot(spots, "fern", Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(fs, fs, fs)), foot + off + Vector3(0.0, -0.02, 0.0)))
	# grass tufts round the cabin, 0 to 30 m out, off the cabin, the deck and the paths
	var left := 1600
	var tries := 0
	while left > 0 and tries < 12000:
		tries += 1
		var p := Vector2(rng.randf_range(-30.0, 30.0), rng.randf_range(-30.0, 30.0))
		if p.x > DEN_FAR_X - 0.8 and p.x < DECK_HALF + 0.8 and p.y > -DECK_DEPTH - 1.6 and p.y < BACK_Z + 2.6:
			continue
		if absf(p.x - 6.6) < 1.0 and p.y < -4.0 and p.y > -16.5:
			continue
		if absf(p.x - 0.7) < 1.0 and p.y > 10.8 and p.y < 22.5:
			continue
		var sz := rng.randf_range(0.5, 1.1)
		_spot(spots, "grass", Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sz, sz * rng.randf_range(0.8, 1.3), sz)), Vector3(p.x, GROUND_Y - 0.02, p.y)))
		left -= 1
	for kind: String in spots:
		var list: Array = spots[kind]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = Trees.kit(kind, mats)
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
			var shade := 0.82 + 0.24 * fmod(float(i) * 0.618, 1.0)
			mm.set_instance_color(i, Color(shade, shade, shade))
		var mmi := MultiMeshInstance3D.new()
		mmi.name = kind.to_pascal_case()
		mmi.multimesh = mm
		var small := kind == "grass" or kind == "fern"
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if small else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if small:
			mmi.visibility_range_end = 60.0
			mmi.visibility_range_end_margin = 8.0
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		holder.add_child(mmi)
	return holder


static func _spot(spots: Dictionary, kind: String, xf: Transform3D) -> void:
	if not spots.has(kind):
		spots[kind] = []
	(spots[kind] as Array).append(xf)
