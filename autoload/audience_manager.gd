extends Node
## AudienceManager: who sits where in the virtual audience. Single source of truth
## for the roster; rooms only draw it (core/audience_view.gd).
##   - Someone who chats gets a free seat and keeps it while they're active. Which seat
##     depends on "audience_seating": random, front (front row first, centre outwards) or
##     front_random (front row first, a random seat within that row).
##   - No chat for "audience_idle_min" minutes -> they leave their seat.
##   - All seats full -> the person idle the longest gives up their seat.
##   - Each person has a colour (platform colour or one picked from their name) and a
##     speech-bubble shape, so they look the same every time they come back.
## The roster survives room changes; each room reports how many seats it has.
## Slots come in three kinds (set_slot_kinds, from the room's audience view):
##   KIND_SEAT       the main audience seats (full silhouettes). Chatters sit here first.
##   KIND_CROWD      the room's big crowd seats (tiers, balcony ...). When the main seats are
##                   full, chatters overflow into these (they take a filler person's place).
##   KIND_PRESENTER  a presenter's spot. Only the chatter linked to that presenter
##                   (Presenters tab: "Chat name") sits there; they never take an audience seat,
##                   never time out while the presenter is on set, and can't be moved or swapped.
## Sections (set_slot_sections, from the audience view): the main seats as four quadrants
## (Q1 front left, Q2 front right, Q3 back left, Q4 back right, as the audience faces the
## stage) and the crowd seats as stadium sections (101.. lower tier, 201.. balcony, 301..
## gallery). With "seating_by_platform" on, the seating plan ("seating_plan") says which
## platforms may sit in each section, so platforms can be kept physically apart.
## Streaming together (NetSession, docs/MULTIPLAYER.md phase 4): the host seats everyone's
## viewers (guests send their chat over, add_chat) and can give each streamer's viewers their own
## area (set_streamer_areas). A guest is a "mirror": it seats nobody itself and shows the host's
## roster (mirror_*), so every PC shows the same people in the same seats.

const BUBBLE_STYLES: int = 4
const KIND_SEAT: int = 0
const KIND_CROWD: int = 1
const KIND_PRESENTER: int = 2
const LINK_PLATFORMS: Dictionary = {"kick": "kick", "twitch": "twitch", "youtube": "youtube", "yt": "youtube", "tiktok": "tiktok"}
const MAX_TEXT: int = 140
## An emote counts as this many characters toward MAX_TEXT.
const EMOTE_WEIGHT: int = 3
const KICK_EMOTE_URL: String = "https://files.kick.com/emotes/%s/fullsize"

## key "platform:user_id" -> {key, name, color: Color, style: int, slot: int, last: float}
var _members: Dictionary = {}
var _slots: Array[String] = []      # slot -> member key ("" = empty)
## Seat layout from the room (set_seat_layout): row per slot (0 = front) and the
## "front" filling order (front row first, centre outwards). Empty = unknown (random).
var _seat_row: PackedInt32Array = []
var _seat_order: PackedInt32Array = []
## Seats whose distance from the stage differs by less than this share a row (metres).
const ROW_TOLERANCE: float = 0.35
const SEATING_MODES: PackedStringArray = ["random", "front", "front_random"]
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _check_in: float = 1.0
var _ignore: PackedStringArray = []
var _hide_avatars: PackedStringArray = []
var _kind: PackedByteArray = []          # slot -> KIND_* (missing = KIND_SEAT)
var _presenter_slot: Dictionary = {}     # presenter n -> slot, for this room's podiums
var _links: Dictionary = {}              # presenter n -> [{platform, name}] (lower case, no "@")
var _section: PackedStringArray = []     # slot -> section id ("" = none, e.g. a presenter spot)
var _section_info: Dictionary = {}       # section id -> {label, kind, order}
var _spots: Array[Vector3] = []          # slot -> seat position (for the seating chart)
var _stage_point: Variant = null
var _plan: Dictionary = {}               # section id -> PackedStringArray of platform groups (empty = anyone)
const PLATFORMS: PackedStringArray = ["kick", "twitch", "youtube", "other"]
const PLATFORM_LABELS: Dictionary = {"kick": "Kick", "twitch": "Twitch", "youtube": "YouTube", "other": "Other"}
var _mirror: bool = false                # guest: showing the host's roster
var _capacity_room: String = ""          # the room the slots belong to (mirror: rosters are per room)
var _pending_roster: Dictionary = {}     # mirror: {room, list} that arrived before its room was ready
var _area_count: int = 0                 # host: streamers sharing the audience (0 = no areas)
var _area_cache: Dictionary = {}         # section id -> streamer index


func _ready() -> void:
	_rng.randomize()
	_parse_ignore()
	_parse_hidden_avatars()
	_parse_links()
	_parse_plan()
	EventBus.chat_message_received.connect(_on_chat)
	EventBus.chat_user_updated.connect(_on_user_updated)
	EventBus.setting_changed.connect(_on_setting_changed)


func _process(delta: float) -> void:
	if _mirror:
		return            # the host decides who leaves
	_check_in -= delta
	if _check_in > 0.0:
		return
	_check_in = 1.0
	_expire_idle()


# ── Public API ───────────────────────────────────────────────
## Called by a room's audience view: how many seats this room has (0 = none).
func set_capacity(count: int) -> void:
	count = maxi(count, 0)
	_capacity_room = String(AppState.get_setting("room_id"))
	if _mirror:
		for i in _slots.size():
			if _slots[i] != "":
				_unseat(i, true)
		_members.clear()
		_slots.resize(count)
		_slots.fill("")
		if String(_pending_roster.get("room", "")) == _capacity_room:
			mirror_roster(_capacity_room, _pending_roster["list"])
		_pending_roster = {}
		_emit_count()
		EventBus.seating_changed.emit()
		return
	# unseat anyone whose seat no longer exists (they stay in the roster)
	for i in range(count, _slots.size()):
		if _slots[i] != "":
			_members[_slots[i]]["slot"] = -1
	_slots.resize(count)
	for i in count:
		if _slots[i] != "" and not _members.has(_slots[i]):
			_slots[i] = ""
	# seat waiting members, most recently active first
	var waiting: Array = _members.values().filter(func(m: Dictionary) -> bool: return int(m["slot"]) < 0)
	waiting.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["last"]) > float(b["last"]))
	for m: Dictionary in waiting:
		var ps := _presenter_spot_for(m)
		if ps >= 0:
			if _slots[ps] == "":
				_seat(m, ps, false)
			continue
		var s := _free_slot(_group_of(m))
		if s < 0:
			continue
		_seat(m, s, false)
	_fill_from_crowd()
	_emit_count()
	EventBus.seating_changed.emit()


## Called by the room's audience view before set_capacity: the kind of every slot and which
## slot is each presenter's spot (presenter n -> slot). Anyone left in a slot that doesn't
## suit them (a presenter's spot they aren't linked to, or an audience seat while their
## presenter spot exists) is taken out; set_capacity seats them again.
func set_slot_kinds(kinds: PackedByteArray, presenter_slots: Dictionary) -> void:
	_kind = kinds
	_presenter_slot = presenter_slots.duplicate()
	if _mirror:
		return
	for i in _slots.size():
		var k := _slots[i]
		if k == "" or not _members.has(k):
			continue
		var m: Dictionary = _members[k]
		var want := _presenter_spot_for(m)
		if (want >= 0 and want != i) or (want < 0 and get_slot_kind(i) == KIND_PRESENTER):
			_slots[i] = ""
			m["slot"] = -1


## KIND_SEAT / KIND_CROWD / KIND_PRESENTER.
func get_slot_kind(slot: int) -> int:
	return _kind[slot] if slot >= 0 and slot < _kind.size() else KIND_SEAT


## Slot of presenter n's spot in this room, or -1.
func get_presenter_slot(n: int) -> int:
	return int(_presenter_slot.get(n, -1))


## Presenter number of a presenter-spot slot, or 0.
func get_slot_presenter(slot: int) -> int:
	for n: int in _presenter_slot.keys():
		if int(_presenter_slot[n]) == slot:
			return n
	return 0


func get_capacity() -> int:
	return _slots.size()


## Called by a room's audience view with each seat's position (same order as the slots)
## and the stage point (middle of the main screen; null = the front is toward -Z).
## Seats are grouped into rows by their distance from the stage along the stage axis.
func set_seat_layout(spots: Array[Vector3], stage_point: Variant = null) -> void:
	_seat_row = PackedInt32Array()
	_seat_order = PackedInt32Array()
	_spots = spots.duplicate()
	_stage_point = stage_point
	var n := spots.size()
	if n == 0:
		return
	var audience: Array[int] = []      # presenter spots have no row and are never "free"
	for i in n:
		if get_slot_kind(i) != KIND_PRESENTER:
			audience.append(i)
	if audience.is_empty():
		_seat_row.resize(n)
		_seat_row.fill(-1)
		return
	var centre := Vector3.ZERO
	for i in audience:
		centre += spots[i]
	centre /= float(audience.size())
	var stage: Vector3 = stage_point if stage_point is Vector3 else centre + Vector3(0, 0, -100.0)
	var axis := Vector2(centre.x - stage.x, centre.z - stage.z)      # from the stage toward the audience
	axis = axis.normalized() if axis.length() > 0.001 else Vector2(0, 1)
	var across := Vector2(-axis.y, axis.x)
	var depth: Array[float] = []
	var side: Array[float] = []
	for p in spots:
		depth.append(Vector2(p.x - stage.x, p.z - stage.z).dot(axis))
		side.append(absf(Vector2(p.x - centre.x, p.z - centre.z).dot(across)))
	var by_depth: Array[int] = audience.duplicate()
	by_depth.sort_custom(func(a: int, b: int) -> bool: return depth[a] < depth[b])
	_seat_row.resize(n)
	_seat_row.fill(-1)
	var row := 0
	var row_start := depth[by_depth[0]]
	for i in by_depth:
		if depth[i] - row_start > ROW_TOLERANCE:
			row += 1
			row_start = depth[i]
		_seat_row[i] = row
	var order: Array[int] = []
	order.assign(by_depth)
	order.sort_custom(func(a: int, b: int) -> bool:
		if _seat_row[a] != _seat_row[b]:
			return _seat_row[a] < _seat_row[b]
		return side[a] < side[b])
	_seat_order = PackedInt32Array(order)


## Row of a seat (0 = front), or -1 if the room gave no layout.
func get_seat_row(slot: int) -> int:
	return _seat_row[slot] if slot >= 0 and slot < _seat_row.size() else -1


## {name, color, style, avatar} for the person in a seat, or {} if it's empty.
## avatar is "" when pictures are off, hidden for this person, or unknown.
func get_seat_member(slot: int) -> Dictionary:
	if slot < 0 or slot >= _slots.size() or _slots[slot] == "":
		return {}
	var m: Dictionary = _members[_slots[slot]]
	var avatar := String(m.get("avatar", ""))
	if not bool(AppState.get_setting("audience_avatars")) or _hide_avatars.has(String(m["name"]).to_lower()):
		avatar = ""
	return {"name": m["name"], "color": m["color"], "style": m["style"], "avatar": avatar,
		"title": String(m.get("title", ""))}


## Seat of a chatter by platform + user id (as Stream Core sends them), or -1.
func find_slot_for_user(platform: String, user_id: String) -> int:
	var m: Dictionary = _members.get("%s:%s" % [platform, user_id], {})
	return int(m.get("slot", -1)) if not m.is_empty() else -1


## Seat of a chatter by login or display name (case-insensitive, "@" allowed), or -1.
func find_slot_by_name(who: String) -> int:
	var n := who.strip_edges().trim_prefix("@").to_lower()
	if n == "":
		return -1
	for i in _slots.size():
		if _slots[i] == "":
			continue
		var m: Dictionary = _members[_slots[i]]
		# YouTube names are handles that start with "@"
		if String(m["name"]).trim_prefix("@").to_lower() == n or String(m.get("username", "")).trim_prefix("@").to_lower() == n:
			return i
	return -1


## Logins and display names of everyone seated (lower case), for Stream Core's target checks.
func get_seated_names() -> PackedStringArray:
	var out := PackedStringArray()
	for k in _slots:
		if k == "":
			continue
		var m: Dictionary = _members[k]
		for n: String in [String(m["name"]).trim_prefix("@").to_lower(), String(m.get("username", "")).trim_prefix("@").to_lower()]:
			if n != "" and not out.has(n):
				out.append(n)
	return out


## Moves the person in a seat to a free seat in the front or back row. Returns the new
## seat, or -1 when there's no free seat that's nearer the front / back than where they are.
func move_to_row(slot: int, where: String) -> int:
	if _mirror:
		return -1
	if slot < 0 or slot >= _slots.size() or _slots[slot] == "" or get_slot_kind(slot) == KIND_PRESENTER:
		return -1
	var laid_out := _seat_row.size() == _slots.size()
	var here := get_slot_kind(slot)
	var group := _group_of(_members[_slots[slot]])
	# rows only compare within a kind: "front" from the crowd means any main seat first;
	# "back" stays within the kind you're in
	var kinds: Array[int] = [here]
	if where != "back":
		kinds = [KIND_SEAT, KIND_CROWD]
	for k in kinds:
		if where != "back" and here == KIND_SEAT and k == KIND_CROWD:
			break          # the crowd is never "further forward" than a main seat
		var best := -1
		for i in _slots.size():
			if _slots[i] != "" or get_slot_kind(i) != k or not slot_allows(i, group):
				continue
			if not laid_out:
				return _move(slot, i)
			if best < 0:
				best = i
			elif where == "back" and _seat_row[i] > _seat_row[best]:
				best = i
			elif where != "back" and _seat_row[i] < _seat_row[best]:
				best = i
		if best < 0:
			continue
		if k == here and ((where == "back" and _seat_row[best] <= _seat_row[slot]) or (where != "back" and _seat_row[best] >= _seat_row[slot])):
			continue      # already as far forward / back as a free seat goes
		return _move(slot, best)
	return -1


## Two people trade seats. False if either seat is empty.
func swap_seats(a: int, b: int) -> bool:
	if _mirror:
		return false       # the host's seating
	if a == b or a < 0 or b < 0 or a >= _slots.size() or b >= _slots.size() or _slots[a] == "" or _slots[b] == "":
		return false
	if get_slot_kind(a) == KIND_PRESENTER or get_slot_kind(b) == KIND_PRESENTER:
		return false
	if not slot_allows(a, _group_of(_members[_slots[b]])) or not slot_allows(b, _group_of(_members[_slots[a]])):
		return false        # the seating plan keeps these two platforms apart
	var ka := _slots[a]
	_slots[a] = _slots[b]
	_slots[b] = ka
	_members[_slots[a]]["slot"] = a
	_members[_slots[b]]["slot"] = b
	for s in [a, b]:
		EventBus.audience_left.emit(s)
		EventBus.audience_seated.emit(s)
	return true


func _move(from: int, to: int) -> int:
	var k := _slots[from]
	_slots[from] = ""
	EventBus.audience_left.emit(from)
	_slots[to] = k
	_members[k]["slot"] = to
	EventBus.audience_seated.emit(to)
	return to


func get_seated_count() -> int:
	return _slots.filter(func(k: String) -> bool: return k != "").size()


## Everyone leaves their seat.
func clear() -> void:
	for i in _slots.size():
		if _slots[i] != "":
			_slots[i] = ""
			EventBus.audience_left.emit(i)
	_members.clear()
	_emit_count()


# ── Chat handling ────────────────────────────────────────────
func _on_chat(msg: Dictionary) -> void:
	if _mirror:
		return            # a guest's chat goes to the host, who seats it (NetSession)
	add_chat(msg)


## Seats the chatter and shows their message. msg as ChatFeed normalizes it; "streamer" (int) says
## whose viewer they are when streaming together (0 = the host).
func add_chat(msg: Dictionary) -> void:
	if bool(msg.get("system", false)):
		return
	var who := String(msg.get("name", ""))
	if who == "" or is_ignored(who):
		return
	var now := Time.get_unix_time_from_system()
	var ts := float(msg.get("timestamp", now))
	var history := bool(msg.get("history", false))
	if history and now - ts > maxf(_idle_seconds(), _crowd_idle_seconds()):
		return        # old backlog from before we connected
	var key := "%s:%s" % [String(msg.get("platform", "")), String(msg.get("user_id", who.to_lower()))]
	var m: Dictionary = _members.get(key, {})
	if m.is_empty():
		m = {"key": key, "name": who, "hex": String(msg.get("color", "")),
			"platform": platform_group(String(msg.get("platform", ""))),
			"style": absi(hash(who.to_lower())) % BUBBLE_STYLES, "slot": -1, "last": ts}
		m["color"] = color_for(who, String(m["hex"]), String(m["platform"]))
		_members[key] = m
	m["last"] = maxf(float(m["last"]), minf(ts, now))
	m["name"] = who
	var login := String(msg.get("username", "")).strip_edges()
	if login != "":
		m["username"] = login
	m["streamer"] = int(msg.get("streamer", 0))
	var title := String(msg.get("title", ""))
	if title != String(m.get("title", "")):
		m["title"] = title
		if int(m["slot"]) >= 0:
			EventBus.audience_updated.emit(int(m["slot"]))
	var avatar := String(msg.get("avatar", ""))
	if avatar != "" and avatar != String(m.get("avatar", "")):
		m["avatar"] = avatar
		if int(m["slot"]) >= 0:
			EventBus.audience_updated.emit(int(m["slot"]))
	var ps := _presenter_spot_for(m)
	if ps >= 0 and int(m["slot"]) != ps:
		# a linked presenter: straight to their spot (giving up any audience seat)
		var was_main := int(m["slot"]) >= 0 and get_slot_kind(int(m["slot"])) == KIND_SEAT
		if int(m["slot"]) >= 0:
			_unseat(int(m["slot"]), false)
		if _slots[ps] != "":
			_unseat(ps, false)
		_seat(m, ps, true)
		if was_main:
			_fill_from_crowd()
	elif ps < 0 and int(m["slot"]) >= 0 and get_slot_kind(int(m["slot"])) == KIND_PRESENTER:
		_unseat(int(m["slot"]), false)      # no longer linked to that presenter
	if int(m["slot"]) < 0 and not _slots.is_empty():
		var s := _free_slot(_group_of(m))
		if s < 0:
			s = _evict_most_idle(_group_of(m))
		if s >= 0:
			_seat(m, s, true)
	if history or int(m["slot"]) < 0:
		return
	var raw := String(msg.get("text", "")).strip_edges()
	if raw == "" or (raw.begins_with("!") and bool(AppState.get_setting("audience_hide_commands"))):
		return
	var parts := message_parts(raw, msg.get("emotes", []) as Array)
	if parts.is_empty():
		return
	var reply_to := String(msg.get("reply_to", "")).strip_edges()
	if reply_to != "":
		# first part: who this answers (the bubble shows "replying to Name"); never an emote
		parts.push_front({"reply_to": reply_to.left(60), "quote": String(msg.get("reply_quote", "")).left(120)})
	EventBus.audience_spoke.emit(int(m["slot"]), parts)


func _seat(m: Dictionary, slot: int, notify_count: bool) -> void:
	m["slot"] = slot
	_slots[slot] = String(m["key"])
	EventBus.audience_seated.emit(slot)
	if notify_count:
		_emit_count()


## A free audience seat: the main seats first, then the crowd seats. Never a presenter spot.
## group: the chatter's platform group; with the seating plan on, only seats in sections that
## allow it (unless "seating_strict" is off and none is free: then any seat).
func _free_slot(group: String = "") -> int:
	var free: Array[int] = []
	var kind := KIND_SEAT
	for pass_n in 2:
		var loose := pass_n == 1
		if loose and (group == "" or not _plan_on() or bool(AppState.get_setting("seating_strict"))):
			break
		for k in [KIND_SEAT, KIND_CROWD]:
			if k == KIND_CROWD and crowd_full():
				break
			for i in _slots.size():
				if _slots[i] == "" and get_slot_kind(i) == k and (loose or slot_allows(i, group)):
					free.append(i)
			if not free.is_empty():
				kind = k
				break
		if not free.is_empty():
			break
	if free.is_empty():
		return -1
	var mode := String(AppState.get_setting("audience_seating"))
	var laid_out := _seat_row.size() == _slots.size()
	if mode == "front" and laid_out:
		for i in _seat_order:
			if _slots[i] == "" and get_slot_kind(i) == kind and free.has(i):
				return i
	elif mode == "front_random" and laid_out:
		var best := 1 << 30
		for i in free:
			best = mini(best, _seat_row[i])
		var in_row: Array[int] = []
		for i in free:
			if _seat_row[i] == best:
				in_row.append(i)
		free = in_row
	return free[_rng.randi_range(0, free.size() - 1)]


## Makes room for a new chatter: the one idle the longest gives up their seat. With the
## seating plan on, only in sections that allow the newcomer's platform (strict), else anywhere.
func _evict_most_idle(group: String = "") -> int:
	var best := -1
	var oldest := INF
	for pass_n in 2:
		var loose := pass_n == 1
		if loose and (best >= 0 or group == "" or not _plan_on() or bool(AppState.get_setting("seating_strict"))):
			break
		for i in _slots.size():
			var k := _slots[i]
			if k != "" and get_slot_kind(i) != KIND_PRESENTER and (loose or slot_allows(i, group)) and float(_members[k]["last"]) < oldest:
				oldest = float(_members[k]["last"])
				best = i
	if best >= 0:
		_unseat(best, false)
	return best


func _unseat(slot: int, forget: bool) -> void:
	var k := _slots[slot]
	if k == "":
		return
	_slots[slot] = ""
	if forget:
		_members.erase(k)
	else:
		_members[k]["slot"] = -1
	EventBus.audience_left.emit(slot)


func _expire_idle() -> void:
	if _mirror:
		return
	var now := Time.get_unix_time_from_system()
	var cutoff := now - _idle_seconds()
	var crowd_cutoff := now - _crowd_idle_seconds()
	var changed := false
	for k: String in _members.keys():
		var m: Dictionary = _members[k]
		var slot := int(m["slot"])
		if slot >= 0 and get_slot_kind(slot) == KIND_PRESENTER:
			continue       # presenters stay on their spot while they're on set
		var limit := crowd_cutoff if slot >= 0 and get_slot_kind(slot) == KIND_CROWD else cutoff
		if float(m["last"]) < limit:
			if slot >= 0:
				_unseat(slot, true)
				changed = true
			else:
				_members.erase(k)
	if _fill_from_crowd():
		changed = true
	if changed:
		_emit_count()


## "Crowd chatters move down": chatters sitting in the crowd take main seats as they free up,
## most recently active first. Returns true if anyone moved.
func _fill_from_crowd() -> bool:
	if _mirror:
		return false
	if not bool(AppState.get_setting("audience_crowd_move_down")):
		return false
	var crowd: Array = []
	for i in _slots.size():
		if _slots[i] != "" and get_slot_kind(i) == KIND_CROWD:
			crowd.append(_members[_slots[i]])
	if crowd.is_empty():
		return false
	crowd.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["last"]) > float(b["last"]))
	var moved := false
	for m: Dictionary in crowd:
		var to := _free_slot(_group_of(m))
		if to < 0 or get_slot_kind(to) != KIND_SEAT:
			continue
		_move(int(m["slot"]), to)
		moved = true
	return moved


func _emit_count() -> void:
	EventBus.audience_count_changed.emit(get_seated_count(), _slots.size())


## Chatters sitting in crowd seats right now.
func get_crowd_count() -> int:
	var n := 0
	for i in _slots.size():
		if _slots[i] != "" and get_slot_kind(i) == KIND_CROWD:
			n += 1
	return n


## "Most chatters in the crowd" ("audience_crowd_max", 0 = no limit). Each chatter in a crowd
## seat costs a silhouette, name tag and bubble; the filler crowd is free. With the cap reached,
## a new chatter takes the seat of whoever has been quiet the longest (main or crowd), the same
## way a full room behaves, so the crowd never holds more chatters than this.
func _crowd_cap() -> int:
	return maxi(int(AppState.get_setting("audience_crowd_max")), 0)


func crowd_full() -> bool:
	var cap := _crowd_cap()
	return cap > 0 and get_crowd_count() >= cap


## The cap was lowered: the crowd chatters quiet the longest leave until it fits.
func _enforce_crowd_cap() -> void:
	var cap := _crowd_cap()
	if cap <= 0:
		return
	var crowd: Array[int] = []
	for i in _slots.size():
		if _slots[i] != "" and get_slot_kind(i) == KIND_CROWD:
			crowd.append(i)
	if crowd.size() <= cap:
		return
	crowd.sort_custom(func(a: int, b: int) -> bool: return float(_members[_slots[a]]["last"]) < float(_members[_slots[b]]["last"]))
	for n in crowd.size() - cap:
		_unseat(crowd[n], false)
	_emit_count()


func _idle_seconds() -> float:
	return maxf(float(AppState.get_setting("audience_idle_min")), 0.05) * 60.0


## Idle timeout for chatters in crowd seats ("audience_crowd_idle_min").
func _crowd_idle_seconds() -> float:
	return maxf(float(AppState.get_setting("audience_crowd_idle_min")), 0.05) * 60.0


## The message as a list of text pieces and emotes ({"url", "name"}), in order.
##   - Twitch: Stream Core sends emote ranges (native + BTTV/FFZ/7TV), inclusive code points.
##   - Kick: emotes are inline tokens "[emote:123:name]".
## Spaces are tidied and the whole thing is capped at max_text (an emote counts EMOTE_WEIGHT).
## Also used by the chat screen (core/chat_screen.gd).
func message_parts(text: String, ranges: Array, max_text: int = MAX_TEXT) -> Array:
	var raw: Array = []
	var pos := 0
	var sorted := ranges.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("start", 0)) < int(b.get("start", 0)))
	for e: Dictionary in sorted:
		var s := int(e.get("start", -1))
		var t := int(e.get("end", -1))
		if s < pos or t < s or t >= text.length():
			continue
		var url := String(e.get("static_url", ""))
		if url == "":
			url = String(e.get("url", ""))
		if url == "":
			continue
		if s > pos:
			raw.append(text.substr(pos, s - pos))
		raw.append({"url": url, "name": text.substr(s, t - s + 1)})
		pos = t + 1
	if pos < text.length():
		raw.append(text.substr(pos))
	# Kick tokens inside the text pieces
	var kick := RegEx.create_from_string("\\[emote:(\\d+):([^\\]]+)\\]")
	var parts: Array = []
	for piece: Variant in raw:
		if piece is Dictionary:
			parts.append(piece)
			continue
		var s2 := String(piece)
		var at := 0
		for m in kick.search_all(s2):
			if m.get_start() > at:
				parts.append(s2.substr(at, m.get_start() - at))
			parts.append({"url": KICK_EMOTE_URL % m.get_string(1), "name": m.get_string(2)})
			at = m.get_end()
		if at < s2.length():
			parts.append(s2.substr(at))
	# tidy whitespace and cap the length
	var spaces := RegEx.create_from_string("\\s+")
	var out: Array = []
	var budget := max_text
	for p: Variant in parts:
		if budget <= 0:
			out.append("…")
			break
		if p is Dictionary:
			out.append(p)
			budget -= EMOTE_WEIGHT
			continue
		var s3 := spaces.sub(String(p), " ", true)
		if s3.length() > budget:
			s3 = s3.substr(0, budget - 1).strip_edges(false, true) + "…"
		budget -= s3.length()
		out.append(s3)
	if not out.is_empty() and out[0] is String:
		out[0] = String(out[0]).strip_edges(true, false)
	if not out.is_empty() and out[-1] is String:
		out[-1] = String(out[-1]).strip_edges(false, true)
	return out.filter(func(p: Variant) -> bool: return p is Dictionary or String(p) != "")


## Platform colour when it's usable, otherwise a colour picked from the name.
## Either way it's kept bright enough to read on a white bubble outline and in a dark room.
func color_for(who: String, platform_hex: String, platform: String = "") -> Color:
	var mode := String(AppState.get_setting("audience_color_by"))
	if mode == "platform":
		return platform_color(platform)
	var c: Color
	if mode == "chat" and Color.html_is_valid(platform_hex):
		c = Color.html(platform_hex)
	else:
		var h := float(absi(hash(who.to_lower())) % 1000) / 1000.0
		c = Color.from_hsv(fposmod(h * 0.618034 * 7.0, 1.0), 0.7, 0.95)
	var s := c.s
	if s < 0.15:
		# grey/white/black names: give them a soft colour so they still stand apart
		return Color.from_hsv(c.h if s > 0.02 else float(absi(hash(who)) % 360) / 360.0, 0.35, 0.95)
	return Color.from_hsv(c.h, clampf(s, 0.45, 0.85), clampf(c.v, 0.75, 1.0))


## The platform group a chat platform belongs to: kick, twitch, youtube or other.
func platform_group(platform: String) -> String:
	var p := platform.strip_edges().to_lower()
	if p == "yt":
		return "youtube"
	return p if p in ["kick", "twitch", "youtube"] else "other"


## A platform's colour (Audience tab), used when colouring by platform and in the seating chart.
func platform_color(platform: String) -> Color:
	return AppState.get_setting("platform_color_" + platform_group(platform)) as Color


func _group_of(m: Dictionary) -> String:
	if _area_count > 1:
		return "streamer%d" % int(m.get("streamer", 0))
	if m.has("platform"):
		return String(m["platform"])
	return platform_group(String(m.get("key", "")).get_slice(":", 0))


## Every member's colour again (after a colour setting changes).
func _recolor_all() -> void:
	for m: Dictionary in _members.values():
		m["color"] = color_for(String(m["name"]), String(m.get("hex", "")), _group_of(m))
		if int(m["slot"]) >= 0:
			EventBus.audience_updated.emit(int(m["slot"]))


# ── Seating plan (sections by platform) ──────────────────────
## Called by the room's audience view: the section of every slot, and each section's
## {label, kind (KIND_SEAT / KIND_CROWD), order}.
func set_slot_sections(sections: PackedStringArray, info: Dictionary) -> void:
	_section = sections
	_section_info = info.duplicate(true)
	_area_cache.clear()


func get_section(slot: int) -> String:
	return _section[slot] if slot >= 0 and slot < _section.size() else ""


## This room's sections in order: [{id, label, kind, count, allowed: PackedStringArray}].
func get_sections() -> Array[Dictionary]:
	var counts: Dictionary = {}
	for i in _section.size():
		if _section[i] != "":
			counts[_section[i]] = int(counts.get(_section[i], 0)) + 1
	var out: Array[Dictionary] = []
	for id: String in counts.keys():
		var inf: Dictionary = _section_info.get(id, {})
		out.append({"id": id, "label": String(inf.get("label", id)), "kind": int(inf.get("kind", KIND_SEAT)),
			"order": int(inf.get("order", 0)), "count": int(counts[id]), "allowed": get_section_platforms(id)})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["order"]) < int(b["order"]))
	return out


## Platforms the plan allows in a section (empty = anyone).
func get_section_platforms(id: String) -> PackedStringArray:
	return _plan.get(id, PackedStringArray())


## Sets which platforms may sit in a section (empty = anyone) and saves the plan.
func set_section_platforms(id: String, groups: PackedStringArray) -> void:
	var plan := _plan.duplicate()
	if groups.is_empty():
		plan.erase(id)
	else:
		plan[id] = groups
	_save_plan(plan)


## Replaces the whole plan: {section id: PackedStringArray}.
func set_plan(plan: Dictionary) -> void:
	_save_plan(plan)


func _save_plan(plan: Dictionary) -> void:
	var out: Dictionary = {}
	for id: String in plan.keys():
		out[id] = ",".join(plan[id])
	AppState.set_setting("seating_plan", JSON.stringify(out))


func _parse_plan() -> void:
	_plan.clear()
	var raw := String(AppState.get_setting("seating_plan")).strip_edges()
	if raw == "":
		return
	var data: Variant = JSON.parse_string(raw)
	if not data is Dictionary:
		return
	for id: String in (data as Dictionary).keys():
		var groups := PackedStringArray()
		for p in String(data[id]).split(",", false):
			var g := platform_group(p)
			if not groups.has(g):
				groups.append(g)
		if not groups.is_empty():
			_plan[id] = groups


func _plan_on() -> bool:
	return bool(AppState.get_setting("seating_by_platform"))


## Ready-made plans for this room's sections:
##   "anyone"        no plan (everyone sits anywhere)
##   "twitch_apart"  Twitch on the audience's left (front + back left, the left half of every
##                   crowd level), everyone else on the right
##   "quadrant_each" Kick, Twitch, YouTube, other: a quadrant each, crowd sections taking turns
func apply_preset(preset: String) -> void:
	if preset == "anyone":
		AppState.set_setting("seating_by_platform", false)
		set_plan({})
		return
	var plan: Dictionary = {}
	var others := PackedStringArray(["kick", "youtube", "other"])
	var by_level: Dictionary = {}
	for sec in get_sections():
		var id := String(sec["id"])
		if int(sec["kind"]) == KIND_SEAT:
			if preset == "twitch_apart":
				plan[id] = PackedStringArray(["twitch"]) if id in ["Q1", "Q3"] else others
			else:
				plan[id] = PackedStringArray([PLATFORMS[clampi(int(id.substr(1)) - 1, 0, 3)]])
		else:
			var level := int(id) / 100
			if not by_level.has(level):
				by_level[level] = []
			(by_level[level] as Array).append(id)
	for level: int in by_level.keys():
		var ids: Array = by_level[level]
		ids.sort_custom(func(x: String, y: String) -> bool: return int(x) < int(y))
		for k in ids.size():
			if preset == "twitch_apart":
				plan[ids[k]] = PackedStringArray(["twitch"]) if k < ids.size() / 2 else others
			else:
				plan[ids[k]] = PackedStringArray([PLATFORMS[k % PLATFORMS.size()]])
	set_plan(plan)
	AppState.set_setting("seating_by_platform", true)


## Can a chatter of this platform group sit in this slot under the seating plan?
func slot_allows(slot: int, group: String) -> bool:
	if group.begins_with("streamer"):
		var area := _area_of_section(get_section(slot))
		return area < 0 or area == int(group.trim_prefix("streamer"))
	if not _plan_on() or group == "":
		return true
	var id := get_section(slot)
	if id == "" or not _plan.has(id):
		return true
	return (_plan[id] as PackedStringArray).has(group)


## How many seats each platform may use in this room under the plan (all seats when it's off).
func get_platform_capacity() -> Dictionary:
	var out: Dictionary = {}
	for g in PLATFORMS:
		var n := 0
		for i in _slots.size():
			if get_slot_kind(i) != KIND_PRESENTER and slot_allows(i, g):
				n += 1
		out[g] = n
	return out


## Everything the seating chart draws: seat positions, sections, kinds, who sits where
## (platform group, "" = empty) and the stage point.
func get_chart() -> Dictionary:
	var taken := PackedStringArray()
	taken.resize(_slots.size())
	for i in _slots.size():
		taken[i] = String(_members[_slots[i]].get("platform", "other")) if _slots[i] != "" and _members.has(_slots[i]) else ""
	return {"spots": _spots, "sections": _section, "kinds": _kind, "taken": taken, "stage": _stage_point}


## After the plan changes: anyone sitting where their platform no longer may moves to a seat
## that allows it; with nowhere to go they wait (strict) or stay put.
func reseat_by_plan() -> void:
	if _mirror:
		EventBus.seating_changed.emit()
		return
	var changed := false
	if _plan_on() or _area_count > 1:
		for i in _slots.size():
			if _slots[i] == "" or get_slot_kind(i) == KIND_PRESENTER:
				continue
			var m: Dictionary = _members[_slots[i]]
			var g := _group_of(m)
			if slot_allows(i, g):
				continue
			var to := -1
			for k in [KIND_SEAT, KIND_CROWD]:
				if k == KIND_CROWD and get_slot_kind(i) != KIND_CROWD and crowd_full():
					break
				for j in _slots.size():
					if _slots[j] == "" and get_slot_kind(j) == k and slot_allows(j, g):
						to = j
						break
				if to >= 0:
					break
			if to >= 0:
				_move(i, to)
				changed = true
			elif bool(AppState.get_setting("seating_strict")):
				_unseat(i, false)
				changed = true
	if _fill_from_crowd():
		changed = true
	if changed:
		_emit_count()
	EventBus.seating_changed.emit()


## True for names on the "Ignore names" list (bots).
func is_ignored(who: String) -> bool:
	return _ignore.has(who.to_lower())


func _on_user_updated(info: Dictionary) -> void:
	if not _mirror:
		update_user(info)


## A chatter's picture arrived (Stream Core's user_update; on the host also a guest's, forwarded).
func update_user(info: Dictionary) -> void:
	var key := "%s:%s" % [String(info.get("platform", "")), String(info.get("user_id", ""))]
	if not _members.has(key):
		return
	var m: Dictionary = _members[key]
	m["avatar"] = String(info.get("avatar", ""))
	if int(m["slot"]) >= 0:
		EventBus.audience_updated.emit(int(m["slot"]))


func _refresh_all_seats() -> void:
	for i in _slots.size():
		if _slots[i] != "":
			EventBus.audience_updated.emit(i)


func _parse_hidden_avatars() -> void:
	_hide_avatars.clear()
	for part in String(AppState.get_setting("audience_hide_avatars")).split(",", false):
		var p := part.strip_edges().to_lower()
		if p != "":
			_hide_avatars.append(p)


func _parse_ignore() -> void:
	_ignore.clear()
	for part in String(AppState.get_setting("audience_ignore")).split(",", false):
		var p := part.strip_edges().to_lower()
		if p != "":
			_ignore.append(p)


## Presenter n's spot for this member when they're linked to a presenter who is on set in
## this room, else -1.
func _presenter_spot_for(m: Dictionary) -> int:
	var n := linked_presenter(String(m.get("key", "")).get_slice(":", 0), String(m.get("name", "")), String(m.get("username", "")))
	if n <= 0 or not _presenter_slot.has(n) or not bool(AppState.get_setting(AppState.presenter_key(n, "on"))):
		return -1
	var s := int(_presenter_slot[n])
	return s if s < _slots.size() else -1


## Which presenter (1..4) a chatter is linked to (Presenters tab: "Chat name"), or 0.
## Matches the login or display name, ignoring case and a leading "@"; a link written
## "kick:name" only matches on that platform.
func linked_presenter(platform: String, display_name: String, login: String) -> int:
	var names := [display_name.strip_edges().trim_prefix("@").to_lower(), login.strip_edges().trim_prefix("@").to_lower()]
	platform = platform.to_lower()
	for n: int in _links.keys():
		for l: Dictionary in _links[n]:
			if String(l["platform"]) != "" and String(l["platform"]) != platform:
				continue
			if names.has(String(l["name"])):
				return n
	return 0


func _parse_links() -> void:
	_links.clear()
	for n in range(1, AppState.PRESENTER_COUNT + 1):
		var arr: Array = []
		for part in String(AppState.get_setting(AppState.presenter_key(n, "chat"))).split(",", false):
			var p := part.strip_edges().to_lower()
			var plat := ""
			var colon := p.find(":")
			if colon > 0 and LINK_PLATFORMS.has(p.substr(0, colon).strip_edges()):
				plat = LINK_PLATFORMS[p.substr(0, colon).strip_edges()]
				p = p.substr(colon + 1).strip_edges()
			p = p.trim_prefix("@")
			if p != "":
				arr.append({"platform": plat, "name": p})
		if not arr.is_empty():
			_links[n] = arr


## After a presenter's link or on-set switch changes: the right person on each spot.
func _reconcile_presenters() -> void:
	if _mirror:
		return
	var changed := false
	for n: int in _presenter_slot.keys():
		var ps := int(_presenter_slot[n])
		if ps >= _slots.size():
			continue
		var k := _slots[ps]
		if k != "" and _presenter_spot_for(_members[k]) != ps:
			_unseat(ps, false)        # a regular chatter again: seated on their next message
			changed = true
		if _slots[ps] != "":
			continue
		for m: Dictionary in _members.values():
			if _presenter_spot_for(m) == ps:
				if int(m["slot"]) >= 0:
					_unseat(int(m["slot"]), false)
				_seat(m, ps, false)
				changed = true
				break
	if _fill_from_crowd():
		changed = true
	if changed:
		_emit_count()


func _on_setting_changed(key: String, _value: Variant) -> void:
	if key.begins_with("presenter_") and (key.ends_with("_chat") or key.ends_with("_on")):
		_parse_links()
		_reconcile_presenters()
	elif key == "seating_plan":
		_parse_plan()
		reseat_by_plan()
	elif key == "seating_by_platform" or key == "seating_strict":
		reseat_by_plan()
	elif key == "audience_color_by" or key.begins_with("platform_color_"):
		_recolor_all()
		EventBus.seating_changed.emit()
	elif key == "audience_crowd_max":
		_enforce_crowd_cap()
	elif key == "audience_crowd_move_down" and bool(AppState.get_setting(key)):
		if _fill_from_crowd():
			_emit_count()
	elif key == "audience_ignore":
		_parse_ignore()
	elif key == "audience_hide_avatars":
		_parse_hidden_avatars()
		_refresh_all_seats()
	elif key == "audience_avatars":
		_refresh_all_seats()


# ── Streaming together ───────────────────────────────────────
## Guest: show the host's roster instead of seating this PC's own chat (or go back to normal).
func set_mirror(on: bool) -> void:
	if on == _mirror:
		return
	clear()
	_mirror = on
	_pending_roster = {}


func is_mirror() -> bool:
	return _mirror


## Host: give each of `count` streamers' viewers their own sections (0 or 1 = no areas). The main
## seats split by quadrant (2 streamers: left / right; 4: a quadrant each), each crowd level into
## `count` runs of neighbouring sections. Everyone is moved to their area right away.
func set_streamer_areas(count: int) -> void:
	count = clampi(count, 0, 4)
	if count == _area_count:
		return
	_area_count = count
	_area_cache.clear()
	reseat_by_plan()


func _area_of_section(id: String) -> int:
	if _area_count < 2 or id == "":
		return -1
	if _area_cache.is_empty():
		var by_level: Dictionary = {}
		for sec in get_sections():
			var sid := String(sec["id"])
			if int(sec["kind"]) == KIND_SEAT:
				var q := clampi(int(sid.substr(1)) - 1, 0, 3)       # Q1 front left .. Q4 back right
				var quad_area := {2: [0, 1, 0, 1], 3: [0, 1, 2, 2], 4: [0, 1, 2, 3]}
				_area_cache[sid] = int((quad_area[_area_count] as Array)[q])
			else:
				var level := int(sid) / 100
				if not by_level.has(level):
					by_level[level] = []
				(by_level[level] as Array).append(sid)
		for level: int in by_level.keys():
			var ids: Array = by_level[level]
			ids.sort_custom(func(x: String, y: String) -> bool: return int(x) < int(y))
			for k in ids.size():
				_area_cache[ids[k]] = mini(k * _area_count / ids.size(), _area_count - 1)
	return int(_area_cache.get(id, -1))


## Host: everyone seated, for the guests: [{slot, m}] (m: wire_member()).
func get_roster() -> Array:
	var out: Array = []
	for i in _slots.size():
		if _slots[i] != "" and _members.has(_slots[i]):
			out.append({"slot": i, "m": wire_member(i)})
	return out


## Host: what a guest needs to draw the person in a seat ({} = empty seat).
func wire_member(slot: int) -> Dictionary:
	if slot < 0 or slot >= _slots.size() or _slots[slot] == "" or not _members.has(_slots[slot]):
		return {}
	var m: Dictionary = _members[_slots[slot]]
	return {"key": String(m["key"]), "name": String(m["name"]), "username": String(m.get("username", "")),
		"platform": String(m.get("platform", "other")), "hex": String(m.get("hex", "")), "style": int(m["style"]),
		"color": m["color"], "avatar": String(m.get("avatar", "")), "title": String(m.get("title", ""))}


## Mirror: the host's whole roster for a room (it waits if this PC hasn't loaded that room yet).
func mirror_roster(room: String, list: Array) -> void:
	if not _mirror:
		return
	if room != _capacity_room or room != String(AppState.get_setting("room_id")):
		_pending_roster = {"room": room, "list": list}
		return
	for i in _slots.size():
		if _slots[i] != "":
			_unseat(i, true)
	_members.clear()
	for e: Variant in list:
		if e is Dictionary and (e as Dictionary).get("slot") is int and (e as Dictionary).get("m") is Dictionary:
			mirror_seat(room, int(e["slot"]), e["m"], false)
	_emit_count()
	EventBus.seating_changed.emit()


func mirror_seat(room: String, slot: int, wm: Dictionary, notify: bool = true) -> void:
	if not _mirror or room != _capacity_room or slot < 0 or slot >= _slots.size():
		return
	var key := String(wm.get("key", "")).left(120)
	if key == "":
		return
	if _slots[slot] != "":
		_unseat(slot, true)
	if _members.has(key) and int(_members[key]["slot"]) >= 0:
		_unseat(int(_members[key]["slot"]), true)
	var m := {"key": key, "slot": -1, "last": Time.get_unix_time_from_system()}
	_apply_wire(m, wm)
	_members[key] = m
	_seat(m, slot, notify)
	if notify:
		EventBus.seating_changed.emit()


func mirror_leave(room: String, slot: int) -> void:
	if _mirror and room == _capacity_room and slot >= 0 and slot < _slots.size() and _slots[slot] != "":
		_unseat(slot, true)
		_emit_count()
		EventBus.seating_changed.emit()


func mirror_update(room: String, slot: int, wm: Dictionary) -> void:
	if not _mirror or room != _capacity_room or slot < 0 or slot >= _slots.size() or _slots[slot] == "":
		return
	_apply_wire(_members[_slots[slot]], wm)
	EventBus.audience_updated.emit(slot)


## parts: Strings and emote Dictionaries {url, name} (only https pictures are kept), and maybe a
## first {reply_to, quote} saying who the message answers.
func mirror_speak(room: String, slot: int, parts: Array) -> void:
	if not _mirror or room != _capacity_room or slot < 0 or slot >= _slots.size() or _slots[slot] == "":
		return
	var clean: Array = []
	for part: Variant in parts.slice(0, 80):
		if part is String:
			clean.append(String(part).left(MAX_TEXT))
		elif part is Dictionary and (part as Dictionary).has("reply_to") and clean.is_empty():
			clean.append({"reply_to": String(part["reply_to"]).left(60), "quote": String(part.get("quote", "")).left(120)})
		elif part is Dictionary and String((part as Dictionary).get("url", "")).begins_with("https://"):
			clean.append({"url": String(part["url"]).left(500), "name": String(part.get("name", "")).left(60)})
	if not clean.is_empty():
		EventBus.audience_spoke.emit(slot, clean)


func _apply_wire(m: Dictionary, wm: Dictionary) -> void:
	m["name"] = String(wm.get("name", "?")).left(40)
	m["username"] = String(wm.get("username", "")).left(40)
	m["platform"] = platform_group(String(wm.get("platform", "other")))
	m["hex"] = String(wm.get("hex", "")).left(9)
	m["style"] = clampi(int(wm.get("style", 0)), 0, BUBBLE_STYLES - 1)
	m["color"] = wm["color"] if wm.get("color") is Color else color_for(String(m["name"]), String(m["hex"]), String(m["platform"]))
	var avatar := String(wm.get("avatar", ""))
	m["avatar"] = avatar.left(500) if avatar.begins_with("https://") else ""
	m["title"] = String(wm.get("title", "")).left(40)
