extends Room
## Route 22 Drive-In: a desert drive-in theatre beside Route 22, red sandstone behind the screen.
## The big screen stands at the north end of the lot; the chat audience sits on blankets and lawn
## chairs, in four convertibles and in the beds of four pickups, and at the picnic table; up to
## four presenters stand at podiums on the little stage under the screen. Traffic runs both ways
## on Route 22 past the entrance and the neon marquee.
## The other half of Route 22 is the Cruise (rooms/route22_cruise: the guests ride in a woody down
## the endless road, no screen, no audience); the Room tab's Scene switch jumps between the two.
##
## The parts:
##   r22_drivein_builder.gd  builds the lot, the screen, the seats, the buildings and the rocks
##   r22_desert.gd   hour, sky, weather, sun, fog, rain, sand, shimmer, sound (shared with the Cruise)
##   r22_traffic.gd  vehicles on Route 22 (two-way here, laid along the road's frame)
##   r22_extras.gd   tumbleweeds, dust devils, vultures, a jackrabbit, a lizard
## The house lights are the four lot light poles (LIGHTS_House / LAMP_Lot_n): on at night only,
## dimmed while a film plays (Room._target_level), off with Lot lights. Their bulbs and the lit
## windows glow with them (r22_desert.gd lamp_scale).
## Settings: see get_controls(); defaults in AppState.DEFAULTS ("r22_" keys), the shared ones in
## NetSession.SHARED_BASE.

const Geo := preload("res://rooms/route22/r22_geo.gd")
const Builder := preload("res://rooms/route22/r22_drivein_builder.gd")
const Desert := preload("res://rooms/route22/r22_desert.gd")
const Traffic := preload("res://rooms/route22/r22_traffic.gd")
const Extras := preload("res://rooms/route22/r22_extras.gd")
## The scene switch and the shared desert controls live in the Cruise's script (static functions).
const Cruise := preload("res://rooms/route22_cruise/route22_cruise_room.gd")
## This room's id (rooms/route22/room_info.tres) and the Cruise's: the Scene switch.
const MY_ID := "route22"
const OTHER_ID := "route22_cruise"
## How bright the lot lights are by day (they are mostly for the night).
const LAMPS_BY_DAY: float = 0.1

var _desert: Desert
var _traffic: Traffic
var _extras: Extras
var _kit: Dictionary
var _marquee: Array = []           # Label3D: the marquee's second line, both faces
var _retired: bool = false


func _ready() -> void:
	# the set and its markers first: Room._ready() and RoomHost read them straight away
	_kit = Geo.new_kit()
	var out := Builder.build(self, _kit)
	_marquee = out["marquee_words"]
	super._ready()
	_desert = Desert.new()
	add_child(_desert)
	# heat shimmer: sheets over the lot's far corners and down the road either side
	var heat: Array[Transform3D] = []
	for p: Vector3 in [Vector3(-45.0, 2.2, -30.0), Vector3(45.0, 2.2, -30.0)]:
		heat.append(Transform3D(Basis.IDENTITY, p))
	for x: float in [-70.0, 70.0]:
		heat.append(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(x, 2.2, Builder.ROAD_Z)))
	_desert.setup(self, _kit, Vector3(0.0, 0.0, 4.0), heat, Vector2(60.0, 4.4), true)
	_traffic = Traffic.new()
	(out["traffic_frame"] as Node3D).add_child(_traffic)
	_traffic.setup(_kit, _desert, true, Vector2(-400.0, 400.0))
	_extras = Extras.new()
	_desert.add_child(_extras)
	_extras.setup(_kit, Vector3(90.0, -140.0, 110.0))
	_show_marquee()
	EventBus.setting_changed.connect(_on_r22_setting_changed)
	# the Scene switch shows where we are
	if String(AppState.get_setting("r22_scene")) != "drivein":
		AppState.set_setting("r22_scene", "drivein")


func _exit_tree() -> void:
	if EventBus.setting_changed.is_connected(_on_r22_setting_changed):
		EventBus.setting_changed.disconnect(_on_r22_setting_changed)


## RoomHost calls this (through propagate_call, so the desert's retire() runs too) when another
## room replaces this one: hands the sky over.
func retire() -> void:
	_retired = true
	_exit_tree()


func _on_r22_setting_changed(key: String, value: Variant) -> void:
	match key:
		"r22_scene":
			# off to the Cruise (only while this room is the one showing)
			if String(value) == "cruise" and not _retired and String(AppState.get_setting("room_id")) == MY_ID:
				AppState.request_room(OTHER_ID)
		"r22_marquee":
			_show_marquee()


## The marquee's second line: the Marquee text setting, in capitals (SafeText-cleaned, it can
## come from a co-stream host).
func _show_marquee() -> void:
	var text := SafeText.clean(String(AppState.get_setting("r22_marquee"))).to_upper()
	for l: Label3D in _marquee:
		l.text = text


func _process(delta: float) -> void:
	super._process(delta)
	if _retired:
		return
	var wind := clampf(float(AppState.get_setting("r22_wind")), 0.0, 1.0)
	_desert.lamp_scale = _level
	_desert.road_noise = 0.0
	_desert.tick(delta, 0.0, 0.0, 0.0, 0.0)
	_traffic.tick(delta, 0.0)
	_extras.tick(delta, 0.0, wind, _desert.day)


## The lot lights: off with their tick box, faint by day, and on top of that what every room
## does (the House lights slider, dimming for a film).
func _target_level() -> float:
	if not bool(AppState.get_setting("r22_lot_lights")):
		return 0.0
	var day := _desert.day if _desert else 0.0
	return super._target_level() * lerpf(1.0, LAMPS_BY_DAY, day)


## The parts, for tests.
func get_traffic() -> Traffic:
	return _traffic


func get_desert() -> Desert:
	return _desert


func get_marquee_text() -> String:
	return (_marquee[0] as Label3D).text if not _marquee.is_empty() else ""


## Room tab: the scene switch, the marquee, the lot lights, the road, then the desert's hour,
## weather and roadside controls (shared with the Cruise).
func get_controls() -> Array[Dictionary]:
	var out: Array[Dictionary] = [{"heading": "Route 22"}]
	out.append(Cruise.scene_control())
	out.append_array([
		{"key": "r22_marquee", "label": "Marquee text", "type": "text", "placeholder": "TONIGHT: CHAT'S PICK",
			"tooltip": "The second line on the drive-in's sign by the road, under ROUTE 22 DRIVE-IN. Shown in capitals."},
		{"key": "r22_lot_lights", "label": "Lot lights", "type": "check",
			"tooltip": "The four light poles over the lot. They come on at dusk and dim while a film plays, like the house lights in the other rooms."},
		{"key": "r22_traffic", "label": "How busy", "min": 0.0, "max": 100.0, "step": 1.0, "format": "%d", "zero": "Empty road",
			"tooltip": "How much traffic goes by on Route 22 past the entrance, both ways. 100 = about one every 10 seconds. 0 = an empty road."},
	])
	out.append_array(Cruise.desert_controls())
	out.append_array([
		{"heading": "Look"},
		{"key": "r22_detail", "label": "Set detail", "type": "option", "options": [["auto", "Auto (follows Graphics quality)"], ["low", "Low (flat colours)"], ["full", "Detailed"]],
			"tooltip": "How detailed the desert is drawn on this PC. Detailed: photo grain on the rock, ground and road, and haze and sunbeams in the air (with the graphics settings that have volumetric fog). Low: flat colours, the lightest. Auto: Low on the Low graphics setting, Detailed otherwise. Each PC in a co-stream chooses its own."},
	])
	return out
