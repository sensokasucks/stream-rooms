class_name CoreLooks
extends Node
## Audience looks from Stream Core: the speech bubble and silhouette looks are edited on Core's
## dashboard (Overlays > Audience looks, admin/audience-looks.js there) and arrive over the
## Core WebSocket as {"type": "audience_looks", "data": ...}, on connect and after every save.
## ChatFeed makes one of these as its child and hands it each such packet (apply()).
##
## apply() turns the packet into the same settings the room already reads through AudienceStyle:
## audience_bubble_theme, audience_bubble_style, audience_silhouette, audience_saved_styles and
## audience_style_groups (all but the theme are JSON text). Core keeps the data in
## data/audience_looks.json (core/audience_looks.py); the keys are AudienceStyle's.
##
## Silhouette pictures are Core stored files, written "media:<name>" in a style's "file". The
## packet's "pictures" gives each one's /media address and version. Each picture is downloaded
## from Core once per version and imported with AudienceStyle.import_picture (which keeps it in
## user://silhouettes/ as core_<name>.png); the list of what is here is PICTURES_FILE. Until a
## picture is here, a style using it shows the classic silhouette; the looks are applied again
## when the download finishes.

## Which Core pictures are here: {stored name: {"version": int, "file": "user://silhouettes/..."}}.
const PICTURES_FILE: String = "user://silhouettes/core_pictures.json"
## Downloads land here first (AudienceStyle.import_picture then makes the 256 x 320 copies).
const DOWNLOAD_DIR: String = "user://silhouettes/core_downloads/"
const MEDIA_PREFIX: String = "media:"
## Largest picture accepted from Core, bytes (Core's own limit for pictures is 15 MB).
const MAX_PICTURE_BYTES: int = 16 * 1024 * 1024

var _pictures: Dictionary = {}       # PICTURES_FILE's contents
var _active: Dictionary = {}         # stored name -> HTTPRequest while it downloads
var _last: Dictionary = {}           # the last packet's data, applied again after a download


func _ready() -> void:
	_pictures = _read_json(PICTURES_FILE)


## One "audience_looks" packet's data from Core. Ignored until the streamer has saved looks in
## Core once ("edited"), so a fresh Core never resets looks that were set before.
func apply(data: Dictionary) -> void:
	if not bool(data.get("edited", false)):
		return
	_last = data
	var pics: Dictionary = data.get("pictures", {}) if data.get("pictures") is Dictionary else {}
	for stored: String in pics.keys():
		var p: Variant = pics[stored]
		if p is Dictionary and not _is_here(stored, int((p as Dictionary).get("version", 0))):
			_download(stored, String((p as Dictionary).get("url", "")), int((p as Dictionary).get("version", 0)))
	var theme := String(data.get("bubble_theme", "light"))
	_put_setting("audience_bubble_theme", theme if theme in ["light", "dark", "custom"] else "light")
	_put_setting("audience_bubble_style", _json(data.get("bubble")))
	_put_setting("audience_silhouette", _json(_local_figure(data.get("silhouette"))))
	var saved_in: Dictionary = data.get("saved", {}) if data.get("saved") is Dictionary else {}
	var own_figs: Dictionary = {}
	var figs_in: Variant = saved_in.get("silhouette")
	if figs_in is Dictionary:
		for n: String in (figs_in as Dictionary).keys():
			own_figs[n] = _local_figure((figs_in as Dictionary)[n])
	var bubbles_in: Variant = saved_in.get("bubble")
	_put_setting("audience_saved_styles", JSON.stringify({
		"bubble": bubbles_in if bubbles_in is Dictionary else {},
		"silhouette": own_figs,
	}))
	_put_setting("audience_style_groups", _json(data.get("groups")))


## True while Core pictures are still downloading (for tests).
func is_busy() -> bool:
	return not _active.is_empty()


## A silhouette style with "media:<name>" turned into the picture here, or the classic shape
## while the picture isn't here yet (AudienceStyle.merge_figure only takes files in user://silhouettes/).
func _local_figure(raw: Variant) -> Dictionary:
	if not raw is Dictionary:
		return {}
	var f := (raw as Dictionary).duplicate()
	var file := String(f.get("file", ""))
	if file.begins_with(MEDIA_PREFIX):
		var stored := file.substr(MEDIA_PREFIX.length())
		var here: Variant = _pictures.get(stored)
		if here is Dictionary and FileAccess.file_exists(String((here as Dictionary).get("file", ""))):
			f["file"] = String(here["file"])
		else:
			f["file"] = ""
			f["shape"] = "classic"
	return f


func _is_here(stored: String, version: int) -> bool:
	var here: Variant = _pictures.get(stored)
	return here is Dictionary and int((here as Dictionary).get("version", -1)) == version \
		and FileAccess.file_exists(String((here as Dictionary).get("file", "")))


## Fetches one picture from Core (the address is made full with ChatFeed.core_url).
func _download(stored: String, url: String, version: int) -> void:
	if _active.has(stored) or url == "":
		return
	var req := HTTPRequest.new()
	req.body_size_limit = MAX_PICTURE_BYTES
	add_child(req)
	_active[stored] = req
	req.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
		_active.erase(stored)
		req.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS or code != 200:
			push_warning("Core silhouette picture %s: download failed (%d / %d)" % [stored, result, code])
			return
		if save_picture(stored, version, url, body) != "" and not _last.is_empty():
			apply(_last))
	if req.request(ChatFeed.core_url(url)) != OK:
		_active.erase(stored)
		req.queue_free()


## Keeps a downloaded picture: writes it to DOWNLOAD_DIR, imports it as a silhouette and notes the
## version. url: its Core address (for the file type). Returns the imported file, "" if it couldn't
## be read. Called when a download finishes (and by test_audience_looks with a picture of its own).
func save_picture(stored: String, version: int, url: String, body: PackedByteArray) -> String:
	var ext := url.get_slice("?", 0).get_extension().to_lower()
	if not ext in ["png", "jpg", "jpeg", "webp"]:
		ext = "png"
	DirAccess.make_dir_recursive_absolute(DOWNLOAD_DIR)
	# "core_" keeps Core's pictures apart from ones imported straight into Stream Rooms
	var safe := stored.to_lower().validate_filename().replace(" ", "_").left(34)
	var path := DOWNLOAD_DIR + "core_" + safe + "." + ext
	var fa := FileAccess.open(path, FileAccess.WRITE)
	if fa == null:
		return ""
	fa.store_buffer(body)
	fa.close()
	var file := AudienceStyle.import_picture(path)
	if file == "":
		push_warning("Core silhouette picture %s couldn't be read" % stored)
		return ""
	_pictures[stored] = {"version": version, "file": file}
	var out := FileAccess.open(PICTURES_FILE, FileAccess.WRITE)
	if out != null:
		out.store_string(JSON.stringify(_pictures, "\t"))
		out.close()
	return file


## Sets a setting only when it changes (each change saves settings and redraws the audience).
func _put_setting(key: String, value: String) -> void:
	if String(AppState.get_setting(key)) != value:
		AppState.set_setting(key, value)


## A Dictionary as JSON text; "" for an empty or missing one (= the defaults).
func _json(v: Variant) -> String:
	return JSON.stringify(v) if v is Dictionary and not (v as Dictionary).is_empty() else ""


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return v if v is Dictionary else {}
