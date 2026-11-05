extends Node
## Co-stream staying in sync (NetSession "Staying in sync", work list items 1, 2, 3 and 22): the first
## sync with its progress, a guest's see-through avatar keyed alike on every PC, the host's warnings
## for podiums guests can't see, pause to react for everyone, the audience fixing itself when a seat
## change got lost, a guest whose
## connection drops getting back in on its own (no popups, same part of the audience, the chat from
## while it was gone arriving), and a guest the host removes NOT coming back.
## The guest writes its results to a file; the host prints them with its own.
##   <redot console exe> --path . _tests/test_costream_resync.tscn -- C:/temp/sr_tests --mp-profile=test

const SESSION_PORT: int = 7398
const PASSWORD: String = "resyncpass"

var _fails: int = 0
var _out: String = ""
var _lines: PackedStringArray = []


func _check(ok: bool, what: String) -> void:
	var line := ("PASS " if ok else "FAIL ") + what
	print(line)
	_lines.append(line)
	if not ok:
		_fails += 1


func _secs(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _wait_for(cond: Callable, secs: float) -> bool:
	var t := 0.0
	while t < secs:
		if bool(cond.call()):
			return true
		await _secs(0.25)
		t += 0.25
	return bool(cond.call())


func _chat(platform: String, who: String, text: String) -> void:
	EventBus.chat_message_received.emit({"platform": platform, "user_id": who, "name": who, "username": who,
		"color": "", "text": text, "emotes": [], "timestamp": Time.get_unix_time_from_system(),
		"history": false, "system": false})


func _slot(platform: String, who: String) -> int:
	return AudienceManager.find_slot_for_user(platform, who)


## The streamer number a seated chatter came from (0 = host), -1 when not seated.
func _streamer_of(platform: String, who: String) -> int:
	var s := _slot(platform, who)
	return int(AudienceManager.wire_member(s).get("streamer", -1)) if s >= 0 else -1


## Host: the one guest's row in the people list ({} if none).
func _guest_row() -> Dictionary:
	for p: Dictionary in NetSession.get_info()["peers"]:
		if int(p["id"]) != 1:
			return p
	return {}


func _ready() -> void:
	NetSession.auto_confirm = true      # (only for the first join; see below)
	_out = OS.get_cmdline_user_args()[0]
	AppState.set_setting("chat_enabled", false)                       # (never the real Stream Core)
	AppState.set_setting("chat_core_url", "ws://127.0.0.1:9/ws")
	AppState.set_setting("panel_window", false)
	AppState.set_setting("audience_enabled", true)
	AppState.set_setting("together_port", SESSION_PORT)
	AppState.set_setting("together_password", PASSWORD)
	AppState.set_setting("together_address", "127.0.0.1:%d" % SESSION_PORT)
	for g in ["room", "curtain", "presenters"]:
		AppState.set_setting("together_share_" + g, true)          # (an earlier test may have unticked one)
	AppState.set_setting("together_streamer_looks", false)
	AppState.request_room("theater")
	add_child(load("res://core/main.tscn").instantiate())
	await _secs(5.0)
	if OS.get_cmdline_user_args().has("--role=guest"):
		await _guest()
	else:
		await _host()


# ── Host ─────────────────────────────────────────────────────
func _host() -> void:
	AppState.set_setting("together_name", "Host")
	AppState.set_setting("together_bind", "local")
	AppState.set_setting("together_shared_audience", true)
	AppState.set_setting("together_audience_areas", true)
	NetSession.host()
	_chat("twitch", "hostfan1", "hi from the host's chat")
	_check(await _wait_for(func() -> bool: return _slot("twitch", "hostfan1") >= 0, 5.0), "the host's viewer sits down")

	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://settings_resyncguest.cfg"))
	DirAccess.remove_absolute(_out.path_join("costream_resync_guest.txt"))
	var args := PackedStringArray(["--path", ProjectSettings.globalize_path("res://"), "--resolution", "960x540",
		"--position", "980,0", "res://_tests/test_costream_resync.tscn", "--", _out, "--mp-profile=resyncguest", "--role=guest"])
	_check(OS.create_process(OS.get_executable_path(), args) > 0, "started the guest copy")
	_check(await _wait_for(func() -> bool: return not _guest_row().is_empty(), 90.0), "the guest joined")
	var first_id := int(_guest_row().get("id", 0))
	_check(await _wait_for(func() -> bool: return bool(_guest_row().get("synced", false)), 60.0), "the list shows the guest in sync")
	_check(await _wait_for(func() -> bool: return _slot("kick", "guestfan1") >= 0, 30.0), "the guest's viewer sits down")
	_check(_streamer_of("kick", "guestfan1") == 1, "the guest's viewer is the guest's (streamer 1)")

	# podiums: the guest's see-through web avatar is keyed with the avatar colour on every PC
	_check(await _wait_for(func() -> bool: return not NetSession.avatar_key("ResyncGuest").is_empty(), 20.0),
		"the host knows the guest's avatar is a see-through page")
	AppState.set_setting(AppState.presenter_key(1, "on"), true)
	AppState.set_setting(AppState.presenter_key(1, "source"), "peer")
	AppState.set_setting(AppState.presenter_key(1, "peer"), "ResyncGuest")
	AppState.set_setting(AppState.presenter_key(1, "key_color"), Color(1, 0, 1))   # (the podium's own guess: ignored)
	# podiums guests can't see are pointed out
	AppState.set_setting(AppState.presenter_key(2, "on"), true)
	AppState.set_setting(AppState.presenter_key(2, "source"), "tab")
	_check(NetSession.podium_warning(2).contains("silhouette"), "a tab podium is pointed out (%s)" % NetSession.podium_warning(2))
	AppState.set_setting(AppState.presenter_key(2, "source"), "web")
	AppState.set_setting(AppState.presenter_key(2, "url"), "http://localhost:5000/avatar")
	_check(NetSession.podium_warning(2) != "", "so is a web page on this PC")
	AppState.set_setting(AppState.presenter_key(2, "url"), "https://vdo.ninja/?view=abc")
	_check(NetSession.podium_warning(2) == "", "a web page anyone can open is fine")
	AppState.set_setting(AppState.presenter_key(2, "on"), false)

	# pause to react: for everyone
	AppState.set_source_mode("file")
	AppState.set_react_paused(true)
	await _secs(3.0)
	AppState.set_react_paused(false)

	# the guest drops its connection; from now on no popups may be needed to get it back in
	NetSession.auto_confirm = false
	_check(await _wait_for(func() -> bool: return _guest_row().is_empty(), 60.0), "noticed the guest dropping")
	_check(await _wait_for(func() -> bool: return not _guest_row().is_empty() and int(_guest_row()["id"]) != first_id, 60.0),
		"the guest came back by itself, without the popup")
	var back_id := int(_guest_row().get("id", 0))
	_check(NetSession._streamer_index(back_id) == 1, "and keeps its part of the audience (streamer 1)")
	_check(await _wait_for(func() -> bool: return _slot("kick", "guestfan2") >= 0, 30.0), "the chat from while it was gone arrived")
	_check(_streamer_of("kick", "guestfan2") == 1, "and sits in the guest's part")
	_check(_slot("kick", "guestfan1") >= 0 and _streamer_of("kick", "guestfan1") == 1, "the guest's first viewer is still in its part")

	# Remove: the guest must stay out
	await _secs(8.0)                    # (the guest checks a few things first)
	NetSession.remove_peer(back_id)
	_check(await _wait_for(func() -> bool: return _guest_row().is_empty(), 20.0), "Remove sends the guest away")
	await _secs(10.0)
	_check(_guest_row().is_empty(), "and it doesn't come back by itself")
	_check(not NetSession._is_away("ResyncGuest"), "its part of the audience isn't kept")

	var f := _out.path_join("costream_resync_guest.txt")
	await _wait_for(func() -> bool: return FileAccess.file_exists(f), 60.0)
	var text := FileAccess.get_file_as_string(f)
	if text == "":
		_check(false, "the guest wrote its results")
	for line in text.split("\n", false):
		_check(line.begins_with("PASS "), "guest: " + line.substr(5))
	NetSession.leave()
	print("DONE fails=", _fails)
	AppState.request_quit(1 if _fails > 0 else 0)


# ── Guest ────────────────────────────────────────────────────
func _guest() -> void:
	AppState.set_setting("together_name", "ResyncGuest")
	AppState.set_setting("together_avatar_source", "web")       # (a see-through avatar page)
	AppState.set_source_mode("file")                             # (something on the big screen to pause)
	var pauses: Array = []
	EventBus.react_pause_changed.connect(func(p: bool) -> void: pauses.append(p))
	var progress: Array = []          # sync_progress values seen while syncing
	EventBus.net_state_changed.connect(func(info: Dictionary) -> void:
		if float(info.get("sync_progress", -1.0)) >= 0.0:
			progress.append(float(info["sync_progress"])))
	NetSession.join()
	_check(await _wait_for(func() -> bool: return NetSession.get_role() == "guest" and AudienceManager.is_mirror(), 30.0),
		"joined, and shows the host's audience")
	_check(await _wait_for(func() -> bool: return NetSession._synced, 60.0), "the first sync finished")
	_check(not progress.is_empty(), "the Co-stream tab showed sync progress (%d steps)" % progress.size())
	_check(String(NetSession.get_info()["status"]).begins_with("In sync with Host"), "the status says it's in sync (%s)" % String(NetSession.get_info()["status"]))
	_check(_slot("twitch", "hostfan1") >= 0, "the host's viewer is seated here")
	_chat("kick", "guestfan1", "hi from the guest's chat")
	_check(await _wait_for(func() -> bool: return _slot("kick", "guestfan1") >= 0, 15.0), "this PC's viewer sits down once the host seats them")

	# a seat change that got lost: the audience check notices and fixes it
	var lost := _slot("twitch", "hostfan1")
	AudienceManager.mirror_leave(AudienceManager.seats_room(), lost)
	_check(_slot("twitch", "hostfan1") < 0, "(the host's viewer is gone here, as if a message got lost)")
	_check(await _wait_for(func() -> bool: return _slot("twitch", "hostfan1") == lost, 20.0), "the audience check put them back in the same seat")
	_check(int(NetSession.get_info()["aud_resyncs"]) >= 1, "it asked the host for the audience again")

	# the host's podium shows this PC's avatar: keyed with the avatar colour, not the podium's own
	_check(await _wait_for(func() -> bool: return String(AppState.get_setting(AppState.presenter_key(1, "source"))) == "peer", 20.0),
		"the host's podium shows this PC's avatar")
	_check(NetSession.avatar_key("ResyncGuest").get("color", Color.BLACK) == NetSession.AVATAR_KEY_COLOR,
		"and it's keyed with the avatar colour here too")
	# the host paused and unpaused for everyone
	_check(await _wait_for(func() -> bool: return pauses.has(true) and pauses.has(false), 30.0),
		"the host's pause to react paused this PC too, and unpaused it (%s)" % str(pauses))

	# the connection drops: keep showing the audience, hold this PC's chat, get back in
	NetSession.auto_confirm = false
	NetSession.simulate_drop()
	await _secs(0.5)
	_check(bool(NetSession.get_info()["reconnecting"]), "reconnecting after the drop")
	_check(AudienceManager.is_mirror() and _slot("twitch", "hostfan1") >= 0, "the shared audience stays on screen meanwhile")
	_chat("kick", "guestfan2", "did I miss anything?")
	_check(await _wait_for(func() -> bool: return NetSession.get_role() == "guest" and NetSession._admitted, 60.0),
		"got back in without the popup")
	_check(String(NetSession.get_info()["status"]).begins_with("Reconnected") or String(NetSession.get_info()["status"]).begins_with("Syncing")
		or String(NetSession.get_info()["status"]).begins_with("In sync"), "the status says so (%s)" % String(NetSession.get_info()["status"]))
	_check(await _wait_for(func() -> bool: return NetSession._synced, 60.0), "and synced again")
	_check(await _wait_for(func() -> bool: return _slot("kick", "guestfan2") >= 0, 20.0), "the chat from while it was gone is seated")
	_check(_slot("kick", "guestfan1") >= 0, "the earlier viewer is still here")

	# Remove: no reconnecting
	_check(await _wait_for(func() -> bool: return NetSession.get_role() == "off", 60.0), "the host removed this copy")
	await _secs(6.0)
	_check(NetSession.get_role() == "off" and not bool(NetSession.get_info()["reconnecting"]), "and it didn't try to reconnect")
	_check(not AudienceManager.is_mirror(), "and has its own audience again")
	DirAccess.make_dir_recursive_absolute(_out)
	var f := FileAccess.open(_out.path_join("costream_resync_guest.txt"), FileAccess.WRITE)
	f.store_string("\n".join(_lines) + "\n")
	f.close()
	print("DONE fails=", _fails)
	AppState.request_quit(1 if _fails > 0 else 0)
