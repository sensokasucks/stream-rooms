extends Room
## Drive-In (1950s): the room script. The set itself (lot, cars, screen tower, snack bar, fence,
## the simple trees) is the Blender model drive_in.glb; this script adds the outdoor look the
## Lakeside Campfire built (rooms/campfire/), reusing its pieces rather than copying them:
##   - Time of day ("drive_time", hours; "drive_day_minutes" lets the clock run): _apply_time()
##     moves the sun and the moon and sets the campfire's sky shader (camp_sky.gdshader: sunset
##     colours, stars, Milky Way, shooting stars, aurora, clouds from a noise picture, snow-capped
##     mountains and a far tree line on the horizon), the ambient light, the haze and the lot's
##     lamps (dim by day, full at night, on top of the House lights slider).
##   - Clouds / Stars / Aurora / Mist sliders ("drive_clouds", "drive_stars", "drive_aurora",
##     "drive_mist"): the sky's layers and the ground mist (camp_mist.gdshader sheets lying low
##     over the lot, thickest at dusk and at night).
##   - Fireflies ("drive_fireflies"): drifting specks over the grass round the lot on dark nights.
##   - Set detail ("drive_detail", each PC's own, never shared): Simple keeps the model's flat
##     colours and its simple trees, the lightest for a slow graphics card. Detailed lays CC0
##     photo textures on the asphalt, the gravel ramps and the grass (drive_ground.gdshader;
##     textures/ here and the campfire's), wood and cloth grain on the fence, truck bed, blanket
##     and chair (drive_detail.gdshader), puts a belt of leaf-card trees round the lot in place of
##     the simple ones (the campfire's campfire_trees.gd: firs, pines, oaks, maples, birches) and
##     grass tufts and ferns along the fence, plaster and concrete grain on the snack bar and
##     the screen tower, and swaps the model's plain blocks for modelled props
##     (models/props.glb from models/make_props.py: the speaker posts, the lot lights, the snack
##     bar's lamps, the lawn chairs, the cooler and the popcorn; _build_detailed_props) and the
##     parked cars and the pickup for Route 22's Blender models (_build_detailed_cars).
##     Auto follows Graphics quality (Low = Simple).
##     Both looks are built when the room loads; _apply_detail() only shows one, so switching is
##     instant.
## The shared settings (all drive_* but drive_detail and drive_fireflies) travel in a co-stream
## with the host's "room" group (NetSession.SHARED_BASE), so everyone sits under the same sky.

const SKY_SHADER := preload("res://rooms/campfire/camp_sky.gdshader")
const MIST_SHADER := preload("res://rooms/campfire/camp_mist.gdshader")
const GROUND_SHADER := preload("res://rooms/drive_in/drive_ground.gdshader")
const DETAIL_SHADER := preload("res://rooms/drive_in/drive_detail.gdshader")
const Trees := preload("res://rooms/campfire/campfire_trees.gd")
const CAMP_TEX := "res://rooms/campfire/textures/"
const OWN_TEX := "res://rooms/drive_in/textures/"
## The fence round the lot (x min, z min, x max, z max, metres; from the .glb's Fence mesh).
## The detailed trees stand outside it and drive_ground.gdshader starts the forest floor there.
const FENCE := Rect2(-70.0, -76.0, 140.0, 124.0)
## The ground's photo materials: imported material name -> [photo, metres per copy, tint,
## patchiness, roughness, forest floor under the trees (grass only)].
const GROUND_LOOKS: Dictionary = {
	"Asphalt": [OWN_TEX + "ground_asphalt.jpg", 5.0, Color(0.62, 0.62, 0.64), 0.45, 0.82, false],
	"Gravel_Ramp": [OWN_TEX + "ground_gravel.jpg", 2.6, Color(0.84, 0.8, 0.74), 0.3, 0.95, false],
	"Grass": [CAMP_TEX + "ground_grass.jpg", 3.2, Color(0.72, 0.8, 0.64), 0.35, 0.95, true],
}
## Wood and cloth that gain a photo's grain: imported material name -> [detail picture, metres
## per copy]. Their colour is copied from the imported material.
const GRAIN_LOOKS: Dictionary = {
	"Wood_Fence": [CAMP_TEX + "detail_planks.jpg", 1.3],
	"Truck_Bed_Wood": [CAMP_TEX + "detail_planks.jpg", 1.1],
	"Blanket": [CAMP_TEX + "detail_fabric.jpg", 0.45],
	"Canvas_Chair": [CAMP_TEX + "detail_fabric.jpg", 0.45],
	"Stand_Wall": [OWN_TEX + "detail_plaster.jpg", 2.4],
	"Stand_Roof": [OWN_TEX + "detail_plaster.jpg", 2.4],
	"Screen_Frame": [OWN_TEX + "detail_concrete.jpg", 3.5],
}
## The model's simple trees, hidden in the Detailed look (the belt of detailed trees replaces them).
const SIMPLE_TREES: PackedStringArray = ["Trees", "Tree_Trunks"]
## The model's plain blocks that the Detailed look hides, as _build_detailed_props puts modelled
## props in their places.
const SIMPLE_PROPS: PackedStringArray = ["Speaker_Posts", "Speaker_Boxes", "Light_Poles", "Lamp_Heads", "Lawn_Chair_Canvas",
	"Lawn_Chair_Frames", "Cooler", "Popcorn", "Popcorn_Bucket"]
## The modelled props (made by models/make_props.py; one mesh per prop, surfaces named by material).
const PROPS := "res://rooms/drive_in/models/props.glb"
## How each prop surface looks: material name -> [colour, metallic, roughness], or the name of
## the drive_in.glb material it borrows (so the cooler, the popcorn bucket and the lamps keep
## the colours and glow the Simple look has).
const PROP_LOOKS: Dictionary = {
	"post": [Color(0.2, 0.27, 0.22), 0.4, 0.5], "concrete": [Color(0.5, 0.5, 0.47), 0.0, 0.95],
	"speaker": [Color(0.6, 0.62, 0.6), 0.7, 0.35], "grille": [Color(0.04, 0.04, 0.04), 0.3, 0.6],
	"chrome": [Color(0.8, 0.8, 0.82), 1.0, 0.15], "cord": [Color(0.02, 0.02, 0.02), 0.0, 0.6],
	"steel": [Color(0.3, 0.34, 0.33), 0.5, 0.5], "shade": [Color(0.26, 0.32, 0.29), 0.5, 0.45],
	"alu": [Color(0.82, 0.82, 0.84), 0.9, 0.3], "web_a": [Color(0.1, 0.42, 0.24), 0.0, 0.75],
	"web_b": [Color(0.88, 0.88, 0.84), 0.0, 0.75], "armrest": [Color(0.42, 0.26, 0.13), 0.0, 0.6],
	"white": [Color(0.9, 0.9, 0.87), 0.0, 0.5],
	"lamp_glow": "Lamp_Glow", "cooler": "Cooler_Blue", "stripe_red": "Stripe_Red", "stripe_white": "Stripe_White",
	"popcorn": "Popcorn",
}
## The parked cars' Blender models: Route 22's (rooms/route22/models/vehicles.glb, made by
## make_vehicles.py there), read when the room loads, so a new export shows up here by itself.
const VEHICLES := "res://rooms/route22/models/vehicles.glb"
const CAR_TEX := "res://rooms/route22/textures/"
## The plain blocks of each parked car's paint in drive_in.glb, and the two-tone roof colour.
const CAR_PAINT_PREFIX := "Paint_"
## How each vehicle surface looks: material name in vehicles.glb -> [colour, metallic,
## roughness] (a plain material), ["grain", detail picture, metres per copy, colour] (the
## Route 22 photo grain through drive_detail.gdshader), or the drive_in.glb material it borrows
## (the lamps, so they glow as in the Simple look). "paint", "ivory" (the roof of a two-tone
## car), "wood", "trim" and "bed" are worked out per car in _car_material.
const CAR_LOOKS: Dictionary = {
	"chrome": [Color(0.8, 0.8, 0.82), 1.0, 0.12], "hub": [Color(0.8, 0.8, 0.82), 1.0, 0.15],
	"glass": [Color(0.03, 0.04, 0.05), 0.2, 0.05], "dark": [Color(0.05, 0.05, 0.055), 0.0, 0.7],
	"white": [Color(0.9, 0.9, 0.86), 0.0, 0.55], "whitewall": [Color(0.9, 0.9, 0.86), 0.0, 0.7],
	"plate": [Color(0.95, 0.8, 0.2), 0.3, 0.45], "amber": [Color(1.0, 0.55, 0.1), 0.0, 0.3],
	"tyre": ["grain", CAR_TEX + "prop_rubber.jpg", 0.5, Color(0.07, 0.07, 0.075)],
	"pad": ["grain", CAR_TEX + "prop_leather.jpg", 0.5, Color(0.05, 0.05, 0.055)],
	"seat": ["grain", CAR_TEX + "prop_leather.jpg", 0.5, Color(0.08, 0.07, 0.065)],
	"leather": ["grain", CAR_TEX + "prop_leather.jpg", 0.5, Color(0.88, 0.84, 0.76)],
	"carpet": ["grain", CAMP_TEX + "detail_fabric.jpg", 0.3, Color(0.05, 0.05, 0.055)],
	"lamp_front": "Head_Light", "lamp_tail": "Tail_Light",
}
## How high the floor of the pickup model's bed is (metres; vehicles.glb "pickup", "bed"
## surface). The things on the bed (chairs, cooler, popcorn, blanket) come down to it.
@export var pickup_bed_floor: float = 0.7
## The middle of the screen on the ground: the speaker posts' rows curve round it, and each
## post's front faces it (its speakers hang left and right, towards the cars either side).
const SCREEN_MIDDLE := Vector2(0.0, -60.0)
## Where the snack bar and the screen's legs stand (x min, z min, size): no grass tufts there.
const NO_GRASS: Array[Rect2] = [Rect2(-11.5, 20.5, 23.0, 9.5), Rect2(-15.8, -65.0, 31.6, 6.0)]

@export_group("Time of day")
@export var sun_energy: float = 1.3
@export var moon_energy: float = 0.16
@export var moon_color: Color = Color(0.62, 0.7, 0.95)
## The ambient light by day and by night (the night one is the model's old moonlit blue).
@export var day_ambient: Color = Color(0.55, 0.63, 0.78)
@export var day_ambient_energy: float = 0.55
@export var night_ambient: Color = Color(0.1, 0.13, 0.26)
@export var night_ambient_energy: float = 0.28
## Hours the clock must move before the sky and lights are worked out again.
@export var time_step: float = 0.02
## The lot's lamps by full day, as a share of their night brightness.
@export_range(0.0, 1.0) var lamps_by_day: float = 0.0

@export_group("Detailed set")
## Trees in the belt round the lot (Detailed look only), and grass tufts / ferns along the fence.
@export var tree_count: int = 480
@export var grass_count: int = 5200
@export var fern_count: int = 900

var _sun: DirectionalLight3D      # the sun by day, the moon by night
var _fx: Node3D                   # everything this script adds (mist, fireflies, detailed plants)
var _detailed: Node3D             # the detailed trees and undergrowth (shown in the Detailed look)
var _detailed_props: Node3D       # the modelled props (shown in the Detailed look)
var _prop_meshes: Dictionary = {} # prop name -> its mesh with this room's materials (_prop_mesh)
var _prop_counts: Dictionary = {} # how many of each prop were placed (for tests)
var _detailed_cars: Node3D        # the modelled cars and pickup (shown in the Detailed look)
var _simple_cars: Array[Node3D] = []   # the model's own cars and pickup (hidden in the Detailed look)
var _car_mats: Dictionary = {}    # look key -> Material, so cars of one colour share theirs
var _bed_drop: float = 0.0        # how far the things on the truck bed come down in the Detailed look
var _blanket: Node3D              # the model's blanket on the truck bed (moved down with _bed_drop)
var _fireflies: Array[CPUParticles3D] = []
var _mist_mat: ShaderMaterial
var _ground_swaps: Array[Dictionary] = []   # {mesh, surface, simple, detailed}: see _swap_materials
var _hour: float = 21.0           # the room's clock, hours 0..24 (starts at "drive_time")
var _hour_drawn: float = -99.0    # the hour the sky was last drawn for
var _env_drawn: int = 0           # instance id of the Environment it was drawn on
var _day: float = 0.0             # 0 = night, 1 = full day (from _apply_time)
var _retired: bool = false        # another room has taken over (retire()): leave the sky alone
var _plant_counts: Dictionary = {}   # how many of each kind were planted (for tests)


func _ready() -> void:
	# The model's own moonlight is replaced by the sun / moon lamp below (old saved scenes may
	# still have one).
	var old_moon := get_node_or_null("Moonlight")
	if old_moon:
		old_moon.free()
	super._ready()
	_fx = Node3D.new()
	_fx.name = "OutdoorLook"
	add_child(_fx)
	_build_sun()
	_build_mist()
	_build_fireflies()
	_swap_materials()
	_build_detailed_plants()
	_build_detailed_cars()
	_build_detailed_props()
	_hour = fposmod(float(AppState.get_setting("drive_time")), 24.0)
	EventBus.setting_changed.connect(_on_drive_setting_changed)
	_apply_detail()


## The room is freed on a room swap: drop the EventBus connection with it.
func _exit_tree() -> void:
	if EventBus.setting_changed.is_connected(_on_drive_setting_changed):
		EventBus.setting_changed.disconnect(_on_drive_setting_changed)


## RoomHost calls this (through propagate_call) when another room replaces this one, three
## seconds before it is freed: stop touching the sky, which is the new room's now.
func retire() -> void:
	_retired = true
	_exit_tree()


## Room tab: the set's detail, the hour and the sky.
func get_controls() -> Array[Dictionary]:
	return [
		{"heading": "Drive-In"},
		{"key": "drive_detail", "label": "Set detail", "type": "option",
			"options": [["auto", "Auto (follows Graphics quality)"], ["low", "Simple"], ["full", "Detailed"]],
			"tooltip": "How detailed the drive-in is drawn on this PC. Detailed: photo textures on the asphalt, the gravel and the grass, wood and cloth grain, a forest of firs, pines, oaks, maples and birches round the lot, and grass tufts and ferns along the fence. Simple: the original flat-coloured set, the lightest for a slow graphics card. Auto picks from Graphics quality: Low = Simple, otherwise Detailed. Each PC in a co-stream chooses its own."},
		{"key": "drive_fireflies", "label": "Fireflies at night", "type": "check",
			"tooltip": "Small drifting lights over the grass round the lot on dark nights."},
		{"heading": "Time of day"},
		{"key": "drive_time", "label": "Time of day", "min": 0.0, "max": 24.0, "step": 0.1, "format": "%.1f h",
			"tooltip": "The hour at the drive-in, 0 to 24. 6 = sunrise, 12 = noon, 18 = sunset (to the left of the screen), 21 = a moonlit night. The lot's lamps come on as it gets dark."},
		{"key": "drive_day_minutes", "label": "Day length", "min": 0.0, "max": 120.0, "step": 1.0, "format": "%d min", "zero": "Clock stopped",
			"tooltip": "Lets the clock run: how many minutes a full day and night takes, starting from the Time of day. 0 = the clock stands still."},
		{"heading": "Sky"},
		{"key": "drive_clouds", "label": "Clouds", "min": 0.0, "max": 2.0, "step": 0.01, "format": "%d%%", "scale": 100.0,
			"tooltip": "How much cloud drifts across the sky. 0% = a clear sky (and the lightest on a slow graphics card), 200% = overcast."},
		{"key": "drive_stars", "label": "Stars", "min": 0.0, "max": 2.0, "step": 0.01, "format": "%d%%", "scale": 100.0,
			"tooltip": "How bright the stars and the Milky Way are at night, with the odd shooting star. 0% = none."},
		{"key": "drive_aurora", "label": "Aurora", "min": 0.0, "max": 2.0, "step": 0.01, "format": "%d%%", "scale": 100.0,
			"tooltip": "Green and violet northern lights behind the screen at night. 0% = none (and lighter on a slow graphics card)."},
		{"key": "drive_mist", "label": "Mist", "min": 0.0, "max": 1.0, "step": 0.01, "format": "%d%%", "scale": 100.0,
			"tooltip": "The haze in the air and on the mountains, and the mist lying low over the lot (thickest at dusk and at night)."},
	]


func _on_drive_setting_changed(key: String, _value: Variant) -> void:
	match key:
		"drive_time":
			_hour = fposmod(float(AppState.get_setting("drive_time")), 24.0)
		"drive_clouds", "drive_stars", "drive_aurora", "drive_mist", "drive_fireflies", "photosensitive_safe":
			_hour_drawn = -100.0        # _run_clock redraws the sky and lights next frame
		"drive_detail", "graphics_quality":
			_apply_detail()


func _process(delta: float) -> void:
	super._process(delta)
	_run_clock(delta)


# ── Set detail ───────────────────────────────────────────────
## The look the set is drawn in on this PC: "low" (Simple) or "full" (Detailed). From
## "drive_detail" (Room tab > Set detail, each PC's own); its "auto" follows
## "graphics_quality": low = "low", anything else = "full".
func detail_level() -> String:
	var choice := String(AppState.get_setting("drive_detail"))
	if choice in ["low", "full"]:
		return choice
	return "low" if String(AppState.get_setting("graphics_quality")) == "low" else "full"


## Shows the Simple or the Detailed look. Called once when the room loads and whenever
## "drive_detail" or "graphics_quality" changes. Nothing is built or loaded here.
func _apply_detail() -> void:
	var detailed := detail_level() == "full"
	for s: Dictionary in _ground_swaps:
		(s["mesh"] as MeshInstance3D).set_surface_override_material(int(s["surface"]), s["detailed"] if detailed else s["simple"])
	for simple_name: String in SIMPLE_TREES + SIMPLE_PROPS:
		var n := find_child(simple_name, true, false) as Node3D
		if n:
			n.visible = not detailed
	if _detailed:
		_detailed.visible = detailed
	if _detailed_props:
		_detailed_props.visible = detailed
	if _detailed_cars:
		_detailed_cars.visible = detailed
		for car in _simple_cars:
			car.visible = not detailed
		if _blanket:
			_blanket.position.y = -_bed_drop if detailed else 0.0


## Makes the Detailed look's materials for the ground (GROUND_LOOKS) and the wood and cloth
## (GRAIN_LOOKS), and notes for every mesh surface that uses one of those imported materials
## which material to show in each look (_ground_swaps; _apply_detail switches them). The Simple
## look's entry is whatever override was there before (none, normally), so the model's own
## material shows.
func _swap_materials() -> void:
	var noise := load(CAMP_TEX + "sky_noise.png") as Texture2D
	var made: Dictionary = {}       # imported material name -> its Detailed material
	for n in find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or mi.get_parent() == _fx or _fx.is_ancestor_of(mi):
			continue
		for s in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(s)
			if m == null:
				continue
			var mat_name := m.resource_name
			if not GROUND_LOOKS.has(mat_name) and not GRAIN_LOOKS.has(mat_name):
				continue
			if not made.has(mat_name):
				var sm := ShaderMaterial.new()
				if GROUND_LOOKS.has(mat_name):
					var look: Array = GROUND_LOOKS[mat_name]
					sm.shader = GROUND_SHADER
					sm.set_shader_parameter("photo", load(String(look[0])))
					sm.set_shader_parameter("tile_size", float(look[1]))
					sm.set_shader_parameter("tint", look[2])
					sm.set_shader_parameter("patchiness", float(look[3]))
					sm.set_shader_parameter("roughness", float(look[4]))
					sm.set_shader_parameter("noise", noise)
					if bool(look[5]):
						sm.set_shader_parameter("use_forest", 1.0)
						sm.set_shader_parameter("forest", load(CAMP_TEX + "ground_forest.jpg"))
						sm.set_shader_parameter("fence_rect", Vector4(FENCE.position.x, FENCE.position.y, FENCE.end.x, FENCE.end.y))
				else:
					var grain: Array = GRAIN_LOOKS[mat_name]
					sm.shader = DETAIL_SHADER
					sm.set_shader_parameter("grain_tex", load(String(grain[0])))
					sm.set_shader_parameter("tile", float(grain[1]))
					var col := (m as BaseMaterial3D).albedo_color if m is BaseMaterial3D else Color(0.5, 0.5, 0.5)
					sm.set_shader_parameter("base", col)
				made[mat_name] = sm
			_ground_swaps.append({"mesh": mi, "surface": s, "simple": mi.get_surface_override_material(s), "detailed": made[mat_name]})


# ── The detailed trees and undergrowth ───────────────────────
## How far (metres) a point on the ground is outside the fence; 0 or less = inside it.
static func outside_fence(p: Vector2) -> float:
	var d := Vector2(maxf(FENCE.position.x - p.x, p.x - FENCE.end.x), maxf(FENCE.position.y - p.y, p.y - FENCE.end.y))
	if d.x <= 0.0 and d.y <= 0.0:
		return maxf(d.x, d.y)
	return Vector2(maxf(d.x, 0.0), maxf(d.y, 0.0)).length()


## Builds the Detailed look's plants (hidden until _apply_detail shows them), the same on every
## PC (fixed random seed):
##   - a belt of trees round the lot, 5 to 50 m outside the fence, thicker near it, as
##     MultiMeshes (one per kind) of the campfire's leaf-card trees (campfire_trees.gd kit()).
##     Mostly firs and pines with oaks, maples and birches between, and young firs filling in
##     at the belt's inner edge, where the cameras see it best;
##   - grass tufts on the grass strips inside the fence (not on the asphalt, under the snack
##     bar or the screen's legs) and ferns along the foot of the trees. These cast no shadows.
func _build_detailed_plants() -> void:
	_detailed = Node3D.new()
	_detailed.name = "DetailedPlants"
	_detailed.visible = false
	_fx.add_child(_detailed)
	var mats := Trees.materials(0.06)
	var rng := RandomNumberGenerator.new()
	rng.seed = 19561114
	var spots: Dictionary = {}      # kind -> [Array[Transform3D], PackedColorArray]
	var tries := 0
	var planted := 0
	while planted < tree_count and tries < tree_count * 40:
		tries += 1
		var p := Vector2(rng.randf_range(FENCE.position.x - 50.0, FENCE.end.x + 50.0), rng.randf_range(FENCE.position.y - 50.0, FENCE.end.y + 50.0))
		var out := outside_fence(p)
		# thickest just outside the fence, thinning out towards the back of the belt
		if out < 5.0 or out > 50.0 or rng.randf() > lerpf(1.0, 0.25, (out - 5.0) / 45.0):
			continue
		var roll := rng.randf()
		var kind := "fir"
		if out < 11.0 and roll < 0.25:
			kind = "young_fir"
		else:
			kind = _pick_species(rng.randf())
		var tall := rng.randf_range(11.0, 21.0)
		var wide := tall * 0.38
		match kind:
			"young_fir":
				tall = rng.randf_range(3.5, 7.0)
				wide = tall * 0.45
			"pine":
				tall = rng.randf_range(14.0, 22.0)
				wide = tall * 0.5
			"oak", "maple":
				tall = rng.randf_range(9.0, 15.0)
				wide = tall * rng.randf_range(0.65, 0.85)
			"birch":
				tall = rng.randf_range(10.0, 16.0)
				wide = tall * 0.55
		var shade := rng.randf_range(0.78, 1.08)
		var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(wide, tall, wide)), Vector3(p.x, -0.06, p.y))
		_add_spot(spots, kind, xf, Color(shade, shade, shade))
		planted += 1
	# grass tufts inside the fence, off the asphalt (the lot is x -50..50, z -55..35)
	var lot := Rect2(-50.5, -55.5, 101.0, 91.0)
	var grass_left := grass_count
	tries = 0
	while grass_left > 0 and tries < grass_count * 6:
		tries += 1
		var p := Vector2(rng.randf_range(FENCE.position.x - 8.0, FENCE.end.x + 8.0), rng.randf_range(FENCE.position.y - 8.0, FENCE.end.y + 8.0))
		if lot.has_point(p) or outside_fence(p) > 6.0 or _on_no_grass(p):
			continue
		var size := rng.randf_range(0.55, 1.15)
		var shade := rng.randf_range(0.8, 1.08)
		_add_spot(spots, "grass", Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(size, size * rng.randf_range(0.8, 1.3), size)), Vector3(p.x, -0.07, p.y)), Color(shade, shade, shade))
		grass_left -= 1
	# ferns at the foot of the trees, just outside the fence
	var ferns_left := fern_count
	tries = 0
	while ferns_left > 0 and tries < fern_count * 20:
		tries += 1
		var p := Vector2(rng.randf_range(FENCE.position.x - 20.0, FENCE.end.x + 20.0), rng.randf_range(FENCE.position.y - 20.0, FENCE.end.y + 20.0))
		var out := outside_fence(p)
		if out < 1.0 or out > 18.0:
			continue
		var size := rng.randf_range(0.7, 1.3)
		var shade := rng.randf_range(0.8, 1.05)
		_add_spot(spots, "fern", Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(size, size, size)), Vector3(p.x, -0.07, p.y)), Color(shade, shade, shade))
		ferns_left -= 1
	for kind: String in spots:
		var row: Array = spots[kind]
		var list: Array[Transform3D] = row[0]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = Trees.kit(kind, mats)       # brings its own materials (bark and cards)
		mm.instance_count = list.size()
		var tints: PackedColorArray = row[1]
		for i in list.size():
			mm.set_instance_transform(i, list[i])
			mm.set_instance_color(i, tints[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = kind.to_pascal_case()
		mmi.multimesh = mm
		# trees cast shadows; the small plants don't (too small to matter, and shadows cost)
		var small := kind == "grass" or kind == "fern"
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if small else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if small:
			mmi.visibility_range_end = 70.0          # tufts vanish past 70 m from the camera
			mmi.visibility_range_end_margin = 10.0
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		_detailed.add_child(mmi)
		_plant_counts[kind] = list.size()


## The kind of a tall tree in the belt for a random roll 0..1: firs, pines, oaks, maples, birches.
static func _pick_species(roll: float) -> String:
	if roll < 0.36:
		return "fir"
	if roll < 0.5:
		return "pine"
	if roll < 0.68:
		return "oak"
	if roll < 0.84:
		return "maple"
	return "birch"


## Adds one plant to the lists _build_detailed_plants turns into MultiMeshes.
static func _add_spot(spots: Dictionary, kind: String, xf: Transform3D, tint: Color) -> void:
	if not spots.has(kind):
		var none: Array[Transform3D] = []
		spots[kind] = [none, PackedColorArray()]
	var row: Array = spots[kind]
	(row[0] as Array[Transform3D]).append(xf)
	var tints: PackedColorArray = row[1]
	tints.append(tint)
	row[1] = tints        # (a PackedColorArray is copied when read out of an Array)


static func _on_no_grass(p: Vector2) -> bool:
	for r: Rect2 in NO_GRASS:
		if r.has_point(p):
			return true
	return false


## How many of each kind of plant the Detailed look has (for tests): {"fir": n, "grass": n, ...}.
func get_plant_counts() -> Dictionary:
	return _plant_counts


# ── The modelled cars ────────────────────────────────────────
## Builds the Detailed look's cars (hidden until _apply_detail shows them): every parked car in
## drive_in.glb ("Car_00", "Car_01", ...) and the backed-in "Pickup_Truck" get a Route 22 Blender
## model (VEHICLES) in their place, the same colour. Where each stands and which way it faces
## comes from the original's own lamps (its "Head_Light" and "Tail_Light" surfaces), so it also
## gets the same nose-up tilt on the ramps; its wheels go down to where the original's lowest
## point is. Two-tone cars become hardtops with a roof in their second colour; the plain ones are
## two hardtops to one convertible. The pickup gets its tailgate down, its tail where the
## original's is, and the things on its bed come down to the model's lower bed (_bed_drop).
func _build_detailed_cars() -> void:
	if not ResourceLoader.exists(VEHICLES):
		return
	var root := (load(VEHICLES) as PackedScene).instantiate()
	var models: Dictionary = {}       # kind -> {"mesh", "lamp_mid": the middle of its lamps, "low": its box}
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var fronts := Vector3.ZERO
		var tails := Vector3.ZERO
		var nf := 0
		var nt := 0
		for c in mi.get_children():
			if String(c.name).contains("_LampFront_"):
				fronts += (c as Node3D).position
				nf += 1
			elif String(c.name).contains("_LampTail_"):
				tails += (c as Node3D).position
				nt += 1
		var front := fronts / maxf(nf, 1)
		var tail := tails / maxf(nt, 1)
		models[String(mi.name)] = {"mesh": mi.mesh, "front": front, "tail": tail, "box": mi.get_aabb()}
	root.free()
	if not models.has("classic") or not models.has("pickup"):
		return
	_detailed_cars = Node3D.new()
	_detailed_cars.name = "DetailedCars"
	_detailed_cars.visible = false
	_fx.add_child(_detailed_cars)
	var plain := 0
	for n in find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var car_name := String(mi.name)
		var is_pickup := car_name == "Pickup_Truck"
		if mi.mesh == null or _fx.is_ancestor_of(mi) or not (car_name.begins_with("Car_") or is_pickup):
			continue
		# its paint colours (first = the body, a second = the roof) and its lamps
		var paints: Array[Color] = []
		var head := Vector3.ZERO
		var tail := Vector3.ZERO
		var to_room := global_transform.affine_inverse() * mi.global_transform
		for s in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(s)
			var look := m.resource_name if m else ""
			if m is BaseMaterial3D and (look.begins_with(CAR_PAINT_PREFIX) or look == "Truck_Red"):
				paints.append((m as BaseMaterial3D).albedo_color)
			elif look == "Head_Light" or look == "Tail_Light":
				var sum := Vector3.ZERO
				var verts: PackedVector3Array = mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
				for v in verts:
					sum += to_room * v
				if look == "Head_Light":
					head = sum / maxf(verts.size(), 1)
				else:
					tail = sum / maxf(verts.size(), 1)
		if paints.is_empty() or head.is_equal_approx(tail):
			continue
		var kind := "pickup"
		if not is_pickup:
			if paints.size() > 1 or plain % 3 != 1:
				kind = "classic"
			else:
				kind = "convertible"
			if paints.size() == 1:
				plain += 1
		var model: Dictionary = models[kind]
		# facing: the model's lamps line up with the original's (model front = -Z)
		var turn := Basis.looking_at((head - tail).normalized())
		var own_tilt := Basis.looking_at(((model["front"] as Vector3) - (model["tail"] as Vector3)).normalized())
		var facing := turn * own_tilt.inverse()
		var xf := Transform3D(facing, Vector3.ZERO)
		if is_pickup:
			# its tail at the original's tail (the bed's load stays on the bed)
			xf.origin = tail - facing * (model["tail"] as Vector3)
		else:
			xf.origin = (head + tail) * 0.5 - facing * (((model["front"] as Vector3) + (model["tail"] as Vector3)) * 0.5)
		# wheels down: the model's lowest corner to the original's lowest point
		var low := INF
		var box: AABB = model["box"]
		for k in 8:
			low = minf(low, (xf * box.get_endpoint(k)).y)
		xf.origin.y += _room_aabb(mi).position.y - low
		var paint := paints[0]
		var roof := paints[1] if paints.size() > 1 else Color(0.92, 0.88, 0.78)
		_add_car(model["mesh"], xf, paint, roof)
		if is_pickup and models.has("pickup_gate_down"):
			_add_car((models["pickup_gate_down"] as Dictionary)["mesh"], xf, paint, roof)
			var frames := find_child("Lawn_Chair_Frames", true, false) as MeshInstance3D
			var old_floor := _room_aabb(frames).position.y if frames else pickup_bed_floor
			_bed_drop = maxf(0.0, old_floor - (xf.origin.y + pickup_bed_floor))
		_simple_cars.append(mi)
		_prop_counts[kind] = int(_prop_counts.get(kind, 0)) + 1
	_blanket = find_child("Blanket", true, false) as Node3D


## Adds one vehicle model at xf (room space) with this room's materials for its colours.
func _add_car(mesh: Mesh, xf: Transform3D, paint: Color, roof: Color) -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Car%d" % _detailed_cars.get_child_count()
	mi.mesh = mesh
	_detailed_cars.add_child(mi)
	mi.transform = xf
	for s in mesh.get_surface_count():
		var from := mesh.surface_get_material(s)
		var m := _car_material(from.resource_name if from else "", paint, roof)
		if m:
			mi.set_surface_override_material(s, m)


## The material for a vehicle surface (CAR_LOOKS by its material name; the paint ones from the
## car's own colours), made once and shared by every car that needs the same one.
func _car_material(look: String, paint: Color, roof: Color) -> Material:
	var key := look
	var spec: Variant = CAR_LOOKS.get(look, null)
	match look:
		"paint", "wood", "trim":            # (wood and trim are the woody's: plain paint here)
			key = "paint_" + paint.to_html()
			spec = ["paint", paint]
		"ivory":
			key = "paint_" + roof.to_html()
			spec = ["paint", roof]
		"bed":
			spec = ["grain", CAMP_TEX + "detail_planks.jpg", 1.1, Color(0.35, 0.22, 0.12)]
	if _car_mats.has(key):
		return _car_mats[key]
	var made: Material = null
	if spec is String:
		made = _imported_material(String(spec))
	elif spec is Array and str((spec as Array)[0]) == "paint":
		# glossy car paint: a clear coat over a slightly metallic colour
		var sm := StandardMaterial3D.new()
		sm.albedo_color = (spec as Array)[1]
		sm.metallic = 0.3
		sm.roughness = 0.32
		sm.clearcoat_enabled = true
		sm.clearcoat = 0.7
		sm.clearcoat_roughness = 0.12
		made = sm
	elif spec is Array and str((spec as Array)[0]) == "grain":
		var gm := ShaderMaterial.new()
		gm.shader = DETAIL_SHADER
		gm.set_shader_parameter("grain_tex", load(String((spec as Array)[1])))
		gm.set_shader_parameter("tile", float((spec as Array)[2]))
		gm.set_shader_parameter("base", (spec as Array)[3])
		made = gm
	elif spec is Array:
		var pm := StandardMaterial3D.new()
		pm.albedo_color = (spec as Array)[0]
		pm.metallic = float((spec as Array)[1])
		pm.roughness = float((spec as Array)[2])
		if look == "amber":
			pm.emission_enabled = true
			pm.emission = (spec as Array)[0]
			pm.emission_energy_multiplier = 0.4
		made = pm
	_car_mats[key] = made
	return made


## A material of drive_in.glb by its name (the first mesh surface that uses it), or null.
func _imported_material(mat_name: String) -> Material:
	for n in find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or _fx.is_ancestor_of(mi):
			continue
		for s in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(s)
			if m and m.resource_name == mat_name:
				return m
	return null


# ── The modelled props ───────────────────────────────────────
## Builds the Detailed look's props (hidden until _apply_detail shows them) where the model's
## plain blocks stand, finding them from the blocks' own shapes (so moving a block in Blender
## moves its prop):
##   - a speaker post at the foot of every post in "Speaker_Posts" (one MultiMesh), facing
##     the middle of the screen;
##   - a lot light at the foot of every pole in "Light_Poles", its arm towards the lamp head
##     the model has next to it ("Lamp_Heads"); the two low lamp heads under the snack bar's
##     canopy get the small wall lamp;
##   - lawn chairs where "Lawn_Chair_Canvas" has one, the cooler and the popcorn bucket on the
##     truck bed where the blocks are (lowered by _bed_drop onto the pickup model's bed, which
##     is lower than the model's own: _build_detailed_cars runs first and sets it).
## The lamps' light still comes from the room's LAMP_ markers (Room), which stay where they are.
func _build_detailed_props() -> void:
	if not ResourceLoader.exists(PROPS):
		return
	var scene := load(PROPS) as PackedScene
	var root := scene.instantiate()
	var meshes: Dictionary = {}       # prop name -> its Mesh as made in Blender
	for n in root.find_children("*", "MeshInstance3D", true, false):
		meshes[String(n.name)] = (n as MeshInstance3D).mesh
	root.free()
	_detailed_props = Node3D.new()
	_detailed_props.name = "DetailedProps"
	_detailed_props.visible = false
	_fx.add_child(_detailed_props)
	# speaker posts: one MultiMesh for all of them
	var posts := _feet("Speaker_Posts", 0.05, 1.0)
	if not posts.is_empty() and meshes.has("speaker_post"):
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _prop_mesh(meshes, "speaker_post")
		mm.instance_count = posts.size()
		for i in posts.size():
			var p: Vector3 = posts[i]
			var to_screen := Vector3(SCREEN_MIDDLE.x - p.x, 0.0, SCREEN_MIDDLE.y - p.z)
			mm.set_instance_transform(i, Transform3D(Basis.looking_at(to_screen.normalized()), p))
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "SpeakerPosts"
		mmi.multimesh = mm
		_detailed_props.add_child(mmi)
		_prop_counts["speaker_post"] = posts.size()
	# lot lights, their arms towards the model's lamp heads; the low heads get wall lamps
	var heads := _feet("Lamp_Heads", 99.0, 1.5)
	var high_heads: Array[Vector3] = []
	for h: Vector3 in heads:
		if h.y > 6.0:
			high_heads.append(h)
		elif meshes.has("wall_lamp"):
			# (_feet gives the lowest point: the lamp's lens; the prop hangs 0.22 m below its top)
			_place_prop(meshes, "wall_lamp", Transform3D(Basis.IDENTITY, h + Vector3(0.0, 0.22, 0.0)))
	for p: Vector3 in _feet("Light_Poles", 0.05, 1.0):
		var toward := Vector3.FORWARD
		var best := INF
		for h: Vector3 in high_heads:
			var d := Vector2(h.x - p.x, h.z - p.z)
			if d.length() < best and d.length() > 0.05:
				best = d.length()
				toward = Vector3(d.x, 0.0, d.y).normalized()
		if meshes.has("light_pole"):
			_place_prop(meshes, "light_pole", Transform3D(Basis.looking_at(toward), p))
	# on the truck bed: the chairs face the screen (the truck is backed in)
	# (one chair per piece of canvas: the frames' tubes are too far apart to group; the chair
	# stands where the frames reach lowest, on the bed floor)
	var floor_y := 0.0
	var frames := find_child("Lawn_Chair_Frames", true, false) as MeshInstance3D
	if frames:
		floor_y = _room_aabb(frames).position.y
	for p: Vector3 in _feet("Lawn_Chair_Canvas", 99.0, 0.15):
		if meshes.has("lawn_chair"):
			_place_prop(meshes, "lawn_chair", Transform3D(Basis.IDENTITY, Vector3(p.x, floor_y - _bed_drop, p.z)))
	for pair: Array in [["Cooler", "cooler"], ["Popcorn_Bucket", "popcorn"]]:
		var block := find_child(String(pair[0]), true, false) as MeshInstance3D
		if block and meshes.has(pair[1]):
			var box := _room_aabb(block)
			_place_prop(meshes, String(pair[1]), Transform3D(Basis.IDENTITY, Vector3(box.get_center().x, box.position.y - _bed_drop, box.get_center().z)))


## Adds one prop (a MeshInstance3D with this room's materials) at xf, room space.
func _place_prop(meshes: Dictionary, prop: String, xf: Transform3D) -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Prop" + prop.to_pascal_case()     # (not the model's own block names, which find_child looks up)
	mi.mesh = _prop_mesh(meshes, prop)
	_detailed_props.add_child(mi)
	mi.transform = xf
	_prop_counts[prop] = int(_prop_counts.get(prop, 0)) + 1


## A prop's mesh with the room's materials on its surfaces (PROP_LOOKS, by the surface's
## material name); made once per prop. A copy, so the props.glb resource stays untouched.
func _prop_mesh(meshes: Dictionary, prop: String) -> Mesh:
	if _prop_meshes.has(prop):
		return _prop_meshes[prop]
	var mesh := (meshes[prop] as Mesh).duplicate() as Mesh
	var imported: Dictionary = {}     # drive_in.glb material name -> material (for PROP_LOOKS' borrowed ones)
	for n in find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or _fx.is_ancestor_of(mi):
			continue
		for s in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(s)
			if m:
				imported[m.resource_name] = m
	for s in mesh.get_surface_count():
		var from := mesh.surface_get_material(s)
		var look: Variant = PROP_LOOKS.get(from.resource_name if from else "", null)
		if look is String and imported.has(look):
			mesh.surface_set_material(s, imported[look])
		elif look is Array:
			var sm := StandardMaterial3D.new()
			sm.albedo_color = look[0]
			sm.metallic = float(look[1])
			sm.roughness = float(look[2])
			mesh.surface_set_material(s, sm)
	_prop_meshes[prop] = mesh
	return mesh


## Where the separate pieces of one of the model's meshes stand: its triangles between the
## ground and `top` (metres up), grouped into pieces whose outlines seen from above are more
## than `gap` metres apart. Returns one point per piece: the middle of its outline (x, z) at its
## lowest vertex (y), room space.
func _feet(mesh_name: String, top: float, gap: float) -> Array[Vector3]:
	var found: Array[Vector3] = []
	var mi := find_child(mesh_name, true, false) as MeshInstance3D
	if mi == null or mi.mesh == null:
		return found
	var to_room := global_transform.affine_inverse() * mi.global_transform
	var outlines: Array[Rect2] = []   # per piece: its outline from above (x, z)
	var lows: Array[float] = []       # per piece: its lowest y
	# triangle by triangle (a big quad has its corners far apart; the triangle keeps them together)
	var corners := mi.mesh.get_faces()
	for t in range(0, corners.size(), 3):
		var p0 := to_room * corners[t]
		var p1 := to_room * corners[t + 1]
		var p2 := to_room * corners[t + 2]
		if maxf(p0.y, maxf(p1.y, p2.y)) > top:
			continue
		var tri := Rect2(Vector2(p0.x, p0.z), Vector2.ZERO).expand(Vector2(p1.x, p1.z)).expand(Vector2(p2.x, p2.z))
		var low := minf(p0.y, minf(p1.y, p2.y))
		var hit := -1
		for c in outlines.size():
			if outlines[c].grow(gap).intersects(tri, true):
				hit = c
				break
		if hit < 0:
			outlines.append(tri)
			lows.append(low)
		else:
			outlines[hit] = outlines[hit].merge(tri)
			lows[hit] = minf(lows[hit], low)
	# pieces started apart can grow into each other (their vertices came in any order): join those
	var joined := true
	while joined:
		joined = false
		for a in outlines.size():
			for b in range(a + 1, outlines.size()):
				if outlines[a].grow(gap).intersects(outlines[b], true):
					outlines[a] = outlines[a].merge(outlines[b])
					lows[a] = minf(lows[a], lows[b])
					outlines.remove_at(b)
					lows.remove_at(b)
					joined = true
					break
			if joined:
				break
	for c in outlines.size():
		var mid := outlines[c].get_center()
		found.append(Vector3(mid.x, lows[c], mid.y))
	return found


## A mesh's box in room space.
func _room_aabb(mi: MeshInstance3D) -> AABB:
	return (global_transform.affine_inverse() * mi.global_transform) * mi.get_aabb()


## How many of each modelled prop the Detailed look has (for tests): {"speaker_post": n, ...}.
func get_prop_counts() -> Dictionary:
	return _prop_counts


# ── Time of day and the sky ──────────────────────────────────
## One lamp for the sun and the moon (only one of them lights the lot at a time).
func _build_sun() -> void:
	_sun = DirectionalLight3D.new()
	_sun.name = "SunMoon"
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 120.0
	_sun.light_angular_distance = 0.8
	_fx.add_child(_sun)


## Called every frame. Moves the clock on while "drive_day_minutes" is above 0, and redraws the
## sky and lights when the hour has moved by time_step or the app swapped the Environment (a
## graphics setting changed).
func _run_clock(delta: float) -> void:
	if _retired:
		return
	var day_minutes := float(AppState.get_setting("drive_day_minutes"))
	if day_minutes > 0.0:
		_hour = fposmod(_hour + delta * 24.0 / (day_minutes * 60.0), 24.0)
	var env := get_world_3d().environment if is_inside_tree() else null
	var env_id := env.get_instance_id() if env else 0
	if absf(_hour - _hour_drawn) >= time_step or env_id != _env_drawn:
		_hour_drawn = _hour
		_env_drawn = env_id
		_apply_time(env)


## The hour the room's clock shows now, 0..24 (for tests; "drive_time" only says where it started).
func get_hour() -> float:
	return _hour


## 0 = night, 1 = full day, at the hour last drawn (for tests).
func get_daylight() -> float:
	return _day


## Where the sun is at an hour: a unit vector pointing AT it. The same path as the Lakeside
## Campfire's (campfire_room.gd sun_at): it rises on the right (+X), is highest at noon and sets
## to the left of and a little behind the screen.
static func sun_at(hour: float) -> Vector3:
	var a := (hour - 6.0) / 12.0 * PI
	return Vector3(cos(a), sin(a), 0.5 * cos(a) - 0.05).normalized()


## Where the moon is: it crosses the sky above and behind the screen while the sun is down
## (the same as campfire_room.gd moon_at), roughly where the model's old moonlight came from.
static func moon_at(hour: float) -> Vector3:
	var b := (hour - 18.0) / 12.0 * PI
	return Vector3(cos(b) * 0.8, sin(b) * 0.75 + 0.12, -0.62).normalized()


## Everything that follows the hour (_hour): the sky shader's uniforms, the sun / moon lamp, the
## ambient light, the haze, the ground mist and the fireflies. env = the Environment in use; it is
## only touched when it is this room's own (its sky uses camp_sky.gdshader), never another room's.
func _apply_time(env: Environment) -> void:
	var sun := sun_at(_hour)
	var moon := moon_at(_hour)
	_day = smoothstep(-0.12, 0.22, sun.y)
	var dusk := (1.0 - smoothstep(0.0, 0.4, absf(sun.y))) * smoothstep(-0.3, -0.05, sun.y)
	var clouds := clampf(float(AppState.get_setting("drive_clouds")), 0.0, 2.0)
	var mist := clampf(float(AppState.get_setting("drive_mist")), 0.0, 1.0)
	var turn := global_basis.orthonormalized()                   # the shaders work in world space
	# the horizon colour camp_sky.gdshader mixes, for the haze and the mist
	var hor := Color(0.015, 0.02, 0.05).lerp(Color(0.5, 0.68, 0.92), _day).lerp(Color(0.92, 0.5, 0.38), dusk * 0.6)
	var haze := hor.lerp(Color(0.6, 0.66, 0.74) * (0.06 + 0.94 * _day), 0.4)
	if env and env.sky and env.sky.sky_material is ShaderMaterial and (env.sky.sky_material as ShaderMaterial).shader == SKY_SHADER:
		var sky := env.sky.sky_material as ShaderMaterial
		sky.set_shader_parameter("cloud_noise", load(CAMP_TEX + "sky_noise.png"))
		sky.set_shader_parameter("sun_dir", turn * sun)
		sky.set_shader_parameter("moon_dir", turn * moon)
		sky.set_shader_parameter("day", _day)
		sky.set_shader_parameter("dusk", dusk)
		sky.set_shader_parameter("twinkle", 0.0 if bool(AppState.get_setting("photosensitive_safe")) else 1.0)
		sky.set_shader_parameter("cloud_amount", clouds)
		sky.set_shader_parameter("star_amount", float(AppState.get_setting("drive_stars")))
		sky.set_shader_parameter("aurora_amount", float(AppState.get_setting("drive_aurora")))
		sky.set_shader_parameter("haze", mist)
		env.ambient_light_color = night_ambient.lerp(day_ambient, _day).lerp(Color(0.62, 0.42, 0.48), dusk * 0.35)
		env.ambient_light_energy = lerpf(night_ambient_energy, day_ambient_energy, _day)
		# the volumetric fog (it also makes the projector's beam show) takes the haze's colour;
		# thinner by day, when the sun would turn it into a white wash
		env.volumetric_fog_albedo = Color(0.8, 0.82, 0.9).lerp(haze, 0.5)
		env.volumetric_fog_density = (0.0015 + 0.004 * mist) * lerpf(1.0, 0.35, _day)
		env.fog_light_color = haze
		env.fog_density = (0.0004 + 0.0025 * mist) * lerpf(1.0, 0.6, _day)
	# the sun by day, the moon by night
	var light_dir := sun
	var light_col := Color(1.0, 0.55, 0.25).lerp(Color(1.0, 0.96, 0.88), smoothstep(0.05, 0.45, sun.y))
	var energy := sun_energy * smoothstep(0.0, 0.2, sun.y)
	if sun.y <= 0.02:
		light_dir = moon
		light_col = moon_color
		energy = moon_energy * smoothstep(0.05, 0.25, moon.y)
	_sun.light_color = light_col
	_sun.light_energy = energy
	_sun.visible = energy > 0.002
	var world_dir := turn * light_dir
	_sun.global_basis = Basis.looking_at(-world_dir, Vector3.UP if absf(world_dir.y) < 0.99 else Vector3.FORWARD)
	if _mist_mat:
		# the mist on the ground: a little all day, most at dusk and through the night
		_mist_mat.set_shader_parameter("amount", mist * clampf(0.15 + 0.85 * maxf(dusk, 0.8 * (1.0 - _day)), 0.0, 1.0))
		_mist_mat.set_shader_parameter("color", hor.lerp(Color(0.75, 0.8, 0.86) * (0.1 + 0.9 * _day), 0.5))
	var out_tonight := bool(AppState.get_setting("drive_fireflies")) and _day < 0.35
	for f in _fireflies:
		f.emitting = out_tonight
		f.visible = out_tonight or f.visible and _day < 0.5


## The lot's lamps (the house lights) are off by full day, on top of what every room does (the
## House lights slider, dimming for a video).
func _target_level() -> float:
	return super._target_level() * lerpf(1.0, lamps_by_day, _day)


# ── Mist and fireflies ───────────────────────────────────────
## Ground mist: two big flat sheets lying low over the whole lot (the campfire's
## camp_mist.gdshader, which thins them out close to the camera). _apply_time sets how thick.
func _build_mist() -> void:
	_mist_mat = ShaderMaterial.new()
	_mist_mat.shader = MIST_SHADER
	_mist_mat.set_shader_parameter("noise", load(CAMP_TEX + "sky_noise.png"))
	var holder := Node3D.new()
	holder.name = "Mist"
	_fx.add_child(holder)
	for i in 2:
		var sheet := PlaneMesh.new()
		sheet.size = Vector2(240.0, 230.0)
		var mi := MeshInstance3D.new()
		mi.mesh = sheet
		mi.material_override = _mist_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(mi)
		mi.position = Vector3(0.0, 0.3 + 0.55 * float(i), -14.0)


## Fireflies: slow drifting specks over the grass strips down both sides of the lot and behind
## the screen (three box-shaped swarms). _apply_time lets them out on dark nights.
func _build_fireflies() -> void:
	# [centre, half size]: left strip, right strip, behind the screen
	var swarms: Array = [[Vector3(-61.0, 1.4, -14.0), Vector3(9.0, 1.2, 58.0)], [Vector3(61.0, 1.4, -14.0), Vector3(9.0, 1.2, 58.0)],
		[Vector3(0.0, 1.4, -68.0), Vector3(50.0, 1.2, 7.0)]]
	var speck := QuadMesh.new()
	speck.size = Vector2(0.16, 0.16)
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.vertex_color_use_as_albedo = true
	sm.albedo_color = Color(2.5, 2.5, 2.5)
	sm.albedo_texture = _soft_dot()
	sm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	sm.billboard_keep_scale = true
	sm.disable_fog = true           # (fog on a glow that is added to the picture shows as a pale square)
	speck.material = sm
	var glow := Gradient.new()      # each one fades in, glows, fades out
	glow.set_color(0, Color(0.0, 0.0, 0.0, 1.0))
	glow.add_point(0.25, Color(0.75, 1.0, 0.3, 1.0))
	glow.add_point(0.6, Color(0.6, 0.9, 0.2, 1.0))
	glow.set_color(glow.get_point_count() - 1, Color(0.0, 0.0, 0.0, 1.0))
	for s: Array in swarms:
		var f := CPUParticles3D.new()
		f.name = "Fireflies"
		f.amount = 70
		f.lifetime = 7.0
		f.randomness = 1.0
		f.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		f.emission_box_extents = s[1]
		f.direction = Vector3(1.0, 0.2, 0.0)
		f.spread = 180.0
		f.gravity = Vector3.ZERO
		f.initial_velocity_min = 0.1
		f.initial_velocity_max = 0.35
		f.color_ramp = glow
		f.mesh = speck
		f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		f.emitting = false
		f.visible = false
		f.visibility_aabb = AABB(-(s[1] as Vector3) - Vector3.ONE * 3.0, (s[1] as Vector3) * 2.0 + Vector3.ONE * 6.0)
		_fx.add_child(f)
		f.position = s[0]
		_fireflies.append(f)


## A round soft spot picture (white in the middle fading out) for the fireflies.
static func _soft_dot() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	g.add_point(0.3, Color(0.6, 0.6, 0.6, 1.0))
	g.set_color(g.get_point_count() - 1, Color(0.0, 0.0, 0.0, 1.0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 32
	t.height = 32
	return t
