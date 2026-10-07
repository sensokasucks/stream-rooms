extends Node
## Reactions: the game side of Stream Core's chat reactions (🍅, !tomato @bob ...).
##
## Stream Core owns the rules (permissions, cooldowns, points, opt-outs). This manager:
##   - introduces the game to Core ("hello" with the effects it can play) on every connect,
##   - keeps Core told what the current room offers ("room_state": targets, guests, seated),
##   - passes Core's reactions to the room's ReactionLayer (EventBus.reaction_play),
##   - reports each result back ("reaction_result": hit / fallback / dropped, dropped refunds),
##   - owns applause / boo meters, which live across room changes.
## Protocol: FlaVR_leftovers/fridge-stream-core/docs/REACTIONS.md

const PROTOCOL: int = 1
## A reaction the room never reports on counts as dropped after this long.
const RESULT_TIMEOUT: float = 20.0
## room_state is sent at most this often (seats change a lot during busy chat).
const ROOM_STATE_MIN_GAP: float = 1.0

## The effects this game can play. Settings (params) are left to Core's built-in list except
## where the game adds its own; Core fills in defaults and sends them with each reaction.
const EFFECTS: Array[Dictionary] = [
	{"id": "throw", "label": "Throw at target", "targeted": true, "params": [
		{"name": "object", "type": "text", "default": "🍅", "label": "Object (emoji)"},
		{"name": "impact", "type": "select", "default": "splat", "options": ["splat", "bounce", "stick", "shatter"]},
		{"name": "stick_sec", "type": "number", "default": 6, "label": "Splat stays (s)", "min": 0, "max": 60},
		{"name": "arc_height", "type": "number", "default": 1.0, "label": "Arc height", "min": 0.2, "max": 4},
		{"name": "splat_color", "type": "color", "default": "#d8321f", "label": "Splat colour"},
	]},
	{"id": "pile_up", "label": "Pile up on stage", "targeted": true, "params": []},
	{"id": "float_up", "label": "Float up from seat", "targeted": false, "params": []},
	{"id": "fall_down", "label": "Drift down on target", "targeted": true, "params": []},
	{"id": "rain", "label": "Rain across the room", "targeted": false, "params": []},
	{"id": "confetti", "label": "Confetti burst", "targeted": true, "params": []},
	{"id": "wiggle", "label": "Sender's silhouette moves", "targeted": false, "params": []},
	{"id": "stand_cheer", "label": "Stand and cheer", "targeted": false, "params": []},
	{"id": "big_shout", "label": "Big shout bubble", "targeted": false, "params": []},
	{"id": "stadium_wave", "label": "Stadium wave", "targeted": false, "params": []},
	{"id": "spotlight", "label": "Spotlight", "targeted": true, "params": []},
	{"id": "lights", "label": "Room lights", "targeted": false, "params": []},
	{"id": "camera_shake", "label": "Camera shake", "targeted": false, "params": []},
	{"id": "meter", "label": "Applause / boo meter", "targeted": false, "params": []},
	{"id": "crowd_motion", "label": "Crowd moves", "targeted": false, "params": []},
	{"id": "sign", "label": "Hold up a sign", "targeted": false, "params": []},
	{"id": "seat_prop", "label": "Seat prop", "targeted": false, "params": []},
	{"id": "highfive", "label": "High five", "targeted": true, "params": []},
	{"id": "seat_move", "label": "Move seat", "targeted": false, "params": []},
	{"id": "seat_swap", "label": "Swap seats", "targeted": true, "params": []},
	{"id": "stage_fire", "label": "Stage fire (cartoon)", "targeted": false, "params": []},
	{"id": "fireworks", "label": "Fireworks", "targeted": false, "params": []},
]

var _room_id: String = ""
var _room_open: bool = false
var _room_owner: int = 0          # instance id of the ReactionLayer that registered last
var _targets: Array = []          # [{id, label, aliases}]
var _guests: Array = []           # [{id, name, aliases}]
var _state_dirty: bool = false
var _state_wait: float = 0.0
var _pending: Dictionary = {}     # reaction id -> seconds left before it counts as dropped
var _meters: Dictionary = {}      # meter id -> {value, goal, decay, label, idle}
var _last: Array[Dictionary] = [] # recent reactions for the panel: {reaction, from, target, outcome}


func _ready() -> void:
	EventBus.chat_status_changed.connect(_on_chat_status)
	EventBus.reaction_received.connect(_on_reaction)
	EventBus.reaction_finished.connect(_on_finished)
	EventBus.audience_seated.connect(_on_seats_changed)
	EventBus.audience_left.connect(_on_seats_changed)
	EventBus.room_changed.connect(_on_room_changed)
	EventBus.curtain_changed.connect(func(_c: bool, _s: String) -> void: _send_stage_state())


func _process(delta: float) -> void:
	_state_wait = maxf(_state_wait - delta, 0.0)
	if _state_dirty and _state_wait <= 0.0:
		_send_room_state()
	for id: String in _pending.keys():
		_pending[id] = float(_pending[id]) - delta
		if float(_pending[id]) <= 0.0:
			_pending.erase(id)
			_report(id, "dropped")
	_decay_meters(delta)


# ── Public API ───────────────────────────────────────────────
## Called by a room's ReactionLayer once it knows what the room offers.
## targets: [{id, label, aliases}], guests: [{id, name, aliases}]. owner: the layer itself.
func set_room_targets(layer: Object, targets: Array, guests: Array) -> void:
	_room_owner = layer.get_instance_id()
	_targets = targets.duplicate(true)
	_guests = guests.duplicate(true)
	_room_open = true
	_mark_dirty()


## Called by the ReactionLayer when its room goes away. The old room is freed after the
## new one has registered, so only the layer that registered last can close the room.
func clear_room(layer: Object) -> void:
	if layer.get_instance_id() != _room_owner:
		return
	_room_open = false
	_targets.clear()
	_guests.clear()
	_mark_dirty()


func get_effect_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for e in EFFECTS:
		out.append(String(e["id"]))
	return out


func get_recent() -> Array[Dictionary]:
	return _last.duplicate()


## Plays a made-up reaction in the current room (panel "Test" button). Nothing is sent to Core.
func play_test(effect: String, target: Dictionary = {}, params: Dictionary = {}) -> void:
	var names := ChatFeed.TEST_NAMES
	var who := names[randi() % names.size()]
	var slot := -1
	for i in AudienceManager.get_capacity():
		if not AudienceManager.get_seat_member(i).is_empty():
			slot = i
			break
	if slot >= 0:
		who = String(AudienceManager.get_seat_member(slot)["name"])
	var d := {"id": "test-%d" % Time.get_ticks_msec(), "reaction": effect, "label": effect, "effect": effect,
		"params": params, "count": 1, "target": _or_null(target),
		"from": {"platform": "test", "id": who.to_lower(), "username": who.to_lower(), "display_name": who},
		"route": "game", "message": "", "test": true}
	_on_reaction(d)


# ── Core link ────────────────────────────────────────────────
func _on_chat_status(info: Dictionary) -> void:
	if not bool(info.get("connected", false)):
		return
	var effects: Array = []
	for e in EFFECTS:
		effects.append(e.duplicate(true))
	ChatFeed.send_message({"type": "hello", "data": {
		"client": "stream_rooms", "protocol": PROTOCOL, "effects": effects}})
	_state_wait = 0.0
	_send_room_state()
	_send_stage_state()


## Tells Core whether the stage curtain is open (Admin → Live controls shows it).
func _send_stage_state() -> void:
	ChatFeed.send_message({"type": "stage_state", "data": {"curtain": "closed" if AppState.is_curtain_closed() else "open"}})


func _on_room_changed(room_id: String) -> void:
	_room_id = room_id
	_mark_dirty()


func _on_seats_changed(_slot: int) -> void:
	_mark_dirty()


func _mark_dirty() -> void:
	_state_dirty = true


func _send_room_state() -> void:
	_state_dirty = false
	_state_wait = ROOM_STATE_MIN_GAP
	var data := {"room": _room_id if _room_open else "", "targets": _targets, "guests": _guests}
	# No seats in this room -> leave "seated" out, so Core doesn't refuse @names we can still show.
	if AudienceManager.get_capacity() > 0:
		data["seated"] = Array(AudienceManager.get_seated_names())
	ChatFeed.send_message({"type": "room_state", "data": data})


# ── Reactions ────────────────────────────────────────────────
func _on_reaction(d: Dictionary) -> void:
	if String(d.get("route", "game")) != "game":
		return            # meant for the browser fallback overlay
	var id := String(d.get("id", ""))
	if not bool(AppState.get_setting("reactions_enabled")) or not _room_open:
		_report(id, "dropped")
		return
	if String(d.get("effect", "")) == "meter":
		_meter_add(d)
		_report(id, "hit")
		return
	if not get_effect_ids().has(String(d.get("effect", ""))):
		_report(id, "dropped")
		return
	if id != "":
		_pending[id] = RESULT_TIMEOUT
	_remember(d, "sent")
	d["seed"] = randi()        # streaming together: the same throw lands in the same place on every PC
	EventBus.reaction_play.emit(d)


func _on_finished(reaction_id: String, outcome: String) -> void:
	if not _pending.has(reaction_id):
		return
	_pending.erase(reaction_id)
	_report(reaction_id, outcome)


func _report(reaction_id: String, outcome: String) -> void:
	for r in _last:
		if String(r["id"]) == reaction_id:
			r["outcome"] = outcome
	if reaction_id == "" or reaction_id.begins_with("test-"):
		return
	ChatFeed.send_message({"type": "reaction_result", "data": {"id": reaction_id, "outcome": outcome}})


func _remember(d: Dictionary, outcome: String) -> void:
	var from: Dictionary = d.get("from", {}) if d.get("from") is Dictionary else {}
	var t: Variant = d.get("target")
	_last.push_front({"id": String(d.get("id", "")), "reaction": String(d.get("reaction", d.get("effect", ""))),
		"from": String(from.get("display_name", from.get("username", ""))),
		"target": String((t as Dictionary).get("name", (t as Dictionary).get("type", ""))) if t is Dictionary else "",
		"outcome": outcome})
	while _last.size() > 12:
		_last.pop_back()


# ── Meters (applause / boo) ──────────────────────────────────
func _meter_add(d: Dictionary) -> void:
	var p: Dictionary = d.get("params", {}) if d.get("params") is Dictionary else {}
	var mid := String(p.get("meter_id", "applause"))
	var goal := maxf(float(p.get("goal", 20)), 1.0)
	var m: Dictionary = _meters.get(mid, {"value": 0.0})
	m["goal"] = goal
	m["decay"] = maxf(float(p.get("decay_sec", 20)), 1.0)
	m["idle"] = 0.0
	m["label"] = String(d.get("label", mid))
	m["value"] = minf(float(m["value"]) + maxf(float(d.get("count", 1)), 1.0), goal)
	_meters[mid] = m
	_remember(d, "hit")
	EventBus.reaction_meter_changed.emit(mid, String(m["label"]), float(m["value"]), goal)
	if float(m["value"]) >= goal:
		m["value"] = 0.0
		var payoff := String(p.get("payoff_effect", "confetti"))
		EventBus.reaction_meter_changed.emit(mid, String(m["label"]), 0.0, goal)
		if get_effect_ids().has(payoff) and payoff != "meter":
			EventBus.reaction_play.emit({"id": "", "reaction": mid, "label": String(m["label"]), "effect": payoff,
				"params": {"count": 160}, "count": 1, "target": null, "from": d.get("from", {}), "route": "game", "seed": randi()})


func _decay_meters(delta: float) -> void:
	for mid: String in _meters.keys():
		var m: Dictionary = _meters[mid]
		if float(m["value"]) <= 0.0:
			continue
		m["idle"] = float(m["idle"]) + delta
		if float(m["idle"]) < 3.0:
			continue          # a short grace period before it starts draining
		var before := float(m["value"])
		m["value"] = maxf(before - float(m["goal"]) * delta / float(m["decay"]), 0.0)
		if int(before) != int(float(m["value"])) or float(m["value"]) == 0.0:
			EventBus.reaction_meter_changed.emit(mid, String(m["label"]), float(m["value"]), float(m["goal"]))


## A Dictionary, or null when it's empty (a ternary with two types is a warning).
func _or_null(d: Dictionary) -> Variant:
	if d.is_empty():
		return null
	return d
