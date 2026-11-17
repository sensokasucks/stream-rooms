extends Node3D
## The Route 22 Cruise's car: the red woody convertible the co-stream guests ride in (our own
## design in the style of Sen's reference sheet; built by r22_vehicles.gd "woody"). It never moves:
## the road slides under it (r22_trip.gd). This node gives it its good looks and its life:
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
const Vehicles := preload("res://rooms/route22/r22_vehicles.gd")
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
	var parts := ["paint", "wood", "trim", "chrome", "rubber", "white", "leather", "dark", "glass", "lamp_front", "lamp_tail"]
	var bufs: Dictionary = {}
	for p: String in parts:
		bufs[p] = Geo.Buf.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 22
	var info := Vehicles.build("woody", bufs, Color(0.62, 0.05, 0.04), {"no_wheels": true}, rng)
	seats.assign(info["seats"])
	var mats := _materials()
	for p: String in parts:
		var b: Geo.Buf = bufs[p]
		if b.is_empty():
			continue
		var mi := Geo.add_mesh(_body, "Car_" + p, b, mats[p], p != "glass")
		mi.extra_cull_margin = 2.0
	_lamp_mat = mats["lamp_front"]
	_tail_mat = mats["lamp_tail"]
	# the plate's words
	Geo.add_words(_body, "ROUTE 22", Vector3(0.0, 0.53, 2.775), 0.0, 0.09, Color(0.1, 0.1, 0.12))
	# the wheels, each its own node so it can turn
	var wb := {"rubber": Geo.Buf.new(), "white": Geo.Buf.new(), "chrome": Geo.Buf.new()}
	Vehicles.wheel(wb, Vector3(0.11, 0.0, 0.0), Vehicles.WHEEL_R, 0.22, true)
	for w: Array in info["wheels"]:
		var c: Vector3 = w[0]
		_wheel_r = float(w[1])
		var holder := Node3D.new()
		holder.name = "Wheel"
		add_child(holder)
		holder.position = c - Vector3(0.11 * signf(c.x), 0.0, 0.0)
		if c.x < 0.0:
			holder.rotation = Vector3(0.0, PI, 0.0)       # the left wheels' faces point left
		for p: String in wb:
			Geo.add_mesh(holder, p, wb[p], mats[p], true)
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
	for p: Vector3 in info["front_lights"]:
		# (small: the main camera looks straight into them from in front of the car)
		_glows.append(Geo.add_glow(kit, _body, p, Color(1.6, 1.5, 1.25), 0.3))
	for p: Vector3 in info["tail_lights"]:
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


## The car's materials, by part.
func _materials() -> Dictionary:
	var m: Dictionary = {}
	var paint := StandardMaterial3D.new()
	paint.vertex_color_use_as_albedo = true
	paint.metallic = 0.25
	paint.roughness = 0.32
	paint.clearcoat_enabled = true
	paint.clearcoat = 1.0
	paint.clearcoat_roughness = 0.08
	m["paint"] = paint
	var wood := StandardMaterial3D.new()
	wood.albedo_texture = load(Geo.CAMP_TEX + "detail_planks.jpg")
	wood.albedo_color = Color(2.0, 2.0, 2.0)          # the grain picture averages 0.5: x2 = no change
	wood.vertex_color_use_as_albedo = true
	wood.uv1_triplanar = true
	wood.uv1_scale = Vector3(0.9, 0.25, 0.9)           # grain stretched along the car
	wood.roughness = 0.4
	wood.clearcoat_enabled = true
	wood.clearcoat = 0.8
	wood.clearcoat_roughness = 0.15
	m["wood"] = wood
	m["trim"] = wood
	var chrome := StandardMaterial3D.new()
	chrome.vertex_color_use_as_albedo = true
	chrome.metallic = 1.0
	chrome.roughness = 0.12
	m["chrome"] = chrome
	var rubber := StandardMaterial3D.new()
	rubber.vertex_color_use_as_albedo = true
	rubber.roughness = 0.9
	m["rubber"] = rubber
	m["dark"] = rubber
	var white := StandardMaterial3D.new()
	white.vertex_color_use_as_albedo = true
	white.roughness = 0.6
	m["white"] = white
	var leather := StandardMaterial3D.new()
	leather.vertex_color_use_as_albedo = true
	leather.roughness = 0.45
	leather.clearcoat_enabled = true
	leather.clearcoat = 0.3
	m["leather"] = leather
	var glass := StandardMaterial3D.new()
	glass.vertex_color_use_as_albedo = true
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(1.0, 1.0, 1.0, 0.18)
	glass.metallic = 0.6
	glass.roughness = 0.05
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	m["glass"] = glass
	for key: String in ["lamp_front", "lamp_tail"]:
		var lamp := StandardMaterial3D.new()
		lamp.vertex_color_use_as_albedo = true
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
	fade.add_point(0.15, Color(0.78, 0.58, 0.42, 0.12))
	fade.set_color(fade.get_point_count() - 1, Color(0.75, 0.58, 0.45, 0.0))
	_dust.color_ramp = fade
	var puff := QuadMesh.new()
	puff.size = Vector2(1.0, 1.0)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	var dot := GradientTexture2D.new()
	dot.fill = GradientTexture2D.FILL_RADIAL
	dot.fill_from = Vector2(0.5, 0.5)
	dot.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.set_color(0, Color.WHITE)
	g.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	dot.gradient = g
	m.albedo_texture = dot
	puff.material = m
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
