class_name CrowdLayer
extends MultiMeshInstance3D
## The filler crowd: one silhouette per crowd seat, all drawn in one go (a MultiMesh with
## crowd.gdshader), so hundreds of people cost about as much as one. AudienceView owns it:
##   - a share of the seats ("audience_crowd_fill") gets a filler person, picked the same way
##     every time so the crowd doesn't reshuffle;
##   - when a chatter overflows into a crowd seat, AudienceView draws them in full and hides
##     the filler person there (set_taken);
##   - crowd-wide motions and the stadium wave run in the shader: one uniform per frame while
##     they play, nothing per person.

const SHADER: Shader = preload("res://core/audience/crowd.gdshader")
const MOTIONS: Dictionary = {"dance": 1, "cheer": 2, "wiggle": 3, "jump": 4, "wave": 4, "flinch": 3, "spin": 3}
## Muted colours for filler people, so chatters (bright platform colours) still stand out.
const TINTS: PackedColorArray = [Color(0.55, 0.52, 0.62), Color(0.62, 0.5, 0.45), Color(0.46, 0.55, 0.6),
	Color(0.6, 0.58, 0.46), Color(0.5, 0.6, 0.5), Color(0.62, 0.48, 0.55), Color(0.52, 0.52, 0.52)]

var _mat: ShaderMaterial = ShaderMaterial.new()
var _count: int = 0
var _filler: PackedByteArray = []     # 1 = this seat has a filler person at the current fill
var _taken: PackedByteArray = []      # 1 = a chatter sits here (drawn by AudienceView)
var _tints: PackedColorArray = []
var _motion_t: float = -1.0
var _motion_len: float = 0.0
var _wave_t: float = -1.0
var _wave_len: float = 0.0


## seats: seat transforms (global, basis scale = person size). bust_* as in AudienceView.
func setup(seats: Array[Transform3D], bust_height: float, bust_lift: float, silhouette: Texture2D) -> void:
	_count = seats.size()
	var quad := QuadMesh.new()
	var aspect := float(silhouette.get_width()) / float(silhouette.get_height())
	quad.size = Vector2(bust_height * aspect, bust_height)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = _count
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	_tints.resize(_count)
	var box := AABB()
	for i in _count:
		var t := seats[i]
		var sc := t.basis.get_scale().x * rng.randf_range(0.93, 1.07)
		# local to this node (it sits at the origin, but keep it right if it doesn't)
		var local := global_transform.affine_inverse() * Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * sc), t.origin)
		mm.set_instance_transform(i, local)
		mm.set_instance_custom_data(i, Color(rng.randf(), rng.randf(), 0.0, 0.0))
		_tints[i] = TINTS[rng.randi() % TINTS.size()].lerp(Color(0.5, 0.5, 0.55), rng.randf_range(0.0, 0.3))
		var head := local.origin + Vector3.UP * (bust_lift + bust_height) * sc
		box = AABB(local.origin, Vector3.ZERO) if i == 0 else box.expand(local.origin)
		box = box.expand(head + Vector3.UP * 0.5)
	multimesh = mm
	custom_aabb = box.grow(1.0)
	_mat.shader = SHADER
	_mat.set_shader_parameter("silhouette", silhouette)
	_mat.set_shader_parameter("quad_size", quad.size)
	_mat.set_shader_parameter("lift", bust_lift)
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_filler.resize(_count)
	_taken.resize(_count)
	_taken.fill(0)
	set_fill(float(AppState.get_setting("audience_crowd_fill")))


func get_count() -> int:
	return _count


## How full the filler crowd is (0..1). The same seats fill first every time.
func set_fill(fill: float) -> void:
	fill = clampf(fill, 0.0, 1.0)
	for i in _count:
		_filler[i] = 1 if _seat_rank(i) < fill else 0
		_apply(i)


func is_filler(i: int) -> bool:
	return i >= 0 and i < _count and _filler[i] == 1 and _taken[i] == 0


func get_filler_count() -> int:
	var n := 0
	for i in _count:
		if _filler[i] == 1 and _taken[i] == 0:
			n += 1
	return n


## A chatter sits in crowd seat i (AudienceView draws them): hide the filler person there.
func set_taken(i: int, taken: bool) -> void:
	if i < 0 or i >= _count:
		return
	_taken[i] = 1 if taken else 0
	_apply(i)


## House light level 0..1: filler people dim with the room (chatters don't).
func set_light_level(level: float) -> void:
	_mat.set_shader_parameter("brightness", lerpf(0.4, 1.0, clampf(level, 0.0, 1.0)))


## Everyone in the filler crowd moves at once ("dance", "cheer", "wiggle", "jump").
func play_motion(style: String, seconds: float) -> void:
	_mat.set_shader_parameter("motion_style", int(MOTIONS.get(style, 3)))
	_motion_len = clampf(seconds, 0.3, 20.0) + 0.25
	_motion_t = 0.0
	_mat.set_shader_parameter("motion_len", _motion_len)
	_mat.set_shader_parameter("motion_t", 0.0)


## The stadium wave: across = the row direction, lo = the first head's position along it.
## Same timing as AudienceView.play_wave, so both crowds wave together.
func play_wave(speed: float, across: Vector3, lo: float, hi: float) -> void:
	speed = clampf(speed, 0.2, 4.0)
	_mat.set_shader_parameter("wave_across", across)
	_mat.set_shader_parameter("wave_lo", lo)
	_mat.set_shader_parameter("wave_speed", speed)
	_wave_len = (hi - lo) / (4.0 * speed) + 0.5
	_wave_t = 0.0
	_mat.set_shader_parameter("wave_t", 0.0)


func _process(delta: float) -> void:
	if _motion_t >= 0.0:
		_motion_t += delta
		if _motion_t > _motion_len:
			_motion_t = -1.0
		_mat.set_shader_parameter("motion_t", _motion_t)
	if _wave_t >= 0.0:
		_wave_t += delta
		if _wave_t > _wave_len:
			_wave_t = -1.0
		_mat.set_shader_parameter("wave_t", _wave_t)


func _apply(i: int) -> void:
	var c := _tints[i]
	c.a = 1.0 if (_filler[i] == 1 and _taken[i] == 0) else 0.0
	multimesh.set_instance_color(i, c)


## A fixed pseudo-random 0..1 per seat, so the fill picks the same seats every time.
func _seat_rank(i: int) -> float:
	return float(absi(hash(i * 7919 + 17)) % 10000) / 10000.0
