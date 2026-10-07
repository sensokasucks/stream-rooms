class_name StageCurtain
extends Node3D
## A red velvet stage curtain in front of the main screen: two panels that draw apart
## (stage_curtain.gdshader does the folds and the gathering), a pelmet with swags, gold
## fringe and tassels, an optional hanging sign, a spotlight and sounds for the reveal.
## Attached by RoomHost to rooms with a main screen. State lives in AppState (B / Shift+B,
## the Room tab, Stream Core's !curtain); this node animates it and reports when the screen
## is actually hidden (AppState.set_curtain_covering).
## Placement: in front of the screen, or on a CURTAIN_Main marker if the room has one
## (bottom centre of the opening, +Z towards the audience; its X scale = opening width).

const SHADER: Shader = preload("res://core/stage_curtain.gdshader")
const GATHER: float = 0.14
const GOLD: Color = Color(0.85, 0.66, 0.25)
## Spotlight energy: a soft wash while the curtain is closed, full for the reveal.
const WASH: float = 4.0
const SHOW: float = 14.0

## Distance in front of the screen (metres).
@export var offset: float = 0.3
@export var close_time: float = 1.6
@export var open_time: float = 2.4
@export var roll_time: float = 2.4

var _panels: Array[ShaderMaterial] = []
var _open: float = 1.0
var _last_open: float = 1.0
var _motion: float = 0.0
var _tween: Tween
var _show: Tween
var _half: float = 4.0
var _height: float = 5.0
var _sign: Node3D
var _sign_label: Label3D
var _sign_board: MeshInstance3D
var _spot: SpotLight3D
var _audio: AudioStreamPlayer
var _pelmet_mat: StandardMaterial3D


## screen: the room's main screen. room: for markers (CURTAIN_Main, REPLY / CHAT screens).
func setup(room: Room, screen: MeshInstance3D) -> void:
	var f := _frame(room, screen)
	global_transform = Transform3D(Basis(f["across"], Vector3.UP, f["normal"]), f["origin"])
	_half = float(f["half"])
	_height = float(f["height"])
	_build(float(f["pelmet"]), float(f["drop"]))
	_open = 0.0 if AppState.is_curtain_closed() else 1.0
	_last_open = _open
	_apply()
	_refresh_enabled()
	AppState.set_curtain_present(self, visible)
	AppState.set_curtain_covering(AppState.is_curtain_closed() and visible)
	if AppState.is_curtain_closed():
		_spot.visible = true
		_spot.light_energy = WASH


func _ready() -> void:
	EventBus.curtain_changed.connect(_on_curtain)
	EventBus.setting_changed.connect(_on_setting_changed)


func _exit_tree() -> void:
	EventBus.curtain_changed.disconnect(_on_curtain)
	EventBus.setting_changed.disconnect(_on_setting_changed)
	if _show and _show.is_valid() and AppState.is_show_dimmed():
		AppState.set_show_dimmed(false)
	AppState.set_curtain_present(self, false)


func _process(delta: float) -> void:
	var speed := absf(_open - _last_open) / maxf(delta, 0.0001)
	_last_open = _open
	_motion = maxf(_motion - delta * 0.8, clampf(speed * 0.9, 0.0, 1.0))
	for m in _panels:
		m.set_shader_parameter("open_amount", _open)
		m.set_shader_parameter("motion", _motion)


## 0 = closed, 1 = open (for tests).
func get_open_amount() -> float:
	return _open


# ── Moving ───────────────────────────────────────────────────
func _on_curtain(closed: bool, style: String) -> void:
	if not visible:
		return
	if _show and _show.is_valid():
		_show.kill()
		AppState.set_show_dimmed(false)
		_spot_to(0.0, 0.3)
	if style == "instant":
		_stop_tween()
		_open = 0.0 if closed else 1.0
		AppState.set_curtain_covering(closed)
		_spot_to(WASH if closed else 0.0, 0.01)
		return
	if closed:
		AppState.set_curtain_covering(true)
		_move_to(0.0, close_time)
		_spot_to(WASH, 1.2)
		return
	if style == "reveal":
		_reveal()
		return
	_move_to(1.0, open_time)
	AppState.set_curtain_covering(false)
	_spot_to(0.0, 1.5)


func _move_to(target: float, seconds: float) -> Tween:
	_stop_tween()
	var speed := clampf(float(AppState.get_setting("curtain_speed")), 0.25, 4.0)
	var dur := seconds / speed * absf(target - _open)
	if dur < 0.05:
		_open = target
		return null
	_play(CurtainSounds.swish(maxf(dur, 0.6)), 0.0)
	_tween = create_tween()
	if target > _open:     # opening: a little overshoot, then it settles
		_tween.tween_property(self, "_open", target, dur).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		_tween.tween_property(self, "_open", target, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return _tween


func _stop_tween() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()


## Lights down, spotlight on the curtain, drum roll, crash, the curtain sweeps open, lights up.
func _reveal() -> void:
	var lights := bool(AppState.get_setting("curtain_show_lights"))
	_show = create_tween()
	if _open > 0.02:          # open already: close first
		AppState.set_curtain_covering(true)
		var speed := clampf(float(AppState.get_setting("curtain_speed")), 0.25, 4.0)
		_move_to(0.0, close_time)
		_show.tween_interval(close_time / speed * _open + 0.4)
	_show.tween_callback(func() -> void:
		if lights:
			AppState.set_show_dimmed(true)
			_spot_to(SHOW, 0.8)
		_play(CurtainSounds.drum_roll(roll_time), 0.0))
	_show.tween_interval(roll_time)
	_show.tween_callback(func() -> void:
		AppState.set_curtain_covering(false)
		_move_to(1.0, open_time * 1.1))
	var speed2 := clampf(float(AppState.get_setting("curtain_speed")), 0.25, 4.0)
	_show.tween_interval(open_time * 1.1 / speed2 + 0.5)
	_show.tween_callback(func() -> void:
		_spot_to(0.0, 1.2)
		AppState.set_show_dimmed(false))


func _spot_to(energy: float, seconds: float) -> void:
	if _spot == null:
		return
	_spot.visible = true
	var tw := create_tween()
	tw.tween_property(_spot, "light_energy", energy, seconds)
	if energy <= 0.0:
		tw.tween_callback(func() -> void: _spot.visible = false)


func _play(stream: AudioStream, _delay: float) -> void:
	var vol := clampf(float(AppState.get_setting("curtain_sound")), 0.0, 1.0)
	if vol <= 0.001 or _audio == null:
		return
	# a fresh one-shot player per sound: swapping the stream of a player the audio thread is
	# still mixing is avoided entirely
	print("[audio] curtain sound ", stream.get_length(), " s")
	if _audio.playing:
		var old := _audio
		var tw := create_tween()
		tw.tween_property(old, "volume_db", -60.0, 0.15)
		tw.tween_callback(old.queue_free)
		_audio = AudioStreamPlayer.new()
		_audio.bus = &"Master"
		add_child(_audio)
	_audio.stream = stream
	_audio.volume_db = linear_to_db(vol)
	_audio.play()


func _apply() -> void:
	for m in _panels:
		m.set_shader_parameter("open_amount", _open)
	_update_sign()


# ── Settings ─────────────────────────────────────────────────
func _on_setting_changed(key: String, _value: Variant) -> void:
	match key:
		"curtain_enabled":
			_refresh_enabled()
		"curtain_color":
			var c: Color = AppState.get_setting("curtain_color")
			for m in _panels:
				m.set_shader_parameter("velvet", c)
			if _pelmet_mat:
				_pelmet_mat.albedo_color = c
		"curtain_sign":
			_update_sign()


func _refresh_enabled() -> void:
	var on := bool(AppState.get_setting("curtain_enabled"))
	visible = on
	AppState.set_curtain_present(self, on)
	if not on and AppState.is_curtain_closed():
		AppState.set_curtain(false, "instant")


func _update_sign() -> void:
	if _sign == null:
		return
	var text := String(AppState.get_setting("curtain_sign")).strip_edges()
	_sign.visible = text != ""
	_sign_label.text = text


# ── Building ─────────────────────────────────────────────────
## Where the curtain goes: origin = bottom centre of the curtain, in front of the screen.
func _frame(room: Room, screen: MeshInstance3D) -> Dictionary:
	var aabb := screen.get_aabb()
	var xf := screen.global_transform
	var center := xf * aabb.get_center()
	var normal := Vector3.ZERO
	if screen.mesh and screen.mesh.get_surface_count() > 0:
		var normals: Variant = screen.mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
		if normals is PackedVector3Array and not (normals as PackedVector3Array).is_empty():
			normal = (xf.basis * (normals as PackedVector3Array)[0]).normalized()
	if normal == Vector3.ZERO:
		normal = (xf.basis * Vector3.BACK).normalized()
	normal.y = 0.0
	normal = normal.normalized() if normal.length() > 0.01 else Vector3.BACK
	var across := (-normal).cross(Vector3.UP).normalized()    # a viewer's right, facing the screen
	var box := xf * aabb
	var sw := absf(box.size.dot(across.abs()))
	var sh := box.size.y
	var top := box.end.y
	var bottom := box.position.y
	var origin_center := center
	var marker := room.find_child("CURTAIN_Main", true, false) as Node3D
	if marker:
		var mb := marker.global_basis
		normal = mb.z.normalized()
		across = mb.x.normalized()
		origin_center = marker.global_position + Vector3.UP * sh * 0.5
		bottom = marker.global_position.y
		top = bottom + sh
	# wide enough that the gathered panels clear the picture, even from a low side camera
	var half := sw / (2.0 * (1.0 - GATHER)) * 1.08
	# pelmet: its scallops end just above the picture; it hides the curtain track
	var pelmet := clampf(sh * 0.13, 0.22, 0.9)
	var drop := pelmet * 0.35
	var reply := room.get_reply_screen_marker()
	if reply:
		var reply_bottom := reply.global_position.y - room.reply_screen_size.y
		if reply_bottom > top:
			pelmet = clampf(minf(pelmet, (reply_bottom - top - 0.05) / 1.35), 0.12, pelmet)
			drop = pelmet * 0.35
	var pelmet_bottom := top + drop + 0.02
	var curtain_top := pelmet_bottom + pelmet * 0.45
	# the hem: down to the floor when there's one close below, never over a chat screen
	var floor_y := bottom - clampf(sh * 0.2, 0.3, 1.2)
	var chat := room.get_chat_screen_marker()
	if chat and chat.global_position.y <= bottom + 0.05:
		floor_y = maxf(floor_y, chat.global_position.y + 0.03)
	else:
		var hit: Variant = _floor_below(Vector3(origin_center.x, bottom, origin_center.z) + normal * offset, 3.0)
		if hit != null and float(hit) < bottom:
			floor_y = float(hit)
	var origin := Vector3(origin_center.x, floor_y, origin_center.z) + normal * offset
	return {"origin": origin, "normal": normal, "across": across, "half": half,
		"height": curtain_top - floor_y, "pelmet": pelmet, "drop": drop}


func _floor_below(from: Vector3, reach: float) -> Variant:
	if not is_inside_tree():
		return null
	var space := get_world_3d().direct_space_state
	if space == null:
		return null
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * reach))
	if hit.is_empty():
		return null
	return (hit["position"] as Vector3).y


func _build(pelmet: float, drop: float) -> void:
	var c: Color = AppState.get_setting("curtain_color")
	for side in [-1.0, 1.0]:
		var mi := MeshInstance3D.new()
		mi.name = "PanelLeft" if side < 0.0 else "PanelRight"
		mi.mesh = _grid(56, 28, side > 0.0)
		mi.custom_aabb = AABB(Vector3(-_half * 1.1, -0.5, -1.0), Vector3(_half * 2.2, _height + 1.0, 2.0))
		mi.position.z = 0.0 if side > 0.0 else 0.03       # the panels overlap a little in the middle
		var m := ShaderMaterial.new()
		m.shader = SHADER
		m.set_shader_parameter("half_width", _half)
		m.set_shader_parameter("height", _height)
		m.set_shader_parameter("side", side)
		m.set_shader_parameter("gather", GATHER)
		m.set_shader_parameter("folds", clampf(round(_half * 2.4), 8.0, 30.0))
		m.set_shader_parameter("fold_depth", clampf(_half * 0.016, 0.04, 0.12))
		m.set_shader_parameter("velvet", c)
		m.set_shader_parameter("trim", GOLD)
		mi.material_override = m
		add_child(mi)
		_panels.append(m)
	_build_pelmet(pelmet, drop)
	_build_sign()
	_spot = SpotLight3D.new()
	_spot.light_color = Color(1.0, 0.93, 0.8)
	_spot.light_energy = 0.0
	_spot.shadow_enabled = false
	_spot.visible = false
	var dist := maxf(_half * 1.6, 6.0)
	_spot.spot_range = dist * 2.5
	_spot.spot_angle = clampf(rad_to_deg(atan(_half * 1.1 / dist)), 10.0, 70.0)
	_spot.spot_attenuation = 0.5
	add_child(_spot)
	var at := Vector3(0, _height * 0.5 + dist * 0.35, dist)
	_spot.transform = Transform3D(Basis.looking_at(Vector3(0, _height * 0.45, 0) - at, Vector3.UP), at)
	_audio = AudioStreamPlayer.new()
	_audio.bus = &"Master"
	add_child(_audio)


## Flat grid; the shader places the vertices from UV. flip: the right panel is laid out
## mirrored, so its triangles wind the other way to keep the front face towards the audience.
func _grid(cols: int, rows: int, flip: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in rows + 1:
		for i in cols + 1:
			var u := float(i) / cols
			var v := float(j) / rows
			st.set_uv(Vector2(u, v))
			st.set_normal(Vector3.BACK)
			st.add_vertex(Vector3(u, v, 0))
	for j in rows:
		for i in cols:
			var a := j * (cols + 1) + i
			var b := a + 1
			var cc := a + cols + 1
			var d := cc + 1
			if flip:
				st.add_index(a)
				st.add_index(b)
				st.add_index(cc)
				st.add_index(b)
				st.add_index(d)
				st.add_index(cc)
			else:
				st.add_index(a)
				st.add_index(cc)
				st.add_index(b)
				st.add_index(b)
				st.add_index(cc)
				st.add_index(d)
	return st.commit()


## The pelmet (valance) across the top: velvet swags with gold fringe and tassels.
func _build_pelmet(h: float, drop: float) -> void:
	var width := _half * 2.0 + 0.3
	var swags := clampi(int(round(width / 1.6)), 3, 9)
	var top := _height + h * 0.55
	var base := _height - h * 0.45          # straight bottom edge; swags hang below it
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cols := swags * 16
	var rows := 6
	var fringe := SurfaceTool.new()
	fringe.begin(Mesh.PRIMITIVE_TRIANGLES)
	var fringe_len := h * 0.18
	for i in cols + 1:
		var u := float(i) / cols
		var x := -width * 0.5 + u * width
		var sw := sin(PI * fposmod(u * swags, 1.0))
		var bottom := base - drop * sw
		var depth := 0.12 + 0.06 * sw
		for j in rows + 1:
			var v := float(j) / rows
			var y := lerpf(bottom, top, v)
			# swag folds: cloth bulges towards the audience, most at the low point
			var z := depth + 0.05 * sw * (1.0 - v) * sin(v * PI * 3.0)
			st.set_uv(Vector2(u * swags, v))
			st.set_normal(Vector3(0, -0.3 * (1.0 - v) * sw, 1).normalized())
			st.add_vertex(Vector3(x, y, z))
		# fringe below the scallop
		fringe.set_uv(Vector2(u * swags * 40.0, 0))
		fringe.set_normal(Vector3.BACK)
		fringe.add_vertex(Vector3(x, bottom + 0.01, depth + 0.01))
		fringe.set_uv(Vector2(u * swags * 40.0, 1))
		fringe.set_normal(Vector3.BACK)
		fringe.add_vertex(Vector3(x, bottom - fringe_len, depth + 0.02))
	for i in cols:
		for j in rows:
			var a := i * (rows + 1) + j
			var b := a + rows + 1
			st.add_index(a)
			st.add_index(b)
			st.add_index(a + 1)
			st.add_index(a + 1)
			st.add_index(b)
			st.add_index(b + 1)
		var f := i * 2
		fringe.add_index(f)
		fringe.add_index(f + 1)
		fringe.add_index(f + 2)
		fringe.add_index(f + 2)
		fringe.add_index(f + 1)
		fringe.add_index(f + 3)
	var pel := MeshInstance3D.new()
	pel.name = "Pelmet"
	pel.mesh = st.commit()
	_pelmet_mat = StandardMaterial3D.new()
	_pelmet_mat.albedo_color = AppState.get_setting("curtain_color")
	_pelmet_mat.roughness = 0.8
	_pelmet_mat.rim_enabled = true
	_pelmet_mat.rim = 0.6
	_pelmet_mat.rim_tint = 0.5
	_pelmet_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	pel.material_override = _pelmet_mat
	add_child(pel)
	var fr := MeshInstance3D.new()
	fr.name = "Fringe"
	fr.mesh = fringe.commit()
	var fm := StandardMaterial3D.new()
	fm.albedo_color = GOLD
	fm.metallic = 0.8
	fm.roughness = 0.35
	fm.albedo_texture = _fringe_texture()
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	fm.alpha_scissor_threshold = 0.5
	fm.cull_mode = BaseMaterial3D.CULL_DISABLED
	fr.material_override = fm
	add_child(fr)
	# gold rope along the top edge and a tassel at each swag joint
	var gold := StandardMaterial3D.new()
	gold.albedo_color = GOLD
	gold.metallic = 0.85
	gold.roughness = 0.3
	var rope := MeshInstance3D.new()
	var rm := BoxMesh.new()
	rm.size = Vector3(width, h * 0.07, 0.05)
	rope.mesh = rm
	rope.material_override = gold
	rope.position = Vector3(0, top - h * 0.04, 0.2)
	add_child(rope)
	for k in swags + 1:
		var x := -width * 0.5 + width * float(k) / swags
		var knob := MeshInstance3D.new()
		var sp := SphereMesh.new()
		sp.radius = h * 0.07
		sp.height = h * 0.14
		knob.mesh = sp
		knob.material_override = gold
		knob.position = Vector3(x, base - h * 0.02, 0.2)
		add_child(knob)
		var tassel := MeshInstance3D.new()
		var cy := CylinderMesh.new()
		cy.top_radius = h * 0.025
		cy.bottom_radius = h * 0.08
		cy.height = h * 0.35
		tassel.mesh = cy
		tassel.material_override = gold
		tassel.position = Vector3(x, base - h * 0.25, 0.2)
		add_child(tassel)


static var _fringe_tex: Texture2D


static func _fringe_texture() -> Texture2D:
	if _fringe_tex:
		return _fringe_tex
	var img := Image.create(16, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 16:
			# threads: thin vertical strands, a few shorter than others
			var strand := absf(float(x) - 7.5) < 3.0
			var len_ok := y < 32 - (x % 3) * 2
			var shade := 0.75 + 0.25 * sin(float(x) * 1.7)
			img.set_pixel(x, y, Color(shade, shade, shade, 1.0 if strand and len_ok else 0.0))
	_fringe_tex = ImageTexture.create_from_image(img)
	return _fringe_tex


## A board hanging from two gold cords in the middle of the closed curtain.
func _build_sign() -> void:
	_sign = Node3D.new()
	_sign.name = "Sign"
	add_child(_sign)
	var w := clampf(_half * 0.75, 1.2, 4.0)
	var hh := w * 0.28
	_sign.position = Vector3(0, _height * 0.62, 0.36)
	_sign_board = MeshInstance3D.new()
	var q := BoxMesh.new()
	q.size = Vector3(w, hh, 0.04)
	_sign_board.mesh = q
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.07, 0.05, 0.05)
	bm.roughness = 0.6
	_sign_board.material_override = bm
	_sign.add_child(_sign_board)
	var rim := MeshInstance3D.new()
	var rq := BoxMesh.new()
	rq.size = Vector3(w + 0.08, hh + 0.08, 0.03)
	rim.mesh = rq
	var gm := StandardMaterial3D.new()
	gm.albedo_color = GOLD
	gm.metallic = 0.85
	gm.roughness = 0.3
	rim.material_override = gm
	rim.position.z = -0.01
	_sign.add_child(rim)
	for sx in [-0.35, 0.35]:
		var cord := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.012
		cm.bottom_radius = 0.012
		var cord_len := _height - _sign.position.y - hh * 0.5
		cm.height = cord_len
		cord.mesh = cm
		cord.material_override = gm
		cord.position = Vector3(w * sx, hh * 0.5 + cord_len * 0.5, 0)
		_sign.add_child(cord)
	_sign_label = Label3D.new()
	_sign_label.font = SpeechBubble.shared_font()
	_sign_label.font_size = 96
	_sign_label.outline_size = 0
	_sign_label.modulate = Color(1.0, 0.86, 0.5)
	_sign_label.pixel_size = hh * 0.42 / 96.0
	_sign_label.width = w * 0.92 / _sign_label.pixel_size
	_sign_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sign_label.position.z = 0.025
	_sign.add_child(_sign_label)


func _physics_process(_delta: float) -> void:
	# the sign is only up while the curtain is (nearly) closed
	if _sign and _sign.visible:
		var a := clampf(1.0 - _open * 4.0, 0.0, 1.0)
		_sign.scale = Vector3.ONE * maxf(a, 0.001)
