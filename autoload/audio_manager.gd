extends Node
## AudioManager: owns the audio buses, per-room reverb and ambience, and
## mic-driven ducking of the video audio.
##
## Buses (created at startup):
##   Video     - file playback and captured tab audio (reverb + ducking live here)
##   Ambience  - room background loop
##   Mic       - microphone input, only analysed for ducking; never heard
##
## Starting the microphone can hang the whole game on some PCs (Windows' sound system never
## answers). So a marker file is written just before it starts and removed once it's running: if
## the game finds the marker at the next start, the last start hung there, and auto-duck is
## switched off instead of hanging again. "-- --no-mic" on the command line switches it off too.

const VIDEO_BUS: String = "Video"
const AMBIENCE_BUS: String = "Ambience"
const MIC_BUS: String = "Mic"
## How long the microphone must run before the start counts as fine.
const MIC_OK_AFTER_S: float = 3.0

## How long talking must stop before the video comes back up.
@export var duck_hold_s: float = 0.45
@export var duck_attack_db_per_s: float = 120.0
@export var duck_release_db_per_s: float = 30.0

var _reverb: AudioEffectReverb
# Old-speaker chain (before the reverb: the speaker sits in the room).
var _hp: AudioEffectHighPassFilter
var _lp: AudioEffectLowPassFilter
var _dist: AudioEffectDistortion
var _mono: AudioEffectStereoEnhance
var _flutter: AudioEffectChorus
var _speaker_fx: Array[AudioEffect] = []
var _room_info: RoomInfo
var _mic_capture: AudioEffectCapture
var _mic_player: AudioStreamPlayer
var _mic_marker: String = "user://mic_starting" + ("" if AppState.get_profile().is_empty() else "_" + AppState.get_profile())
var _ambience_player: AudioStreamPlayer

var _duck_gain_db: float = 0.0     # current ducking offset (0 or negative)
var _talking: bool = false
var _hold_timer: float = 0.0
var _level_db: float = -80.0
var _level_emit_timer: float = 0.0
## Curtain mute as a fade of the Video bus volume (0 = full, 1 = silent). Done with the bus
## volume rather than AudioServer.set_bus_mute: muting a bus that has a live stream generator
## and effects on it is one of the few things that runs into the audio driver mid-mix.
var _curtain_gain: float = 0.0
var _curtain_target: float = 0.0
const CURTAIN_FADE_S: float = 0.5


func _ready() -> void:
	_ensure_bus(VIDEO_BUS)
	_ensure_bus(AMBIENCE_BUS)
	_ensure_bus(MIC_BUS)
	var video_idx := AudioServer.get_bus_index(VIDEO_BUS)
	_build_speaker_chain(video_idx)
	_reverb = AudioEffectReverb.new()
	AudioServer.add_bus_effect(video_idx, _reverb)
	# Mic bus: analyse only. Effects run before the fader, so the capture still
	# sees the signal while the bus itself is silent.
	var mic_idx := AudioServer.get_bus_index(MIC_BUS)
	_mic_capture = AudioEffectCapture.new()
	_mic_capture.buffer_length = 0.2
	AudioServer.add_bus_effect(mic_idx, _mic_capture)
	AudioServer.set_bus_volume_db(mic_idx, -80.0)

	_ambience_player = AudioStreamPlayer.new()
	_ambience_player.bus = AMBIENCE_BUS
	add_child(_ambience_player)

	EventBus.setting_changed.connect(_on_setting_changed)
	EventBus.curtain_covering_changed.connect(func(_c: bool) -> void: _apply_curtain_mute())
	_apply_volumes()
	var hung := FileAccess.file_exists(_mic_marker)
	if hung or OS.get_cmdline_user_args().has("--no-mic"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_mic_marker))
		print("[audio] %s: auto-duck switched off" % ("the microphone hung the last start" if hung else "--no-mic"))
		AppState.set_setting("duck_enabled", false)     # (saved, so later starts skip it too)
		var why := "Starting the microphone froze the game last time" if hung else "Started without the microphone"
		get_tree().create_timer(4.0).timeout.connect(func() -> void:   # (once the panel can show it)
			EventBus.status_message.emit(why + ", so auto-duck is off now. Tick it again in the React tab to try again.", true))
	_update_mic_input()


## Stream sound off while the stage curtain hides the screen ("curtain_mute"): faded out and
## back in through the bus volume (see _curtain_gain).
func _apply_curtain_mute() -> void:
	var mute := AppState.is_curtain_covering() and bool(AppState.get_setting("curtain_mute"))
	_curtain_target = 1.0 if mute else 0.0
	print("[audio] curtain mute -> ", mute)


func _process(delta: float) -> void:
	if _curtain_gain != _curtain_target:
		_curtain_gain = move_toward(_curtain_gain, _curtain_target, delta / CURTAIN_FADE_S)
		_apply_volumes()
	if _mic_player and _mic_player.playing:
		_level_db = _read_mic_level_db()
	else:
		_level_db = -80.0
	_update_duck(_level_db, delta)
	_level_emit_timer -= delta
	if _level_emit_timer <= 0.0:
		_level_emit_timer = 0.1
		EventBus.mic_level_changed.emit(_level_db)


# ── Public API ───────────────────────────────────────────────
func apply_room(info: RoomInfo) -> void:
	_room_info = info
	_apply_speaker()
	_apply_reverb()
	_ambience_player.stop()
	_ambience_player.stream = info.ambience
	if info.ambience:
		_ambience_player.play()


func is_ducking() -> bool:
	return _talking


# ── Private ──────────────────────────────────────────────────
## Room reverb scaled by the "room_acoustics" setting:
## 0 = dry (no room sound), 1 = the room's own amount, 2 = exaggerated.
func _apply_reverb() -> void:
	if _room_info == null:
		return
	var amount: float = float(AppState.get_setting("room_acoustics"))
	var wet := clampf(_room_info.reverb_wet * amount, 0.0, 0.8)
	_reverb.wet = wet
	# Above 100% the space also sounds a bit bigger, not just louder.
	_reverb.room_size = clampf(_room_info.reverb_room_size * (0.7 + 0.3 * maxf(amount, 1.0)), 0.0, 1.0)
	_reverb.damping = _room_info.reverb_damping
	_reverb.dry = 1.0 - minf(wet * 0.25, 0.2)   # keep overall loudness steady as the room gets louder
	_set_effect_enabled(_reverb, wet > 0.001)


## "Terrible speaker" character from the room (speaker_lofi) scaled by the "room_speaker"
## setting: band-limited (no bass, no treble), mono, slightly overdriven, with the
## pitch wobble ("flutter") of an old optical film soundtrack.
func _apply_speaker() -> void:
	var amount := 0.0
	if _room_info:
		amount = clampf(_room_info.speaker_lofi * float(AppState.get_setting("room_speaker")), 0.0, 1.0)
	var on := amount > 0.001
	for fx in _speaker_fx:
		_set_effect_enabled(fx, on)
	if not on:
		return
	_hp.cutoff_hz = lerpf(20.0, 420.0, amount)
	_hp.resonance = lerpf(0.5, 0.9, amount)
	_lp.cutoff_hz = 20000.0 * pow(3200.0 / 20000.0, amount)     # log sweep 20 kHz -> 3.2 kHz
	_lp.resonance = lerpf(0.5, 1.2, amount)                      # a honky cone resonance
	_dist.drive = 0.32 * amount
	_dist.post_gain = -4.0 * amount
	_mono.pan_pullout = 1.0 - amount
	_flutter.set_voice_depth_ms(0, 0.35 * amount)


func _build_speaker_chain(bus: int) -> void:
	_hp = AudioEffectHighPassFilter.new()
	_lp = AudioEffectLowPassFilter.new()
	_dist = AudioEffectDistortion.new()
	_dist.mode = AudioEffectDistortion.MODE_OVERDRIVE
	_dist.keep_hf_hz = 16000.0
	_mono = AudioEffectStereoEnhance.new()
	_flutter = AudioEffectChorus.new()
	_flutter.voice_count = 1
	_flutter.dry = 0.0
	_flutter.wet = 1.0
	_flutter.set_voice_delay_ms(0, 4.0)
	_flutter.set_voice_rate_hz(0, 5.5)
	_flutter.set_voice_level_db(0, 0.0)
	_flutter.set_voice_cutoff_hz(0, 16000.0)
	_flutter.set_voice_pan(0, 0.0)
	_speaker_fx = [_flutter, _hp, _lp, _dist, _mono]
	for fx in _speaker_fx:
		AudioServer.add_bus_effect(bus, fx)
		_set_effect_enabled(fx, false)


func _set_effect_enabled(fx: AudioEffect, on: bool) -> void:
	var bus := AudioServer.get_bus_index(VIDEO_BUS)
	for i in AudioServer.get_bus_effect_count(bus):
		if AudioServer.get_bus_effect(bus, i) == fx:
			AudioServer.set_bus_effect_enabled(bus, i, on)
			return


func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	AudioServer.add_bus()
	var idx := AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, "Master")


func _update_mic_input() -> void:
	var want: bool = AppState.get_setting("duck_enabled")
	var input_on: bool = ProjectSettings.get_setting("audio/driver/enable_input", false)
	if want and input_on:
		if AudioServer.get_driver_name() == "Dummy":
			print("[audio] no sound device: auto-duck can't listen")
			EventBus.status_message.emit("No sound device here, so auto-duck can't hear you.", true)
			return
		var devices := AudioServer.get_input_device_list()
		if devices.size() <= 1 and (devices.is_empty() or devices[0] == "Default"):
			print("[audio] no microphone found: auto-duck can't listen")
			EventBus.status_message.emit("No microphone found, so auto-duck can't hear you.", true)
			return
		if _mic_player == null:
			_mic_player = AudioStreamPlayer.new()
			_mic_player.stream = AudioStreamMicrophone.new()
			_mic_player.bus = MIC_BUS
			add_child(_mic_player)
		if not _mic_player.playing:
			print("[audio] microphone on (", AudioServer.input_device, ")")
			var marker := FileAccess.open(_mic_marker, FileAccess.WRITE)
			if marker:
				marker.store_string("starting")
				marker.close()        # (written to disk now: if play() hangs, the next start finds it)
			_mic_player.play()
			get_tree().create_timer(MIC_OK_AFTER_S).timeout.connect(func() -> void:
				DirAccess.remove_absolute(ProjectSettings.globalize_path(_mic_marker)))
	elif _mic_player and _mic_player.playing:
		print("[audio] microphone off")
		_mic_player.stop()
		_mic_capture.clear_buffer()


func _read_mic_level_db() -> float:
	var n := _mic_capture.get_frames_available()
	if n <= 0:
		return _level_db
	var frames := _mic_capture.get_buffer(n)
	var sum := 0.0
	for f in frames:
		sum += (f.x * f.x + f.y * f.y) * 0.5
	var rms := sqrt(sum / float(n))
	return linear_to_db(maxf(rms, 0.00001))


## Separate from _process so it can be driven directly in tests.
func _update_duck(level_db: float, delta: float) -> void:
	var enabled: bool = AppState.get_setting("duck_enabled")
	var above: bool = enabled and level_db > float(AppState.get_setting("duck_threshold_db"))
	if above:
		_hold_timer = duck_hold_s
	else:
		_hold_timer = maxf(0.0, _hold_timer - delta)
	var talking := above or _hold_timer > 0.0
	if talking != _talking:
		_talking = talking
		EventBus.ducking_changed.emit(talking)
	var target: float = float(AppState.get_setting("duck_amount_db")) if talking else 0.0
	var rate := duck_attack_db_per_s if target < _duck_gain_db else duck_release_db_per_s
	var new_gain := move_toward(_duck_gain_db, target, rate * delta)
	if not is_equal_approx(new_gain, _duck_gain_db):
		_duck_gain_db = new_gain
		_apply_volumes()


func _apply_volumes() -> void:
	var vol: float = AppState.get_setting("volume")
	var lin := maxf(vol * (1.0 - _curtain_gain), 0.0001)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(VIDEO_BUS),
		maxf(linear_to_db(lin) + _duck_gain_db, -80.0))
	var amb: float = AppState.get_setting("ambience_volume")
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(AMBIENCE_BUS), linear_to_db(maxf(amb, 0.0001)))


func _on_setting_changed(key: String, _value: Variant) -> void:
	match key:
		"volume", "ambience_volume":
			_apply_volumes()
		"curtain_mute":
			_apply_curtain_mute()
		"room_acoustics":
			_apply_reverb()
		"room_speaker":
			_apply_speaker()
		"duck_enabled":
			_update_mic_input()
