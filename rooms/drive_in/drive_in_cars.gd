extends Node3D
## The Drive-In's chat audience, parked: every chatter sits behind the wheel of their own car.
## Made by drive_in_room.gd (_ready, before the room's seats are read), which also hands it the
## lot's car materials (DriveInRoom._car_material).
##
## How it fits the audience code:
##   - The lot has parking spaces along the gravel ramps (spots(): arcs round the screen's foot,
##     front row first, the middle of each row first; Room tab > Parking spaces, setting
##     "drive_spaces", shared in a co-stream). Each space gets an AUDIENCE_Car_nnn marker on the
##     driver's seat, so AudienceView puts the chatter's silhouette, picture, name tag and speech
##     bubbles there like on any room's seat.
##   - A car stands in a space only while its seat's silhouette shows (a chatter, or a filler
##     person with "Filler people in empty main seats"; AudienceView.is_seat_showing). The room
##     sets show_empty_seats false, so empty spaces stay empty. _refresh() runs after every
##     seat change (EventBus audience_seated / audience_left / audience_updated) and after the
##     audience settings that change what shows.
##   - Which car: a Route 22 Blender model (rooms/route22/models/vehicles.glb: the hardtop
##     "classic" or the "convertible"; both have modelled cabins and the hardtop real window
##     openings, made by make_vehicles.py) and a 1950s paint, both picked from the chatter's
##     name, so a chatter always comes back in the same car. Filler people get one from their
##     space's number. Both models share one body, so the driver's seat (the model's Seat_1
##     marker) is in the same place in either; the car is placed so that marker lands on the
##     space's seat. Its glass is see-through (CAR_LOOKS "glass" in drive_in_room.gd).
##   - When a chatter talks (EventBus.audience_spoke) their car blinks its headlights: two
##     blinks, or one slow glow in photosensitive-safe mode; scaled by Flash strength.

const VEHICLES := "res://rooms/route22/models/vehicles.glb"
## The middle of the screen's foot (x, z metres): the parking rows curve round it and the cars
## face it (the model's own 16 cars all point here).
const FOCUS := Vector2(0.0, -60.0)
## The gravel ramps are arcs round FOCUS at these distances (metres), one row of cars on each.
const ROW_RADII: Array[float] = [26.5, 38.5, 50.5, 62.5, 74.5]
## Gap between neighbouring cars along a row (metres, along the arc).
const SPACING: float = 4.1
## How far a row reaches to either side (degrees from straight at the screen).
const MAX_ANGLE: float = 58.0
## The lot's edge (the asphalt is 50 m to either side and runs to z = 35).
const LOT_HALF_WIDTH: float = 47.0
const LOT_BACK: float = 30.0
## No cars here (x min, z min, size): the snack bar.
const KEEP_OUT: Rect2 = Rect2(-13.0, 18.0, 26.0, 14.0)
## The streamer's backed-in pickup (x, z) and how much room it keeps clear round it (metres).
const PICKUP_SPOT := Vector2(5.0, 4.9)
const PICKUP_CLEAR: float = 4.5
## The most spaces the lot holds with the rows above (Room tab > Parking spaces stops here).
const MAX_SPACES: int = 106
## The two models a chatter can come in (vehicles.glb object names; they share one body).
const KINDS: PackedStringArray = ["classic", "convertible", "classic"]
## 1950s paints (the lot's own Paint_* colours first) and roof colours for the hardtops.
const PAINTS: Array[Color] = [Color(0.45, 0.78, 0.65), Color(0.72, 0.08, 0.1), Color(0.93, 0.88, 0.74),
	Color(0.45, 0.68, 0.9), Color(0.93, 0.55, 0.7), Color(0.07, 0.07, 0.08), Color(0.2, 0.72, 0.72),
	Color(0.95, 0.78, 0.25), Color(0.36, 0.5, 0.36), Color(0.55, 0.15, 0.35), Color(0.85, 0.42, 0.15)]
const ROOFS: Array[Color] = [Color(0.92, 0.88, 0.78), Color(0.95, 0.95, 0.93), Color(0.07, 0.07, 0.08)]
## How big the people sit (the seat marker's scale, which AudienceView sizes the silhouette,
## the name tag and the bubbles by): a bust of AudienceView's usual size would put the head
## through the hardtop's roof (the seat is 0.66 m up, the roof 1.43 m; at this scale the head's
## top is about 1.35 m, just under the roof inside).
const SEAT_SCALE: float = 0.72
## Headlight blink: seconds a blink is on, and the light it throws (energy at Flash strength 1).
const BLINK_ON: float = 0.18
const BLINK_LIGHT: float = 2.5

## Gets a car material: Callable(look: String, paint: Color, roof: Color) -> Material
## (DriveInRoom._car_material, so the chatters' cars match the lot's other cars).
var car_material: Callable
## How much the lot's cars tilt nose-up on the ramps (radians; from the model's own cars).
var ramp_pitch: float = 0.0

var _models: Dictionary = {}      # kind -> {"mesh", "seat": Vector3 Seat_1, "front", "tail", "box"}
var _spaces: Array[Dictionary] = []   # {"seat": Vector3, "dir": Vector3, "car": MeshInstance3D, "who": String, "slot": int}
var _slot_space: Dictionary = {}  # audience slot -> index in _spaces (worked out once the audience exists)
var _lamp_on: StandardMaterial3D  # the headlights' lit look while blinking
var _queued: bool = false


## Reads the car models and lays out `count` spaces, each with its AUDIENCE marker. Called by
## the room in _ready(), before RoomHost reads the room's seats.
func build(count: int) -> void:
	_read_models()
	if not _models.has("classic"):
		push_warning("Drive-In: no car models in %s, no parked chatters" % VEHICLES)
		return
	var seat_ref: Dictionary = _models["classic"]
	for p in spots(count):
		var dir := Vector3(FOCUS.x - p.x, 0.0, FOCUS.y - p.z).normalized()
		var xf := _place(seat_ref, p, dir)
		var seat: Vector3 = xf * (seat_ref["seat"] as Vector3)
		var marker := Marker3D.new()
		marker.name = "AUDIENCE_Car_%03d" % _spaces.size()
		add_child(marker)
		marker.position = seat
		marker.scale = Vector3.ONE * SEAT_SCALE
		_spaces.append({"seat": seat, "dir": dir, "car": null, "who": "", "slot": -1})
	_lamp_on = StandardMaterial3D.new()
	_lamp_on.albedo_color = Color(1.0, 0.97, 0.88)
	_lamp_on.emission_enabled = true
	_lamp_on.emission = Color(1.0, 0.95, 0.82)
	_lamp_on.emission_energy_multiplier = 6.0
	EventBus.audience_seated.connect(_on_seat_changed)
	EventBus.audience_left.connect(_on_seat_changed)
	EventBus.audience_updated.connect(_on_seat_changed)
	EventBus.audience_spoke.connect(_on_spoke)
	EventBus.setting_changed.connect(_on_setting_changed)
	_queue_refresh()


func _exit_tree() -> void:
	for pair: Array in [[EventBus.audience_seated, _on_seat_changed], [EventBus.audience_left, _on_seat_changed],
			[EventBus.audience_updated, _on_seat_changed], [EventBus.audience_spoke, _on_spoke],
			[EventBus.setting_changed, _on_setting_changed]]:
		if (pair[0] as Signal).is_connected(pair[1]):
			(pair[0] as Signal).disconnect(pair[1])


## The parking spaces (points on the ground, metres, the room's own space), front row first and
## the middle of each row first, at most `count`. Rows are ROW_RADII arcs round FOCUS; spaces
## are SPACING apart along them, and none on the snack bar, round the streamer's pickup or off
## the lot.
static func spots(count: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for r: float in ROW_RADII:
		var step := rad_to_deg(SPACING / r)
		var a := step * 0.5
		while a < MAX_ANGLE:
			for ang: float in [a, -a]:
				var p := Vector3(FOCUS.x + sin(deg_to_rad(ang)) * r, 0.0, FOCUS.y + cos(deg_to_rad(ang)) * r)
				var flat := Vector2(p.x, p.z)
				if absf(p.x) > LOT_HALF_WIDTH or p.z > LOT_BACK or KEEP_OUT.has_point(flat) or flat.distance_to(PICKUP_SPOT) < PICKUP_CLEAR:
					continue
				out.append(p)
				if out.size() >= count:
					return out
			a += step
	return out


## How many spaces there are (for the tests and the Room tab).
func get_space_count() -> int:
	return _spaces.size()


## The cars standing now (for the tests): [{"seat", "kind", "who"}].
func get_parked() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for sp in _spaces:
		var car := sp["car"] as MeshInstance3D
		if car and car.visible:
			out.append({"seat": sp["seat"], "kind": String(car.get_meta("kind", "")), "who": sp["who"]})
	return out


# ── models ──
## The classic and the convertible from vehicles.glb, with their marker nodes: Seat_1 (the
## driver's seat), LampFront_n / LampTail_n (which way the model points).
func _read_models() -> void:
	if not ResourceLoader.exists(VEHICLES):
		return
	var root := (load(VEHICLES) as PackedScene).instantiate()
	for kind: String in ["classic", "convertible"]:
		var mi := root.find_child(kind, true, false) as MeshInstance3D
		if mi == null:
			continue
		var marks := {"LampFront": [], "LampTail": [], "Seat": []}
		for c in mi.get_children():
			for group: String in marks.keys():
				if String(c.name).contains("_%s_" % group):
					(marks[group] as Array).append(c)
		if (marks["Seat"] as Array).is_empty() or (marks["LampFront"] as Array).is_empty():
			continue
		(marks["Seat"] as Array).sort_custom(func(a: Node, b: Node) -> bool: return String(a.name) < String(b.name))
		_models[kind] = {"mesh": mi.mesh, "seat": (marks["Seat"][0] as Node3D).position,
			"front": _middle(marks["LampFront"]), "tail": _middle(marks["LampTail"]), "box": mi.get_aabb()}
	root.free()


static func _middle(nodes: Array) -> Vector3:
	var sum := Vector3.ZERO
	for n: Node3D in nodes:
		sum += n.position
	return sum / maxf(nodes.size(), 1)


## Where a model stands (room space) when parked at ground point p facing dir: nose up the
## ramp by ramp_pitch (the lamps line up with that slope; the models face -Z), the middle of
## its lamps over p, its lowest corner on the ground.
func _place(model: Dictionary, p: Vector3, dir: Vector3) -> Transform3D:
	var slope := Vector3(dir.x * cos(ramp_pitch), sin(ramp_pitch), dir.z * cos(ramp_pitch))
	var own := Basis.looking_at(((model["front"] as Vector3) - (model["tail"] as Vector3)).normalized())
	var facing := Basis.looking_at(slope) * own.inverse()
	var mid := ((model["front"] as Vector3) + (model["tail"] as Vector3)) * 0.5
	var xf := Transform3D(facing, p - facing * Vector3(mid.x, 0.0, mid.z))
	var low := INF
	for k in 8:
		low = minf(low, (xf * (model["box"] as AABB).get_endpoint(k)).y)
	xf.origin.y -= low
	return xf


# ── who parks where ──
func _on_seat_changed(_slot: int) -> void:
	_queue_refresh()


## The audience settings that change which seats show (Audience tab).
func _on_setting_changed(key: String, _value: Variant) -> void:
	if key in ["audience_enabled", "audience_fill_main", "audience_crowd_fill", "audience_show_empty"]:
		_queue_refresh()


## Many seat changes come at once (a busy chat, a room load): look once at the end of the frame.
func _queue_refresh() -> void:
	if not _queued:
		_queued = true
		_refresh.call_deferred()


## Parks a car in every space whose seat shows someone and takes away the others. A space keeps
## its car while the same person sits there; a newcomer gets their own.
func _refresh() -> void:
	_queued = false
	var view := get_parent().get_node_or_null("Audience") as AudienceView
	if view == null or _models.is_empty():
		return
	if _slot_space.is_empty():
		_map_slots(view)
	for slot: int in _slot_space.keys():
		var sp: Dictionary = _spaces[int(_slot_space[slot])]
		sp["slot"] = slot
		var shown := view.is_seat_showing(slot)
		var who := ""
		if shown:
			var m := AudienceManager.get_seat_member(slot)
			who = String(m.get("name", "")) if not m.is_empty() else "filler %d" % slot
		var car := sp["car"] as MeshInstance3D
		if not shown:
			if car:
				car.visible = false
			sp["who"] = ""
			continue
		if car and car.visible and String(sp["who"]) == who:
			continue
		sp["who"] = who
		_park(sp, who)


## Which audience slot sits in which space: AudienceView numbers the room's seats in the order
## Room.get_audience_seats() gave them (some may have been dropped near a camera), so match
## each main seat to the space under its head.
func _map_slots(view: AudienceView) -> void:
	for slot in view.get_seat_count():
		var head := view.get_seat_head(slot)
		for i in _spaces.size():
			var seat: Vector3 = to_global(_spaces[i]["seat"])
			if Vector2(head.x - seat.x, head.z - seat.z).length() < 0.05 and head.y > seat.y:
				_slot_space[slot] = i
				break


## Puts `who`'s car in the space (the same model and paint every time for the same name).
func _park(sp: Dictionary, who: String) -> void:
	var h := absi(hash(who))
	var kind := KINDS[h % KINDS.size()]
	if not _models.has(kind):
		kind = "classic"
	var model: Dictionary = _models[kind]
	@warning_ignore("integer_division")
	var paint := PAINTS[(h / 7) % PAINTS.size()]
	@warning_ignore("integer_division")
	var roof := ROOFS[(h / 89) % ROOFS.size()]
	var car := sp["car"] as MeshInstance3D
	if car == null:
		car = MeshInstance3D.new()
		car.name = "Car%03d" % _spaces.find(sp)
		add_child(car)
		sp["car"] = car
	car.mesh = model["mesh"]
	car.set_meta("kind", kind)
	# the seat stays where it is: the car is placed round it (the same seat in either model)
	var dir: Vector3 = sp["dir"]
	var xf := _place(model, Vector3.ZERO, dir)
	xf.origin += (sp["seat"] as Vector3) - xf * (model["seat"] as Vector3)
	car.transform = xf
	for s in car.mesh.get_surface_count():
		var from := car.mesh.surface_get_material(s)
		var look := from.resource_name if from else ""
		car.set_surface_override_material(s, car_material.call(look, paint, roof) if car_material.is_valid() else null)
	car.visible = true


# ── headlights ──
## A chatter's message: their car blinks its headlights.
func _on_spoke(slot: int, _parts: Array) -> void:
	if not _slot_space.has(slot):
		return
	var car := _spaces[int(_slot_space[slot])]["car"] as MeshInstance3D
	if car == null or not car.visible:
		return
	_blink(car)


## Two quick blinks (one slow glow in photosensitive-safe mode): the headlight surfaces light
## up and a small lamp throws light ahead of the car, scaled by Flash strength.
func _blink(car: MeshInstance3D) -> void:
	if car.has_meta("blinking"):
		return
	var lamp_surface := -1
	for s in car.mesh.get_surface_count():
		var m := car.mesh.surface_get_material(s)
		if m and m.resource_name == "lamp_front":
			lamp_surface = s
	var strength := clampf(float(AppState.get_setting("flash_strength")), 0.0, 1.0)
	var safe := bool(AppState.get_setting("photosensitive_safe"))
	if safe:
		strength = minf(strength, 0.3)
	if lamp_surface < 0 or strength <= 0.0:
		return
	car.set_meta("blinking", true)
	var normal := car.get_surface_override_material(lamp_surface)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.95, 0.82)
	light.omni_range = 6.0
	light.light_energy = 0.0
	light.shadow_enabled = false
	add_child(light)
	# just ahead of the nose (the models face -Z)
	var box := car.mesh.get_aabb()
	light.position = car.transform * Vector3(0.0, 0.7, box.position.z - 0.6)
	var tw := create_tween()
	var on := func() -> void: car.set_surface_override_material(lamp_surface, _lamp_on)
	var off := func() -> void: car.set_surface_override_material(lamp_surface, normal)
	if safe:
		tw.tween_callback(on)
		tw.tween_property(light, "light_energy", BLINK_LIGHT * strength, 0.4)
		tw.tween_property(light, "light_energy", 0.0, 0.5)
		tw.tween_callback(off)
	else:
		for i in 2:
			tw.tween_callback(on)
			tw.tween_callback(func() -> void: light.light_energy = BLINK_LIGHT * strength)
			tw.tween_interval(BLINK_ON)
			tw.tween_callback(off)
			tw.tween_callback(func() -> void: light.light_energy = 0.0)
			tw.tween_interval(BLINK_ON)
	tw.tween_callback(func() -> void:
		light.queue_free()
		if is_instance_valid(car):
			car.remove_meta("blinking"))
