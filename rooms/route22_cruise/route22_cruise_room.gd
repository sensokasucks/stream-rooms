extends Room
## Route 22 Cruise: the "just chatting" backdrop. Up to four co-stream guests ride in a red woody
## convertible down an endless two-lane desert highway at sunset (or any hour and weather), past
## red sandstone, roadside places, other traffic and billboards showing pictures Sen picks.
## No big screen and no chat audience here: that is the Drive-In (rooms/route22, the same desert;
## the Room tab's Scene switch jumps between the two).
##
## How it moves without moving: the car and the cameras stand still at the world's origin while
## the desert slides back past them (rooms/route22/r22_trip.gd: 24 road pieces from a shuffled
## bag, about ten in view; the ground's and the road's pictures slide in their shaders). The
## road curves and rolls away in the distance (a bend in every Route 22 shader), so it never
## looks like a straight treadmill. Nothing is ever far from the origin, so nothing jitters.
##
## The parts (all in rooms/route22/):
##   r22_desert.gd   hour, sky, weather, sun, fog, rain, sand, shimmer, sound (shared with the Drive-In)
##   r22_trip.gd     the road pieces (r22_pieces.gd), curves, the speed, co-stream travel sync
##   r22_billboards.gd  boards along the road with Sen's pictures
##   r22_traffic.gd  oncoming and overtaking vehicles
##   r22_extras.gd   tumbleweeds, dust devils, vultures, a jackrabbit, a lizard, coyotes
##   r22_car.gd      the woody
## The presenters (PRESENTER_1..4) sit in the woody: two on the front bench, two up on the rear
## deck behind the back seat so the Windshield camera sees all four.
## Settings: see get_controls(); defaults in AppState.DEFAULTS ("r22_" keys), the ones a
## co-stream shares in NetSession.SHARED_BASE.

const Geo := preload("res://rooms/route22/r22_geo.gd")
const Desert := preload("res://rooms/route22/r22_desert.gd")
const Trip := preload("res://rooms/route22/r22_trip.gd")
const Billboards := preload("res://rooms/route22/r22_billboards.gd")
const Traffic := preload("res://rooms/route22/r22_traffic.gd")
const Extras := preload("res://rooms/route22/r22_extras.gd")
const Car := preload("res://rooms/route22/r22_car.gd")
## This room's id (rooms/route22_cruise/room_info.tres) and the Drive-In's: the Scene switch.
const MY_ID := "route22_cruise"
const OTHER_ID := "route22"
## The woody's place: its middle, in the right-hand lane.
const CAR_AT := Vector3(1.8, 0.0, 0.0)
## Where the riders sit, car space: front bench, and up on the rear deck behind the back seat.
const SEATS: Array[Vector3] = [Vector3(-0.42, 0.67, -0.2), Vector3(0.42, 0.67, -0.2), Vector3(-0.5, 1.02, 1.95), Vector3(0.5, 1.02, 1.95)]
## Camera views: [name (after "CAM_"; the number sets the order), where it stands, what it looks at].
const CAMERAS: Array = [
	["01_Windshield", Vector3(1.8, 1.9, -6.0), Vector3(1.8, 1.2, 0.6)],
	["02_Back_Seat_View", Vector3(1.8, 2.3, 5.6), Vector3(1.8, 1.3, -6.0)],
	["03_Passenger_Side", Vector3(4.4, 1.45, -1.4), Vector3(1.6, 1.2, 0.6)],
	["04_Driver_Side", Vector3(-0.2, 1.5, -1.0), Vector3(2.2, 1.15, 0.7)],
	["05_Hood", Vector3(1.8, 1.3, -3.4), Vector3(1.8, 1.15, 0.6)],
	["06_Chase", Vector3(1.8, 4.2, 13.0), Vector3(1.8, 1.0, -12.0)],
	["07_Drone", Vector3(7.0, 19.0, 24.0), Vector3(0.0, 0.0, -40.0)],
	["08_Roadside", Vector3(4.7, 0.65, -9.5), Vector3(1.8, 1.1, 0.0)],
	["09_Reaction", Vector3(1.8, 1.6, -4.4), Vector3(1.8, 1.2, 0.4)],
	["10_Road_Ahead", Vector3(1.2, 1.7, -3.3), Vector3(0.2, 3.0, -100.0)],
]

var _desert: Desert
var _trip: Trip
var _boards: Billboards
var _traffic: Traffic
var _extras: Extras
var _car: Car
var _kit: Dictionary
var _retired: bool = false


func _ready() -> void:
	# the markers first: Room._ready() and RoomHost read them straight away
	_kit = Geo.new_kit()
	_build_set()
	super._ready()
	_desert = Desert.new()
	add_child(_desert)
	var heat: Array[Transform3D] = []
	for z: float in [-70.0, -125.0, -190.0, 70.0, 125.0]:
		heat.append(Transform3D(Basis.IDENTITY, Vector3(0.0, 2.2, z)))
	_desert.setup(self, _kit, Vector3(CAR_AT.x, 0.0, -6.0), heat, Vector2(90.0, 4.4), true)
	_boards = Billboards.new()
	_desert.add_child(_boards)
	_boards.setup(_kit)
	_trip = Trip.new()
	_desert.add_child(_trip)
	_trip.setup(_kit, _boards)
	_traffic = Traffic.new()
	_desert.add_child(_traffic)
	_traffic.setup(_kit, _desert, false, Vector2(-420.0, 320.0))
	_extras = Extras.new()
	_desert.add_child(_extras)
	_extras.setup(_kit, Vector3(70.0, -170.0, 60.0), _desert)
	EventBus.setting_changed.connect(_on_r22_setting_changed)
	# the Scene switch shows where we are
	if String(AppState.get_setting("r22_scene")) != "cruise":
		AppState.set_setting("r22_scene", "cruise")


func _exit_tree() -> void:
	if EventBus.setting_changed.is_connected(_on_r22_setting_changed):
		EventBus.setting_changed.disconnect(_on_r22_setting_changed)


## RoomHost calls this (through propagate_call, so the desert's retire() runs too) when another
## room replaces this one: hands the sky over.
func retire() -> void:
	_retired = true
	_exit_tree()


func _on_r22_setting_changed(key: String, value: Variant) -> void:
	# the Scene switch: off to the Drive-In (only while this room is the one showing)
	if key == "r22_scene" and String(value) == "drivein" and not _retired and String(AppState.get_setting("room_id")) == MY_ID:
		AppState.request_room(OTHER_ID)


func _process(delta: float) -> void:
	super._process(delta)
	if _retired:
		return
	var wind := clampf(float(AppState.get_setting("r22_wind")), 0.0, 1.0)
	_trip.tick(delta, wind, _desert.night)
	_desert.road_noise = clampf(_trip.speed / 22.0, 0.0, 1.2)
	_desert.tick(delta, _trip.travel, _trip.bend, _trip.hill, _trip.speed)
	_traffic.tick(delta, _trip.speed)
	_extras.tick(delta, _trip.speed, wind, _desert.day)
	_car.tick(delta, _trip.speed, _desert.night, _desert.wet, Desert.detail_level() == "full")


## The ground, the road, the car and the markers. The ground and the road never move (their
## pictures slide in their shaders); everything that slides lives under the desert node.
func _build_set() -> void:
	var set_root := Node3D.new()
	set_root.name = "Set"
	add_child(set_root)
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	ground.mesh = Geo.ground_sheet(700.0, -760.0, 520.0)
	var gm := Geo.ground_material(_kit)
	gm.set_shader_parameter("shoulder", Geo.SHOULDER)
	ground.material_override = gm
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ground.extra_cull_margin = 80.0
	set_root.add_child(ground)
	var road := MeshInstance3D.new()
	road.name = "Road"
	road.mesh = Geo.road_strip(3.9, -760.0, 520.0, 2.0)
	road.material_override = Geo.road_material(_kit)
	road.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	road.extra_cull_margin = 80.0
	set_root.add_child(road)
	road.position.y = 0.005
	_car = Car.new()
	set_root.add_child(_car)
	_car.build(_kit)
	_car.position = CAR_AT
	var markers := Node3D.new()
	markers.name = "Markers"
	add_child(markers)
	for c: Array in CAMERAS:
		var cam := Marker3D.new()
		cam.name = "CAM_" + String(c[0])
		markers.add_child(cam)
		cam.transform = Transform3D(Basis.IDENTITY, c[1]).looking_at(c[2], Vector3.UP)
	# the riders face the Windshield camera
	var windshield: Vector3 = CAMERAS[0][1]
	for i in SEATS.size():
		var at := CAR_AT + SEATS[i]
		_marker(markers, "PRESENTER_%d" % (i + 1), at, windshield)
	_marker(markers, "TARGET_Car", CAR_AT + Vector3(0.0, 1.3, 0.0), windshield)
	_marker(markers, "TARGET_Road", Vector3(1.8, 0.3, -22.0), windshield)


## A marker at `at` whose +Z points (level) at `toward`.
static func _marker(parent: Node3D, node_name: String, at: Vector3, toward: Vector3) -> Marker3D:
	var m := Marker3D.new()
	m.name = node_name
	parent.add_child(m)
	var dir := toward - at
	dir.y = 0.0
	if dir.length() < 0.001:
		dir = Vector3.FORWARD
	m.transform = Transform3D(Basis.looking_at(-dir.normalized(), Vector3.UP), at)
	return m


## How far the car has driven (metres; for tests).
func get_travel() -> float:
	return _trip.travel


## The parts, for tests.
func get_trip() -> Trip:
	return _trip


func get_traffic() -> Traffic:
	return _traffic


func get_billboards() -> Billboards:
	return _boards


func get_desert() -> Desert:
	return _desert


## Room tab: the scene switch, the drive, the billboards, the hour, the weather, the roadside.
func get_controls() -> Array[Dictionary]:
	var out: Array[Dictionary] = [{"heading": "Route 22"}]
	out.append(scene_control())
	out.append_array([
		{"key": "r22_speed", "label": "Speed", "min": 0.0, "max": 120.0, "step": 1.0, "format": "%d km/h", "zero": "Parked",
			"tooltip": "How fast the woody drives. 50 km/h is an easy cruise; 0 parks it at the roadside (the desert stands still)."},
		{"key": "r22_curves", "label": "Curves and hills", "min": 0.0, "max": 1.0, "step": 0.01, "format": "%d%%", "scale": 100.0,
			"tooltip": "How much the road winds and rolls away in the distance. 0% = dead straight and flat."},
		{"key": "r22_traffic", "label": "How busy", "min": 0.0, "max": 100.0, "step": 1.0, "format": "%d", "zero": "Empty road",
			"tooltip": "How much other traffic there is: pickups, semis, motorhomes, motorcycles, old sedans and the odd tour bus. 100 = about one every 10 seconds, mostly oncoming, now and then one overtaking. 0 = an empty road."},
		{"key": "r22_scenery", "label": "Landmarks and stops", "min": 0.0, "max": 100.0, "step": 1.0, "format": "%d%%", "zero": "Lonely road",
			"tooltip": "How much of the road has something to look at (rock formations, gas stations, motels, diners and other stops) rather than plain open desert. 100% = a landmark every few seconds, a highlight reel. 50% = every other stretch. 0% = nothing but poles, brush and the far buttes, like a real lonely desert highway."},
		{"heading": "Billboards"},
		{"key": "r22_bb_amount", "label": "How common", "min": 0.0, "max": 100.0, "step": 1.0, "format": "%d", "zero": "None",
			"tooltip": "How often a billboard comes by. 40 = about one every 15 seconds at 50 km/h, 100 = about one every 6 seconds, 0 = none."},
		{"key": "r22_bb_folder", "label": "Picture folder", "type": "text", "placeholder": "empty = the app's billboards folder",
			"tooltip": "A folder of pictures (PNG, JPG, WebP or GIF, animated GIFs play) for the billboards, for example your friends' promo pictures. Empty = the \"billboards\" folder in Stream Rooms' data folder. Changes are read when you change this box (or switch rooms)."},
		{"key": "r22_bb_core", "label": "Stream Core pictures", "type": "text", "placeholder": "stored file names, comma-separated",
			"tooltip": "Names of pictures in Stream Core's Stored files to add to the billboards, separated by commas. Stream Rooms fetches them from Core."},
		{"key": "r22_bb_order", "label": "Order", "type": "option", "options": [["shuffle", "Shuffle"], ["order", "In order"]],
			"tooltip": "Shuffle: every picture once in a random order, then a new round. In order: the folder's pictures by file name, then the Core ones as typed."},
		{"key": "r22_bb_lit", "label": "Lit at night", "type": "check",
			"tooltip": "Lamps light the billboards after dark."},
		{"key": "r22_bb_filler", "label": "Filler ads when the set is empty", "type": "check",
			"tooltip": "With no pictures set, the billboards show made-up roadside ads (a rock shop, a diner, hot jerky...). Off: no billboards until you add pictures."},
		{"key": "r22_bb_classic", "label": "Shape: classic two-post board", "type": "check", "tooltip": "A big board on two steel posts with a catwalk and lamps."},
		{"key": "r22_bb_monopole", "label": "Shape: tall single pole", "type": "check", "tooltip": "A board high up on one thick pole."},
		{"key": "r22_bb_wooden", "label": "Shape: weathered wooden sign", "type": "check", "tooltip": "A low, leaning wooden sign; the picture looks sun-bleached."},
		{"key": "r22_bb_rooftop", "label": "Shape: on an old roadside stop", "type": "check", "tooltip": "A board on a frame on the roof of a little roadside shack."},
		{"key": "r22_bb_neon", "label": "Shape: neon arrow", "type": "check", "tooltip": "A board with a big pink neon arrow pointing at it."},
		{"key": "r22_bb_trailer", "label": "Shape: parked trailer", "type": "check", "tooltip": "An old box trailer parked in the dirt with the picture on its side."},
	])
	out.append_array(desert_controls())
	out.append_array([
		{"heading": "Look"},
		{"key": "r22_detail", "label": "Set detail", "type": "option", "options": [["auto", "Auto (follows Graphics quality)"], ["low", "Low (flat colours)"], ["full", "Detailed"]],
			"tooltip": "How detailed the desert is drawn on this PC. Detailed: photo grain on the rock, ground and road, haze and sunbeams in the air (with the graphics settings that have volumetric fog), and the car's chrome and paint reflecting the desert going by. Low: flat colours, the lightest. Auto: Low on the Low graphics setting, Detailed otherwise. Each PC in a co-stream chooses its own."},
	])
	return out


## The Scene switch, the same in both Route 22 rooms.
static func scene_control() -> Dictionary:
	return {"key": "r22_scene", "label": "Scene", "type": "option", "options": [["drivein", "Drive-in lot (with the audience)"], ["cruise", "Cruise (just chatting, in the car)"]],
		"tooltip": "Route 22 has two scenes in the same desert: the drive-in lot, with the big screen and the chat audience in lawn chairs, convertibles and pickup beds, and the cruise, where co-stream guests ride in the red woody down the endless highway. Switching loads the other one."}


## The hour, the weather and the roadside life: the same controls in both Route 22 rooms.
static func desert_controls() -> Array[Dictionary]:
	return [
		{"heading": "Time of day"},
		{"key": "r22_time", "label": "Time of day", "min": 0.0, "max": 24.0, "step": 0.1, "format": "%.1f h",
			"tooltip": "The hour in the desert, 0 to 24. 6 = sunrise behind you, 12 = noon, 18 = sunset straight down the road ahead (and behind the drive-in screen). Night brings the Milky Way."},
		{"key": "r22_day_minutes", "label": "Day length", "min": 0.0, "max": 120.0, "step": 1.0, "format": "%d min", "zero": "Clock stopped",
			"tooltip": "Lets the clock run: how many minutes a whole day and night takes, starting from the Time of day. 0 = the clock stands still."},
		{"heading": "Weather"},
		{"key": "r22_weather", "label": "Weather", "type": "option",
			"options": [["clear", "Clear"], ["clouddeck", "Cloud deck (glowing sunset ceiling)"], ["dust", "Dust storm"], ["storm", "Thunderstorm"], ["afterrain", "After rain (wet road, rainbow)"]],
			"tooltip": "Clear: open sky. Cloud deck: a ceiling of cloud that lights up orange at sunset. Dust storm: brown air, blowing sand, the sun a pale disc. Thunderstorm: dark cloud, rain and lightning (soft and slow in photosensitive-safe mode). After rain: a wet, shining road with puddles, clearing cloud and a rainbow opposite a low sun. Changes ease in over a few seconds."},
		{"key": "r22_clouds", "label": "Clouds", "min": 0.0, "max": 2.0, "step": 0.01, "format": "%d%%", "scale": 100.0,
			"tooltip": "More or less cloud than the weather normally brings. 0% = none."},
		{"key": "r22_stars", "label": "Stars", "min": 0.0, "max": 2.0, "step": 0.01, "format": "%d%%", "scale": 100.0,
			"tooltip": "How bright the stars and the Milky Way are on clear nights. 0% = none."},
		{"key": "r22_heat", "label": "Heat shimmer", "min": 0.0, "max": 1.0, "step": 0.01, "format": "%d%%", "scale": 100.0,
			"tooltip": "On hot, dry afternoons the air over the road wobbles and the far road shines like water (a mirage). 0% = off."},
		{"key": "r22_wind", "label": "Wind", "min": 0.0, "max": 1.0, "step": 0.01, "format": "%d%%", "scale": 100.0,
			"tooltip": "How hard the wind blows: the brush sways, tumbleweeds roll faster, cloud shadows race, and at the top sand blows across the road."},
		{"heading": "Roadside"},
		{"key": "r22_plants", "label": "Plant life", "min": 0.0, "max": 100.0, "step": 1.0, "format": "%d%%", "zero": "Bare desert",
			"tooltip": "How thick the desert brush grows (creosote, sage, brittlebush, grass, cholla, yucca). 100% = as thick as it gets, 0% = bare sand and rock."},
		{"key": "r22_animals", "label": "Animals", "min": 0.0, "max": 100.0, "step": 1.0, "format": "%d%%", "zero": "None",
			"tooltip": "How often animals show up: the circling vultures, jackrabbits and lizards, and the coyotes (and their howls). 100% = often, 50% = half as often, 0% = none. Each still has its own tick box below."},
		{"key": "r22_tumbleweeds", "label": "Tumbleweeds", "type": "check", "tooltip": "Tumbleweeds bouncing across in the wind."},
		{"key": "r22_dust_devils", "label": "Dust devils", "type": "check", "tooltip": "Little whirlwinds of dust spinning up out in the desert by day."},
		{"key": "r22_birds", "label": "Vultures overhead", "type": "check", "tooltip": "A few vultures circling high up by day. (Ravens perch on the telephone wires either way.)"},
		{"key": "r22_critters", "label": "Jackrabbits and lizards", "type": "check", "tooltip": "Now and then a jackrabbit bounds across or a lizard skitters over the gravel."},
		{"key": "r22_coyotes", "label": "Coyotes", "type": "check", "tooltip": "From dusk to dawn (and once in a while by day) a few coyotes trot across out in the desert. At night you sometimes hear them howl."},
		{"key": "r22_neon", "label": "Neon signs", "type": "check", "tooltip": "The neon on the gas station, motel, diner, the drive-in's marquee and the neon-arrow billboards glows at night."},
	]
