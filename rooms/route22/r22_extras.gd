extends Node3D
## Route 22's roadside life, in both rooms: tumbleweeds bouncing across in the wind, dust devils
## spinning up out in the desert, vultures circling high overhead, and now and then a jackrabbit
## bounding across or a lizard skittering over the gravel. Each has its own tick box on the Room
## tab (r22_tumbleweeds, r22_dust_devils, r22_birds, r22_critters; shared in a co-stream, though
## where each one turns up is every PC's own luck).
## The room makes one, calls setup() once and tick() every frame with the scenery's speed: in
## the Cruise everything here also slides back past the car at that speed (+Z), in the Drive-In
## the speed is 0. Their meshes use the prop material, so they bend with the road too.

const Geo := preload("res://rooms/route22/r22_geo.gd")

## How many tumbleweeds are about at once, and how many dust devils at most.
const TUMBLEWEEDS: int = 3
const DUST_DEVILS: int = 2
const VULTURES: int = 3

var _kit: Dictionary
## The area things turn up in (room space): x from -half.x to half.x, z from near to far.
var _half_x: float = 60.0
var _z_far: float = -160.0
var _z_near: float = 60.0
## Room-space spots where nothing may run (the Drive-In's cars): they pass behind instead.
var _rng := RandomNumberGenerator.new()
var _weeds: Array[Node3D] = []
var _weed_vel: Array[Vector3] = []
var _devils: Array[CPUParticles3D] = []
var _devil_life: Array[float] = []
var _birds: Array[Node3D] = []
var _bird_angle: Array[float] = []
var _critter: Node3D
var _critter_kind: String = ""
var _critter_vel: Vector3 = Vector3.ZERO
var _critter_wait: float = 8.0
var _hop: float = 0.0
var _rabbit_mesh: ArrayMesh
var _lizard_mesh: ArrayMesh


## area: x = half width, y = farthest z (negative, ahead), z = nearest z (behind), room space.
func setup(kit: Dictionary, area: Vector3) -> void:
	_kit = kit
	_half_x = area.x
	_z_far = area.y
	_z_near = area.z
	_rng.randomize()
	name = "Extras"
	var weed := _tumbleweed_mesh()
	for i in TUMBLEWEEDS:
		var mi := MeshInstance3D.new()
		mi.name = "Tumbleweed"
		mi.mesh = weed
		mi.material_override = kit["prop"]
		mi.extra_cull_margin = 30.0
		add_child(mi)
		_weeds.append(mi)
		_weed_vel.append(Vector3.ZERO)
		_respawn_weed(i, true)
	for i in DUST_DEVILS:
		var d := _dust_devil()
		_devils.append(d)
		_devil_life.append(_rng.randf_range(-20.0, 0.0))
	var bird := _bird_mesh()
	for i in VULTURES:
		var b := MeshInstance3D.new()
		b.name = "Vulture"
		b.mesh = bird
		b.material_override = kit["prop"]
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(b)
		_birds.append(b)
		_bird_angle.append(TAU * float(i) / float(VULTURES))
	_rabbit_mesh = _rabbit()
	_lizard_mesh = _lizard()
	_critter = MeshInstance3D.new()
	_critter.name = "Critter"
	(_critter as MeshInstance3D).material_override = kit["prop"]
	_critter.visible = false
	add_child(_critter)


## Called every frame by the room. speed = metres a second the scenery slides back (+Z), wind 0..1.
func tick(delta: float, speed: float, wind: float, day: float) -> void:
	var drift := Vector3(0.0, 0.0, speed * delta)
	var weeds_on := bool(AppState.get_setting("r22_tumbleweeds"))
	for i in _weeds.size():
		var w := _weeds[i]
		w.visible = weeds_on
		if not weeds_on:
			continue
		# rolling with the wind (+X), bouncing, and sliding back with the scenery
		var v := _weed_vel[i]
		v.x = lerpf(v.x, 2.0 + 7.0 * wind, delta * 0.8)
		v.y -= 9.8 * delta
		w.position += v * delta + drift
		if w.position.y < 0.45:
			w.position.y = 0.45
			v.y = _rng.randf_range(0.5, 2.5) * (0.4 + wind)
		_weed_vel[i] = v
		w.rotate(Vector3(0.0, 0.0, -1.0).normalized(), v.x * delta / 0.45)
		if w.position.x > _half_x or w.position.z > _z_near:
			_respawn_weed(i, false)
	var devils_on := bool(AppState.get_setting("r22_dust_devils")) and day > 0.4
	for i in _devils.size():
		var d := _devils[i]
		_devil_life[i] -= delta
		d.position += drift + Vector3(1.5 * wind, 0.0, 0.0) * delta
		if _devil_life[i] < 0.0 or d.position.z > _z_near:
			# a new one far out, alive 12 to 25 s (some rest in between)
			_devil_life[i] = _rng.randf_range(12.0, 25.0)
			var side := -1.0 if _rng.randf() < 0.5 else 1.0
			d.position = Vector3(side * _rng.randf_range(25.0, _half_x), 0.0, _rng.randf_range(_z_far, _z_far * 0.4))
			d.emitting = devils_on and _rng.randf() < 0.7
		elif not devils_on:
			d.emitting = false
	var birds_on := bool(AppState.get_setting("r22_birds")) and day > 0.25
	for i in _birds.size():
		var b := _birds[i]
		b.visible = birds_on
		if not birds_on:
			continue
		# slow wide circles high over the road ahead, each at its own height, wings tilting
		_bird_angle[i] += delta * (0.12 + 0.03 * float(i))
		var a := _bird_angle[i]
		var r := 28.0 + 9.0 * float(i)
		b.position = Vector3(cos(a) * r - 10.0, 42.0 + 7.0 * float(i) + 2.0 * sin(a * 2.0), sin(a) * r * 0.7 - 70.0)
		b.rotation = Vector3(0.0, -a, 0.35)
	_run_critter(delta, drift)


## Now and then a jackrabbit bounds across, or a lizard skitters over the gravel, close to the road.
func _run_critter(delta: float, drift: Vector3) -> void:
	var on := bool(AppState.get_setting("r22_critters"))
	if _critter.visible:
		_hop += delta
		var p := _critter.position + _critter_vel * delta + drift
		if _critter_kind == "rabbit":
			p.y = absf(sin(_hop * 7.0)) * 0.35
		_critter.position = p
		if absf(p.x) > 22.0 or p.z > _z_near or not on:
			_critter.visible = false
			_critter_wait = _rng.randf_range(18.0, 40.0)
		return
	_critter_wait -= delta
	if _critter_wait > 0.0 or not on:
		return
	_critter_kind = "rabbit" if _rng.randf() < 0.6 else "lizard"
	var mi := _critter as MeshInstance3D
	mi.mesh = _rabbit_mesh if _critter_kind == "rabbit" else _lizard_mesh
	var dir := 1.0 if _rng.randf() < 0.5 else -1.0
	var speed := 6.0 if _critter_kind == "rabbit" else 2.5
	_critter_vel = Vector3(dir * speed, 0.0, 0.0)
	_critter.position = Vector3(-dir * 20.0, 0.0, _rng.randf_range(-45.0, -14.0))
	_critter.rotation = Vector3(0.0, -PI * 0.5 * dir, 0.0)
	_hop = 0.0
	_critter.visible = true


func _respawn_weed(i: int, anywhere: bool) -> void:
	var w := _weeds[i]
	w.position = Vector3(_rng.randf_range(-_half_x, _half_x) if anywhere else -_half_x, 0.5, _rng.randf_range(_z_far * 0.6, minf(_z_near, 10.0)))
	_weed_vel[i] = Vector3(3.0, 0.0, 0.0)


## A dust devil: a thin spinning column of dust specks (particles swirling round its axis).
func _dust_devil() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "DustDevil"
	p.amount = 160
	p.lifetime = 4.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_radius = 1.2
	p.emission_ring_inner_radius = 0.2
	p.emission_ring_height = 0.5
	p.direction = Vector3.UP
	p.spread = 10.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 4.0
	p.gravity = Vector3(0.0, 1.0, 0.0)
	p.tangential_accel_min = 8.0
	p.tangential_accel_max = 12.0
	p.radial_accel_min = 0.3
	p.radial_accel_max = 0.8
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.6
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.4))
	grow.add_point(Vector2(1.0, 1.6))
	p.scale_amount_curve = grow
	var fade := Gradient.new()
	fade.set_color(0, Color(0.8, 0.55, 0.38, 0.0))
	fade.add_point(0.2, Color(0.78, 0.55, 0.38, 0.35))
	fade.set_color(fade.get_point_count() - 1, Color(0.75, 0.55, 0.4, 0.0))
	p.color_ramp = fade
	var puff := QuadMesh.new()
	puff.size = Vector2(1.2, 1.2)
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
	p.mesh = puff
	p.local_coords = false
	p.emitting = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	return p


## A tumbleweed: a tangle of thin dry twigs in a ball.
func _tumbleweed_mesh() -> ArrayMesh:
	var b := Geo.Buf.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for i in 70:
		var a := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized() * 0.45
		var c := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized() * 0.4
		b.rod(a, c, 0.012, 3, Color(0.6, 0.48, 0.3).lerp(Color(0.45, 0.35, 0.22), rng.randf()))
	return b.to_mesh()


## A vulture seen from below: a dark body and long fingered wings (6 m up, it reads as a shape).
func _bird_mesh() -> ArrayMesh:
	var b := Geo.Buf.new()
	var dark := Color(0.08, 0.07, 0.07)
	b.quad(Vector3(-0.1, 0.0, -0.4), Vector3(0.1, 0.0, -0.4), Vector3(0.12, 0.0, 0.5), Vector3(-0.12, 0.0, 0.5), dark)
	for sx: float in [-1.0, 1.0]:
		b.quad(Vector3(sx * 0.1, 0.0, -0.15), Vector3(sx * 1.6, 0.15, -0.05), Vector3(sx * 1.7, 0.18, 0.25), Vector3(sx * 0.1, 0.0, 0.25), dark)
	return b.to_mesh()


## A jackrabbit mid-bound: a long body, big upright ears.
func _rabbit() -> ArrayMesh:
	var b := Geo.Buf.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var fur := Color(0.55, 0.45, 0.35)
	b.blob(Vector3(0.0, 0.25, 0.0), Vector3(0.12, 0.13, 0.28), 8, 5, fur, fur.darkened(0.2), 0.1, rng)
	b.blob(Vector3(0.0, 0.36, -0.26), Vector3(0.08, 0.08, 0.1), 7, 4, fur, fur, 0.05, rng)
	for sx: float in [-0.04, 0.04]:
		b.quad(Vector3(sx, 0.4, -0.25), Vector3(sx * 1.5, 0.62, -0.2), Vector3(sx * 1.8, 0.62, -0.15), Vector3(sx, 0.4, -0.2), fur.darkened(0.1))
	return b.to_mesh()


## A lizard: a low flat body and a long tail.
func _lizard() -> ArrayMesh:
	var b := Geo.Buf.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 6
	var skin := Color(0.5, 0.45, 0.3)
	b.blob(Vector3(0.0, 0.04, 0.0), Vector3(0.05, 0.03, 0.12), 6, 4, skin, skin.darkened(0.3), 0.1, rng)
	b.rod(Vector3(0.0, 0.03, 0.1), Vector3(0.02, 0.02, 0.35), 0.015, 4, skin)
	return b.to_mesh()
