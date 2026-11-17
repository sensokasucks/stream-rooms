extends Node3D
## The Route 22 Cruise's car: the red woody convertible the co-stream guests ride in (our own
## design in the style of Sen's reference sheet). The model is models/woody.glb, made by
## models/make_woody.py with Blender; its material names pick the looks in _materials() and its
## empty marker nodes say where the wheels, seats and lamps are (see that script's header).
## It never moves: the road slides under it (r22_trip.gd). This node gives it its looks and life:
##   - its own materials: clear-coated red paint, varnished wood panels in pale trim, chrome,
##     red leather, whitewall tyres, a windscreen you can see through,
##   - wheels that turn at the road's speed,
##   - headlights (two spotlights lighting the road ahead, glare on the lamps) and tail lights at
##     night,
##   - a faint dust trail off the back wheels on a dry road,
##   - on Detailed (the Set detail choice), a reflection probe riding with the car that re-takes
##     its picture of the passing desert every second or so, for the chrome and the paint,
##   - a gentle sway of the body on the road.
## The plate says ROUTE 22. route22_cruise_room.gd makes it (build) and calls tick() every frame.

const Geo := preload("res://rooms/route22/r22_geo.gd")
## The modelled car (body, one wheel, marker nodes): models/make_woody.py.
const MODEL := preload("res://rooms/route22/models/woody.glb")
## Seconds between the reflection probe's new pictures (Detailed only).
const PROBE_EVERY: float = 1.2

## Where the seats are, in the car's space (the presenters sit on them; route22_cruise_room.gd).
var seats: Array[Vector3] = []

var _body: Node3D                     # everything but the wheels (it sways a little)
var _wheels: Array[Node3D] = []
var _wheel_r: float = 0.36
var _lamp_mat: StandardMaterial3D
var _tail_mat: StandardMaterial3D
var _beams: Array[SpotLight3D] = []
var _glows: Array[MeshInstance3D] = []
var _dust: CPUParticles3D
## The render layer (bit 12) the car's own meshes are also on, so the reflection probe can be
## told to light only them (ReflectionProbe.reflection_mask).
const REFLECT_LAYER: int = 1 << 11
var _probe: ReflectionProbe
var _probe_in: float = 0.0
var _time: float = 0.0


## Builds the car under this node. kit: r22_geo.gd new_kit() (for the lamps' glare).
func build(kit: Dictionary) -> void:
	name = "Woody"
	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)
	var model := MODEL.instantiate() as Node3D
	_body.add_child(model)
	var mats := _materials()
	var wheel_mesh: Mesh = null
	for n in model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		# each surface's material name in the model picks our own material for it
		for i in mi.mesh.get_surface_count():
			var from := mi.mesh.surface_get_material(i)
			var look := String(from.resource_name) if from else ""
			if mats.has(look):
				mi.set_surface_override_material(i, mats[look])
		mi.extra_cull_margin = 2.0
		if mi.name == "Wheel":
			wheel_mesh = mi.mesh
			mi.visible = false          # the pattern for the four turning wheels below
	_lamp_mat = mats["lamp_front"]
	_tail_mat = mats["lamp_tail"]
	var wheel_at: Array[Vector3] = _marks(model, "Wheel_")
	seats = _marks(model, "Seat_")
	var front_lights := _marks(model, "LampFront_")
	var tail_lights := _marks(model, "LampTail_")
	# the plate's words
	var plate := model.find_child("PlateWords", true, false) as Node3D
	if plate:
		Geo.add_words(_body, "ROUTE 22", plate.position, 0.0, 0.085, Color(0.1, 0.1, 0.12))
	# the wheels, each its own node so it can turn (the model's wheel faces +X: turned round on the left)
	_wheel_r = wheel_at[0].y if not wheel_at.is_empty() else 0.36
	for c in wheel_at:
		var holder := Node3D.new()
		holder.name = "Wheel"
		add_child(holder)
		holder.position = c
		if c.x < 0.0:
			holder.rotation = Vector3(0.0, PI, 0.0)
		var wm := MeshInstance3D.new()
		wm.mesh = wheel_mesh
		for i in wheel_mesh.get_surface_count():
			var from := wheel_mesh.surface_get_material(i)
			if from and mats.has(String(from.resource_name)):
				wm.set_surface_override_material(i, mats[String(from.resource_name)])
		holder.add_child(wm)
		_wheels.append(holder)
	# headlights: two spotlights down the road ahead, glare on the four lamps; glare on the tail lights
	for x: float in [-0.58, 0.58]:
		var s := SpotLight3D.new()
		s.name = "Headlight"
		s.light_color = Color(1.0, 0.92, 0.78)
		s.light_energy = 0.0
		s.spot_range = 55.0
		s.spot_angle = 24.0
		s.spot_attenuation = 0.6
		s.shadow_enabled = false
		_body.add_child(s)
		s.position = Vector3(x, 0.7, -2.9)
		s.rotation = Vector3(deg_to_rad(-4.0), 0.0, 0.0)
		_beams.append(s)
	for p: Vector3 in front_lights:
		# (small: the main camera looks straight into them from in front of the car)
		_glows.append(Geo.add_glow(kit, _body, p, Color(1.6, 1.5, 1.25), 0.3))
	for p: Vector3 in tail_lights:
		_glows.append(Geo.add_glow(kit, _body, p, Color(1.4, 0.12, 0.08), 0.3))
	_build_dust()
	_probe = ReflectionProbe.new()
	_probe.name = "CarReflections"
	_probe.size = Vector3(80.0, 30.0, 80.0)
	_probe.origin_offset = Vector3(0.0, 2.0, 0.0)
	_probe.box_projection = false
	_probe.interior = false
	_probe.update_mode = ReflectionProbe.UPDATE_ONCE
	_probe.max_distance = 300.0
	_probe.mesh_lod_threshold = 4.0
	# only the car wears these reflections: without the mask everything inside the probe's box
	# (80 m of ground, road and rocks) took its ambient light from the probe too, which showed as
	# a square of lighter ground round the car
	_probe.reflection_mask = REFLECT_LAYER
	add_child(_probe)
	_probe.position = Vector3(0.0, 1.2, 0.0)
	for mi in find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).layers |= REFLECT_LAYER


## The positions of the model's marker nodes whose names start with `prefix`, in name order
## (Wheel_1.., Seat_1.., LampFront_1.., LampTail_1..: models/make_woody.py).
func _marks(model: Node3D, prefix: String) -> Array[Vector3]:
	var found: Array[Node] = model.find_children(prefix + "*", "Node3D", true, false)
	found.sort_custom(func(a: Node, b: Node) -> bool: return String(a.name) < String(b.name))
	var out: Array[Vector3] = []
	for n in found:
		out.append((n as Node3D).position)
	return out


## The car's materials, by the material names in the model.
func _materials() -> Dictionary:
	var m: Dictionary = {}
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.62, 0.05, 0.04)
	paint.metallic = 0.25
	paint.roughness = 0.32
	paint.clearcoat_enabled = true
	paint.clearcoat = 1.0
	paint.clearcoat_roughness = 0.08
	m["paint"] = paint
	# The wood panels (teak) and their frames (pale maple): CC0 Poly Haven veneer photos
	# (textures/make_textures.py car_*), varnished. The model's own UVs are in metres, U along
	# the grain (make_woody.py decal): one photo covers 1.4 m along the car and 0.7 m across.
	for key: String in ["wood", "trim"]:
		var wood := StandardMaterial3D.new()
		wood.albedo_texture = load(Geo.TEX + ("car_wood.jpg" if key == "wood" else "car_maple.jpg"))
		wood.uv1_scale = Vector3(0.7, 1.4, 1.0)
		wood.normal_enabled = true
		wood.normal_texture = load(Geo.TEX + "car_wood_nor.jpg")
		wood.normal_scale = 0.6
		wood.roughness = 0.38
		wood.clearcoat_enabled = true
		wood.clearcoat = 0.8
		wood.clearcoat_roughness = 0.15
		m[key] = wood
	var chrome := StandardMaterial3D.new()
	chrome.albedo_color = Color(0.82, 0.82, 0.84)
	chrome.metallic = 1.0
	chrome.roughness = 0.12
	m["chrome"] = chrome
	var rubber := StandardMaterial3D.new()
	rubber.albedo_color = Color(0.03, 0.03, 0.035)
	rubber.roughness = 0.9
	m["rubber"] = rubber
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.05, 0.045, 0.045)
	dark.roughness = 0.85
	m["dark"] = dark
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.92, 0.9, 0.85)
	white.roughness = 0.6
	m["white"] = white
	var plate := StandardMaterial3D.new()
	plate.albedo_color = Color(0.95, 0.8, 0.2)
	plate.roughness = 0.5
	m["plate"] = plate
	# The seats' red vinyl, the black padding (dash top, the folded top's cover) and the floor
	# carpet: photo grain laid on from three sides (the seats and floor have no UVs of their
	# own), in the car's own space so it stays put. uv1_scale = repeats per metre.
	for key: String in ["leather", "pad", "carpet"]:
		var soft := StandardMaterial3D.new()
		var grain := "car_carpet" if key == "carpet" else "car_leather"
		soft.albedo_texture = load(Geo.TEX + grain + ".jpg")
		soft.normal_enabled = true
		soft.normal_texture = load(Geo.TEX + grain + "_nor.jpg")
		soft.uv1_triplanar = true
		if key == "leather":
			soft.uv1_scale = Vector3(2.2, 2.2, 2.2)
			soft.normal_scale = 0.9
			soft.roughness = 0.42
			soft.clearcoat_enabled = true
			soft.clearcoat = 0.3
		elif key == "pad":
			soft.albedo_color = Color(0.13, 0.9, 1.0)       # tints the red photo down to black vinyl
			soft.uv1_scale = Vector3(2.6, 2.6, 2.6)
			soft.normal_scale = 0.8
			soft.roughness = 0.55
		else:
			soft.uv1_scale = Vector3(1.6, 1.6, 1.6)
			soft.normal_scale = 1.2
			soft.roughness = 0.95
		m[key] = soft
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.6, 0.7, 0.75, 0.18)
	glass.metallic = 0.6
	glass.roughness = 0.05
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	m["glass"] = glass
	# the amber turn lamps under the headlights (not lit: they only catch the daylight)
	var amber := StandardMaterial3D.new()
	amber.albedo_color = Color(1.0, 0.45, 0.06)
	amber.roughness = 0.25
	m["amber"] = amber
	for key: String in ["lamp_front", "lamp_tail"]:
		var lamp := StandardMaterial3D.new()
		lamp.albedo_color = Color(1.0, 0.95, 0.82) if key == "lamp_front" else Color(0.9, 0.08, 0.05)
		lamp.emission_enabled = true
		lamp.emission = Color(1.0, 0.92, 0.75) if key == "lamp_front" else Color(1.0, 0.08, 0.04)
		lamp.emission_energy_multiplier = 0.0
		lamp.roughness = 0.2
		m[key] = lamp
	return m


## A faint plume of dust off the back wheels (only on a dry road, and only when moving).
func _build_dust() -> void:
	_dust = CPUParticles3D.new()
	_dust.name = "DustTrail"
	_dust.amount = 60
	_dust.lifetime = 2.5
	_dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_dust.emission_box_extents = Vector3(1.0, 0.1, 0.2)
	_dust.direction = Vector3(0.0, 0.3, 1.0)
	_dust.spread = 25.0
	_dust.initial_velocity_min = 3.0
	_dust.initial_velocity_max = 6.0
	_dust.gravity = Vector3(0.0, 0.25, 0.0)
	_dust.damping_min = 1.0
	_dust.damping_max = 2.0
	_dust.scale_amount_min = 1.0
	_dust.scale_amount_max = 2.5
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.3))
	grow.add_point(Vector2(1.0, 1.5))
	_dust.scale_amount_curve = grow
	var fade := Gradient.new()
	fade.set_color(0, Color(0.8, 0.6, 0.45, 0.0))
	fade.add_point(0.15, Color(0.78, 0.58, 0.42, 0.22))
	fade.set_color(fade.get_point_count() - 1, Color(0.75, 0.58, 0.45, 0.0))
	_dust.color_ramp = fade
	var puff := QuadMesh.new()
	puff.size = Vector2(1.4, 1.4)
	# a ragged wisp, not a round blob (r22_dust.gdshader), each turned its own way and slowly turning
	puff.material = Geo.dust_material()
	_dust.angle_min = 0.0
	_dust.angle_max = 360.0
	_dust.angular_velocity_min = -25.0
	_dust.angular_velocity_max = 25.0
	_dust.mesh = puff
	_dust.local_coords = false
	_dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_dust.emitting = false
	add_child(_dust)
	_dust.position = Vector3(0.0, 0.2, 2.6)


## Called every frame by the room: speed (m/s of the road), night 0..1 (lights), wet 0..1,
## detailed = the Set detail look is "full" (the reflection probe).
func tick(delta: float, speed: float, night: float, wet: float, detailed: bool) -> void:
	_time += delta
	for w in _wheels:
		w.rotate_object_local(Vector3.RIGHT, -speed / maxf(_wheel_r, 0.1) * delta * (1.0 if w.rotation.y < 1.0 else -1.0))
	# the body rides the road: a slow float and a little shiver, only while moving
	var moving := clampf(speed / 14.0, 0.0, 1.0)
	_body.position.y = moving * (0.006 * sin(_time * 1.7) + 0.003 * sin(_time * 7.3))
	_body.rotation.z = moving * 0.002 * sin(_time * 1.1)
	var on := night > 0.15
	for s in _beams:
		s.visible = on
		s.light_energy = 3.0 * night
	_lamp_mat.emission_energy_multiplier = 2.0 * night
	_tail_mat.emission_energy_multiplier = 0.3 + 2.5 * night
	_dust.emitting = speed > 4.0 and wet < 0.2
	_probe.visible = detailed
	if detailed:
		_probe_in -= delta
		if _probe_in <= 0.0:
			_probe_in = PROBE_EVERY
			# (an "update once" probe takes a new picture whenever one of its settings changes)
			_probe.intensity = 1.0 if _probe.intensity < 1.0 else 0.999
