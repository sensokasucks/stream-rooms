extends Room
## Route 81 Cruise: the Route 22 Cruise's green sister. The same red woody with up to four
## co-stream guests in it, on an endless Pennsylvania interstate instead of a desert two-lane:
## a divided highway through forest, rock cuts, overlooks over a ridge-and-valley view, and
## tunnels. No big screen and no chat audience. The Room tab's Scenery switch (r22_land) jumps
## between this room and the desert Cruise (rooms/route22_cruise).
##
## Like the desert Cruise, the car and the cameras stand still at the world's origin and the
## land slides back past them. The parts:
##   rooms/route81/r81_land.gd     the land's shapes, trees, materials, the far ridges
##   rooms/route81/r81_pieces.gd   guardrails, tunnels, signs
##   rooms/route81/r81_trip.gd     which land comes where, curves, heading, altitude, tunnels
##   rooms/route81/r81_traffic.gd  the other vehicles on both roads
## and from Route 22 (rooms/route22/), unchanged or with small hooks:
##   r22_desert.gd   hour, sky, weather, sun, fog, rain, sound (green_land = true here)
##   r22_car.gd      the woody
##   r22_geo.gd      the mesh builder and the kit of shared materials
## The riders' seats and the ten cameras are the desert Cruise's (the car is the same), so a
## streamer's habits carry over.
## Settings: see get_controls(). The drive, hour and weather use the desert's "r22_" keys (one
## Speed slider for both sceneries); what only this room has is "r81_". Defaults in
## AppState.DEFAULTS, the shared ones in NetSession.SHARED_BASE.

const Geo := preload("res://rooms/route22/r22_geo.gd")
const Desert := preload("res://rooms/route22/r22_desert.gd")
const Car := preload("res://rooms/route22/r22_car.gd")
const Land := preload("res://rooms/route81/r81_land.gd")
const Trip := preload("res://rooms/route81/r81_trip.gd")
## (the desert Cruise's trip, for the Speed control both Cruises share)
const DesertTrip := preload("res://rooms/route22/r22_trip.gd")
const Vistas := preload("res://rooms/route81/r81_vistas.gd")
const Billboards := preload("res://rooms/route22/r22_billboards.gd")
const Bobbles := preload("res://rooms/route22/r22_bobbles.gd")
const Traffic := preload("res://rooms/route81/r81_traffic.gd")
const DesertCruise := preload("res://rooms/route22_cruise/route22_cruise_room.gd")
## This room's id (rooms/route81/room_info.tres) and the desert Cruise's: the Scenery switch.
const MY_ID := "route81"
const DESERT_ID := "route22_cruise"
## The woody's place: its middle, in the right-hand lane (the dashed line is X = 0).
const CAR_AT := Vector3(1.8, 0.0, 0.0)
## How far the cameras must see while this room shows: the far ridges stand up to 12 km away and
## are long (r81_land.gd RIDGES). The camera's own reach is put back when the room leaves.
const CAMERA_FAR: float = 30000.0

var _desert: Desert
var _trip: Trip
var _traffic: Traffic
var _car: Car
var _kit: Dictionary
var _backdrop: Node3D
var _vistas: Vistas
var _boards: Billboards            # Route 81's own billboard set (r22_billboards.gd, "r81_bb_" settings)
var _bobbles: Bobbles             # the presenters' dashboard bobbleheads (r22_bobbles.gd)
var _retired: bool = false
var _camera: Camera3D            # the camera whose reach we raised
var _camera_far: float = 0.0     # its reach before


func _ready() -> void:
	# the markers first: Room._ready() and RoomHost read them straight away
	_kit = Geo.new_kit()
	Land.add_materials(_kit)
	_build_set()
	super._ready()
	_desert = Desert.new()
	# green country: cooler and more sky light than the desert's, no dust, and thinner fog (the
	# view is the point here: the valley and the ridges must show through it)
	_desert.green_land = true
	_desert.fog_scale = 0.35
	_desert.day_ambient = Color(0.62, 0.68, 0.74)
	_desert.day_ambient_energy = 0.85
	add_child(_desert)
	var heat: Array[Transform3D] = []
	for z: float in [-70.0, -125.0, -190.0, 70.0, 125.0]:
		heat.append(Transform3D(Basis.IDENTITY, Vector3(0.0, 2.2, z)))
	_desert.setup(self, _kit, Vector3(CAR_AT.x, 0.0, -6.0), heat, Vector2(90.0, 4.4), true)
	_trip = Trip.new()
	_desert.add_child(_trip)
	# Route 81's own billboards: the desert Cruise's script with other settings ("r81_bb_"),
	# other folders and shapes, so the two roads keep separate picture sets
	_boards = Billboards.new()
	_desert.add_child(_boards)
	_boards.setup(_kit, {"prefix": "r81_bb_", "folder": "user://billboards_route81", "core_folder": "user://billboards_route81_core",
		"shapes": Billboards.SHAPES_81, "ads": PackedStringArray(["ad_diner", "ad_motel", "ad_candy", "ad_jerky", "ad_services"])})
	_trip.setup(_kit, _backdrop, _vistas, _boards)
	_traffic = Traffic.new()
	_desert.add_child(_traffic)
	_traffic.setup(_kit, _desert, false, Vector2(-520.0, 320.0))
	EventBus.setting_changed.connect(_on_route_setting_changed)
	# the Scenery switch shows where we are
	if String(AppState.get_setting("r22_land")) != "route81":
		AppState.set_setting("r22_land", "route81")


func _exit_tree() -> void:
	if EventBus.setting_changed.is_connected(_on_route_setting_changed):
		EventBus.setting_changed.disconnect(_on_route_setting_changed)
	_restore_camera()


## RoomHost calls this (through propagate_call, so the desert's retire() runs too) when another
## room replaces this one: hands the sky and the camera back.
func retire() -> void:
	_retired = true
	_exit_tree()


func _on_route_setting_changed(key: String, value: Variant) -> void:
	# the Scenery switch: off to the desert (only while this room is the one showing)
	if key == "r22_land" and String(value) == "desert" and not _retired and String(AppState.get_setting("room_id")) == MY_ID:
		AppState.request_room(DESERT_ID)


func _process(delta: float) -> void:
	super._process(delta)
	if _retired:
		return
	_reach_far()
	_trip.tick(delta, _desert.night)
	_desert.heading = _trip.heading
	_trip.mist = _desert.mist
	_drift_weather(delta)
	_desert.cover = _trip.cover
	_desert.road_noise = clampf(_trip.speed / 22.0, 0.0, 1.2)
	_desert.tick(delta, _trip.travel, _trip.bend, _trip.hill, _trip.speed)
	_traffic.tick(delta, _trip.speed)
	# headlights on in the tunnels as well as at night
	_car.tick(delta, _trip.speed, maxf(_desert.night, _trip.cover), _desert.wet, Desert.detail_level() == "full")
	_bobbles.tick(delta, _trip.speed, _trip.bend, _trip.hill)


## Lets the camera in use see as far as the far ridges (once per camera; put back by
## _restore_camera when the room leaves).
func _reach_far() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or cam == _camera:
		return
	_restore_camera()
	_camera = cam
	_camera_far = cam.far
	cam.far = maxf(cam.far, CAMERA_FAR)


func _restore_camera() -> void:
	if _camera and is_instance_valid(_camera) and _camera_far > 0.0:
		_camera.far = _camera_far
	_camera = null
	_camera_far = 0.0


## The two roads, the far view, the car and the markers. The roads never move (their pictures
## slide in their shader); everything that slides lives under the desert node.
func _build_set() -> void:
	var set_root := Node3D.new()
	set_root.name = "Set"
	add_child(set_root)
	# our road, and the other direction's: the same strip turned round, across the median
	var z_far := -(Trip.AHEAD + 60.0)
	var z_near := Trip.BEHIND + 60.0
	for ours: bool in [true, false]:
		var road := MeshInstance3D.new()
		road.name = "Road" if ours else "RoadOpposite"
		road.mesh = Land.road_strip(Land.ROAD_L, Land.ROAD_R, z_near if ours else -z_near, z_far if ours else -z_far, 2.0)
		road.material_override = _kit["road81" if ours else "road81_opp"]
		road.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		road.extra_cull_margin = 700.0
		set_root.add_child(road)
		road.position = Vector3(0.0 if ours else Land.OPP_C, 0.005, 0.0)
		if not ours:
			road.rotation = Vector3(0.0, PI, 0.0)
	_backdrop = Land.build_backdrop(_kit)
	set_root.add_child(_backdrop)
	# the distant views stand on the far view and turn with it; r81_trip.gd picks them
	_vistas = Vistas.new()
	_vistas.setup(_kit)
	_backdrop.add_child(_vistas)
	_car = Car.new()
	set_root.add_child(_car)
	_car.plate_text = "ROUTE 81"
	_car.dusty = false
	_car.build(_kit)
	_car.position = CAR_AT
	# the presenters' bobbleheads on the dash (they ride in the car's space)
	_bobbles = Bobbles.new()
	_car.add_child(_bobbles)
	_bobbles.setup(self, presenter_size)
	var markers := Node3D.new()
	markers.name = "Markers"
	add_child(markers)
	for c: Array in DesertCruise.CAMERAS:
		var cam := Marker3D.new()
		cam.name = "CAM_" + String(c[0])
		markers.add_child(cam)
		cam.transform = Transform3D(Basis.IDENTITY, c[1]).looking_at(c[2], Vector3.UP)
	# the riders face the Windshield camera
	var windshield: Vector3 = DesertCruise.CAMERAS[0][1]
	for i in DesertCruise.SEATS.size():
		DesertCruise._marker(markers, "PRESENTER_%d" % (i + 1), CAR_AT + DesertCruise.SEATS[i], windshield)
	DesertCruise._marker(markers, "TARGET_Car", CAR_AT + Vector3(0.0, 1.3, 0.0), windshield)
	DesertCruise._marker(markers, "TARGET_Road", Vector3(1.8, 0.3, -22.0), windshield)


## How far the car has driven (metres; for tests).
func get_travel() -> float:
	return _trip.travel


## The room's materials by name (r22_geo.gd new_kit plus r81_land.gd add_materials), for tests.
## What the weather can turn into from each weather: [next weather, its share of the chances].
const DRIFT: Dictionary = {
	"clear": [["clouddeck", 0.6], ["fog", 0.2], ["drizzle", 0.2]],
	"clouddeck": [["clear", 0.45], ["drizzle", 0.3], ["storm", 0.15], ["fog", 0.1]],
	"fog": [["clear", 0.6], ["clouddeck", 0.4]],
	"drizzle": [["clouddeck", 0.4], ["afterrain", 0.35], ["storm", 0.25]],
	"storm": [["afterrain", 0.8], ["drizzle", 0.2]],
	"afterrain": [["clear", 0.7], ["clouddeck", 0.3]],
}
## Seconds a weather lasts before it drifts on (a random time between the two).
const DRIFT_EVERY := Vector2(240.0, 540.0)
var _drift_in: float = 300.0


## "Weather changes by itself" (r81_drift): every few minutes the Weather setting moves on to
## one of the weathers that follow the current one (DRIFT). Not on a co-stream guest: the
## setting is shared, so the host's drift reaches everyone.
func _drift_weather(delta: float) -> void:
	if not bool(AppState.get_setting("r81_drift")) or NetSession.get_role() == "guest":
		return
	_drift_in -= delta
	if _drift_in > 0.0:
		return
	_drift_in = randf_range(DRIFT_EVERY.x, DRIFT_EVERY.y)
	AppState.set_setting("r22_weather", next_weather(String(AppState.get_setting("r22_weather")), randf()))


## The weather that follows `now` for a roll 0..1 (see DRIFT; the desert's dust counts as clear).
static func next_weather(now: String, roll: float) -> String:
	var options: Array = DRIFT.get(now, DRIFT["clear"])
	for o: Array in options:
		roll -= float(o[1])
		if roll < 0.0:
			return String(o[0])
	return String(options[0][0])


## Route 81's billboards (for tests).
func get_billboards() -> Billboards:
	return _boards


func get_kit() -> Dictionary:
	return _kit


## The parts, for tests.
func get_trip() -> Trip:
	return _trip


func get_traffic() -> Traffic:
	return _traffic


func get_desert() -> Desert:
	return _desert


## Room tab: the scenery switch, the drive, the road's make-up, the hour, the weather, the look.
func get_controls() -> Array[Dictionary]:
	var out: Array[Dictionary] = [{"heading": "Route 81"}]
	out.append(DesertCruise.land_control())
	out.append_array([
		DesertTrip.speed_control("How fast the woody drives, in miles an hour. 30 mph is an easy cruise (slow for an interstate, but it gives the view time); 0 parks it on the shoulder. The same slider as the desert Cruise's."),
		{"key": "r22_curves", "label": "Curves", "min": 0.0, "max": 1.0, "step": 0.01, "format": "%d%%", "scale": 100.0,
			"tooltip": "How much the highway bends left and right. Here the curves also swing the far ridges and the sun round, like a real change of direction. 0% = dead straight."},
		{"key": "r22_hills", "label": "Hills", "min": 0.0, "max": 1.0, "step": 0.01, "format": "%d%%", "scale": 100.0,
			"tooltip": "How much the highway rises and dips ahead of the car. 0% = flat. (How high above the valley the road runs is the Country's own.)"},
		{"key": "r22_traffic", "label": "How busy", "min": 0.0, "max": 100.0, "step": 1.0, "format": "%d", "zero": "Empty road",
			"tooltip": "How much other traffic there is, a lot of it trucks: on the other road across the median, and now and then one passing you in the left lane. 100 = about one every 6 seconds. 0 = an empty road."},
		{"heading": "The road"},
		{"key": "r81_tunnels", "label": "Tunnels", "type": "option", "options": [["short", "Often (about every 4 km)"], ["medium", "Now and then (about every 7 km)"], ["long", "Seldom (about every 13 km)"], ["never", "Never"]],
			"tooltip": "How often the highway goes through a mountain. Each tunnel is 400 m long, and the country on its far side is different: another height, another stretch of the ridges."},
		{"key": "r81_country", "label": "Country", "type": "option", "options": [["tour", "The tour (changes after every tunnel)"], ["ridge", "Ridge and gaps"], ["farm", "Farm valley"], ["river", "River crossing"], ["endless", "Endless Mountains"], ["coal", "Coal plateau"], ["city", "City valley"]],
			"tooltip": "What kind of country the highway runs through. The tour: each kind in turn, a new one on the far side of every tunnel. Ridge and gaps: woods, rock cuts and overlooks. Farm valley: crop fields, farms, small towns and gas stations. River crossing: a long bridge over a wide river. Endless Mountains: the highest road, with the widest views. Coal plateau: patch towns, some abandoned, one over a mine fire with smoke coming out of the ground, a coal breaker and black culm banks. City valley: an old industrial city of brick mills, smokestacks and row houses along the road."},
		{"key": "r81_views", "label": "How often views open up", "min": 0.0, "max": 1.0, "step": 0.01, "format": "%d%%", "scale": 100.0, "zero": "Never",
			"tooltip": "How much of the road has an overlook on one side (a guardrail and the ground falling away to the valley) rather than woods or a rock cut. 100% = about half of every side; 0% = woods and rock all the way."},
		{"key": "r81_forest", "label": "Forest density", "min": 0.0, "max": 100.0, "step": 1.0, "format": "%d%%", "zero": "No trees",
			"tooltip": "How many of the trees near the road are drawn on this PC. 100% = all of them. Lower it if the room runs slowly; the far forest is painted and stays. Each PC in a co-stream chooses its own."},
		{"key": "r81_season", "label": "Season", "type": "option", "options": [["summer", "Summer (green)"], ["fall", "Fall colours"]],
			"tooltip": "Summer: every shade of green. Fall: the hardwoods turn gold, orange and red; the pines stay green."},
		{"key": "r81_lights", "label": "Streetlights", "type": "option", "options": [["sodium", "Sodium (orange)"], ["led", "LED (white)"], ["mixed", "Mixed"], ["off", "Off"]],
			"tooltip": "The lamps on the tall poles in the median before and after every tunnel, and the lamps inside the tunnels. Sodium: the old orange glow. LED: cool white. Mixed: every other pole has been replaced with LED. Off: the poles stand dark (the tunnels stay lit)."},
		{"heading": "Billboards"},
		{"key": "r81_bb_amount", "label": "How common", "min": 0.0, "max": 100.0, "step": 1.0, "format": "%d", "zero": "None",
			"tooltip": "How often a billboard comes by on Route 81. They stand in fields, at the edge of towns and, on tall poles, in front of the woods; never at an overlook, a rock cut, the bridge or a tunnel, so in the mountains they are rarer than this says. 0 = none."},
		{"key": "r81_bb_folder", "label": "Picture folder", "type": "text", "placeholder": "empty = the app's billboards_route81 folder",
			"tooltip": "A folder of pictures (PNG, JPG, WebP or GIF, animated GIFs play) for Route 81's billboards. This is a separate set from the desert Cruise's. Empty = the \"billboards_route81\" folder in Stream Rooms' data folder. Changes are read when you change this box (or switch rooms)."},
		{"key": "r81_bb_core", "label": "Stream Core pictures", "type": "text", "placeholder": "stored file names, comma-separated",
			"tooltip": "Names of pictures in Stream Core's Stored files to add to Route 81's billboards, separated by commas. Stream Rooms fetches them from Core. Easier in Core's dashboard: Setup > Stream Rooms settings > Route 81 billboards > Choose pictures picks and uploads them."},
		{"key": "r81_bb_order", "label": "Order", "type": "option", "options": [["shuffle", "Shuffle"], ["order", "In order"]],
			"tooltip": "Shuffle: every picture once in a random order, then a new round. In order: the folder's pictures by file name, then the Core ones as typed."},
		{"key": "r81_bb_lit", "label": "Lit at night", "type": "check",
			"tooltip": "Lamps light the billboards after dark (the barn and the wooden sign have none)."},
		{"key": "r81_bb_filler", "label": "Filler ads when the set is empty", "type": "check",
			"tooltip": "With no pictures set, the billboards show made-up roadside ads (a diner, a motel, candy...). Off: no billboards until you add pictures."},
		{"key": "r81_bb_classic", "label": "Shape: classic two-post board", "type": "check", "tooltip": "A big board on two steel posts with a catwalk and lamps."},
		{"key": "r81_bb_monopole", "label": "Shape: tall single pole", "type": "check", "tooltip": "A board high up on one thick pole, the kind that stands in front of the woods."},
		{"key": "r81_bb_wooden", "label": "Shape: weathered wooden sign", "type": "check", "tooltip": "A low, leaning wooden sign in a field; the picture looks sun-bleached."},
		{"key": "r81_bb_trailer", "label": "Shape: parked trailer", "type": "check", "tooltip": "An old box trailer parked in a field with the picture on its side."},
		{"key": "r81_bb_barn", "label": "Shape: painted barn", "type": "check", "tooltip": "A red barn in a field with the picture painted on its end wall, a little weathered."},
		{"heading": "Time of day"},
		{"key": "r22_time", "label": "Time of day", "min": 0.0, "max": 24.0, "step": 0.1, "format": "%.1f h",
			"tooltip": "The hour, 0 to 24. 6 = sunrise, 12 = noon, 18 = sunset. Where the sun stands along the road changes as the highway curves."},
		{"key": "r22_day_minutes", "label": "Day length", "min": 0.0, "max": 120.0, "step": 1.0, "format": "%d min", "zero": "Clock stopped",
			"tooltip": "Lets the clock run: how many minutes a whole day and night takes, starting from the Time of day. 0 = the clock stands still."},
		{"heading": "Weather"},
		{"key": "r22_weather", "label": "Weather", "type": "option",
			"options": [["clear", "Clear"], ["clouddeck", "Cloud deck"], ["fog", "Valley fog"], ["drizzle", "Drizzle"], ["storm", "Thunderstorm"], ["afterrain", "After rain (wet road, rainbow)"]],
			"tooltip": "Clear: open sky. Cloud deck: a ceiling of cloud that lights up at sunset. Valley fog: fog lies in the valleys and hangs over the road; on the Detailed look the sun and the lamps throw beams in it. Drizzle: a grey sky and a steady light rain, no thunder. Thunderstorm: dark cloud, rain and lightning (soft and slow in photosensitive-safe mode). After rain: a wet, shining road, clearing cloud and a rainbow opposite a low sun. Changes ease in over a few seconds. (The desert's dust storm counts as Clear here; in the desert, fog shows as a cloud deck and drizzle as After rain.)"},
		{"key": "r81_drift", "label": "Weather changes by itself", "type": "check",
			"tooltip": "Off: the weather stays what you picked. On: every few minutes it moves on by itself, the way weather does (clear, cloud, a foggy spell, drizzle, now and then a thunderstorm and the wet road after it). In a co-stream the host's weather is everyone's. For the hour to move too, set Day length."},
		{"key": "r22_clouds", "label": "Clouds", "min": 0.0, "max": 2.0, "step": 0.01, "format": "%d%%", "scale": 100.0,
			"tooltip": "More or less cloud than the weather normally brings. 0% = none."},
		{"key": "r22_stars", "label": "Stars", "min": 0.0, "max": 2.0, "step": 0.01, "format": "%d%%", "scale": 100.0,
			"tooltip": "How bright the stars and the Milky Way are on clear nights. 0% = none."},
		{"key": "r22_heat", "label": "Heat shimmer", "min": 0.0, "max": 1.0, "step": 0.01, "format": "%d%%", "scale": 100.0,
			"tooltip": "On hot, dry afternoons the air over the asphalt wobbles. 0% = off."},
		{"key": "r22_wind", "label": "Wind", "min": 0.0, "max": 1.0, "step": 0.01, "format": "%d%%", "scale": 100.0,
			"tooltip": "How hard the wind blows: the trees sway and cloud shadows race over the hills."},
	])
	out.append_array(Bobbles.controls())
	out.append_array([
		{"heading": "Look"},
		{"key": "r22_detail", "label": "Set detail", "type": "option", "options": [["auto", "Auto (follows Graphics quality)"], ["low", "Low (flat colours)"], ["full", "Detailed"]],
			"tooltip": "How detailed the set is drawn on this PC. Detailed: photo textures on the rock, the ground and the road, modelled cars and trucks, trees drawn further out, haze and sunbeams in the air, and the car's chrome and paint reflecting what goes by. Low: flat colours and fewer trees, the lightest. Auto: Low on the Low graphics setting, Detailed otherwise. Each PC in a co-stream chooses its own."},
	])
	return out
