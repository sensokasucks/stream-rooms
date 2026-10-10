extends Room
## Neon City room: everything the Blender model can't do by itself.
##   - Rain that follows whichever camera is active.
##   - Flying traffic along lanes above the avenue (+ distant high lanes); every few
##     craft carries a light that sweeps across the building faces.
##   - Street traffic with head/tail lights (reflected by the wet road in Forward+).
##   - FLARE_* markers become flickering fire with occasional bursts.
##   - A generated rain + city-hum ambience on the Ambience bus (no audio files needed).
## Coordinates are Redot's: the avenue runs along -Z toward the billboard.

@export_group("Rain")
@export var rain_enabled: bool = true
## Raindrops at 100% on the Rain slider (the slider goes to 200%).
@export var rain_amount: int = 6000
@export var rain_speed: float = 28.0
@export var rain_color: Color = Color(0.7, 0.8, 1.0, 0.32)

@export_group("Hologram")
## Mesh behind the main screen. It fades out with the screen's Transparency setting,
## so a see-through screen floats in front of the tower instead of a dark box.
@export var screen_housing_name: String = "Screen_Housing"

@export_group("Traffic")
@export var flying_count: int = 34
@export var ground_count: int = 26
## Every Nth flying craft carries a real light.
@export var lit_craft_every: int = 5
@export var avenue_z_range: Vector2 = Vector2(-280.0, 70.0)

@export_group("Flares")
@export var flare_prefix: String = "FLARE_"
@export var flare_color: Color = Color(1.0, 0.55, 0.18)

@export_group("Ambience")
@export var ambience_enabled: bool = true
@export_range(0.0, 1.0) var rain_loudness: float = 0.35

var _rain: GPUParticles3D
var _craft: Array[Dictionary] = []      # {node, dir, speed, min, max, axis}
var _cars: Array[Dictionary] = []
var _flares: Array[Dictionary] = []     # {mesh, light, base_scale, burst}
var _noise: FastNoiseLite = FastNoiseLite.new()
var _time: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _amb_playback: AudioStreamGeneratorPlayback
var _lp: float = 0.0
var _lp2: float = 0.0
var _hum_phase: float = 0.0
var _housing: MeshInstance3D
var _housing_mat: StandardMaterial3D


func _ready() -> void:
	super._ready()
	_rng.seed = 2049
	_noise.frequency = 2.5
	if rain_enabled:
		_build_rain()
	_build_flying_traffic()
	_build_ground_traffic()
	_build_flares()
	if ambience_enabled:
		_amb_playback = _start_generated_ambience(22050.0, 0.35)
	EventBus.setting_changed.connect(_on_setting_changed)
	_apply_rain()
	_housing = find_child(screen_housing_name, true, false) as MeshInstance3D
	_apply_housing()


func _exit_tree() -> void:
	EventBus.setting_changed.disconnect(_on_setting_changed)


func get_controls() -> Array[Dictionary]:
	if not rain_enabled:
		return []
	return [
		{"heading": "Weather"},
		{"key": "rain_amount", "label": "Rain", "min": 0.0, "max": 2.0, "step": 0.01, "format": "%d%%", "scale": 100.0,
			"tooltip": "How much rain you see (and hear). 0% = dry night, 200% = downpour."},
	]


func _on_setting_changed(key: String, _value: Variant) -> void:
	if key == "rain_amount":
		_apply_rain()
	elif key == "holo_transparency":
		_apply_housing()


func _apply_housing() -> void:
	if _housing == null or _housing.mesh == null:
		return
	var t := clampf(float(AppState.get_setting("holo_transparency")), 0.0, 1.0)
	if t <= 0.001:
		_housing.material_override = null
		_housing.visible = true
		return
	if _housing_mat == null:
		var src := _housing.mesh.surface_get_material(0) as BaseMaterial3D
		_housing_mat = (src.duplicate() if src else StandardMaterial3D.new()) as StandardMaterial3D
		_housing_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_housing_mat.albedo_color.a = 1.0 - t
	_housing.material_override = _housing_mat
	_housing.visible = t < 0.999


func _process(delta: float) -> void:
	super._process(delta)
	_time += delta
	_follow_camera()
	_move(_craft, delta)
	_move(_cars, delta)
	_update_flares(delta)
	_fill_ambience()


# ── Rain ─────────────────────────────────────────────────────
func _build_rain() -> void:
	_rain = GPUParticles3D.new()
	_rain.name = "Rain"
	_rain.amount = rain_amount * 2      # room for 200%; amount_ratio picks how many are live
	_rain.lifetime = 1.6
	_rain.preprocess = 1.6
	_rain.local_coords = false
	_rain.visibility_aabb = AABB(Vector3(-45, -60, -45), Vector3(90, 90, 90))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(38, 1, 38)
	pm.direction = Vector3(0.06, -1.0, 0.03)
	pm.spread = 2.0
	pm.initial_velocity_min = rain_speed * 0.85
	pm.initial_velocity_max = rain_speed * 1.1
	pm.gravity = Vector3(0, -9.8, 0)
	pm.particle_flag_align_y = true
	_rain.process_material = pm
	var drop := BoxMesh.new()
	drop.size = Vector3(0.012, 0.6, 0.012)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = rain_color
	m.disable_receive_shadows = true
	drop.material = m
	_rain.draw_pass_1 = drop
	_rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_rain)


func _rain_level() -> float:
	return clampf(float(AppState.get_setting("rain_amount")), 0.0, 2.0)


func _apply_rain() -> void:
	if _rain == null:
		return
	var r := _rain_level()
	_rain.amount_ratio = r * 0.5
	_rain.visible = r > 0.001
	_rain.emitting = r > 0.001


func _follow_camera() -> void:
	if _rain == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var fwd := -cam.global_transform.basis.z
	fwd.y = 0.0
	_rain.global_position = cam.global_position + fwd.normalized() * 14.0 + Vector3(0, 26, 0)


# ── Traffic ──────────────────────────────────────────────────
func _light_mat(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color * energy
	return m


func _vehicle(body_size: Vector3, head: Color, tail: Color, body_color: Color) -> Node3D:
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = body_size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = body_color
	mat.metallic = 0.6
	mat.roughness = 0.3
	bm.material = mat
	body.mesh = bm
	root.add_child(body)
	# lights: vehicles face -Z; head lights at -Z end, tail lights at +Z end
	for side in [-1.0, 1.0]:
		for spec in [[head, -1.0], [tail, 1.0]]:
			var l := MeshInstance3D.new()
			var lm := BoxMesh.new()
			lm.size = Vector3(body_size.x * 0.22, body_size.y * 0.25, 0.08)
			lm.material = _light_mat(spec[0], 3.0)
			l.mesh = lm
			l.position = Vector3(side * body_size.x * 0.32, 0.0, float(spec[1]) * body_size.z * 0.5)
			l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(l)
	return root


func _build_flying_traffic() -> void:
	var lanes_x := [-8.0, -4.0, 4.0, 8.0]
	var heights := [23.0, 28.0, 33.0, 37.0, 41.0]   # below the billboard tower's traffic portal (44.5 m), above the gantry
	for i in flying_count:
		var far := i % 6 == 5                     # every 6th is on a distant high lane crossing the view
		var head := Color(0.75, 0.95, 1.0)
		var tail := Color(1.0, 0.1, 0.35) if _rng.randf() < 0.6 else Color(1.0, 0.35, 0.05)
		var v := _vehicle(Vector3(2.2, 0.8, 4.8), head, tail, Color(0.06, 0.065, 0.08))
		v.name = "Craft%d" % i
		add_child(v)
		var d := {"node": v, "speed": _rng.randf_range(14.0, 32.0)}
		if far:
			var z := _rng.randf_range(-520.0, -360.0)
			var y := _rng.randf_range(260.0, 300.0)   # above the skyline and arcologies
			var dir := 1.0 if _rng.randf() < 0.5 else -1.0
			v.position = Vector3(_rng.randf_range(-400.0, 400.0), y, z)
			v.rotation.y = -dir * PI / 2.0
			d.merge({"axis": 0, "dir": dir, "min": -420.0, "max": 420.0})
		else:
			var dir := 1.0 if i % 2 == 0 else -1.0    # +1 = toward the viewer (+Z)
			v.position = Vector3(lanes_x[i % lanes_x.size()] * (1.0 if dir > 0.0 else -1.0),
				heights[_rng.randi() % heights.size()] + _rng.randf_range(-2.0, 2.0),
				_rng.randf_range(avenue_z_range.x, avenue_z_range.y))
			v.rotation.y = 0.0 if dir < 0.0 else PI
			d.merge({"axis": 2, "dir": dir, "min": avenue_z_range.x, "max": avenue_z_range.y})
			if lit_craft_every > 0 and i % lit_craft_every == 0:
				var ol := OmniLight3D.new()
				ol.light_color = Color(0.35, 0.85, 1.0) if i % 2 == 0 else Color(1.0, 0.3, 0.7)
				ol.light_energy = 2.0
				ol.omni_range = 14.0
				ol.position = Vector3(0, -1.2, 0)
				ol.light_volumetric_fog_energy = 1.5
				v.add_child(ol)
		_craft.append(d)


func _build_ground_traffic() -> void:
	var lanes := [[-8.2, 1.0], [-2.8, 1.0], [2.8, -1.0], [8.2, -1.0]]   # left lanes toward viewer
	for i in ground_count:
		var lane: Array = lanes[i % lanes.size()]
		var v := _vehicle(Vector3(1.9, 1.3, 4.4), Color(1.0, 0.95, 0.85), Color(1.0, 0.05, 0.03),
			Color(_rng.randf_range(0.02, 0.2), _rng.randf_range(0.02, 0.1), _rng.randf_range(0.02, 0.15)))
		v.name = "Car%d" % i
		add_child(v)
		var dir: float = lane[1]
		v.position = Vector3(lane[0], 0.75, _rng.randf_range(avenue_z_range.x, avenue_z_range.y))
		v.rotation.y = 0.0 if dir < 0.0 else PI
		_cars.append({"node": v, "axis": 2, "dir": dir, "speed": _rng.randf_range(9.0, 15.0),
			"min": avenue_z_range.x, "max": avenue_z_range.y})


func _move(list: Array[Dictionary], delta: float) -> void:
	for d in list:
		var n: Node3D = d["node"]
		var axis: int = d["axis"]
		var p := n.position
		p[axis] += float(d["dir"]) * float(d["speed"]) * delta
		if p[axis] > float(d["max"]):
			p[axis] = float(d["min"])
		elif p[axis] < float(d["min"]):
			p[axis] = float(d["max"])
		n.position = p


# ── Flare stacks ─────────────────────────────────────────────
func _build_flares() -> void:
	var flame_mat := StandardMaterial3D.new()
	flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flame_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	flame_mat.albedo_color = Color(flare_color.r * 2.5, flare_color.g * 2.0, flare_color.b, 0.85)
	for n in find_children(flare_prefix + "*", "Node3D", true, false):
		var marker := n as Node3D
		var flame := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 2.2
		sm.height = 9.0
		sm.material = flame_mat
		flame.mesh = sm
		flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		flame.position = Vector3(0, 4.0, 0)
		marker.add_child(flame)
		var l := OmniLight3D.new()
		l.light_color = flare_color
		l.omni_range = 90.0
		l.light_energy = 3.0
		l.light_volumetric_fog_energy = 2.0
		l.position = Vector3(0, 6.0, 0)
		marker.add_child(l)
		_flares.append({"mesh": flame, "light": l, "seed": _rng.randf() * 100.0,
			"burst": 0.0, "next_burst": _rng.randf_range(3.0, 10.0)})


func _update_flares(delta: float) -> void:
	for f in _flares:
		f["next_burst"] = float(f["next_burst"]) - delta
		if float(f["next_burst"]) <= 0.0:
			f["burst"] = 1.0
			f["next_burst"] = _rng.randf_range(5.0, 14.0)
		f["burst"] = maxf(0.0, float(f["burst"]) - delta * 0.8)
		var flick := 0.75 + 0.35 * _noise.get_noise_1d(_time * 6.0 + float(f["seed"]))
		var b: float = float(f["burst"])
		var s := flick * (1.0 + 1.6 * b * b)
		var mesh: MeshInstance3D = f["mesh"]
		mesh.scale = Vector3(s * 0.9, s * (1.0 + b), s * 0.9)
		mesh.position.y = 4.0 * s * (1.0 + b * 0.8)
		(f["light"] as OmniLight3D).light_energy = 3.0 * flick * (1.0 + 3.0 * b)


# ── Ambience: rain hiss + distant hum, generated live ─────────
func _fill_ambience() -> void:
	if _amb_playback == null:
		return
	var n := _amb_playback.get_frames_available()
	if n <= 0:
		return
	var buf := PackedVector2Array()
	buf.resize(n)
	var step := TAU * 52.0 / 22050.0
	var rain_now := rain_loudness * sqrt(_rain_level() * 0.5) * 1.414   # 100% = rain_loudness
	for i in n:
		var w := _rng.randf() * 2.0 - 1.0
		_lp += (w - _lp) * 0.35            # soften the white noise into a rain hiss
		_lp2 += (_lp - _lp2) * 0.02        # low rumble
		var drop := 0.0
		if _rng.randf() < 0.0009:
			drop = _rng.randf_range(0.2, 0.5) * (1.0 if _rng.randf() < 0.5 else -1.0)
		_hum_phase += step
		var hum := sin(_hum_phase) * 0.02
		var s := (_lp * 0.5 + _lp2 * 1.5 + drop) * rain_now + hum
		buf[i] = Vector2(s, s * 0.97 + (_rng.randf() - 0.5) * 0.01 * rain_now)
	_amb_playback.push_buffer(buf)
