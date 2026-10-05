extends Room
## Old-school classroom with a 16 mm film projector.
##   - REEL_* nodes (from Blender) spin while the film runs and spin down on a react pause.
##   - CLOCK_Hour / CLOCK_Minute / CLOCK_Second show the real time.
##   - The glowing lamp globes dim along with the house lights.
##   - Dust drifts through the projector beam (only the specks inside the beam show).
##   - A generated projector whirr + film clatter, faint room tone and the clock's tick
##     play on the Ambience bus (no audio files needed).
## The old-film picture and the tinny speaker come from room_info.tres
## (screen_film_amount, screen_matte, speaker_lofi).

const DUST_SHADER: Shader = preload("res://rooms/classroom/beam_dust.gdshader")
const MIX_RATE: float = 22050.0

@export_group("Projector")
@export var reel_prefix: String = "REEL_"
## Revolutions per second of the full feed reel; the take-up reel turns faster.
@export var feed_reel_rps: float = 0.45
@export var takeup_reel_rps: float = 0.95
## Seconds to spin up / run down.
@export var spin_ease: float = 1.2

@export_group("Beam dust")
@export var dust_enabled: bool = true
@export var dust_amount: int = 500
@export var dust_color: Color = Color(1.0, 0.95, 0.85, 0.35)

@export_group("Clock")
@export var clock_prefix: String = "CLOCK_"

@export_group("Lamp globes")
## Mesh whose emission follows the house lights.
@export var lamp_mesh_name: String = "Lamp_Globes"

@export_group("Sound")
@export var ambience_enabled: bool = true
@export_range(0.0, 1.0) var projector_loudness: float = 0.35
@export_range(0.0, 1.0) var room_tone_loudness: float = 0.06
@export_range(0.0, 1.0) var clock_tick_loudness: float = 0.12

var _reels: Array[Node3D] = []
var _spin: float = 0.0              # 0 = stopped, 1 = running
var _hands: Dictionary = {}          # "Hour"/"Minute"/"Second" -> Node3D
var _lamp_mat: StandardMaterial3D
var _lamp_energy: float = 1.0
var _dust: GPUParticles3D
var _dust_mat: ShaderMaterial
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

var _amb_player: AudioStreamPlayer
var _amb_playback: AudioStreamGeneratorPlayback
var _t: float = 0.0                  # sample clock (seconds)
var _motor_phase: float = 0.0
var _noise_lp: float = 0.0
var _noise_lp2: float = 0.0
var _click_env: float = 0.0
var _next_click: float = 0.0
var _tick_env: float = 0.0
var _last_second: int = -1


func _ready() -> void:
	super._ready()
	_rng.seed = 1957
	for n in find_children(reel_prefix + "*", "Node3D", true, false):
		_reels.append(n as Node3D)
	for key in ["Hour", "Minute", "Second"]:
		var h := find_child(clock_prefix + key, true, false) as Node3D
		if h:
			_hands[key] = h
	_setup_lamp_globes()
	if dust_enabled:
		_build_dust.call_deferred()
	if ambience_enabled:
		_build_ambience()


func _process(delta: float) -> void:
	super._process(delta)
	var running := AppState.is_playback_active() and not AppState.is_react_paused()
	_spin = move_toward(_spin, 1.0 if running else 0.0, delta / maxf(spin_ease, 0.01))
	_spin_reels(delta)
	_update_clock()
	if _lamp_mat:
		_lamp_mat.emission_energy_multiplier = _lamp_energy * _level
	if _dust_mat:
		_dust_mat.set_shader_parameter("intensity", 0.15 + 0.85 * _spin)
	_fill_ambience()


# ── Reels + clock ────────────────────────────────────────────
func _spin_reels(delta: float) -> void:
	if _spin <= 0.0:
		return
	for r in _reels:
		var rps := takeup_reel_rps if String(r.name).to_lower().contains("take") else feed_reel_rps
		r.rotate_object_local(Vector3.RIGHT, -TAU * rps * _spin * delta)


func _update_clock() -> void:
	var t := Time.get_time_dict_from_system()
	var sec := float(t["second"])
	var minute := float(t["minute"]) + sec / 60.0
	var hour := fmod(float(t["hour"]), 12.0) + minute / 60.0
	# Hands point up (12 o'clock) at rest and turn clockwise as seen from the room.
	if _hands.has("Hour"):
		(_hands["Hour"] as Node3D).rotation = Vector3(0, 0, -hour / 12.0 * TAU)
	if _hands.has("Minute"):
		(_hands["Minute"] as Node3D).rotation = Vector3(0, 0, -minute / 60.0 * TAU)
	if _hands.has("Second"):
		(_hands["Second"] as Node3D).rotation = Vector3(0, 0, -sec / 60.0 * TAU)
	if int(sec) != _last_second:
		_last_second = int(sec)
		_tick_env = 1.0


# ── Lamp globes ──────────────────────────────────────────────
func _setup_lamp_globes() -> void:
	var mi := find_child(lamp_mesh_name, true, false) as MeshInstance3D
	if mi == null or mi.mesh == null:
		return
	var m := mi.get_active_material(0) as StandardMaterial3D
	if m == null:
		return
	_lamp_mat = m.duplicate() as StandardMaterial3D
	_lamp_energy = _lamp_mat.emission_energy_multiplier
	mi.set_surface_override_material(0, _lamp_mat)


# ── Dust in the beam ─────────────────────────────────────────
func _build_dust() -> void:
	var marker := get_projector_marker()
	var screen := find_screen()
	if marker == null or screen == null:
		return
	var from := marker.global_position
	var aabb := screen.get_aabb()
	var to := screen.global_transform * aabb.get_center()
	var size := screen.global_transform.basis * aabb.size
	var dist := from.distance_to(to)
	var half := Vector2(maxf(absf(size.x), absf(size.z)), absf(size.y)) * 0.5
	var dir := (to - from).normalized()

	_dust = GPUParticles3D.new()
	_dust.name = "BeamDust"
	add_child(_dust)
	_dust.look_at_from_position((from + to) * 0.5, to, Vector3.UP)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(half.x, half.y, dist * 0.5)
	pm.gravity = Vector3(0, -0.004, 0)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.01
	pm.initial_velocity_max = 0.05
	pm.scale_min = 0.5
	pm.scale_max = 1.3
	_dust.process_material = pm
	_dust.amount = dust_amount
	_dust.lifetime = 14.0
	_dust.preprocess = 14.0
	_dust.local_coords = false
	_dust.visibility_aabb = AABB(Vector3(-half.x - 1, -half.y - 1, -dist * 0.5 - 1), Vector3(half.x * 2 + 2, half.y * 2 + 2, dist + 2))
	var quad := QuadMesh.new()
	quad.size = Vector2(0.005, 0.005)
	_dust_mat = ShaderMaterial.new()
	_dust_mat.shader = DUST_SHADER
	_dust_mat.set_shader_parameter("beam_origin", from)
	_dust_mat.set_shader_parameter("beam_dir", dir)
	_dust_mat.set_shader_parameter("beam_tan", maxf(half.x, half.y) / maxf(dist, 0.1))
	_dust_mat.set_shader_parameter("color", dust_color)
	quad.material = _dust_mat
	_dust.draw_pass_1 = quad


# ── Sound: projector + room tone + clock ─────────────────────
func _build_ambience() -> void:
	_amb_player = AudioStreamPlayer.new()
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = MIX_RATE
	gen.buffer_length = 0.3
	_amb_player.stream = gen
	_amb_player.bus = AudioManager.AMBIENCE_BUS
	add_child(_amb_player)
	_amb_player.play()
	_amb_playback = _amb_player.get_stream_playback() as AudioStreamGeneratorPlayback


func _fill_ambience() -> void:
	if _amb_playback == null:
		return
	var n := _amb_playback.get_frames_available()
	if n <= 0:
		return
	var buf := PackedVector2Array()
	buf.resize(n)
	var dt := 1.0 / MIX_RATE
	var run := _spin
	var clatter_hz := 24.0 * (0.6 + 0.4 * run)      # the claw pulls film 24 times a second
	for i in n:
		_t += dt
		var w := _rng.randf() * 2.0 - 1.0
		_noise_lp += (w - _noise_lp) * 0.25           # fan whoosh
		_noise_lp2 += (w - _noise_lp2) * 0.02         # low room tone
		# claw / shutter clatter: a short noisy click every frame
		if run > 0.01 and _t >= _next_click:
			_next_click = _t + 1.0 / clatter_hz * _rng.randf_range(0.97, 1.03)
			_click_env = 1.0
		_click_env *= 0.992
		var click := w * _click_env * _click_env
		_motor_phase += TAU * 120.0 * (0.5 + 0.5 * run) * dt
		var motor := sin(_motor_phase) * 0.35 + sin(_motor_phase * 2.0) * 0.15 + sin(_motor_phase * 3.0) * 0.08
		var proj := (click * 0.55 + _noise_lp * 0.5 + motor * 0.12) * run * projector_loudness
		# clock tick: a tiny woodblock click once per second
		_tick_env *= 0.985
		var tick := sin(_t * TAU * 1800.0) * _tick_env * _tick_env * clock_tick_loudness
		var tone := _noise_lp2 * room_tone_loudness * 3.0
		var s := proj + tick + tone
		buf[i] = Vector2(s, s * 0.9 + click * 0.05 * run * projector_loudness)
	_amb_playback.push_buffer(buf)
