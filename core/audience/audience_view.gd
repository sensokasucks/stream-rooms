class_name AudienceView
extends Node3D
## Draws the chat audience in the current room. Attached to the room by RoomHost and freed
## with it. The roster itself lives in AudienceManager; this node only shows it.
##
## Three kinds of seat (slots in this order):
##   - main seats (AudienceRow / AUDIENCE_ markers): a full silhouette each, with a name tag,
##     the chatter's picture and speech bubbles.
##   - crowd seats (the room's crowd_seats_file, e.g. the lecture hall's tiers, balcony and
##     gallery): a filler crowd drawn all at once by CrowdLayer. When the main seats are full,
##     chatters overflow into these; a crowd seat with a chatter in it gets a full silhouette
##     like a main seat, and only for as long as they sit there.
##   - presenter spots (PRESENTER_<n>): the chatter linked to that presenter (Presenters tab,
##     "Chat name"). Their commands and bubbles come from the podium; in silhouette mode the
##     presenter picture can take their colour and chat picture ("chat look").
##
## Performance: per frame, the seats are only revisited when the camera moves; bubbles that
## the camera can't see (off-screen or behind the balcony) aren't drawn, and far-away animated
## bubbles redraw at a lower rate.

const SILHOUETTE: Texture2D = preload("res://core/audience/silhouette.png")
const EMPTY_COLOR: Color = Color(0.6, 0.6, 0.66, 0.22)
const SPEAKER_COLOR_BOOST: float = 1.25
## Where the head is in silhouette.png (pixels): centre and the radius inside the rim.
const HEAD_CENTER: Vector2 = Vector2(128, 94)
const HEAD_RADIUS: float = 56.0
const AVATAR_PX: int = 128
## How often bubbles check whether the camera can see them (seconds).
const BUBBLE_CHECK: float = 0.2
## Newer bubbles win: an older bubble whose picture overlaps a newer one on screen is pushed up,
## and one that would have to move more than this many of its own heights fades out early.
const NUDGE_GAP_PX: float = 6.0
const NUDGE_MAX_HEIGHTS: float = 2.5
## Name tags fade out between these camera distances (metres), so wide shots don't fill with tags.
@export var tag_fade_start: float = 16.0
@export var tag_fade_end: float = 28.0

## Height of the silhouette (head-and-shoulders bust), metres.
@export var bust_height: float = 0.78
## How far the bust's bottom sits above the seat surface.
@export var bust_lift: float = 0.18
## Gap between the top of the head and the tail of a speech bubble.
@export var bubble_gap: float = 0.12
## Bubble size in metres per pixel at 100% bubble size.
@export var bubble_pixel_size: float = 0.0021
@export var fade_time: float = 0.35
## Silhouettes closer to the camera than this fade out, so heads in the front row
## don't block the view (they're fully visible again at near_fade_end).
@export var near_fade_start: float = 1.2
@export var near_fade_end: float = 2.6
## Bubbles and name tags grow with distance so they stay readable from far cameras:
## normal size up to this distance, then proportionally larger...
@export var readable_distance: float = 5.0
## ...up to this many times their normal size.
@export var max_distance_scale: float = 3.5
## Animated bubbles (GIF emotes) further than this from the camera redraw at far_bubble_fps.
@export var far_bubble_distance: float = 14.0
@export var far_bubble_fps: float = 12.0

var _seats: Array[Dictionary] = []
var _rich: Array[int] = []          # seats with nodes: main seats, presenter spots, chatters in crowd seats
var _bubbling: Array[int] = []      # seats with a message up (drawn, or waiting until the camera sees it)
var _crowd: CrowdLayer
var _presenter_slots: Dictionary = {}   # presenter n -> slot
var _presenter_nodes: Dictionary = {}   # presenter n -> Presenter
var _bounds: AABB = AABB()
var _last_cam: Transform3D = Transform3D()
var _dirty: bool = true
var _vis_clock: float = 0.0
var _light: float = -1.0


## Called by RoomHost. seats: main seat transforms (global); stage_point: middle of the main
## screen, so AudienceManager knows which seats are the front row; crowd: crowd seat
## transforms; presenters: Room.get_presenter_setups(); presenter_nodes: n -> Presenter.
## crowd_info: Room.get_crowd_seat_info() (level + facing per crowd seat, for the sections).
func setup(seats: Array[Transform3D], stage_point: Variant = null, crowd: Array[Transform3D] = [],
		presenters: Array[Dictionary] = [], presenter_size: Vector2 = Vector2.ONE, presenter_nodes: Dictionary = {},
		crowd_info: Array[Dictionary] = []) -> void:
	var spots: Array[Vector3] = []
	var kinds := PackedByteArray()
	for t in seats:
		var s := _new_seat("seat", t)
		_seats.append(s)
		_make_rich(_seats.size() - 1)
		spots.append(t.origin)
		kinds.append(AudienceManager.KIND_SEAT)
	if not crowd.is_empty():
		_crowd = CrowdLayer.new()
		_crowd.name = "Crowd"
		add_child(_crowd)
		_crowd.setup(crowd, bust_height, bust_lift, SILHOUETTE)
		for i in crowd.size():
			var c := _new_seat("crowd", crowd[i])
			c["crowd_i"] = i
			_seats.append(c)
			spots.append(crowd[i].origin)
			kinds.append(AudienceManager.KIND_CROWD)
	_presenter_nodes = presenter_nodes
	for p in presenters:
		var n := int(p["n"])
		var marker := p["marker"] as Node3D
		var b := marker.global_basis.orthonormalized()
		var sc := presenter_size.y * 0.98 / bust_height
		var origin := marker.global_position + b.z * 0.04 - Vector3.UP * bust_lift * sc
		var ps := _new_seat("presenter", Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * sc), origin))
		ps["n"] = n
		_seats.append(ps)
		var slot := _seats.size() - 1
		_make_rich(slot)
		_presenter_slots[n] = slot
		spots.append(origin)
		kinds.append(AudienceManager.KIND_PRESENTER)
		_mirror_presenter(slot)
	_bounds = _compute_bounds()
	AudienceManager.set_slot_kinds(kinds, _presenter_slots)
	_compute_sections(spots, kinds, stage_point, crowd_info)
	AudienceManager.set_seat_layout(spots, stage_point)
	AudienceManager.set_capacity(_seats.size())
	for i in _seats.size():
		_refresh_seat(i, false)
	_apply_visibility()


func _ready() -> void:
	EventBus.audience_seated.connect(_on_seated)
	EventBus.audience_left.connect(_on_left)
	EventBus.audience_spoke.connect(_on_spoke)
	EventBus.emote_ready.connect(_on_emote_ready)
	EventBus.audience_updated.connect(_on_updated)
	EventBus.setting_changed.connect(_on_setting_changed)


func _exit_tree() -> void:
	EventBus.emote_ready.disconnect(_on_emote_ready)
	EventBus.audience_updated.disconnect(_on_updated)
	EventBus.audience_seated.disconnect(_on_seated)
	EventBus.audience_left.disconnect(_on_left)
	EventBus.audience_spoke.disconnect(_on_spoke)
	EventBus.setting_changed.disconnect(_on_setting_changed)


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var xf := cam.global_transform
	if _dirty or not xf.is_equal_approx(_last_cam):
		_last_cam = xf
		_dirty = false
		var names_on := bool(AppState.get_setting("audience_names"))
		for i in _rich:
			_update_view(i, xf.origin, names_on)
	if _crowd:
		var room := get_parent() as Room
		var level := room._level if room else 1.0
		if not is_equal_approx(level, _light):
			_light = level
			_crowd.set_light_level(level)
	_vis_clock -= delta
	var check := _vis_clock <= 0.0
	if check:
		_vis_clock = BUBBLE_CHECK
	for i in _bubbling.duplicate():
		var s: Dictionary = _seats[i]
		s["timer"] = float(s["timer"]) - delta
		if float(s["timer"]) <= 0.0:
			_next_bubble(i)
			continue
		if check:
			_check_bubble(i, cam)
		elif bool(s["throttle"]) and s["viewport"] != null:
			s["anim_clock"] = float(s["anim_clock"]) - delta
			if float(s["anim_clock"]) <= 0.0:
				s["anim_clock"] = 1.0 / maxf(far_bubble_fps, 1.0)
				(s["viewport"] as SubViewport).render_target_update_mode = SubViewport.UPDATE_ONCE
	if check and _bubbling.size() > 1:
		_nudge_bubbles(cam)


## Fades a silhouette next to the camera and sizes its name tag and bubble for the distance.
func _update_view(i: int, cam_pos: Vector3, names_on: bool) -> void:
	var s: Dictionary = _seats[i]
	var root: Node3D = s["root"]
	var sc: float = s["scale"]
	var head := root.global_position + Vector3.UP * (bust_lift + bust_height) * sc
	var d := head.distance_to(cam_pos)
	var near := smoothstep(near_fade_start * sc, near_fade_end * sc, d)
	s["fade"] = lerpf(0.08, 1.0, near)
	_paint(i)
	var grow := clampf(d / readable_distance, 1.0, max_distance_scale)
	var label: Label3D = s["label"]
	var far_fade := 1.0 - smoothstep(tag_fade_start, tag_fade_end, d)
	label.visible = names_on and bool(s["seated"]) and bool(s["show"]) and not bool(s["active"]) and near > 0.5 and far_fade > 0.03
	label.modulate.a = far_fade
	label.outline_modulate.a = far_fade
	label.scale = Vector3.ONE * grow
	(s["holder"] as Node3D).scale = Vector3.ONE * grow


func _paint(i: int) -> void:
	var s: Dictionary = _seats[i]
	if not bool(s["rich"]):
		return
	var c: Color = s["color"]
	var fade: float = s["fade"]
	(s["sprite"] as Sprite3D).modulate = Color(c.r, c.g, c.b, c.a * fade)
	(s["head"] as Sprite3D).modulate = Color(1, 1, 1, fade)


func _set_color(i: int, c: Color) -> void:
	_seats[i]["color"] = c
	_paint(i)


# ── Public API (used by the room's ReactionLayer) ───────────
func get_seat_count() -> int:
	return _seats.size()


func is_seat_taken(slot: int) -> bool:
	return slot >= 0 and slot < _seats.size() and bool(_seats[slot]["seated"])


## Centre of the silhouette's head (global), where things hit and bubbles float from.
func get_seat_head(slot: int) -> Vector3:
	if slot < 0 or slot >= _seats.size():
		return global_position
	var s: Dictionary = _seats[slot]
	var up := Vector3(0, (bust_lift + bust_height * 0.82) * float(s["scale"]), 0)
	if bool(s["rich"]):
		return (s["root"] as Node3D).global_transform * up
	return (s["xf"] as Transform3D).origin + up


func get_seat_scale(slot: int) -> float:
	return float(_seats[slot]["scale"]) if slot >= 0 and slot < _seats.size() else 1.0


## Box around every audience seat (global; main and crowd seats, not presenter spots), for
## effects that cover the whole audience.
func get_seats_bounds() -> AABB:
	return _bounds


## How many filler people are showing (for tests and the Audience tab).
func get_filler_count() -> int:
	var n := _crowd.get_filler_count() if _crowd and _crowd.visible else 0
	for i in _rich:
		if bool(_seats[i].get("filler", false)):
			n += 1
	return n


## Moves one person's silhouette: "wiggle", "jump", "wave", "spin", "flinch", "dance" or "cheer".
func play_motion(slot: int, style: String, seconds: float) -> void:
	if slot < 0 or slot >= _seats.size() or not bool(_seats[slot]["rich"]):
		return
	var s: Dictionary = _seats[slot]
	var root: Node3D = s["root"]
	var spr: Sprite3D = s["sprite"]
	var base: Vector3 = s["base"]
	var sc: float = float(s["scale"])
	var old: Tween = s["motion"]
	if old and old.is_valid():
		old.kill()
	root.position = base
	spr.scale = Vector3.ONE
	var tw := create_tween()
	s["motion"] = tw
	seconds = clampf(seconds, 0.2, 20.0)
	match style:
		"jump", "wave":
			var hops := maxi(int(seconds / 0.45), 1) if style == "jump" else 1
			var h := (0.22 if style == "jump" else 0.3) * sc
			for i in hops:
				tw.tween_property(root, "position", base + Vector3.UP * h, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
				tw.tween_property(root, "position", base, 0.22).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		"spin":
			var turns := maxi(int(seconds / 0.5), 1)
			for i in turns:
				tw.tween_property(spr, "scale:x", -1.0, 0.25)
				tw.tween_property(spr, "scale:x", 1.0, 0.25)
		"flinch":
			tw.set_parallel(true)
			tw.tween_property(root, "position", base + Vector3.DOWN * 0.1 * sc, 0.08)
			tw.tween_property(spr, "scale", Vector3(1.08, 0.9, 1.0), 0.08)
			tw.chain().tween_property(root, "position", base, 0.45).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
			tw.tween_property(spr, "scale", Vector3.ONE, 0.45).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		"dance":     # bob and sway to the beat
			var beats := maxi(int(seconds / 0.3), 2)
			for i in beats:
				var side := Vector3.RIGHT * (0.09 if i % 2 == 0 else -0.09) * sc
				tw.tween_property(root, "position", base + side + Vector3.UP * 0.1 * sc, 0.15).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
				tw.tween_property(root, "position", base + side * 0.5, 0.15).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
			tw.tween_property(root, "position", base, 0.15)
		"cheer":
			tw.tween_property(root, "position", base + Vector3.UP * 0.32 * sc, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			var bounces := maxi(int((seconds - 0.5) / 0.3), 1)
			for i in bounces:
				tw.tween_property(root, "position", base + Vector3.UP * 0.4 * sc, 0.15)
				tw.tween_property(root, "position", base + Vector3.UP * 0.32 * sc, 0.15)
			tw.tween_property(root, "position", base, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		_:   # wiggle: side to side
			var n := maxi(int(seconds / 0.2), 2)
			var side := Vector3.RIGHT * 0.07 * sc
			for i in n:
				tw.tween_property(root, "position", base + (side if i % 2 == 0 else -side), 0.1).set_trans(Tween.TRANS_SINE)
			tw.tween_property(root, "position", base, 0.1)


## The whole filler crowd moves at once (crowd-wide reactions: dance, cheer ...).
func play_filler_motion(style: String, seconds: float) -> void:
	if _crowd and _crowd.visible:
		_crowd.play_motion(style, seconds)
	for i in _rich:
		if bool(_seats[i].get("filler", false)):
			var delay := randf() * 0.25
			get_tree().create_timer(delay).timeout.connect(func() -> void:
				if is_inside_tree():
					play_motion(i, style, seconds))


## A wave that rolls across every seat (left to right as the audience sees the stage),
## the filler crowd included.
func play_wave(speed: float, stage_point: Vector3) -> void:
	var order: Array[int] = []
	for i in _rich:
		if String(_seats[i]["kind"]) != "presenter":
			order.append(i)
	# sort by position along the row direction (perpendicular to "towards the stage")
	var towards := stage_point - _bounds.get_center()
	towards.y = 0.0
	var across := towards.normalized().cross(Vector3.UP) if towards.length() > 0.01 else Vector3.RIGHT
	var lo := INF
	var hi := -INF
	for i in _seats.size():
		if String(_seats[i]["kind"]) == "presenter":
			continue
		var d := get_seat_head(i).dot(across)
		lo = minf(lo, d)
		hi = maxf(hi, d)
	if lo == INF:
		return
	speed = clampf(speed, 0.2, 4.0)
	for i in order:
		var delay := (get_seat_head(i).dot(across) - lo) / (4.0 * speed)
		get_tree().create_timer(delay).timeout.connect(func() -> void:
			if is_inside_tree():
				play_motion(i, "wave", 0.4))
	if _crowd and _crowd.visible:
		_crowd.play_wave(speed, across, lo, hi)


## Holds up a sign over the seat (the "!sign" reaction): a white board with a coloured rim.
func hold_sign(slot: int, text: String, color: Color, seconds: float) -> void:
	if slot < 0 or slot >= _seats.size() or not bool(_seats[slot]["rich"]):
		return
	var s: Dictionary = _seats[slot]
	var old: Variant = s.get("sign")
	if is_instance_valid(old):
		(old as Node).queue_free()
	var sc := float(s["scale"])
	var chars := clampi(text.length(), 3, 60)
	var lines := 1 if chars <= 16 else (2 if chars <= 34 else 3)
	var per_line := ceili(float(chars) / float(lines))
	var w := clampf(float(per_line) * 0.085 + 0.3, 0.6, 1.8) * sc
	var h := (0.16 + 0.15 * lines) * sc
	var sign_root := Node3D.new()
	sign_root.position.y = 0.25 * sc + h * 0.5
	(s["holder"] as Node3D).add_child(sign_root)
	s["sign"] = sign_root
	var board := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(w, h)
	board.mesh = q
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.no_depth_test = true
	mat.render_priority = 11
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = _sign_texture(color)
	board.material_override = mat
	board.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sign_root.add_child(board)
	var l := Label3D.new()
	l.text = SafeText.clean(text)
	l.font = SpeechBubble.shared_font()
	l.font_size = 52
	l.outline_size = 0
	l.modulate = Color(0.07, 0.07, 0.09)
	l.pixel_size = 0.0028 * sc
	l.width = (w * 0.9) / l.pixel_size
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.render_priority = 12
	l.double_sided = true
	sign_root.add_child(l)
	sign_root.scale = Vector3.ONE * 0.2
	var tw := create_tween()
	tw.tween_property(sign_root, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# a little wave while it's up
	var bobs := maxi(int(seconds / 1.2), 1)
	for i in bobs:
		tw.tween_property(sign_root, "position:y", sign_root.position.y + 0.05 * sc, 0.6).set_trans(Tween.TRANS_SINE)
		tw.tween_property(sign_root, "position:y", sign_root.position.y, 0.6).set_trans(Tween.TRANS_SINE)
	tw.tween_property(sign_root, "scale", Vector3.ONE * 0.01, 0.25)
	tw.tween_callback(sign_root.queue_free)
	play_motion(slot, "jump", 0.5)


static var _sign_textures: Dictionary = {}


static func _sign_texture(rim: Color) -> Texture2D:
	var key := rim.to_html(false)
	if _sign_textures.has(key):
		return _sign_textures[key]
	var W := 128
	var H := 64
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	var r := 10.0
	for y in H:
		for x in W:
			# rounded rectangle: distance to the inner box
			var dx := maxf(maxf(r - x, x - (W - 1 - r)), 0.0)
			var dy := maxf(maxf(r - y, y - (H - 1 - r)), 0.0)
			var d := sqrt(dx * dx + dy * dy)
			var a := clampf(r - d + 0.5, 0.0, 1.0)
			var edge := minf(minf(x, W - 1 - x), minf(y, H - 1 - y))
			var c := rim if (edge < 6.0 or d > r - 6.0) else Color(0.98, 0.97, 0.93)
			img.set_pixel(x, y, Color(c.r, c.g, c.b, a))
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_sign_textures[key] = tex
	return tex


## A prop for a while: "sleep" (dozes, Zzz), "snack" (popcorn) or "phone" (lit-up face).
func seat_prop(slot: int, prop: String, seconds: float) -> void:
	if slot < 0 or slot >= _seats.size() or not bool(_seats[slot]["rich"]):
		return
	var s: Dictionary = _seats[slot]
	var sc := float(s["scale"])
	var root: Node3D = s["root"]
	var holder: Node3D = s["holder"]
	seconds = clampf(seconds, 2.0, 60.0)
	var icon := Label3D.new()
	icon.font = SpeechBubble.shared_font()
	icon.font_size = 64
	icon.outline_size = 0
	icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	icon.no_depth_test = true
	icon.render_priority = 11
	icon.pixel_size = 0.0035 * sc
	var tw := create_tween()
	match prop:
		"sleep":
			icon.text = "💤"
			icon.position = Vector3(0.18 * sc, -0.05 * sc, 0)
			holder.add_child(icon)
			var base: Vector3 = s["base"]
			var sink := create_tween()
			sink.tween_property(root, "position", base + Vector3.DOWN * 0.08 * sc, 0.8).set_trans(Tween.TRANS_SINE)
			sink.tween_interval(maxf(seconds - 1.6, 0.2))
			sink.tween_property(root, "position", base, 0.8).set_trans(Tween.TRANS_SINE)
			var puffs := maxi(int(seconds / 1.5), 1)
			for i in puffs:
				tw.tween_property(icon, "position:y", 0.25 * sc, 1.2).from(-0.05 * sc)
				tw.parallel().tween_property(icon, "modulate:a", 0.0, 1.2).from(1.0)
				tw.tween_interval(0.3)
		"phone":
			icon.text = "📱"
			icon.pixel_size = 0.0028 * sc
			icon.position = Vector3(0.0, -0.42 * sc, 0.12 * sc)
			holder.add_child(icon)
			var glow := OmniLight3D.new()
			glow.light_color = Color(0.55, 0.75, 1.0)
			glow.omni_range = 0.9 * sc
			glow.light_energy = 0.0
			glow.shadow_enabled = false
			glow.position = Vector3(0, -0.3 * sc, 0.3 * sc)
			holder.add_child(glow)
			var gl := create_tween()
			gl.tween_property(glow, "light_energy", 1.4, 0.3)
			gl.tween_interval(maxf(seconds - 0.6, 0.2))
			gl.tween_property(glow, "light_energy", 0.0, 0.3)
			gl.tween_callback(glow.queue_free)
			tw.tween_interval(seconds)
		_:     # snack: popcorn bobbing up to the mouth
			icon.text = "🍿"
			icon.position = Vector3(0.14 * sc, -0.4 * sc, 0.1 * sc)
			holder.add_child(icon)
			var bites := maxi(int(seconds / 0.9), 1)
			for i in bites:
				tw.tween_property(icon, "position:y", -0.3 * sc, 0.25).set_trans(Tween.TRANS_SINE)
				tw.tween_property(icon, "position:y", -0.4 * sc, 0.35).set_trans(Tween.TRANS_SINE)
				tw.tween_interval(0.3)
	tw.tween_property(icon, "modulate:a", 0.0, 0.3)
	tw.tween_callback(icon.queue_free)


## A big bubble of text over a seat (the "big shout" reaction).
func shout(slot: int, text: String, color: Color, seconds: float) -> void:
	if slot < 0 or slot >= _seats.size() or not bool(_seats[slot]["rich"]):
		return
	var s: Dictionary = _seats[slot]
	# the previous shout may already have freed itself: check before touching it
	var old_tw: Variant = s.get("shout_tween")
	if old_tw is Tween and (old_tw as Tween).is_valid():
		(old_tw as Tween).kill()
	var old: Variant = s["shout"]
	if is_instance_valid(old):
		(old as Node).queue_free()
	var l := Label3D.new()
	l.text = SafeText.clean(text)
	l.font = SpeechBubble.shared_font()
	l.font_size = 72
	l.pixel_size = 0.004 * float(s["scale"])
	l.modulate = Color.WHITE
	l.outline_modulate = color
	l.outline_size = 22
	l.width = 900.0
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.render_priority = 12
	l.fixed_size = false
	l.position.y = 0.35 * float(s["scale"])
	(s["holder"] as Node3D).add_child(l)
	s["shout"] = l
	l.scale = Vector3.ONE * 0.3
	var tw := create_tween()
	tw.tween_property(l, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(maxf(seconds - 0.6, 0.3))
	tw.tween_property(l, "modulate:a", 0.0, 0.35)
	tw.parallel().tween_property(l, "outline_modulate:a", 0.0, 0.35)
	tw.tween_callback(l.queue_free)
	s["shout_tween"] = tw
	play_motion(slot, "jump", 0.5)


# ── Building ─────────────────────────────────────────────────
func _new_seat(kind: String, t: Transform3D) -> Dictionary:
	return {"kind": kind, "xf": t, "scale": t.basis.get_scale().x, "rich": false, "n": 0, "crowd_i": -1,
		"root": null, "base": Vector3.ZERO, "motion": null, "shout": null, "sprite": null, "head": null,
		"avatar": "", "label": null, "holder": null, "bubble_sprite": null, "viewport": null, "bubble": null,
		"queue": [], "timer": 0.0, "seated": false, "filler": false, "show": true, "look": false, "color": EMPTY_COLOR,
		"fade": 1.0, "parts": [], "waiting": [], "active": false, "pending": false, "animated": false,
		"vis": true, "vp_off": false, "throttle": false, "anim_clock": 0.0}


## Gives a seat its nodes: silhouette, picture, name tag and bubble anchor.
func _make_rich(i: int) -> void:
	var s: Dictionary = _seats[i]
	if bool(s["rich"]):
		return
	var t: Transform3D = s["xf"]
	var sc: float = s["scale"]
	var root := Node3D.new()
	root.name = "Seat%d" % i
	add_child(root)
	root.global_position = t.origin
	var spr := Sprite3D.new()
	spr.texture = SILHOUETTE
	spr.pixel_size = bust_height * sc / float(SILHOUETTE.get_height())
	spr.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	spr.shaded = false
	spr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	spr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	spr.position.y = (bust_lift + bust_height * 0.5) * sc
	spr.modulate = EMPTY_COLOR
	root.add_child(spr)
	# the chatter's profile picture, laid over the silhouette's head (inside its coloured rim)
	var head := Sprite3D.new()
	head.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	head.shaded = false
	head.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	head.render_priority = 1
	head.pixel_size = spr.pixel_size * (HEAD_RADIUS * 2.0) / float(AVATAR_PX)
	var sil_center := Vector2(SILHOUETTE.get_width(), SILHOUETTE.get_height()) * 0.5
	head.position.y = spr.position.y + (sil_center.y - HEAD_CENTER.y) * spr.pixel_size
	head.position.x = (HEAD_CENTER.x - sil_center.x) * spr.pixel_size
	head.visible = false
	root.add_child(head)
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 40
	label.pixel_size = 0.0022 * sc
	label.outline_size = 12
	label.outline_modulate = Color(0, 0, 0, 0.85)
	label.position.y = (bust_lift + bust_height + 0.07) * sc
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	label.visible = false
	root.add_child(label)
	var holder := Node3D.new()      # bubble anchor (tail tip); scaled with camera distance
	holder.position.y = (bust_lift + bust_height + bubble_gap) * sc
	root.add_child(holder)
	s["root"] = root
	s["base"] = root.position
	s["sprite"] = spr
	s["head"] = head
	s["label"] = label
	s["holder"] = holder
	s["rich"] = true
	s["color"] = EMPTY_COLOR
	s["fade"] = 1.0
	_rich.append(i)
	_dirty = true


## A chatter left a crowd seat: their nodes go (the filler person comes back).
func _drop_rich(i: int) -> void:
	var s: Dictionary = _seats[i]
	if not bool(s["rich"]):
		return
	_end_bubble(i, false)
	(s["queue"] as Array).clear()
	for key in ["motion", "shout_tween"]:
		var tw: Variant = s.get(key)
		if tw is Tween and (tw as Tween).is_valid():
			(tw as Tween).kill()
	(s["root"] as Node3D).queue_free()
	var fresh := _new_seat(String(s["kind"]), s["xf"])
	fresh["crowd_i"] = s["crowd_i"]
	_seats[i] = fresh
	_rich.erase(i)


## Presenter spot: the presenter's picture follows the spot's moves (jumps, dances ...).
func _mirror_presenter(slot: int) -> void:
	var s: Dictionary = _seats[slot]
	var p: Variant = _presenter_nodes.get(int(s["n"]))
	if p == null or not is_instance_valid(p):
		return
	var pic := (p as Presenter).get_picture()
	if pic == null:
		return
	var rt := RemoteTransform3D.new()
	rt.name = "PictureFollow"
	(s["root"] as Node3D).add_child(rt)
	rt.global_transform = pic.global_transform
	rt.remote_path = rt.get_path_to(pic)


## Sections for seating by platform (see AudienceManager): the main seats as four quadrants
## as the audience faces the stage (Q1 front left, Q2 front right, Q3 back left, Q4 back
## right) and the crowd seats as stadium sections: one per wall the seats face, numbered from
## the audience's left, round the back, to the right, per level (101.. lower tier, 201..
## balcony, 301.. gallery).
func _compute_sections(spots: Array[Vector3], kinds: PackedByteArray, stage_point: Variant, crowd_info: Array[Dictionary]) -> void:
	var n := spots.size()
	var sections := PackedStringArray()
	sections.resize(n)
	var info: Dictionary = {}
	var main: Array[int] = []
	var crowd: Array[int] = []
	var centre := Vector3.ZERO
	var count := 0
	for i in n:
		if kinds[i] == AudienceManager.KIND_SEAT:
			main.append(i)
		elif kinds[i] == AudienceManager.KIND_CROWD:
			crowd.append(i)
		if kinds[i] != AudienceManager.KIND_PRESENTER:
			centre += spots[i]
			count += 1
	if count == 0:
		AudienceManager.set_slot_sections(sections, info)
		return
	centre /= float(count)
	var stage: Vector3 = stage_point if stage_point is Vector3 else centre + Vector3(0, 0, -100.0)
	var a := Vector3(centre.x - stage.x, 0.0, centre.z - stage.z)      # stage -> audience
	a = a.normalized() if a.length() > 0.001 else Vector3.BACK
	var right := (-a).cross(Vector3.UP).normalized()                     # the audience's right
	# main seats: quadrants
	if not main.is_empty():
		var mc := Vector3.ZERO
		var depths: Array[float] = []
		for i in main:
			mc += spots[i]
			depths.append((spots[i] - stage).dot(a))
		mc /= float(main.size())
		var sorted := depths.duplicate()
		sorted.sort()
		@warning_ignore("integer_division")
		var median: float = sorted[sorted.size() / 2]
		var labels := {"Q1": "Front left", "Q2": "Front right", "Q3": "Back left", "Q4": "Back right"}
		for k in main.size():
			var i := main[k]
			var front := depths[k] < median - 0.01 or (sorted.size() < 4)
			var on_right := (spots[i] - mc).dot(right) >= 0.0
			var id := ("Q2" if on_right else "Q1") if front else ("Q4" if on_right else "Q3")
			sections[i] = id
		for id: String in labels.keys():
			info[id] = {"label": "%s (%s)" % [labels[id], id], "kind": AudienceManager.KIND_SEAT, "order": int(id.substr(1))}
	# crowd seats: group by level and by the way they face (one group per wall)
	if not crowd.is_empty():
		var groups: Dictionary = {}          # "level:bucket" -> [slot, ...]
		for k in crowd.size():
			var i := crowd[k]
			var meta: Dictionary = crowd_info[k] if k < crowd_info.size() else {}
			var level := int(meta.get("level", 1))
			var f: Vector3 = meta.get("facing", Vector3.ZERO)
			var bucket: int
			if f.length() > 0.1:
				bucket = int(round(rad_to_deg(atan2(f.x, f.z)) / 15.0))
			else:
				var d := spots[i] - centre
				bucket = 1000 + int(floor((rad_to_deg(atan2(d.dot(right), d.dot(a))) + 180.0) / 36.0))
			var key := "%d:%d" % [level, bucket]
			if not groups.has(key):
				groups[key] = []
			(groups[key] as Array).append(i)
		var per_level: Dictionary = {}       # level -> [[angle, key]]
		for key: String in groups.keys():
			var level := int(key.get_slice(":", 0))
			var mean := Vector3.ZERO
			for i: int in groups[key]:
				mean += spots[i]
			mean /= float((groups[key] as Array).size())
			var d := mean - centre
			var ang := atan2(d.dot(right), d.dot(a))       # -90° the audience's left, 0 the back, +90° the right
			if not per_level.has(level):
				per_level[level] = []
			(per_level[level] as Array).append([ang, key])
		for level: int in per_level.keys():
			var list: Array = per_level[level]
			list.sort_custom(func(x: Array, y: Array) -> bool: return float(x[0]) < float(y[0]))
			for idx in list.size():
				var id := str(level * 100 + idx + 1)
				for i: int in groups[list[idx][1]]:
					sections[i] = id
				var where: String = ["lower tier", "balcony", "gallery"][clampi(level - 1, 0, 2)]
				info[id] = {"label": "Section %s (%s)" % [id, where], "kind": AudienceManager.KIND_CROWD, "order": level * 100 + idx + 1}
	AudienceManager.set_slot_sections(sections, info)


func _compute_bounds() -> AABB:
	var box := AABB()
	var first := true
	for i in _seats.size():
		if String(_seats[i]["kind"]) == "presenter":
			continue
		var p := get_seat_head(i)
		box = AABB(p, Vector3.ZERO) if first else box.expand(p)
		first = false
	return box


func _refresh_seat(i: int, animate: bool) -> void:
	var s: Dictionary = _seats[i]
	var m := AudienceManager.get_seat_member(i)
	var kind := String(s["kind"])
	if kind == "crowd":
		_crowd.set_taken(int(s["crowd_i"]), not m.is_empty())
		if m.is_empty():
			_drop_rich(i)
			return
		if not bool(s["rich"]):
			_make_rich(i)
			s = _seats[i]
	var spr: Sprite3D = s["sprite"]
	var label: Label3D = s["label"]
	s["seated"] = not m.is_empty()
	s["filler"] = kind == "seat" and not bool(s["seated"]) and _main_filler(i)
	var target := EMPTY_COLOR
	if bool(s["filler"]):
		target = _filler_tint(i)
	if s["seated"]:
		target = (m["color"] as Color)
		label.text = _tag_text(m)
		label.modulate = m["color"]
	else:
		_clear_bubbles(i)
	if kind == "presenter":
		_update_presenter_look(i)
	_refresh_head(i, m)
	var show_seat := _seat_visible(i)
	var old_tw: Variant = s.get("color_tween")
	if old_tw is Tween and (old_tw as Tween).is_valid():
		(old_tw as Tween).kill()        # a newer change wins over a fade still running
	if animate:
		var tw := create_tween().set_parallel(true)
		s["color_tween"] = tw
		tw.tween_method(func(c: Color) -> void: _set_color(i, c), s["color"], target, fade_time)
		if s["seated"]:
			spr.scale = Vector3.ONE * 0.85
			tw.tween_property(spr, "scale", Vector3.ONE, fade_time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		spr.visible = show_seat if kind == "presenter" else true
		if not show_seat and kind != "presenter":
			tw.chain().tween_callback(func() -> void:
				if bool(_seats[i]["rich"]):
					(_seats[i]["sprite"] as Sprite3D).visible = _seat_visible(i))
	else:
		_set_color(i, target)
		spr.visible = show_seat
	_dirty = true


func _seat_visible(i: int) -> bool:
	var s: Dictionary = _seats[i]
	match String(s["kind"]):
		"presenter":
			return bool(s["look"])
		"crowd":
			return bool(s["seated"])
	return bool(s["seated"]) or bool(s.get("filler", false)) or bool(AppState.get_setting("audience_show_empty"))


## "Filler people in empty main seats": the same share of seats as the crowd fullness,
## picked the same way every time.
func _main_filler(i: int) -> bool:
	if not bool(AppState.get_setting("audience_fill_main")):
		return false
	return float(absi(hash(i * 104729 + 3)) % 10000) / 10000.0 < float(AppState.get_setting("audience_crowd_fill"))


func _filler_tint(i: int) -> Color:
	var c: Color = CrowdLayer.TINTS[absi(hash(i * 31 + 7)) % CrowdLayer.TINTS.size()]
	return Color(c.r * 0.85, c.g * 0.85, c.b * 0.85, 0.95)


## Presenter spot: in silhouette mode (with "chat look" on) the podium shows the linked
## chatter's silhouette, colour and picture in place of the plain presenter silhouette.
func _update_presenter_look(i: int) -> void:
	var s: Dictionary = _seats[i]
	var n := int(s["n"])
	var look := bool(s["seated"]) and bool(AppState.get_setting(AppState.presenter_key(n, "on"))) \
		and String(AppState.get_setting(AppState.presenter_key(n, "source"))) == "silhouette" \
		and bool(AppState.get_setting(AppState.presenter_key(n, "chat_look")))
	s["show"] = look
	if look != bool(s["look"]):
		s["look"] = look
		EventBus.presenter_look_changed.emit(n, look)
	(s["sprite"] as Sprite3D).visible = look
	if bool(s["rich"]) and not look:
		(s["head"] as Sprite3D).visible = false


func _apply_visibility() -> void:
	visible = bool(AppState.get_setting("audience_enabled"))
	if _crowd:
		_crowd.visible = bool(AppState.get_setting("audience_crowd"))
	for i in _rich:
		(_seats[i]["sprite"] as Sprite3D).visible = _seat_visible(i)
	_dirty = true


# ── Speech bubbles ───────────────────────────────────────────
func _on_spoke(slot: int, parts: Array) -> void:
	if slot < 0 or slot >= _seats.size() or not bool(_seats[slot]["rich"]):
		return
	var s: Dictionary = _seats[slot]
	if String(s["kind"]) == "presenter":
		var n := int(s["n"])
		if not bool(AppState.get_setting(AppState.presenter_key(n, "chat_bubbles"))):
			return
	for p: Variant in parts:          # start downloading emotes right away
		if p is Dictionary and (p as Dictionary).has("url"):
			EmoteCache.get_texture(String(p["url"]))
	var q: Array = s["queue"]
	q.append(parts)
	while q.size() > 3:
		q.pop_front()
	if not bool(s["active"]):
		_next_bubble(slot)
	elif float(s["timer"]) > 1.2 and q.size() > 0:
		s["timer"] = 1.2        # someone is typing fast: move the current bubble along


func _next_bubble(i: int) -> void:
	var s: Dictionary = _seats[i]
	var q: Array = s["queue"]
	if q.is_empty():
		_end_bubble(i, true)
		return
	var parts: Array = q.pop_front()
	var m := AudienceManager.get_seat_member(i)
	if m.is_empty():
		_clear_bubbles(i)
		return
	s["parts"] = parts
	s["active"] = true
	if not _bubbling.has(i):
		_bubbling.append(i)
	var seconds := float(AppState.get_setting("audience_bubble_s"))
	if not q.is_empty():
		seconds *= 0.6
	s["timer"] = seconds
	# the speaker's silhouette brightens while they talk
	var boosted := (m["color"] as Color) * SPEAKER_COLOR_BOOST
	_set_color(i, Color(boosted.r, boosted.g, boosted.b, 1.0))
	_dirty = true
	var cam := get_viewport().get_camera_3d()
	s["vis"] = cam == null or _bubble_seen(i, cam)
	if bool(s["vis"]):
		_show_bubble(i)
	else:
		s["pending"] = true     # drawn once the camera can see it (never, if it never does)


## Builds (if needed) and draws the seat's current message, with a little pop.
func _show_bubble(i: int) -> void:
	var s: Dictionary = _seats[i]
	s["pending"] = false
	if s["bubble_sprite"] == null:
		_make_bubble(i)
	_render_bubble(i)
	var spr: Sprite3D = s["bubble_sprite"]
	s["base_y"] = 0.1 * float(s["scale"]) if i % 2 == 1 else 0.0     # stagger neighbours a little
	s["nudge"] = 0.0
	s["born"] = Time.get_ticks_msec()
	spr.position.y = float(s["base_y"])
	spr.modulate = Color(1, 1, 1, 0)
	spr.scale = Vector3.ONE * 0.8
	var tw := create_tween().set_parallel(true)
	tw.tween_property(spr, "modulate:a", 1.0, 0.15)
	tw.tween_property(spr, "scale", Vector3.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var cam := get_viewport().get_camera_3d()
	if cam and _bubbling.size() > 1:
		_nudge_bubbles(cam)


## The bubble's picture on screen: {rect: Rect2 (pixels), wpp: metres per pixel}, or {} when it's
## behind the camera. Measured from the base position (no nudge), so pushes don't add up.
func _bubble_rect(i: int, cam: Camera3D) -> Dictionary:
	var s: Dictionary = _seats[i]
	var spr: Sprite3D = s["bubble_sprite"]
	var vp: SubViewport = s["viewport"]
	if spr == null or vp == null or not bool(s["vis"]):
		return {}
	var holder: Node3D = s["holder"]
	var k := holder.global_transform.basis.get_scale().y
	var size := Vector2(vp.size) * spr.pixel_size * k
	var centre := holder.to_global(Vector3(spr.position.x, float(s["base_y"]), spr.position.z)) \
		+ cam.global_basis.x * spr.offset.x * spr.pixel_size * k + cam.global_basis.y * spr.offset.y * spr.pixel_size * k
	if cam.is_position_behind(centre):
		return {}
	var c := cam.unproject_position(centre)
	var hw := absf((cam.unproject_position(centre + cam.global_basis.x * size.x * 0.5) - c).x)
	var hh := absf((cam.unproject_position(centre + cam.global_basis.y * size.y * 0.5) - c).y)
	if hh < 1.0:
		return {}
	return {"rect": Rect2(c - Vector2(hw, hh), Vector2(hw, hh) * 2.0), "wpp": size.y * 0.5 / hh, "h": size.y}


## Newest first: each older bubble moves up until it clears every newer (or already placed) one,
## eased; one that would have to move more than NUDGE_MAX_HEIGHTS of its height fades out early.
func _nudge_bubbles(cam: Camera3D) -> void:
	var order: Array = _bubbling.duplicate()
	order.sort_custom(func(a: int, b: int) -> bool: return int(_seats[a].get("born", 0)) > int(_seats[b].get("born", 0)))
	var placed: Array[Rect2] = []
	var ending: Array[int] = []
	for i: int in order:
		var info := _bubble_rect(i, cam)
		if info.is_empty():
			continue
		var rect: Rect2 = info["rect"]
		var push := 0.0
		for _pass in 4:
			var moved := Rect2(rect.position - Vector2(0.0, push), rect.size)
			var more := 0.0
			for r in placed:
				if moved.intersects(r):
					more = maxf(more, moved.end.y - r.position.y + NUDGE_GAP_PX)
			if more <= 0.0:
				break
			push += more
		var s: Dictionary = _seats[i]
		var world := push * float(info["wpp"])
		if world > float(info["h"]) * NUDGE_MAX_HEIGHTS:
			ending.append(i)
			continue
		placed.append(Rect2(rect.position - Vector2(0.0, push), rect.size))
		if absf(world - float(s.get("nudge", 0.0))) > 0.002:
			s["nudge"] = world
			var spr: Sprite3D = s["bubble_sprite"]
			var holder: Node3D = s["holder"]
			var local_y := float(s["base_y"]) + world / maxf(holder.scale.y, 0.001)
			var tw := create_tween()
			tw.tween_property(spr, "position:y", local_y, 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	for i in ending:
		_end_bubble(i, true)


## Can the camera see this seat's bubble? Off-screen, or hidden behind the room (the balcony,
## a post ...) counts as not seen. Uses the room's wall collision the camera rig builds.
func _bubble_seen(i: int, cam: Camera3D) -> bool:
	var s: Dictionary = _seats[i]
	var holder: Node3D = s["holder"]
	var p := holder.global_position + Vector3.UP * 0.25 * float(s["scale"]) * holder.scale.y
	if not cam.is_position_in_frustum(p):
		return false
	var space := get_world_3d().direct_space_state
	if space == null:
		return true
	var q := PhysicsRayQueryParameters3D.create(cam.global_position, p, CameraRig.WALL_LAYER)
	var hit := space.intersect_ray(q)
	return hit.is_empty() or (hit["position"] as Vector3).distance_to(p) < 0.6


## Every BUBBLE_CHECK seconds per bubble: draw it only while the camera can see it.
func _check_bubble(i: int, cam: Camera3D) -> void:
	var s: Dictionary = _seats[i]
	var vis := _bubble_seen(i, cam)
	s["vis"] = vis
	if vis and bool(s["pending"]):
		_show_bubble(i)
		return
	var vp: SubViewport = s["viewport"]
	if vp == null:
		return
	if not vis:
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		s["vp_off"] = true
		s["throttle"] = false
		return
	if bool(s["animated"]):
		var far := cam.global_position.distance_to((s["holder"] as Node3D).global_position) > far_bubble_distance
		s["throttle"] = far
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE if far else SubViewport.UPDATE_ALWAYS
	elif bool(s["vp_off"]):
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	s["vp_off"] = false


## Draws the seat's current message into its bubble (again when an emote finishes loading).
func _render_bubble(i: int) -> void:
	var s: Dictionary = _seats[i]
	var m := AudienceManager.get_seat_member(i)
	if m.is_empty() or s["bubble"] == null:
		return
	var textures: Dictionary = {}
	var waiting: Array = []
	for p: Variant in s["parts"]:
		if p is Dictionary and (p as Dictionary).has("url"):
			var url := String(p["url"])
			var tex := EmoteCache.get_texture(url)
			if tex:
				textures[url] = tex
			elif not EmoteCache.is_failed(url):
				waiting.append(url)
	s["waiting"] = waiting
	var vp: SubViewport = s["viewport"]
	var bubble: SpeechBubble = s["bubble"]
	var px := bubble.set_content(String(m["name"]), s["parts"], m["color"], int(m["style"]), textures)
	vp.size = px
	var animated := false
	for t: Texture2D in textures.values():
		animated = animated or EmoteCache.is_animated(t)
	s["animated"] = animated
	# animated emotes need the bubble redrawn every frame; still ones just once
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if animated else SubViewport.UPDATE_ONCE
	s["vp_off"] = false
	s["throttle"] = false
	var spr: Sprite3D = s["bubble_sprite"]
	var sc: float = float(s["scale"]) * float(AppState.get_setting("audience_bubble_size"))
	if String(s["kind"]) == "presenter":
		sc = float(AppState.get_setting("audience_bubble_size")) * 1.2
	spr.pixel_size = bubble_pixel_size * sc
	var tip := bubble.get_tail_tip()
	spr.offset = Vector2(px.x * 0.5 - tip.x, tip.y - px.y * 0.5)   # tail tip on the anchor


## Shows the chatter's picture on the head once it has downloaded (hidden otherwise).
func _refresh_head(i: int, m: Dictionary) -> void:
	var s: Dictionary = _seats[i]
	if not bool(s["rich"]):
		return
	var head: Sprite3D = s["head"]
	var url := String(m.get("avatar", "")) if not m.is_empty() else ""
	s["avatar"] = url
	var tex: Texture2D = EmoteCache.get_circle_texture(url, AVATAR_PX) if url != "" else null
	head.texture = tex
	head.visible = tex != null and bool(s["show"])


func _on_updated(slot: int) -> void:
	if slot >= 0 and slot < _seats.size() and bool(_seats[slot]["rich"]):
		var m := AudienceManager.get_seat_member(slot)
		_refresh_head(slot, m)
		if not m.is_empty():
			var label: Label3D = _seats[slot]["label"]
			label.text = _tag_text(m)
			label.modulate = m["color"]
			var tw: Variant = _seats[slot].get("color_tween")
			if tw is Tween and (tw as Tween).is_valid():
				(tw as Tween).kill()        # a recolour wins over a seat-in fade
			if bool(_seats[slot]["active"]):       # a speaker keeps their brighter colour
				var boosted := (m["color"] as Color) * SPEAKER_COLOR_BOOST
				_set_color(slot, Color(boosted.r, boosted.g, boosted.b, 1.0))
			else:
				_set_color(slot, m["color"])


## Name tag: the name, plus a regular's title from Stream Core ("PixelPanda · Regular").
func _tag_text(m: Dictionary) -> String:
	var t := String(m.get("title", ""))
	if t != "" and bool(AppState.get_setting("audience_titles")):
		return "%s · %s" % [String(m["name"]), t]
	return String(m["name"])


func _on_emote_ready(url: String) -> void:
	for i in _rich:
		var s: Dictionary = _seats[i]
		if String(s["avatar"]) == url:
			_refresh_head(i, AudienceManager.get_seat_member(i))
		if s["bubble"] != null and (s["waiting"] as Array).has(url):
			_render_bubble(i)
			if not bool(s["vis"]):
				(s["viewport"] as SubViewport).render_target_update_mode = SubViewport.UPDATE_DISABLED
				s["vp_off"] = true


func _make_bubble(i: int) -> void:
	var s: Dictionary = _seats[i]
	var vp := SubViewport.new()
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.msaa_2d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var bubble := SpeechBubble.new()
	vp.add_child(bubble)
	s["root"].add_child(vp)
	var spr := Sprite3D.new()
	spr.texture = vp.get_texture()
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.no_depth_test = true
	spr.shaded = false
	spr.render_priority = 10
	spr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	s["holder"].add_child(spr)
	s["viewport"] = vp
	s["bubble"] = bubble
	s["bubble_sprite"] = spr


## The seat's bubble is done: fade it out and free it (fade = false: at once).
func _end_bubble(i: int, fade: bool = true) -> void:
	var s: Dictionary = _seats[i]
	s["active"] = false
	s["pending"] = false
	s["throttle"] = false
	_bubbling.erase(i)
	_dirty = true
	var spr: Sprite3D = s["bubble_sprite"]
	if spr != null:
		var vp: SubViewport = s["viewport"]
		s["bubble_sprite"] = null
		s["viewport"] = null
		s["bubble"] = null
		if fade:
			var tw := create_tween()
			tw.tween_property(spr, "modulate:a", 0.0, 0.3)
			tw.tween_callback(func() -> void:
				spr.queue_free()
				vp.queue_free())
		else:
			spr.queue_free()
			vp.queue_free()
	if not bool(s["rich"]):
		return
	var m := AudienceManager.get_seat_member(i)
	if not m.is_empty():
		_set_color(i, m["color"])


func _clear_bubbles(i: int) -> void:
	(_seats[i]["queue"] as Array).clear()
	_end_bubble(i)


# ── EventBus handlers ────────────────────────────────────────
func _on_seated(slot: int) -> void:
	if slot >= 0 and slot < _seats.size():
		_refresh_seat(slot, true)


func _on_left(slot: int) -> void:
	if slot >= 0 and slot < _seats.size():
		_refresh_seat(slot, true)


func _on_setting_changed(key: String, _value: Variant) -> void:
	if key in ["audience_enabled", "audience_names", "audience_show_empty", "audience_crowd"]:
		_apply_visibility()
	elif key == "audience_crowd_fill" or key == "audience_fill_main":
		if _crowd and key == "audience_crowd_fill":
			_crowd.set_fill(float(AppState.get_setting("audience_crowd_fill")))
		for i in _rich:
			if String(_seats[i]["kind"]) == "seat" and not bool(_seats[i]["seated"]):
				_refresh_seat(i, false)
	elif key == "audience_titles":
		for i in _rich:
			_on_updated(i)
	elif key == "audience_bubble_theme":
		for i in _rich:            # bubbles showing now take the new colours at once
			if _seats[i]["bubble"] != null and bool(_seats[i]["active"]):
				_render_bubble(i)
	elif key.begins_with("presenter_"):
		for n: int in _presenter_slots.keys():
			if key.begins_with("presenter_%d_" % n):
				var slot := int(_presenter_slots[n])
				_update_presenter_look(slot)
				_refresh_head(slot, AudienceManager.get_seat_member(slot))
				if key.ends_with("_chat_bubbles") and not bool(AppState.get_setting(key)):
					_clear_bubbles(slot)
				_dirty = true
