class_name ReactionLayer
extends Node3D
## Plays chat reactions (🍅, !tomato @bob ...) in the current room. Attached by RoomHost and
## freed with the room. Reactions (autoload) decides what to play and talks to Stream Core;
## this node only turns a reaction into something you can see, then reports how it went.
##
## Targets it offers (told to Core through Reactions.set_room_targets):
##   screen   the main screen (aliases tv, stage, movie). A throw with no target lands here.
##   webcam   the WEBCAM_Frame picture, if the room has one (aliases cam, streamer).
##   chat     the chat screen, if the room has one.
##   <name>   every TARGET_<Name> marker in the room (+Z faces the audience).
##   podium<n> the podium itself (a stage spot) for presenters on set.
##   presenter<n> the presenter's picture (a guest; aliases guest<n>, p<n>).
##   @someone anyone seated in the audience.

## Max reaction objects alive at once; extra ones are skipped.
const MAX_LIVE: int = 260
const SPLAT_PX: int = 128
const CONFETTI: PackedColorArray = [Color("ff3b6b"), Color("ffb400"), Color("53fc18"), Color("28c8ff"), Color("a55bff"), Color("ffffff")]

@export var throw_time: float = 0.9
## Size of an emoji object in metres at 100% "Reaction size".
@export var object_size: float = 0.45

var _room: Room
var _audience: AudienceView
var _presenters: Array[Dictionary] = []
var _presenter_size: Vector2 = Vector2.ONE
var _screen: Dictionary = {}          # {pos, normal, right, up, size: Vector2}
var _targets: Dictionary = {}         # id -> {id, label, aliases, pos, normal, right, up, size}
var _guests: Dictionary = {}          # id -> same, plus n
var _pile: Array[Node3D] = []
var _pile_timer: SceneTreeTimer
var _live: int = 0
var _meters: Dictionary = {}          # meter id -> Label3D
static var _splat_tex: Texture2D


## Called by RoomHost after the room, its audience and its presenters are in place.
func setup(room: Room, audience: AudienceView, presenters: Array[Dictionary], presenter_size: Vector2) -> void:
	_room = room
	_audience = audience
	_presenters = presenters
	_presenter_size = presenter_size
	_collect_targets()
	_register()


func _ready() -> void:
	EventBus.reaction_play.connect(_on_play)
	EventBus.reaction_meter_changed.connect(_on_meter)
	EventBus.setting_changed.connect(_on_setting_changed)


func _exit_tree() -> void:
	EventBus.reaction_play.disconnect(_on_play)
	EventBus.reaction_meter_changed.disconnect(_on_meter)
	EventBus.setting_changed.disconnect(_on_setting_changed)
	Reactions.clear_room(self)


# ── Public API ───────────────────────────────────────────────
func get_target_ids() -> PackedStringArray:
	return PackedStringArray(_targets.keys() + _guests.keys())


func get_live_count() -> int:
	return _live


## Where a target is: {pos, normal, kind, slot, fallback}. Used by effects and tests.
func resolve_target(target: Variant) -> Dictionary:
	var out := {"pos": _screen_point(true), "normal": _screen.get("normal", Vector3.BACK), "kind": "stage",
		"slot": -1, "fallback": false}
	if not target is Dictionary:
		return out
	var t: Dictionary = target
	var kind := String(t.get("type", "stage"))
	var target_name := String(t.get("name", "")).to_lower()
	if kind == "user":
		var slot := AudienceManager.find_slot_by_name(target_name)
		if slot >= 0 and _audience and _audience.is_seat_taken(slot):
			var head := _audience.get_seat_head(slot)
			return {"pos": head, "normal": _towards_camera(head), "kind": "user", "slot": slot, "fallback": false}
		out["fallback"] = true
		return out
	var spot: Dictionary = _find_spot(target_name)
	if spot.is_empty():
		out["fallback"] = target_name != ""
		return out
	var jitter: Vector2 = (spot["size"] as Vector2) * 0.35
	var p: Vector3 = spot["pos"] + spot["right"] * randf_range(-jitter.x, jitter.x) + spot["up"] * randf_range(-jitter.y, jitter.y)
	return {"pos": p + spot["normal"] * 0.03, "normal": spot["normal"], "kind": "guest" if spot.has("n") else "stage",
		"slot": -1, "fallback": false}


# ── Targets ──────────────────────────────────────────────────
func _collect_targets() -> void:
	_targets.clear()
	var tv := _room.find_screen()
	var towards := _audience_center()
	if tv:
		var box := tv.global_transform * tv.get_aabb()
		var c := box.get_center()
		var n := towards - c
		n.y = 0.0
		n = n.normalized() if n.length() > 0.01 else Vector3.BACK
		var right := Vector3.UP.cross(n).normalized()
		var width := absf(box.size.dot(right.abs()))
		_screen = {"pos": c, "normal": n, "right": right, "up": Vector3.UP, "size": Vector2(width, box.size.y)}
		_add_target("screen", "Screen", ["tv", "stage", "movie"], _screen)
	else:
		var c2 := towards + Vector3(0, 1.5, -4)
		_screen = {"pos": c2, "normal": Vector3.BACK, "right": Vector3.RIGHT, "up": Vector3.UP, "size": Vector2(3, 2)}
	var cam := _room.get_webcam_marker()
	if cam:
		_add_target("webcam", "Webcam", ["cam", "streamer"], _marker_spot(cam, Vector2(1.2, 0.68), 0.0))
	var chat := _room.get_chat_screen_marker()
	if chat:
		_add_target("chat", "Chat screen", ["chatscreen"], _marker_spot(chat, _room.chat_screen_size, -0.5))
	for n in _room.find_children("TARGET_*", "Node3D", true, false):
		var id := String(n.name).trim_prefix("TARGET_").to_lower()
		_add_target(id, String(n.name).trim_prefix("TARGET_").replace("_", " "), [], _marker_spot(n as Node3D, Vector2(1, 1), 0.0))
	_collect_guests()


## Presenters on set: their picture is a guest target, their podium a stage target.
func _collect_guests() -> void:
	_guests.clear()
	for id: String in _targets.keys():
		if id.begins_with("podium"):
			_targets.erase(id)
	for s in _presenters:
		var n := int(s["n"])
		if not bool(AppState.get_setting(AppState.presenter_key(n, "on"))):
			continue
		var marker := s["marker"] as Node3D
		var spot := _marker_spot(marker, _presenter_size, 0.5)
		spot["id"] = "presenter%d" % n
		spot["name"] = "Presenter %d" % n
		spot["aliases"] = ["guest%d" % n, "p%d" % n]
		spot["n"] = n
		_guests[spot["id"]] = spot
		_add_target("podium%d" % n, "Podium %d" % n, [], _podium_spot(marker, s.get("podium") as Node3D))


## The podium's front face (towards the audience). Rooms without a PODIUM_<n> mesh get a
## podium-sized spot just below the presenter's picture.
func _podium_spot(marker: Node3D, podium: Node3D) -> Dictionary:
	var b := marker.global_basis.orthonormalized()
	var box := AABB()
	var found := false
	if podium:
		var meshes: Array[Node] = podium.find_children("*", "MeshInstance3D", true, false)
		if podium is MeshInstance3D:
			meshes.append(podium)
		for m in meshes:
			var mi := m as MeshInstance3D
			var wb := mi.global_transform * mi.get_aabb()
			box = wb if not found else box.merge(wb)
			found = true
	if not found:
		var c := marker.global_position + b.z * 0.35 + Vector3.UP * 0.55
		return {"pos": c, "normal": b.z, "right": b.x, "up": Vector3.UP, "size": Vector2(0.7, 0.8)}
	var n := b.z
	var half := box.size * 0.5
	var depth := absf(half.x * n.x) + absf(half.y * n.y) + absf(half.z * n.z)
	var width := absf(box.size.dot(b.x.abs()))
	var c2 := box.get_center() + n * depth
	return {"pos": c2, "normal": n, "right": b.x, "up": Vector3.UP, "size": Vector2(width, box.size.y) * 0.8}


func _add_target(id: String, label: String, aliases: Array, spot: Dictionary) -> void:
	spot["id"] = id
	spot["label"] = label
	spot["aliases"] = aliases
	_targets[id] = spot


## A flat spot on a marker (+Z faces the audience). up_shift: move by this much of the height
## (0.5 = the marker is the bottom centre, -0.5 = the top centre).
func _marker_spot(m: Node3D, size: Vector2, up_shift: float) -> Dictionary:
	var b := m.global_basis.orthonormalized()
	return {"pos": m.global_position + b.y * size.y * up_shift, "normal": b.z, "right": b.x, "up": b.y, "size": size}


## Finds a target by id, alias, label or name, ignoring case, spaces, _ - and dots
## ("Presenter 2" finds presenter2, "big piano" finds TARGET_Big_Piano).
func _find_spot(spot_name: String) -> Dictionary:
	var key := _target_key(spot_name)
	if key == "":
		return {}
	for d: Dictionary in _targets.values() + _guests.values():
		var names: Array = [d["id"], d.get("label", ""), d.get("name", "")] + (d["aliases"] as Array)
		for n: Variant in names:
			if _target_key(String(n)) == key:
				return d
	return {}


static func _target_key(s: String) -> String:
	var out := ""
	for c in s.strip_edges().to_lower():
		if not c in [" ", "_", "-", ".", "\t"]:
			out += c
	return out


func _register() -> void:
	var targets: Array = []
	for d: Dictionary in _targets.values():
		targets.append({"id": d["id"], "label": d["label"], "aliases": d["aliases"]})
	var guests: Array = []
	for d: Dictionary in _guests.values():
		guests.append({"id": d["id"], "name": d["name"], "aliases": d["aliases"]})
	Reactions.set_room_targets(self, targets, guests)


func _audience_center() -> Vector3:
	if _audience and _audience.get_seat_count() > 0:
		return _audience.get_seats_bounds().get_center()
	var cams := _room.get_camera_markers()
	return cams[0].global_position if not cams.is_empty() else Vector3(0, 1.2, 6)


func _screen_point(jitter: bool) -> Vector3:
	var p: Vector3 = _screen.get("pos", Vector3.ZERO)
	if jitter and not _screen.is_empty():
		var sz: Vector2 = _screen["size"]
		p += _screen["right"] * randf_range(-0.35, 0.35) * sz.x + _screen["up"] * randf_range(-0.3, 0.3) * sz.y
	return p + (_screen.get("normal", Vector3.BACK) as Vector3) * 0.03


func _towards_camera(p: Vector3) -> Vector3:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return Vector3.BACK
	return (cam.global_position - p).normalized()


## Where the sender is: their seat's head, or just behind the camera if they have no seat.
func _origin(from: Variant) -> Dictionary:
	var slot := _sender_slot(from)
	if slot >= 0:
		return {"pos": _audience.get_seat_head(slot), "slot": slot}
	var cam := get_viewport().get_camera_3d()
	if cam:
		var b := cam.global_basis
		return {"pos": cam.global_position + b * Vector3(randf_range(-0.8, 0.8), -0.5, 0.4), "slot": -1}
	return {"pos": (_screen["pos"] as Vector3) + (_screen["normal"] as Vector3) * 8.0, "slot": -1}


func _sender_slot(from: Variant) -> int:
	if _audience == null or not from is Dictionary:
		return -1
	var f: Dictionary = from
	var slot := AudienceManager.find_slot_for_user(String(f.get("platform", "")), String(f.get("id", "")))
	if slot < 0:
		slot = AudienceManager.find_slot_by_name(String(f.get("username", "")))
	if slot < 0:
		slot = AudienceManager.find_slot_by_name(String(f.get("display_name", "")))
	return slot if _audience.is_seat_taken(slot) else -1


# ── Playing ──────────────────────────────────────────────────
func _on_play(d: Dictionary) -> void:
	var id := String(d.get("id", ""))
	if d.has("seed"):
		seed(int(d["seed"]))     # the same random spread on every PC in a shared session
	var outcome := _play(d)
	EventBus.reaction_finished.emit(id, outcome)


## Starts the effect; returns "hit", "fallback" (target gone, played on the stage) or "dropped".
func _play(d: Dictionary) -> String:
	var p: Dictionary = d.get("params", {}) if d.get("params") is Dictionary else {}
	var count := clampi(int(d.get("count", 1)), 1, 50)
	# a volley: the more there are, the quicker they come (all out within ~2 s)
	var gap := clampf(2.0 / count, 0.05, 0.16)
	var from: Variant = d.get("from")
	var tgt := resolve_target(d.get("target"))
	var outcome := "fallback" if bool(tgt["fallback"]) else "hit"
	if _live >= MAX_LIVE:
		return "dropped"
	match String(d.get("effect", "")):
		"throw":
			for i in count:
				var t := tgt if i == 0 else resolve_target(d.get("target"))
				get_tree().create_timer(gap * i).timeout.connect(func() -> void:
					if is_inside_tree():
						_throw(p, _origin(from), t))
		"pile_up":
			for i in count:
				get_tree().create_timer(gap * i).timeout.connect(func() -> void:
					if is_inside_tree():
						_pile_one(p, _origin(from)))
		"float_up":
			var crowd := _crowd_slots(d)
			if not crowd.is_empty():
				for slot in crowd.slice(0, 14):
					_float_up(p, _audience.get_seat_head(slot))
			else:
				var o := _origin(from)
				_float_up(p, o["pos"])
				if int(o["slot"]) < 0:
					outcome = "fallback"
		"fall_down":
			_fall(p, tgt["pos"], 1.2, 12)
		"rain":
			_rain(p)
		"confetti":
			_confetti(p, tgt["pos"] + (tgt["normal"] as Vector3) * 0.3)
		"wiggle", "stand_cheer":
			var slots := _crowd_slots(d)
			if slots.is_empty() and _sender_slot(from) >= 0:
				slots = [_sender_slot(from)]
			if slots.is_empty():
				return "dropped"
			var style := "cheer" if String(d["effect"]) == "stand_cheer" else String(p.get("style", "wiggle"))
			for slot in slots:
				_audience.play_motion(slot, style, float(p.get("duration_sec", 2.0 if style != "cheer" else 4.0)))
		"crowd_motion":
			var who: Array[int] = []
			var everyone := false
			if String(p.get("who", "all")) == "crowd":
				who = _crowd_slots(d)
				if who.is_empty() and _sender_slot(from) >= 0:
					who = [_sender_slot(from)]
			if who.is_empty() and _audience:
				everyone = true
				for i in _audience.get_seat_count():
					if _audience.is_seat_taken(i):
						who.append(i)
			var mstyle := String(p.get("style", "dance"))
			var secs := clampf(float(p.get("duration_sec", 3.0)), 0.5, 20.0)
			if everyone and _audience and _audience.get_filler_count() > 0:
				_audience.play_filler_motion(mstyle, secs)      # the filler crowd joins in
			elif who.is_empty():
				return "dropped"
			for slot in who:
				var delay := randf() * 0.25
				get_tree().create_timer(delay).timeout.connect(func() -> void:
					if is_inside_tree() and _audience:
						_audience.play_motion(slot, mstyle, secs))
		"sign":
			var text := String(p.get("text", "")).strip_edges().left(60)
			if text == "":
				return "dropped"
			var col := _color(p.get("color", ""), Color("ffd400"))
			var secs2 := clampf(float(p.get("duration_sec", 20.0)), 2.0, 60.0)
			var sslot := _sender_slot(from)
			if sslot >= 0:
				_audience.hold_sign(sslot, text, col, secs2)
			else:
				_shout({"text": text, "color": p.get("color", "#ffd400"), "duration_sec": secs2}, d)
				outcome = "fallback"
		"seat_prop":
			var pslot := _sender_slot(from)
			if pslot < 0:
				return "dropped"
			_audience.seat_prop(pslot, String(p.get("prop", "sleep")), float(p.get("duration_sec", 12.0)))
		"highfive":
			return _highfive(from, d.get("target"))
		"seat_move":
			var mslot := _sender_slot(from)
			if mslot < 0:
				return "dropped"
			var to := AudienceManager.move_to_row(mslot, String(p.get("where", "front")))
			if to < 0:
				return "dropped"
			get_tree().create_timer(0.4).timeout.connect(func() -> void:
				if is_inside_tree() and _audience:
					_audience.play_motion(to, "cheer", 1.5))
		"seat_swap":
			var a := _sender_slot(from)
			var t: Dictionary = resolve_target(d.get("target"))
			var b := int(t.get("slot", -1))
			if a < 0 or b < 0 or not AudienceManager.swap_seats(a, b):
				return "dropped"
		"stage_fire":
			_stage_fire(clampf(float(p.get("duration_sec", 6.0)), 1.0, 30.0))
		"fireworks":
			_fireworks(clampi(int(p.get("count", 6)), 1, 30), clampf(float(p.get("duration_sec", 4.0)), 1.0, 20.0))
		"big_shout":
			return _shout(p, d)
		"stadium_wave":
			if _audience == null or _audience.get_seat_count() == 0:
				return "dropped"
			_audience.play_wave(float(p.get("speed", 1.0)), _screen["pos"])
		"spotlight":
			var aim := tgt
			if d.get("target") == null:
				var o2 := _origin(from)
				if int(o2["slot"]) < 0:
					return "dropped"
				aim = {"pos": o2["pos"], "normal": _towards_camera(o2["pos"])}
			_spotlight(p, aim["pos"])
		"lights":
			_lights(p)
		"camera_shake":
			EventBus.camera_shake_requested.emit(float(p.get("strength", 0.5)), float(p.get("duration_sec", 0.6)))
		_:
			return "dropped"
	return outcome


## Seats of the people a crowd reaction is about (Stream Core's "crowd": combos, launches ...).
func _crowd_slots(d: Dictionary) -> Array[int]:
	var out: Array[int] = []
	if _audience == null or not d.get("crowd") is Array:
		return out
	for ref: Variant in d["crowd"]:
		var slot := _sender_slot(ref)
		if slot >= 0 and not out.has(slot):
			out.append(slot)
	return out


# ── Effects ──────────────────────────────────────────────────
func _size() -> float:
	return object_size * clampf(float(AppState.get_setting("reaction_size")), 0.3, 3.0)


func _object(text: String, scale_by: float = 1.0) -> Label3D:
	var l := Label3D.new()
	l.text = text.strip_edges().left(12) if text.strip_edges() != "" else "🍅"
	l.font = SpeechBubble.shared_font()
	l.font_size = 96
	l.outline_size = 0
	l.pixel_size = _size() * scale_by / 110.0
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.shaded = false
	l.double_sided = true
	l.alpha_cut = Label3D.ALPHA_CUT_DISABLED
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	l.render_priority = 5
	add_child(l)
	_live += 1
	l.tree_exiting.connect(func() -> void: _live -= 1)
	return l


## What an effect throws / drops: the reaction's picture (Core's "img:name" object, sent as
## params.object_image) or else the emoji / emote text. A Sprite3D or a Label3D.
func _thing(p: Dictionary, fallback: String, scale_by: float) -> Node3D:
	var pic: Variant = p.get("object_image")
	if not (pic is Dictionary) or String((pic as Dictionary).get("url", "")) == "":
		return _object(String(p.get("object", fallback)), scale_by)
	var url := _core_url(String((pic as Dictionary)["url"]))
	var s := Sprite3D.new()
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.shaded = false
	s.double_sided = true
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	s.render_priority = 5
	var span := _size() * scale_by * 1.2      # pictures have a margin, so a bit over the emoji size
	# an emote name shows as text until its picture arrives (and stays if it can't be loaded)
	var word := String(p.get("object", ""))
	var stand_in: Label3D = null
	if word != "" and not word.begins_with("img:"):
		stand_in = Label3D.new()
		stand_in.text = word.left(16)
		stand_in.font = SpeechBubble.shared_font()
		stand_in.font_size = 96
		stand_in.outline_size = 12
		stand_in.pixel_size = _size() * scale_by / 110.0 * (0.45 if word.length() > 2 else 1.0)
		stand_in.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		stand_in.shaded = false
		stand_in.render_priority = 5
		s.add_child(stand_in)
	var apply := func(tex: Texture2D) -> void:
		if tex and is_instance_valid(s):
			s.texture = tex
			s.pixel_size = span / float(maxi(tex.get_width(), tex.get_height()))
			if is_instance_valid(stand_in):
				stand_in.queue_free()
	var have := EmoteCache.get_texture(url)
	if have:
		apply.call(have)
	else:
		# first use: shows as soon as the download (or GIF decode) finishes
		var on_ready := func(u: String) -> void:
			if u == url:
				apply.call(EmoteCache.get_texture(url))
		EventBus.emote_ready.connect(on_ready)
		s.tree_exiting.connect(func() -> void:
			if EventBus.emote_ready.is_connected(on_ready):
				EventBus.emote_ready.disconnect(on_ready))
	add_child(s)
	_live += 1
	s.tree_exiting.connect(func() -> void: _live -= 1)
	return s


## Core's relative picture URL ("/reactions/images/boot.png?v=…") on the Core the game is
## connected to (Audience tab > Core address, ws://host:port/ws).
static func _core_url(path: String) -> String:
	if path.begins_with("http://") or path.begins_with("https://"):
		return path
	var ws := String(AppState.get_setting("chat_core_url")).strip_edges()
	var base := ws.replace("wss://", "https://").replace("ws://", "http://")
	var slash := base.find("/", base.find("//") + 2)
	if slash >= 0:
		base = base.left(slash)
	return base + path


func _throw(p: Dictionary, origin: Dictionary, tgt: Dictionary) -> void:
	var obj = _thing(p, "🍅", 1.0)
	var a: Vector3 = origin["pos"]
	var b: Vector3 = tgt["pos"]
	var arc := clampf(float(p.get("arc_height", 1.0)), 0.2, 4.0) * clampf(a.distance_to(b) * 0.18, 0.4, 3.0)
	var mid := (a + b) * 0.5 + Vector3.UP * arc
	var dur := throw_time * clampf(a.distance_to(b) / 8.0, 0.6, 1.6)
	var spin := randf_range(-1.0, 1.0) * TAU * 2.0
	obj.global_position = a
	var tw := create_tween()
	tw.tween_method(func(t: float) -> void:
		if is_instance_valid(obj):
			obj.global_position = a.lerp(mid, t).lerp(mid.lerp(b, t), t)
			obj.rotation.z = spin * t, 0.0, 1.0, dur)
	tw.tween_callback(func() -> void:
		var at: Vector3 = obj.global_position
		obj.queue_free()
		_impact(p, at, tgt))


func _impact(p: Dictionary, at: Vector3, tgt: Dictionary) -> void:
	var kind := String(p.get("impact", "splat"))
	var stick := clampf(float(p.get("stick_sec", 6.0)), 0.0, 60.0)
	var col := _color(p.get("splat_color", ""), _guess_color(String(p.get("object", "🍅"))))
	if int(tgt.get("slot", -1)) >= 0 and _audience:
		_audience.play_motion(int(tgt["slot"]), "flinch", 0.5)
	match kind:
		"bounce":
			var obj = _thing(p, "🍅", 1.0)
			obj.global_position = at
			var n: Vector3 = tgt["normal"]
			var land := at + n * randf_range(0.8, 1.6) + Vector3(randf_range(-0.6, 0.6), -at.y + _floor_y(at), 0)
			var peak := (at + land) * 0.5 + Vector3.UP * 0.6
			var tw := create_tween()
			tw.tween_method(func(t: float) -> void:
				if is_instance_valid(obj):
					obj.global_position = at.lerp(peak, t).lerp(peak.lerp(land, t), t), 0.0, 1.0, 0.7)
			tw.tween_interval(maxf(stick, 0.5))
			tw.tween_property(obj, "modulate:a", 0.0, 0.4)
			tw.tween_callback(obj.queue_free)
		"stick":
			var obj2 = _thing(p, "🍅", 1.0)
			obj2.global_position = at
			obj2.rotation.z = randf_range(-0.6, 0.6)
			var tw2 := create_tween()
			tw2.tween_interval(maxf(stick, 0.8))
			tw2.tween_property(obj2, "modulate:a", 0.0, 0.5)
			tw2.tween_callback(obj2.queue_free)
		"shatter":
			_burst(at, PackedColorArray([col.lightened(0.3), col, Color.WHITE]), 36, 2.5, 0.05)
		_:
			_splat(at, tgt, col, stick)
			_burst(at, PackedColorArray([col, col.darkened(0.25)]), 14, 1.6, 0.04)


func _splat(at: Vector3, tgt: Dictionary, col: Color, stick: float) -> void:
	var s := Sprite3D.new()
	s.texture = _splat_texture()
	s.modulate = col
	s.shaded = false
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	s.render_priority = 4
	s.pixel_size = _size() * 2.2 / float(SPLAT_PX)
	add_child(s)
	_live += 1
	s.tree_exiting.connect(func() -> void: _live -= 1)
	var n: Vector3 = tgt["normal"]
	if String(tgt.get("kind", "")) == "user":
		s.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		s.no_depth_test = false
		s.global_position = at + n * 0.08
		s.pixel_size *= 0.7
	else:
		var up := Vector3.UP if absf(n.dot(Vector3.UP)) < 0.95 else Vector3.FORWARD
		s.global_transform = Transform3D(Basis.looking_at(-n, up), at + n * 0.02)
	s.rotate_object_local(Vector3.FORWARD, randf() * TAU)
	s.scale = Vector3.ONE * 0.2
	var tw := create_tween()
	tw.tween_property(s, "scale", Vector3.ONE, 0.09).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(s, "position", s.position + Vector3.DOWN * 0.12 * _size(), maxf(stick, 0.3)).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(s, "scale", Vector3(1.0, 1.25, 1.0), maxf(stick, 0.3))
	tw.tween_property(s, "modulate:a", 0.0, 0.6)
	tw.tween_callback(s.queue_free)


func _pile_one(p: Dictionary, origin: Dictionary) -> void:
	var sz: Vector2 = _screen["size"]
	var base: Vector3 = (_screen["pos"] as Vector3) + (_screen["normal"] as Vector3) * 0.9 \
		+ (_screen["right"] as Vector3) * randf_range(-0.35, 0.35) * sz.x
	base.y = _floor_y(base) + 0.12 * _size() / object_size * (1.0 + 0.35 * (_pile.size() / 6))
	var obj = _thing(p, "🍅", 1.0)
	var a: Vector3 = origin["pos"]
	var mid := (a + base) * 0.5 + Vector3.UP * 1.5
	obj.global_position = a
	var tw := create_tween()
	tw.tween_method(func(t: float) -> void:
		if is_instance_valid(obj):
			obj.global_position = a.lerp(mid, t).lerp(mid.lerp(base, t), t), 0.0, 1.0, throw_time)
	_pile.append(obj)
	var cap := clampi(int(p.get("max_pile", 30)), 1, 200)
	while _pile.size() > cap:
		var old: Variant = _pile.pop_front()
		if is_instance_valid(old):
			(old as Node).queue_free()
	var clear_after := clampf(float(p.get("clear_after_sec", 90.0)), 5.0, 3600.0)
	_pile_timer = get_tree().create_timer(clear_after)
	var my_timer := _pile_timer
	my_timer.timeout.connect(func() -> void:
		if is_inside_tree() and my_timer == _pile_timer:
			_clear_pile())


func _clear_pile() -> void:
	for o in _pile:
		if is_instance_valid(o):
			var tw := create_tween()
			tw.tween_property(o, "modulate:a", 0.0, 0.8)
			tw.tween_callback(o.queue_free)
	_pile.clear()


func _float_up(p: Dictionary, at: Vector3) -> void:
	var n := clampi(int(p.get("count", 5)), 1, 40)
	var dur := clampf(float(p.get("duration_sec", 3.0)), 0.5, 20.0)
	for i in n:
		var obj = _thing(p, "❤️", 0.7)
		var start := at + Vector3(randf_range(-0.15, 0.15), 0.1, randf_range(-0.15, 0.15))
		var end := start + Vector3(randf_range(-0.5, 0.5), randf_range(1.5, 2.6), randf_range(-0.3, 0.3))
		obj.global_position = start
		obj.modulate.a = 0.0
		var tw := create_tween()
		tw.tween_interval(i * dur * 0.15)
		tw.tween_property(obj, "modulate:a", 1.0, 0.2)
		tw.parallel().tween_property(obj, "global_position", end, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(obj, "modulate:a", 0.0, dur * 0.35).set_delay(dur * 0.65)
		tw.tween_callback(obj.queue_free)


func _fall(p: Dictionary, at: Vector3, radius: float, default_count: int) -> void:
	var n := clampi(int(p.get("count", default_count)), 1, 80)
	var dur := clampf(float(p.get("duration_sec", 4.0)), 0.5, 20.0)
	for i in n:
		var obj = _thing(p, "🌹", 0.8)
		var off := Vector3(randf_range(-radius, radius), 0, randf_range(-radius * 0.5, radius * 0.5))
		var start := at + off + Vector3.UP * randf_range(2.5, 3.5)
		var end := at + off * 1.2 + Vector3.DOWN * randf_range(0.2, 0.8)
		obj.global_position = start
		var fall := dur * randf_range(0.55, 0.8)
		var spin := randf_range(-3.0, 3.0)
		var tw := create_tween()
		tw.tween_interval(randf() * (dur - fall))
		tw.tween_method(func(t: float) -> void:
			if is_instance_valid(obj):
				obj.global_position = start.lerp(end, t) + Vector3(sin(t * 9.0 + spin) * 0.15, 0, 0)
				obj.rotation.z = spin * t
				obj.modulate.a = clampf((1.0 - t) * 4.0, 0.0, 1.0), 0.0, 1.0, fall)
		tw.tween_callback(obj.queue_free)


func _rain(p: Dictionary) -> void:
	var box := AABB(_screen["pos"] as Vector3, Vector3.ZERO)
	if _audience and _audience.get_seat_count() > 0:
		box = box.merge(_audience.get_seats_bounds())
	var n := clampi(int(p.get("count", 40)), 1, 300)
	var dur := clampf(float(p.get("duration_sec", 6.0)), 1.0, 30.0)
	for i in n:
		if _live >= MAX_LIVE:
			break
		var obj = _thing(p, "🎉", 0.8)
		var x := randf_range(box.position.x, box.end.x)
		var z := randf_range(box.position.z, box.end.z)
		var start := Vector3(x, box.end.y + 3.0, z)
		var end := Vector3(x + randf_range(-0.4, 0.4), box.position.y - 0.6, z)
		obj.global_position = start
		obj.visible = false
		var fall := randf_range(1.6, 2.6)
		var tw := create_tween()
		tw.tween_interval(randf() * maxf(dur - fall, 0.2))
		tw.tween_callback(func() -> void: obj.visible = true)
		tw.tween_property(obj, "global_position", end, fall).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(obj, "rotation:z", randf_range(-4.0, 4.0), fall)
		tw.tween_callback(obj.queue_free)


func _confetti(p: Dictionary, at: Vector3) -> void:
	var cols := PackedColorArray()
	for part in String(p.get("colors", "")).split(",", false):
		if Color.html_is_valid(part.strip_edges()):
			cols.append(Color.html(part.strip_edges()))
	_burst(at, cols if not cols.is_empty() else CONFETTI, clampi(int(p.get("count", 80)), 5, 400), 5.0, 0.06)


## One-shot burst of little squares (confetti, splat drops, shatter pieces).
func _burst(at: Vector3, colors: PackedColorArray, amount: int, speed: float, piece: float) -> void:
	var parts := CPUParticles3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(piece, piece * 1.4) * (_size() / object_size)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	quad.material = mat
	parts.mesh = quad
	parts.amount = amount
	parts.one_shot = true
	parts.explosiveness = 0.95
	parts.lifetime = 2.2
	parts.direction = Vector3.UP
	parts.spread = 180.0
	parts.initial_velocity_min = speed * 0.4
	parts.initial_velocity_max = speed
	parts.gravity = Vector3(0, -4.5, 0)
	parts.damping_min = 0.5
	parts.damping_max = 1.5
	parts.angular_velocity_min = -360.0
	parts.angular_velocity_max = 360.0
	var list := colors
	var offs := PackedFloat32Array()
	for i in list.size():
		offs.append(float(i) / float(list.size()))
	var g := Gradient.new()
	g.offsets = offs
	g.colors = list
	g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT   # each piece one solid colour
	parts.color_initial_ramp = g
	parts.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(parts)
	parts.global_position = at
	parts.emitting = true
	_live += 1
	parts.tree_exiting.connect(func() -> void: _live -= 1)
	get_tree().create_timer(parts.lifetime + 0.4).timeout.connect(parts.queue_free)


func _shout(p: Dictionary, d: Dictionary) -> String:
	var from: Dictionary = d.get("from", {}) if d.get("from") is Dictionary else {}
	var who := String(from.get("display_name", from.get("username", "")))
	var msg := String(d.get("message", "")).strip_edges()
	if msg.begins_with("!"):          # "!shout hello chat" -> "hello chat"
		var sp := msg.find(" ")
		msg = msg.substr(sp + 1).strip_edges() if sp > 0 else ""
	var text := String(p.get("text", "{message}")).replace("{message}", msg).replace("{user}", who).strip_edges()
	if text == "":
		text = who
	var col := _color(p.get("color", ""), Color("ffd400"))
	var secs := clampf(float(p.get("duration_sec", 5.0)), 1.0, 20.0)
	var slot := _sender_slot(from)
	if slot >= 0:
		_audience.shout(slot, text.left(120), col, secs)
		return "hit"
	var l := _object(text.left(120), 1.0)
	l.font_size = 72
	l.outline_size = 22
	l.outline_modulate = col
	l.no_depth_test = true
	l.width = 900.0
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.pixel_size = 0.006
	l.global_position = (_screen["pos"] as Vector3) + (_screen["normal"] as Vector3) * 1.5
	var tw := create_tween()
	tw.tween_interval(secs)
	tw.tween_property(l, "modulate:a", 0.0, 0.4)
	tw.tween_callback(l.queue_free)
	return "fallback"


## Both jump, a hand flies from each seat, and they meet in the middle with a clap.
func _highfive(from: Variant, target: Variant) -> String:
	var a := _sender_slot(from)
	var t := resolve_target(target)
	var b := int(t.get("slot", -1))
	if a < 0 or b < 0 or a == b:
		return "dropped"
	var pa := _audience.get_seat_head(a)
	var pb := _audience.get_seat_head(b)
	var mid := (pa + pb) * 0.5 + Vector3.UP * clampf(pa.distance_to(pb) * 0.25, 0.3, 1.5)
	_audience.play_motion(a, "jump", 0.6)
	_audience.play_motion(b, "jump", 0.6)
	for side in [[pa, "✋"], [pb, "🤚"]]:
		var hand := _object(String(side[1]), 0.8)
		var start: Vector3 = side[0]
		hand.global_position = start
		var tw := create_tween()
		tw.tween_property(hand, "global_position", mid, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_interval(0.25)
		tw.tween_property(hand, "modulate:a", 0.0, 0.3)
		tw.tween_callback(hand.queue_free)
	get_tree().create_timer(0.55).timeout.connect(func() -> void:
		if not is_inside_tree():
			return
		_burst(mid, PackedColorArray([Color("ffd400"), Color.WHITE, Color("28c8ff")]), 30, 2.2, 0.05)
		var clap := _object("👏", 1.1)
		clap.global_position = mid + Vector3.UP * 0.15
		var tw2 := create_tween()
		tw2.tween_property(clap, "scale", Vector3.ONE * 1.4, 0.2).from(Vector3.ONE * 0.4)
		tw2.tween_interval(0.5)
		tw2.tween_property(clap, "modulate:a", 0.0, 0.3)
		tw2.tween_callback(clap.queue_free))
	return "hit"


## Harmless cartoon flames along the bottom front of the main screen.
func _stage_fire(secs: float) -> void:
	var sz: Vector2 = _screen["size"]
	var right: Vector3 = _screen["right"]
	var n: Vector3 = _screen["normal"]
	var base: Vector3 = (_screen["pos"] as Vector3) - Vector3.UP * sz.y * 0.5 + n * 0.35
	var spots := clampi(int(sz.x / 0.7), 3, 9)
	for i in spots:
		var at := base + right * lerpf(-0.45, 0.45, float(i) / float(maxi(spots - 1, 1))) * sz.x
		var f := CPUParticles3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(0.22, 0.22) * (_size() / object_size)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.vertex_color_use_as_albedo = true
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		mat.albedo_texture = _soft_dot()
		quad.material = mat
		f.mesh = quad
		f.amount = 40
		f.lifetime = 0.9
		f.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		f.emission_box_extents = Vector3(0.25, 0.02, 0.1)
		f.direction = Vector3.UP
		f.spread = 12.0
		f.gravity = Vector3(0, 1.5, 0)
		f.initial_velocity_min = 0.8
		f.initial_velocity_max = 1.6
		f.scale_amount_min = 0.6
		f.scale_amount_max = 1.3
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.35, 0.75, 1.0])
		g.colors = PackedColorArray([Color(1, 0.95, 0.5, 1), Color(1, 0.6, 0.1, 0.9), Color(0.9, 0.2, 0.05, 0.6), Color(0.3, 0.3, 0.3, 0.0)])
		f.color_ramp = g
		f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(f)
		f.global_position = at
		f.emitting = true
		_live += 1
		f.tree_exiting.connect(func() -> void: _live -= 1)
		var life := f.create_tween()      # bound to the emitter: gone with it if the room changes
		life.tween_interval(secs)
		life.tween_property(f, "emitting", false, 0.0)
		life.tween_interval(f.lifetime + 0.2)
		life.tween_callback(f.queue_free)
		if i % 2 == 0:
			var flame := _object("🔥", 1.3)
			flame.global_position = at + Vector3.UP * 0.15
			var tw := create_tween()
			var hops := maxi(int(secs / 0.4), 1)
			for k in hops:
				tw.tween_property(flame, "scale", Vector3(1.0, 1.15, 1.0), 0.2)
				tw.tween_property(flame, "scale", Vector3(1.05, 0.92, 1.0), 0.2)
			tw.tween_property(flame, "modulate:a", 0.0, 0.4)
			tw.tween_callback(flame.queue_free)
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.55, 0.15)
	glow.omni_range = maxf(sz.x, 6.0)
	glow.shadow_enabled = false
	add_child(glow)
	glow.global_position = base + Vector3.UP * 0.8 + n * 0.6
	var gtw := create_tween()
	var steps := maxi(int(secs / _strobe_step(0.12)), 2)
	for k in steps:
		gtw.tween_property(glow, "light_energy", randf_range(1.5, 3.5) * _flash_k(), _strobe_step(0.12))
	gtw.tween_property(glow, "light_energy", 0.0, 0.4)
	gtw.tween_callback(glow.queue_free)


## Bursts of colour over the stage, one after another, each with a flash of light.
func _fireworks(count: int, secs: float) -> void:
	var sz: Vector2 = _screen["size"]
	var sets: Array[PackedColorArray] = [
		PackedColorArray([Color("ff3b6b"), Color("ffb400"), Color.WHITE]),
		PackedColorArray([Color("28c8ff"), Color("a55bff"), Color.WHITE]),
		PackedColorArray([Color("53fc18"), Color("ffd400"), Color.WHITE]),
		PackedColorArray([Color("ff8a3d"), Color("ff3b6b"), Color("ffd400")]),
	]
	for i in count:
		var delay := secs * float(i) / float(count) + randf() * 0.2
		get_tree().create_timer(delay).timeout.connect(func() -> void:
			if not is_inside_tree():
				return
			var at: Vector3 = (_screen["pos"] as Vector3) + (_screen["right"] as Vector3) * randf_range(-0.45, 0.45) * sz.x \
				+ Vector3.UP * (sz.y * randf_range(0.2, 0.7)) + (_screen["normal"] as Vector3) * randf_range(0.8, 2.0)
			var cols: PackedColorArray = sets[randi() % sets.size()]
			_burst(at, cols, 70, 4.5, 0.05)
			var flash := OmniLight3D.new()
			flash.light_color = cols[0]
			flash.omni_range = 9.0
			flash.shadow_enabled = false
			flash.light_energy = 4.0 * _flash_k()
			add_child(flash)
			flash.global_position = at
			var tw := create_tween()
			tw.tween_property(flash, "light_energy", 0.0, 0.6 if not _safe() else 1.0)
			tw.tween_callback(flash.queue_free))


func _spotlight(p: Dictionary, at: Vector3) -> void:
	var light := SpotLight3D.new()
	light.light_color = _color(p.get("color", ""), Color("fff6d0"))
	light.spot_angle = 11.0
	light.spot_range = 14.0
	light.shadow_enabled = false
	light.light_energy = 0.0
	light.light_volumetric_fog_energy = 2.0
	add_child(light)
	var from := at + _towards_camera(at) * 2.5 + Vector3.UP * 3.5
	light.global_position = from
	light.look_at(at, Vector3.UP if absf((at - from).normalized().y) < 0.99 else Vector3.FORWARD)
	var secs := clampf(float(p.get("duration_sec", 6.0)), 1.0, 30.0)
	var tw := create_tween()
	tw.tween_property(light, "light_energy", 12.0, 0.3)
	tw.tween_interval(secs)
	tw.tween_property(light, "light_energy", 0.0, 0.5)
	tw.tween_callback(light.queue_free)


func _lights(p: Dictionary) -> void:
	var mode := String(p.get("mode", "flicker"))
	var col := _color(p.get("color", ""), Color("ff3b6b"))
	var secs := clampf(float(p.get("duration_sec", 3.0)), 0.5, 20.0)
	var light := OmniLight3D.new()
	light.light_color = col if mode != "dim" else Color.WHITE
	light.omni_range = 40.0
	light.omni_attenuation = 0.4
	light.shadow_enabled = false
	light.light_energy = 0.0
	add_child(light)
	var box := AABB(_screen["pos"] as Vector3, Vector3.ZERO)
	if _audience and _audience.get_seat_count() > 0:
		box = box.merge(_audience.get_seats_bounds())
	light.global_position = box.get_center() + Vector3.UP * 2.5
	var tw := create_tween()
	match mode:
		"dim":        # negative light darkens the room for a moment
			tw.tween_property(light, "light_energy", -2.5, 0.4)
			tw.tween_interval(secs)
			tw.tween_property(light, "light_energy", 0.0, 0.6)
		"tint":
			tw.tween_property(light, "light_energy", 3.0, 0.4)
			tw.tween_interval(secs)
			tw.tween_property(light, "light_energy", 0.0, 0.6)
		"flash":      # a white flash that fades out (FLASHBANG)
			light.light_color = Color.WHITE
			light.omni_range = 60.0
			# safe mode: a soft swell instead of a 0.05 s white-out
			tw.tween_property(light, "light_energy", 16.0 * _flash_k(), 0.05 if not _safe() else 0.45)
			tw.tween_property(light, "light_energy", 0.0, maxf(secs, 0.4 if not _safe() else 1.0)).set_ease(Tween.EASE_IN)
			EventBus.camera_shake_requested.emit(0.25, 0.3)
		"police":     # red and blue take turns
			var blue := OmniLight3D.new()
			blue.light_color = Color(0.15, 0.35, 1.0)
			blue.omni_range = light.omni_range
			blue.omni_attenuation = light.omni_attenuation
			blue.shadow_enabled = false
			blue.light_energy = 0.0
			add_child(blue)
			var sz2: Vector2 = _screen["size"]
			light.light_color = Color(1.0, 0.1, 0.1)
			light.global_position += (_screen["right"] as Vector3) * sz2.x * 0.4
			blue.global_position = light.global_position - (_screen["right"] as Vector3) * sz2.x * 0.8
			var flip := _strobe_step(0.25)
			var e := 5.0 * _flash_k()
			var flips := maxi(int(secs / flip), 2)
			for i in flips:
				var red_on := i % 2 == 0
				tw.tween_callback(func() -> void:
					if is_instance_valid(blue):
						light.light_energy = e if red_on else 0.0
						blue.light_energy = 0.0 if red_on else e)
				tw.tween_interval(flip)
			tw.tween_callback(func() -> void:
				light.light_energy = 0.0
				if is_instance_valid(blue):
					blue.queue_free())
		_:
			var step := _strobe_step(0.09)
			var steps := maxi(int(secs / step), 2)
			for i in steps:
				tw.tween_property(light, "light_energy", randf_range(0.0, 5.0) * _flash_k() if i % 2 == 0 else -1.0 * _flash_k(), step)
			tw.tween_property(light, "light_energy", 0.0, 0.2)
	tw.tween_callback(light.queue_free)


# ── Meters ───────────────────────────────────────────────────
func _on_meter(meter_id: String, label: String, value: float, goal: float) -> void:
	var existing: Variant = _meters.get(meter_id)
	var l: Label3D = existing as Label3D if is_instance_valid(existing) else null
	if l == null:
		if value <= 0.0:
			return
		l = Label3D.new()
		l.font = SpeechBubble.shared_font()
		l.font_size = 64
		l.outline_size = 16
		l.pixel_size = 0.005
		l.no_depth_test = true
		l.render_priority = 11
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		add_child(l)
		var sz: Vector2 = _screen["size"]
		l.global_position = (_screen["pos"] as Vector3) + Vector3.UP * (sz.y * 0.5 + 0.35) + (_screen["normal"] as Vector3) * 0.2
		_meters[meter_id] = l
	var cells := 12
	var filled := clampi(int(round(value / maxf(goal, 1.0) * cells)), 0, cells)
	l.text = "%s  %s%s" % [label, "▰".repeat(filled), "▱".repeat(cells - filled)]
	l.modulate = Color(1, 1, 1, 1)
	if value <= 0.0:
		var tw := create_tween()
		tw.tween_interval(0.8)
		tw.tween_property(l, "modulate:a", 0.0, 0.6)
		tw.tween_callback(func() -> void:
			if is_instance_valid(l) and _meters.get(meter_id) == l:
				_meters.erase(meter_id)
				l.queue_free())


# ── Helpers ──────────────────────────────────────────────────
func _floor_y(near: Vector3) -> float:
	var space := get_world_3d().direct_space_state if is_inside_tree() else null
	if space:
		var q := PhysicsRayQueryParameters3D.create(near + Vector3.UP * 0.5, near + Vector3.DOWN * 20.0)
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			return (hit["position"] as Vector3).y
	var sz: Vector2 = _screen.get("size", Vector2(3, 2))
	return (_screen.get("pos", near) as Vector3).y - sz.y * 0.5 - 0.6


func _color(v: Variant, fallback: Color) -> Color:
	if v is String and Color.html_is_valid(String(v)):
		return Color.html(String(v))
	if v is Color:
		return v
	return fallback


## Splat colour when the settings don't give one.
func _guess_color(obj: String) -> Color:
	if obj.contains("🥚") or obj.contains("🍳"):
		return Color("f5e7a0")
	if obj.contains("🥧") or obj.contains("🎂") or obj.contains("🍰"):
		return Color("f4efe2")
	if obj.contains("🍌") or obj.contains("🍋"):
		return Color("f2d23c")
	if obj.contains("🥦") or obj.contains("🥬") or obj.contains("🍏"):
		return Color("62b83a")
	if obj.contains("🍇") or obj.contains("🍆"):
		return Color("7a3a9a")
	return Color("d8321f")


static var _dot_tex: Texture2D


## A soft round blob (flames).
static func _soft_dot() -> Texture2D:
	if _dot_tex == null:
		var g := GradientTexture2D.new()
		g.width = 64
		g.height = 64
		g.fill = GradientTexture2D.FILL_RADIAL
		g.fill_from = Vector2(0.5, 0.5)
		g.fill_to = Vector2(0.5, 0.0)
		var grad := Gradient.new()
		grad.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
		grad.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.5), Color(1, 1, 1, 0)])
		g.gradient = grad
		_dot_tex = g
	return _dot_tex


static func _splat_texture() -> Texture2D:
	if _splat_tex:
		return _splat_tex
	var img := Image.create(SPLAT_PX, SPLAT_PX, false, Image.FORMAT_RGBA8)
	var c := SPLAT_PX * 0.5
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var lobes: Array[Vector3] = []   # extra droplets: x, y, radius
	for i in 9:
		var ang := rng.randf() * TAU
		var dist := rng.randf_range(0.28, 0.46) * SPLAT_PX
		lobes.append(Vector3(c + cos(ang) * dist, c + sin(ang) * dist, rng.randf_range(3.0, 8.0)))
	var k := [rng.randf_range(0, TAU), rng.randf_range(0, TAU), rng.randf_range(0, TAU)]
	for y in SPLAT_PX:
		for x in SPLAT_PX:
			var dx := x - c
			var dy := y - c
			var ang2 := atan2(dy, dx)
			var r := SPLAT_PX * (0.27 + 0.05 * sin(ang2 * 5.0 + k[0]) + 0.03 * sin(ang2 * 9.0 + k[1]) + 0.02 * sin(ang2 * 13.0 + k[2]))
			var d := sqrt(dx * dx + dy * dy)
			var a := clampf((r - d) / 2.0, 0.0, 1.0)
			for l in lobes:
				var dd := Vector2(x - l.x, y - l.y).length()
				a = maxf(a, clampf((l.z - dd) / 1.5, 0.0, 1.0))
			var shade := 0.82 + 0.18 * clampf(1.0 - d / (SPLAT_PX * 0.3), 0.0, 1.0)
			img.set_pixel(x, y, Color(shade, shade, shade, a))
	_splat_tex = ImageTexture.create_from_image(img)
	return _splat_tex


func _on_setting_changed(key: String, _value: Variant) -> void:
	if key.begins_with("presenter_") and key.ends_with("_on"):
		_collect_guests()
		_register()


# ── Flash safety ─────────────────────────────────────────────
## How bright flashing light gets: the "Flash strength" slider, capped at 30% in photosensitive-safe mode.
func _flash_k() -> float:
	var k := clampf(float(AppState.get_setting("flash_strength")), 0.0, 1.0)
	return minf(k, SAFE_FLASH_CAP) if _safe() else k


func _safe() -> bool:
	return bool(AppState.get_setting("photosensitive_safe"))


## Time between light changes. Safe mode keeps it to under 3 flashes a second (each flash is an
## on + off, so steps of at least 1/6 s ... we use 0.35 s for a margin).
func _strobe_step(normal: float) -> float:
	return maxf(normal, SAFE_STROBE_STEP) if _safe() else normal


const SAFE_FLASH_CAP: float = 0.3
const SAFE_STROBE_STEP: float = 0.35
