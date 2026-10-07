class_name Room
extends Node3D
## Root script for every swappable room scene.
##
## Naming contract (works for nodes imported from Blender too):
##   TVScreen       MeshInstance3D with UVs - the video goes here.
##   CAM_<Name>     Node3D / Marker3D camera presets, sorted by name. -Z is the view direction.
##                  A preset whose name contains "Reaction" is used for react pauses.
##   LIGHTS_House   Node3D whose Light3D children dim while a video plays.
##     LAMP_<Name>  Empties (e.g. from Blender) inside LIGHTS_House. Each one without a
##                  light of its own gets an OmniLight3D using the lamp_* settings below,
##                  so lamp placement can live entirely in the .blend.
##   WEBCAM_Frame   Optional Node3D where the webcam picture is placed. The picture is
##                  1.2 m wide, centred on the marker, and faces the marker's +Z axis.
##                  Without it the webcam is shown as a corner overlay instead.
##   BEAM_Projector Optional Node3D (projection-booth window). A narrow spotlight shines
##                  from it along its -Z axis, tinted by the picture - visible in fog.
##   SCREEN_Mirror_<Name>  Optional extra screen meshes (with UVs) that show the same
##                  picture as TVScreen, each with a soft light spill in front of it.
##   PRESENTER_<n> Optional presenter spots (n = 1..4): bottom centre of the picture behind a
##                  podium, +Z facing the audience. PODIUM_<n> (mesh, shown/hidden with the
##                  presenter) and PODIUM_LIGHT_<n> (lamp aimed along -Z) are optional.
##   AUDIENCE_<Name> Optional chat-audience seats: one empty per seat, on the seat surface.
##                  AudienceRow nodes (core/audience/audience_row.gd) add whole rows.
##
## The room only manages its own house lights. The core app attaches the screen
## material, screen lights and webcam display from outside.

@export var screen_mesh_name: String = "TVScreen"
@export var camera_prefix: String = "CAM_"
@export var house_lights_name: String = "LIGHTS_House"
@export var webcam_marker_name: String = "WEBCAM_Frame"
@export var projector_marker_name: String = "BEAM_Projector"
@export var mirror_screen_prefix: String = "SCREEN_Mirror"
@export var audience_prefix: String = "AUDIENCE_"
## Size of each presenter's picture (width, height) in metres.
@export var presenter_size: Vector2 = Vector2(1.3, 1.25)
## Chat screen: CHAT_Screen marker = top centre of the panel (+Z faces the audience); size in metres.
@export var chat_screen_marker_name: String = "CHAT_Screen"
@export var chat_screen_size: Vector2 = Vector2(8.6, 1.5)
## Reply screen (Stream Core's answers to chat commands): REPLY_Screen marker = top centre.
@export var reply_screen_marker_name: String = "REPLY_Screen"
@export var reply_screen_size: Vector2 = Vector2(8.6, 1.3)
## Extra reply-screen height added upward (the bottom edge stays where the marker puts it).
@export var reply_screen_raise: float = 0.0
## Crowd seats (a JSON file written by the room's Blender generator: {"seats": [{"p": [x, y, z]}, ...]},
## positions in the room's own space, on the seat surface). The filler crowd sits here, and
## chatters overflow into them once the main seats are full. Empty = no crowd.
@export_file("*.json") var crowd_seats_file: String = ""
## Chat windows beside the main screen (SideChats): extra room between them and the screen,
## and their height as a share of the screen's, on top of the Chat tab's settings (e.g. to
## clear the curtain's drapes or statues in front of the stage).
@export var side_chat_extra_gap: float = 0.0
@export var side_chat_height_scale: float = 1.0
## Metres the side chat windows sit in front of the screen (clear of drapes or pillars).
@export var side_chat_forward: float = 0.0
## Metres to move the presenter spots (PRESENTER_<n>, PODIUM_<n>, PODIUM_LIGHT_<n>) towards the
## audience, e.g. to keep the podiums clear of the side chat windows.
@export var presenter_forward: float = 0.0
## Audience seats closer than this (horizontally) to a camera marker are skipped.
@export var audience_camera_clearance: float = 0.45
## House light level while a video plays (0..1 of their original energy).
@export_range(0.0, 1.0) var dimmed_level: float = 0.08
@export var fade_speed: float = 0.6

## Swap imported materials by name, e.g. "Win_Concrete" (from Blender) -> a ShaderMaterial.
## Keys are material names as they appear in the .glb, values are Materials.
@export var material_overrides: Dictionary = {}

## Materials (by imported name) whose glow follows the house lights, e.g. chandelier bulbs.
@export var glow_materials: PackedStringArray = []

@export_group("LAMP_ markers")
@export var lamp_prefix: String = "LAMP_"
@export var lamp_color: Color = Color(1.0, 0.8, 0.55)
@export var lamp_energy: float = 1.5
@export var lamp_range: float = 14.0
@export var lamp_shadows: bool = false

var _house_lights: Array[Light3D] = []
var _base_energy: Dictionary = {}
var _level: float = 1.0
var _glow: Array[Dictionary] = []    # {mat: BaseMaterial3D, energy: float}


func _ready() -> void:
	if absf(presenter_forward) > 0.001:
		_move_presenters_forward()
	if not material_overrides.is_empty():
		_apply_material_overrides()
	if not glow_materials.is_empty():
		_collect_glow_materials()
	var group := find_child(house_lights_name, true, false)
	if group:
		_spawn_lamp_lights(group)
		for n in group.find_children("*", "Light3D", true, false):
			var l := n as Light3D
			_house_lights.append(l)
			_base_energy[l] = l.light_energy


func _process(delta: float) -> void:
	var target := _target_level()
	if is_equal_approx(_level, target):
		return
	_level = move_toward(_level, target, delta * fade_speed)
	for l in _house_lights:
		l.light_energy = _base_energy[l] * _level
		l.visible = _level > 0.01
	for g in _glow:
		(g["mat"] as BaseMaterial3D).emission_energy_multiplier = float(g["energy"]) * _level


# ── Queries used by the core app ─────────────────────────────
func find_screen() -> MeshInstance3D:
	return find_child(screen_mesh_name, true, false) as MeshInstance3D


func get_camera_markers() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for n in find_children(camera_prefix + "*", "Node3D", true, false):
		out.append(n as Node3D)
	out.sort_custom(func(a: Node3D, b: Node3D) -> bool: return String(a.name) < String(b.name))
	return out


func get_camera_label(marker: Node3D) -> String:
	var label := String(marker.name).trim_prefix(camera_prefix)
	# Allow "1_Seat" style names for ordering; show just "Seat".
	var parts := label.split("_", false, 1)
	if parts.size() == 2 and parts[0].is_valid_int():
		label = parts[1]
	return label.replace("_", " ")


func get_webcam_marker() -> Node3D:
	return find_child(webcam_marker_name, true, false) as Node3D


func get_chat_screen_marker() -> Node3D:
	return find_child(chat_screen_marker_name, true, false) as Node3D


## The room's own meshes (walls, floors, furniture), not the things the app adds at runtime
## (audience, curtain, screens, effects).
func get_static_meshes() -> Array[MeshInstance3D]:
	var skip := ["StageCurtain", "Audience", "Reactions", "Presenters", "ScreenLights", "ReplyScreen",
		"ChatScreen", "WebcamDisplay", "SunShafts", "SideChats"]
	var out: Array[MeshInstance3D] = []
	for n in find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var p: Node = mi
		var added := false
		while p != null and p != self:
			if String(p.name) in skip:
				added = true
				break
			p = p.get_parent()
		if not added:
			out.append(mi)
	return out


func get_reply_screen_marker() -> Node3D:
	return find_child(reply_screen_marker_name, true, false) as Node3D


func get_projector_marker() -> Node3D:
	return find_child(projector_marker_name, true, false) as Node3D


## Extra controls this room adds to the Room tab. Each entry is a Dictionary:
##   {"heading": "Weather"}                              a small heading
##   {"key": "rain_amount", "label": "Rain", "min": 0.0, "max": 2.0, "step": 0.01,
##    "format": "%d%%", "scale": 100.0}                  a slider for an AppState setting
##   {"key": "holo_color1", "label": "Line colour", "type": "color"}   a colour picker
## The room reacts to its settings through EventBus.setting_changed.
func get_controls() -> Array[Dictionary]:
	return []


## Slides every presenter spot (marker, podium, podium lamp) presenter_forward metres out from
## the screen, towards the audience.
func _move_presenters_forward() -> void:
	var screen := find_screen()
	if screen == null:
		return
	var n := screen.global_basis.z
	n.y = 0.0
	if n.length() < 0.01:
		return
	n = n.normalized()
	var cams := get_camera_markers()
	if not cams.is_empty() and (cams[0].global_position - screen.global_position).dot(n) < 0.0:
		n = -n
	for s in get_presenter_setups():
		for k in ["marker", "podium", "lamp"]:
			var node := s[k] as Node3D
			if node:
				node.global_position += n * presenter_forward


## Presenter spots: [{n, marker, podium (or null), lamp (or null)}] sorted by n.
func get_presenter_setups() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for n in range(1, AppState.PRESENTER_COUNT + 1):
		var marker := find_child("PRESENTER_%d" % n, true, false) as Node3D
		if marker == null:
			continue
		out.append({"n": n, "marker": marker,
			"podium": find_child("PODIUM_%d" % n, true, false) as Node3D,
			"lamp": find_child("PODIUM_LIGHT_%d" % n, true, false) as Node3D})
	return out


## Chat-audience seat transforms (global): AUDIENCE_* markers plus every AudienceRow,
## minus seats where a camera sits.
func get_audience_seats() -> Array[Transform3D]:
	var seats: Array[Transform3D] = []
	for n in find_children(audience_prefix + "*", "Node3D", true, false):
		if not n is AudienceRow:
			seats.append((n as Node3D).global_transform)
	for n in find_children("*", "Marker3D", true, false):
		if n is AudienceRow:
			seats.append_array((n as AudienceRow).get_seat_transforms())
	var cams := get_camera_markers()
	var out: Array[Transform3D] = []
	var kept: Array[Vector3] = []
	var gap := seat_gap()
	for t in seats:
		var clear := true
		for c in cams:
			var d := c.global_position - t.origin
			if Vector2(d.x, d.z).length() < audience_camera_clearance and absf(d.y) < 1.8:
				clear = false
				break
		if clear and _spaced(t.origin, kept, gap):
			out.append(t)
			kept.append(t.origin)
	return out


## Metres between neighbours along a row (Audience tab > Seat spacing). Seats closer than this
## to one already kept are skipped, so chatters don't sit shoulder to shoulder; rows are further
## apart than this, so they all stay. Cuts a room's capacity, which the owner accepted.
func seat_gap() -> float:
	return clampf(float(AppState.get_setting("audience_seat_gap")), 0.0, 3.0)


func _spaced(p: Vector3, kept: Array[Vector3], gap: float) -> bool:
	if gap <= 0.0:
		return true
	for k in kept:
		if absf(k.y - p.y) < 0.5 and Vector2(k.x - p.x, k.z - p.z).length() < gap - 0.01:
			return false
	return true


## Crowd seat transforms (global), minus seats where a camera sits. Empty if the room has none.
func get_crowd_seats() -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	for e in get_crowd_seat_info():
		out.append(e["xf"])
	return out


## Crowd seats with what the seating plan needs: [{xf, level (1 lower tier, 2 balcony,
## 3 gallery), facing (global, flat; ZERO if unknown)}], minus seats where a camera sits.
func get_crowd_seat_info() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if crowd_seats_file == "" or not FileAccess.file_exists(crowd_seats_file):
		return out
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(crowd_seats_file))
	if not data is Dictionary or not (data as Dictionary).get("seats") is Array:
		push_warning("Room: can't read crowd seats from %s" % crowd_seats_file)
		return out
	var cams := get_camera_markers()
	var levels := {"orch": 1, "bal": 2, "gal": 3}
	var kept: Array[Vector3] = []
	var gap := seat_gap()
	for e: Variant in data["seats"]:
		if not e is Dictionary or not (e as Dictionary).get("p") is Array:
			continue
		var p: Array = e["p"]
		var at := global_transform * Vector3(float(p[0]), float(p[1]), float(p[2]))
		var clear := true
		for c in cams:
			var d := c.global_position - at
			if Vector2(d.x, d.z).length() < audience_camera_clearance and absf(d.y) < 1.8:
				clear = false
				break
		if not clear or not _spaced(at, kept, gap):
			continue
		kept.append(at)
		var facing := Vector3.ZERO
		if (e as Dictionary).get("n") is Array and (e["n"] as Array).size() >= 2:
			facing = (global_basis * Vector3(float(e["n"][0]), 0.0, float(e["n"][1]))).normalized()
		out.append({"xf": Transform3D(Basis.IDENTITY, at), "level": int(levels.get(String(e.get("s", "")), 1)), "facing": facing})
	return out


func get_mirror_screens() -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for n in find_children(mirror_screen_prefix + "*", "MeshInstance3D", true, false):
		out.append(n as MeshInstance3D)
	return out


# ── Private ──────────────────────────────────────────────────
func _apply_material_overrides() -> void:
	for n in find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(s)
			if m and material_overrides.has(m.resource_name):
				mi.set_surface_override_material(s, material_overrides[m.resource_name])


func _collect_glow_materials() -> void:
	var done: Dictionary = {}    # original material -> duplicate, so shared materials stay shared
	for n in find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(s) as BaseMaterial3D
			if m == null or not glow_materials.has(m.resource_name):
				continue
			if not done.has(m):
				var d := m.duplicate() as BaseMaterial3D
				done[m] = d
				_glow.append({"mat": d, "energy": d.emission_energy_multiplier})
			mi.set_surface_override_material(s, done[m])


func _spawn_lamp_lights(group: Node) -> void:
	for n in group.find_children(lamp_prefix + "*", "Node3D", true, false):
		if n is Light3D or not n.find_children("*", "Light3D", false, false).is_empty():
			continue
		var l := OmniLight3D.new()
		l.name = "Light"
		l.light_color = lamp_color
		l.light_energy = lamp_energy
		l.omni_range = lamp_range
		l.omni_attenuation = 1.3
		l.shadow_enabled = lamp_shadows
		l.light_volumetric_fog_energy = 0.4
		n.add_child(l)


## Auto-dim level (playing / react pause / idle) times the House lights setting.
func _target_level() -> float:
	var master := clampf(float(AppState.get_setting("house_lights")), 0.0, 1.0)
	if AppState.is_show_dimmed():
		return 0.15 * master          # curtain reveal: lights down
	if not AppState.get_setting("auto_dim_house"):
		return master
	if AppState.is_react_paused() and AppState.get_setting("react_lights_up"):
		return 0.55 * master
	return (dimmed_level if AppState.is_playback_active() else 1.0) * master
