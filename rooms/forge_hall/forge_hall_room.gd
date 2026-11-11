extends Room
## Forge Hall (a tall hall of carved stone slabs with circuit-board light inlays, a forge
## fireplace, slanted windows under a diamond-plate ceiling and art alcoves; the model comes from
## blender/forge_hall_gen.py, after the owner's reference picture and cross-section sketch).
##   - The LAMP_* markers from Blender become two kinds of house light, tuned by name: the warm
##     hanging lanterns ("Lantern") and a cyan wash either side of the seats ("Neon").
##   - The fire: flames are drawn at the FIRE_Main (firebox) and FIRE_Slot (under the hearth)
##     markers with fire.gdshader, and a flickering orange light stands in front of the firebox.
##     The Fire slider in the Room tab ("forge_fire") scales the flames, the light, the embers
##     and the crackle; 0 puts the fire out. The flicker is gentle (a few percent, slow) and
##     stops in photosensitive-safe mode.
##   - The light inlays (materials Neon_Cyan / Neon_Orange / Neon_Purple: lines set flush into
##     the floor, walls and pillars like the traces of a circuit board; a finer, dimmer second
##     layer, Neon_Fine_Cyan / Neon_Fine_Amber; plus the glowing pipes and the round sign) are
##     scaled by the Inlay brightness slider ("forge_neon"). With Inlay glow ("forge_neon_bloom")
##     off they are held just under the brightness where the picture's bloom starts, so they
##     stay crisp lines with no halo. Like the lantern glass they also dim with the house
##     lights (glow_materials on the room scene).
##   - The screen: the model only has a flat TVScreen rectangle. _shape_screen() swaps its mesh
##     for one that is moved, resized and bent from the "forge_screen_*" settings (Room tab >
##     Screen shape). The LED dots and hologram look are the app's own (RoomInfo.screen_led_amount
##     / screen_hologram on room_info.tres; core/screen_lights.gd), with their sliders added to
##     the Room tab by RoomHost.
##   - Art frames: one in each wall alcove (ART_n markers). _build_art() makes a frame and a
##     canvas; the frame material ("forge_art_frame"), the style ("forge_art_style": a lit
##     picture or a see-through hologram, art_holo.gdshader) and each picture ("forge_art_n",
##     blank = the built-in poster textures/art_n.png) are settings on the Room tab.
##   - Time of day ("forge_time", hours; "forge_day_minutes" lets the clock run): _apply_time()
##     moves the sun and the moon across the sky seen through the slanted windows
##     (forge_sky.gdshader on the room's Environment, with stars at night), changes the room's
##     ambient light, and makes the light through the windows follow: sunbeams (the Lecture
##     Hall's sun_shaft.gdshader) and barred patches on the floor come through the left windows
##     in the morning and the right ones in the afternoon (SHAFT_SkyL_n / SHAFT_SkyR_n
##     markers), warm at sunrise and sunset, and pale blue moonbeams at night. The Light rays
##     slider ("sun_rays", shared with the Lecture Hall) scales them.
##   - Three small live screens (_build_live_screens): one rises out of the floor at the
##     SCREEN_Lift marker when "forge_lift_up" is ticked, two hang above the big screen
##     (SCREEN_Upper_n). Each shows what its "forge_live_n_source" setting says: the webcam,
##     a podium's live feed, a copy of the big screen, a picture file, or a feed of its own
##     named by "forge_live_n_address": an NDI source, a Spout sender or a stream address
##     (RTMP, RTSP, a video file...; core/extra_feeds.gd). The two wall screens can be
##     moved, resized, tilted and turned (_place_wall_screens). They are this PC's
##     only: none of their settings are shared in a co-stream.
##   - A "please stand by" card replaces the curtain (RoomInfo.standby_card on room_info.tres;
##     core/standby_card.gd), and a ReflectionProbe gives the polished granite its reflections.
##   - A generated fire sound (a low roar with crackles) on the Ambience bus.

const MIX_RATE: float = 22050.0
## Small-screen sources that are a feed of the screen's own, fetched by ExtraFeeds
## (core/extra_feeds.gd) from the screen's "forge_live_n_address".
const OWN_FEEDS: Array[String] = ["ndi", "spout", "stream"]
const SHAFT_SHADER := preload("res://rooms/lecture_hall/sun_shaft.gdshader")
const FIRE_SHADER := preload("res://rooms/forge_hall/fire.gdshader")
const SUN_PATCH := preload("res://rooms/forge_hall/textures/sun_patch.png")
const ART_HOLO_SHADER := preload("res://rooms/forge_hall/art_holo.gdshader")
const SKY_SHADER := preload("res://rooms/forge_hall/forge_sky.gdshader")
const GRANITE := preload("res://rooms/forge_hall/textures/slab_granite.png")
## The built-in posters (blender/make_forge_textures.py), %d = 1..ART_POSTERS; the frames take
## them in turn.
const ART_BUILTIN: String = "res://rooms/forge_hall/textures/art_%d.png"
const ART_POSTERS: int = 6
## How many art frames there can be: must match the "forge_art_1".."forge_art_13" settings in
## AppState.DEFAULTS and the ALCOVES list in blender/forge_hall_gen.py.
const ART_COUNT: int = 13
## The small live screens: [marker name, rises from the floor]. Screen n (1..3) uses the
## "forge_live_n_source" / "forge_live_n_picture" settings in AppState.DEFAULTS.
const LIVE_SCREENS: Array = [["SCREEN_Lift", true], ["SCREEN_Upper_1", false], ["SCREEN_Upper_2", false]]
## The glow (emission energy times the colour's brightest channel) the inlays are held under
## while Inlay glow is off. The room's Environment starts its bloom at 1.0 (glow_hdr_threshold
## in room_info.tres), so this must stay below that.
const NO_BLOOM_GLOW: float = 0.8
## Columns the bent screen is cut into (a flat screen uses the same mesh).
const SCREEN_COLUMNS: int = 40
## Imported material names (blender/forge_hall_gen.py, setup_materials) that the two sliders scale.
const NEON_MATERIALS: PackedStringArray = ["Neon_Cyan", "Neon_Orange", "Neon_Purple", "Neon_Fine_Cyan", "Neon_Fine_Amber", "Pipe_Glow", "Rune_Sign"]
const FIRE_MATERIALS: PackedStringArray = ["Embers"]

@export_group("Light groups")
## Energy and range (metres) per light group; _tune_lights() picks the group from the LAMP_ name
## (contains "Lantern" or "Neon").
@export var lantern_energy: float = 3.2
@export var lantern_range: float = 16.0
@export var lantern_color: Color = Color(1.0, 0.72, 0.42)
@export var neon_energy: float = 1.4
@export var neon_range: float = 11.0
@export var neon_color: Color = Color(0.3, 0.85, 1.0)
## The inlays' glow at Light strips 100%, as a share of what the model's materials have (there
## are a lot of them now, and at full strength their bloom hid the stone).
@export_range(0.0, 1.0) var neon_strength: float = 0.6

@export_group("Fire")
## The firebox flames: width and height in metres (the slot's are lower and a little wider).
@export var flame_size: Vector2 = Vector2(1.5, 1.7)
@export var slot_flame_size: Vector2 = Vector2(1.6, 0.55)
## The light the fire throws: energy at Fire 100% with the house lights up, and its range (metres).
@export var fire_light_energy: float = 4.5
@export var fire_light_range: float = 12.0
@export var fire_light_color: Color = Color(1.0, 0.52, 0.2)
## How much the fire's light wavers (share of its energy). 0 = steady.
@export_range(0.0, 0.3) var fire_flicker: float = 0.1
## The fire's light drops to this share while the house lights are dimmed for a video, so it
## doesn't wash over the picture.
@export_range(0.0, 1.0) var fire_dimmed: float = 0.35

@export_group("Sunbeams")
## Half the window pane the sun comes through: x = along the hall, y = up the slanted glass
## (metres). Must match SKY_HW and SKY_HALF_SLANT in blender/forge_hall_gen.py.
@export var skylight_half: Vector2 = Vector2(1.25, 1.37)
## How far the sun's path leans towards the screen end of the hall (0 = it passes straight
## overhead). It sends the beams a little towards the back of the hall.
@export var sun_lean: float = 0.28
## The steepest slant a beam may have: metres across the hall per metre it drops. Keeps the
## low sun's beams landing on the floor instead of on the far wall.
@export var beam_max_slant: float = 1.8
@export var moon_color: Color = Color(0.55, 0.68, 1.0)
## Moonbeams' strength as a share of the midday sunbeams'.
@export_range(0.0, 1.0) var moon_strength: float = 0.35
@export_range(0.0, 1.0) var shaft_intensity: float = 0.3
@export var shaft_color: Color = Color(1.0, 0.82, 0.55)
## Brightness of the patches of sunlight on the floor at Light rays 100%.
@export_range(0.0, 2.0) var patch_strength: float = 0.5

@export_group("Screen shape")
## The part of the screen wall the screen may cover, in the TVScreen mesh's own space (metres:
## x across the wall, y up from the floor). It is the screen alcove (ALC_HW / ALC_TOP in
## blender/forge_hall_gen.py) less a small margin; _shape_screen() keeps the screen inside it.
@export var screen_area: Rect2 = Rect2(-4.95, 0.4, 9.9, 7.1)
## Half the angle (degrees) the screen wraps through at Bend 100%.
@export var screen_bend_degrees: float = 50.0

@export_group("Alcove art")
## The largest a picture is drawn (metres, width x height); it keeps its own shape inside that.
@export var art_max_size: Vector2 = Vector2(1.4, 2.0)
## Width of the frame's bars and how far they stand out from the wall (metres).
@export var art_frame_width: float = 0.09
@export var art_frame_depth: float = 0.07
## How far a hologram floats in front of the alcove's back wall (metres).
@export var art_holo_float: float = 0.14
@export var art_holo_tint: Color = Color(0.45, 0.95, 1.0)
## Glow of the "neon" frame material at Light strips 100% with the house lights up.
@export var art_neon_energy: float = 2.5

@export_group("Time of day")
## The room's ambient light at night and by day (colour, energy); _apply_time() mixes them.
@export var night_ambient: Color = Color(0.28, 0.34, 0.6)
@export var night_ambient_energy: float = 0.14
@export var day_ambient: Color = Color(0.5, 0.44, 0.42)
@export var day_ambient_energy: float = 0.26
## The window glass by night and by day (alpha = how much it hides the sky).
@export var night_glass: Color = Color(0.1, 0.14, 0.25, 0.3)
@export var day_glass: Color = Color(0.8, 0.9, 1.0, 0.1)
## The sky's brightness through the windows (1 = as the sky shader draws it).
@export var sky_exposure: float = 0.9
## How far the clock must move (hours) before the sky and the beams are redrawn.
@export var time_step: float = 0.02

@export_group("Live screens")
## The picture area of each small screen (metres). A feed keeps its own shape inside it.
@export var live_screen_size: Vector2 = Vector2(2.6, 1.4625)
## The floor screen when raised: height of its bottom edge above the floor (metres).
@export var lift_height: float = 1.0
## Seconds the floor screen takes to rise or sink.
@export var lift_seconds: float = 2.5

@export_group("Reflections")
## The box the reflection probe covers, in the room's own space (the whole hall: must match
## HALF_W, BACK_Y and CEIL_Z in blender/forge_hall_gen.py).
@export var probe_center: Vector3 = Vector3(0.0, 6.0, 17.0)
@export var probe_size: Vector3 = Vector3(18.2, 12.2, 34.4)
@export_range(0.0, 1.0) var probe_intensity: float = 0.7

@export_group("Sound")
@export var ambience_enabled: bool = true
@export_range(0.0, 1.0) var fire_loudness: float = 0.07

var _amb_playback: AudioStreamGeneratorPlayback
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _lp: float = 0.0             # low-pass state for the fire's roar
var _pop: float = 0.0            # the current crackle, dying away
var _shafts: MeshInstance3D      # the sunbeams (null without SHAFT_Sky markers)
var _shaft_mat: ShaderMaterial
var _patches: MeshInstance3D     # the patches of sunlight on the floor
var _patch_mat: StandardMaterial3D
## Holds what this script draws (flames, sunbeams, patches). Named "SunShafts" so the app
## doesn't count them as the room's own meshes.
var _fx: Node3D
var _fire_mats: Array[ShaderMaterial] = []
var _fire_meshes: Array[MeshInstance3D] = []
var _fire_light: OmniLight3D
var _neon_lights: Array[OmniLight3D] = []
var _screen_box: AABB            # the TVScreen rectangle as the model has it (set once in _shape_screen)
var _screen_has_box: bool = false
## One entry per art frame: {n: int (1..), root: Node3D, canvas: MeshInstance3D,
## bars: Array of MeshInstance3D (top, bottom, left, right), tex: Texture2D (what it shows now),
## path: String (the picture file that was asked for last, "" = the built-in poster)}.
var _art: Array[Dictionary] = []
var _art_frame_mat: StandardMaterial3D     # shared by every frame's bars
var _hour: float = 9.5           # the room's clock, hours 0..24 (starts at "forge_time")
var _hour_drawn: float = -99.0   # the hour the sky and beams were last drawn for
var _env_drawn: int = 0          # instance id of the Environment they were drawn on
var _glass_mat: BaseMaterial3D   # the slanted windows' glass (Sky_Glass in the model)
## The window panes the beams can come through: each pane's transform in the room's space.
var _panes_left: Array[Transform3D] = []
var _panes_right: Array[Transform3D] = []
var _beam_strength: float = 1.0  # 0..1: how strong the sun / moon makes the beams right now
var _beam_color: Color = Color(1.0, 0.82, 0.55)
var _beam_side: int = 0          # -1 = the left windows are lit, 1 = the right ones, 0 = none (rebuild when it changes)
var _beam_dir: Vector3 = Vector3.ZERO      # the direction the beams were last built for
## One entry per small live screen: {n: int (1..3), lift: bool, root: Node3D, body: Node3D
## (what moves up and down; the root itself for a wall screen), panel: MeshInstance3D,
## mat: StandardMaterial3D, path: String (the picture file asked for last), pic: Texture2D}.
var _live: Array[Dictionary] = []
## The feeds' pictures as ScreenFeed last announced them: "webcam", "screen", "podium1".."podium4".
var _feed_tex: Dictionary = {}
var _lift_tween: Tween
var _retired: bool = false       # another room has taken over (retire()): leave the sky alone
var _webcam_claimed: bool = false   # this room told AppState a live screen shows the webcam
var _time: float = 0.0
var _last_level: float = -1.0    # the house light level the patches / fire were last set for


func _ready() -> void:
	super._ready()
	# remember each glow material's own brightness: the sliders scale it from there
	for g in _glow:
		g["base"] = float(g["energy"])
	_tune_lights()
	# before anything reads the screen: RoomHost places the screen's lights, the curtain and
	# the camera's focus from this mesh right after _ready
	_shape_screen()
	_fx = Node3D.new()
	_fx.name = "SunShafts"          # Room.get_static_meshes() skips everything under this name
	add_child(_fx)
	_setup_glass()
	_build_probe()
	_build_art()
	_build_fire()
	_build_sunbeams()
	_build_live_screens()
	_apply_neon()
	_apply_fire()
	_hour = fposmod(float(AppState.get_setting("forge_time")), 24.0)
	if ambience_enabled:
		_amb_playback = _start_generated_ambience(MIX_RATE, 0.3)
	EventBus.setting_changed.connect(_on_fh_setting_changed)
	EventBus.webcam_texture_changed.connect(_on_webcam_texture)
	EventBus.screen_texture_changed.connect(_on_screen_texture)
	EventBus.presenter_texture_changed.connect(_on_presenter_texture)
	EventBus.extra_feed_texture_changed.connect(_on_extra_texture)
	EventBus.room_changed.connect(_on_fh_room_changed)
	# the feeds only announce themselves when they start: ask for what is running now (after
	# RoomHost has finished setting this room up)
	EventBus.feed_textures_requested.emit.call_deferred()


## The room is freed on a room swap: drop the EventBus connections with it.
func _exit_tree() -> void:
	if EventBus.setting_changed.is_connected(_on_fh_setting_changed):
		EventBus.setting_changed.disconnect(_on_fh_setting_changed)
		EventBus.webcam_texture_changed.disconnect(_on_webcam_texture)
		EventBus.screen_texture_changed.disconnect(_on_screen_texture)
		EventBus.presenter_texture_changed.disconnect(_on_presenter_texture)
		EventBus.extra_feed_texture_changed.disconnect(_on_extra_texture)
		EventBus.room_changed.disconnect(_on_fh_room_changed)


## RoomHost calls this (through propagate_call) when another room replaces this one, three
## seconds before it is freed: stop touching the sky and the feeds, which are the new room's now.
func retire() -> void:
	_retired = true         # (the room keeps processing: see RoomHost._retire for why)
	_exit_tree()


## The screen's place, size and bend change where RoomHost puts the screen's lights and the
## curtain, which it only works out when the room loads: so it reloads the room a moment after
## one of these stops changing (the screen itself already moves while the slider is dragged).
func reload_keys() -> PackedStringArray:
	return PackedStringArray(["forge_screen_x", "forge_screen_y", "forge_screen_size", "forge_screen_bend"])


## Room tab: the Fire, Light strips and Light rays sliders, the screen's shape and the alcove
## art. (RoomHost adds the LED dots and Hologram screen sliders after these.)
func get_controls() -> Array[Dictionary]:
	var out: Array[Dictionary] = [
		{"heading": "Forge Hall"},
		{"key": "forge_fire", "label": "Fire", "min": 0.0, "max": 2.0, "step": 0.01, "format": "%d%%", "scale": 100.0,
			"tooltip": "How big the forge fire is: its flames, the light it throws and its crackle. 0% = out."},
		{"key": "forge_neon", "label": "Inlay brightness", "min": 0.0, "max": 3.0, "step": 0.01, "format": "%d%%", "scale": 100.0,
			"tooltip": "How bright the cyan, orange and purple light inlays and the glowing pipes are. 0% = off. With Inlay glow off, 100% is as bright as they get."},
		{"key": "forge_neon_bloom", "label": "Inlay glow (halo round the lines)", "type": "check",
			"tooltip": "On: the light inlays glow with a soft halo. Off: they are crisp lit lines with no halo."},
		{"heading": "Time of day"},
		{"key": "forge_time", "label": "Time of day", "min": 0.0, "max": 24.0, "step": 0.1, "format": "%.1f h",
			"tooltip": "The hour in the hall, 0 to 24: the sky, the sun, the moon and stars, and the light through the windows. 6 = sunrise, 12 = noon, 18 = sunset. The sun shines in from the left in the morning and from the right in the afternoon."},
		{"key": "forge_day_minutes", "label": "Day length", "min": 0.0, "max": 120.0, "step": 1.0, "format": "%d min", "zero": "Clock stopped",
			"tooltip": "Lets the clock run: how many minutes a full day and night takes, starting from the Time of day. 0 = the clock stands still."},
	]
	if _shafts != null:
		out.append({"key": "sun_rays", "label": "Light rays", "min": 0.0, "max": 2.0, "step": 0.01, "format": "%d%%", "scale": 100.0,
			"tooltip": "How visible the sunbeams from the slanted windows and their patches on the floor are. 0% = off."})
	out.append({"heading": "Screen shape"})
	out.append({"key": "forge_screen_bend", "label": "Bend", "min": -1.0, "max": 1.0, "step": 0.01, "format": "%d%%", "scale": 100.0,
		"tooltip": "Bends the screen. Above 0% its edges wrap towards the audience (concave), below 0% its middle bulges out at them (convex). 0% = flat. The room reloads a moment after you let go."})
	out.append({"key": "forge_screen_size", "label": "Size", "min": 0.4, "max": 1.15, "step": 0.01, "format": "%d%%", "scale": 100.0,
		"tooltip": "How big the screen is. 100% = 8.6 metres wide. It never grows past its alcove."})
	out.append({"key": "forge_screen_x", "label": "Move left/right", "min": -3.0, "max": 3.0, "step": 0.05, "format": "%.2f m",
		"tooltip": "Slides the screen along its wall: left (-) or right (+), in metres. It stops at the alcove's edges, so make it smaller first to move it further."})
	out.append({"key": "forge_screen_y", "label": "Move up/down", "min": -2.0, "max": 2.0, "step": 0.05, "format": "%.2f m",
		"tooltip": "Slides the screen down (-) or up (+) its wall, in metres. It stops at the alcove's edges."})
	if not _live.is_empty():
		out.append({"heading": "Small live screens"})
		out.append({"key": "forge_lift_up", "label": "Raise the floor screen", "type": "check",
			"tooltip": "Raises the small screen out of the floor in front of the big screen, or lowers it back in."})
		var names: PackedStringArray = ["Floor screen", "Upper left screen", "Upper right screen"]
		for a in _live:
			var n := int(a["n"])
			out.append({"key": "forge_live_%d_source" % n, "label": names[n - 1], "type": "option",
				"options": [["off", "Off"], ["webcam", "Webcam"], ["podium1", "Podium 1's feed"], ["podium2", "Podium 2's feed"],
					["podium3", "Podium 3's feed"], ["podium4", "Podium 4's feed"], ["screen", "Copy of the big screen"], ["picture", "Picture file"],
					["ndi", "NDI source (name below)"], ["spout", "Spout sender (name below)"], ["stream", "Stream address (below)"]],
				"tooltip": "What this small screen shows. Webcam = the webcam from the sender page. A podium's feed = whatever that podium shows live (it has to be on, in the Presenters tab). NDI source, Spout sender and Stream address give this screen a feed of its own, named in the box below (picture only, no sound). These screens are not sent to co-stream guests."})
			out.append({"key": "forge_live_%d_address" % n, "label": "%s address" % names[n - 1], "type": "text",
				"placeholder": "NDI or Spout name, or rtmp:// rtsp:// address",
				"tooltip": "For NDI source or Spout sender: the source's name, or just part of it (cam 2 finds STUDIO-PC (cam 2)). For Stream address: an rtmp://, rtsp://, srt:// or http stream address, or a video file (it loops); needs ffmpeg in the tools folder. Put listen: in front (listen:rtmp://0.0.0.0:1935/live/cam) to wait for a camera or phone app to connect to this PC instead. Press Enter to apply."})
			out.append({"key": "forge_live_%d_picture" % n, "label": "%s picture" % names[n - 1], "type": "picture",
				"placeholder": "used when it shows Picture file",
				"tooltip": "The picture this screen shows when it is set to Picture file. PNG, JPG, WebP or GIF (animated GIFs play), up to 3 MB."})
		out.append({"heading": "Wall screens: place"})
		out.append({"key": "forge_live_align", "label": "Keep the two wall screens aligned", "type": "check",
			"tooltip": "Ticked: the upper right screen copies the upper left one as a mirror image (same height, size and tilt, the opposite sideways move and turn), so you only set the left one. Unticked: each screen has its own sliders."})
		for n: int in [2, 3]:
			var who := "Upper left" if n == 2 else "Upper right"
			var note := "" if n == 2 else " Ignored while Keep the two wall screens aligned is ticked."
			out.append({"key": "forge_live_%d_x" % n, "label": "%s: left/right" % who, "min": -5.0, "max": 5.0, "step": 0.05, "format": "%.2f m",
				"tooltip": "Slides this screen left (-) or right (+) along the wall, in metres." + note})
			out.append({"key": "forge_live_%d_y" % n, "label": "%s: up/down" % who, "min": -3.0, "max": 3.0, "step": 0.05, "format": "%.2f m",
				"tooltip": "Slides this screen down (-) or up (+) the wall, in metres." + note})
			out.append({"key": "forge_live_%d_size" % n, "label": "%s: size" % who, "min": 0.3, "max": 2.5, "step": 0.01, "format": "%d%%", "scale": 100.0,
				"tooltip": "How big this screen is. 100% = 2.6 m wide." + note})
			out.append({"key": "forge_live_%d_tilt" % n, "label": "%s: tilt" % who, "min": -45.0, "max": 45.0, "step": 1.0, "format": "%d°",
				"tooltip": "Leans the top of this screen towards the seats (+), so it looks down at them, or back (-)." + note})
			out.append({"key": "forge_live_%d_turn" % n, "label": "%s: turn" % who, "min": -60.0, "max": 60.0, "step": 1.0, "format": "%d°",
				"tooltip": "Turns this screen's face to the right (+) or the left (-), as seen from the seats." + note})
	if not _art.is_empty():
		out.append({"heading": "Alcove art"})
		out.append({"key": "forge_art_frame", "label": "Frame", "type": "option",
			"options": [["brass", "Brass"], ["steel", "Steel"], ["wood", "Dark wood"], ["granite", "Granite"], ["neon", "Light strip"], ["none", "No frame"]],
			"tooltip": "What the frames round the alcove art are made of. Light strip glows and follows the Inlay brightness slider."})
		out.append({"key": "forge_art_style", "label": "Art style", "type": "option",
			"options": [["picture", "Picture"], ["hologram", "Hologram"]],
			"tooltip": "Picture: flat on the wall, lit by the room. Hologram: see-through and glowing, floating in front of the wall with scan lines."})
		for a in _art:
			out.append({"key": "forge_art_%d" % int(a["n"]), "label": "Art %d" % int(a["n"]), "type": "picture",
				"placeholder": "blank = the built-in poster",
				"tooltip": "The picture in alcove %d (1 to 6 = the left wall from the front, 7 to 11 = the right wall, 12 and 13 = the back wall). PNG, JPG, WebP or GIF (animated GIFs play), up to 3 MB. Blank = a built-in poster." % int(a["n"])})
	return out


func _on_fh_setting_changed(key: String, _value: Variant) -> void:
	match key:
		"forge_fire":
			_apply_fire()
		"forge_neon", "forge_neon_bloom":
			_apply_neon()
		"forge_time":
			_hour = fposmod(float(AppState.get_setting("forge_time")), 24.0)
		"forge_lift_up":
			_move_lift(true)
		"sun_rays":
			_apply_sun_rays()
		"forge_screen_x", "forge_screen_y", "forge_screen_size", "forge_screen_bend":
			_shape_screen()         # shown at once; RoomHost reloads the room shortly after
		"forge_art_frame", "forge_art_style", "photosensitive_safe":
			_apply_art_frame()
			for a in _art:
				_apply_art(a)
		_:
			if key.begins_with("forge_art_"):
				for a in _art:
					if key == "forge_art_%d" % int(a["n"]):
						_load_art(a)
			elif key.begins_with("forge_live_"):
				for a in _live:
					if key == "forge_live_%d_picture" % int(a["n"]):
						_load_live_picture(a)
				_place_wall_screens()
				_request_feeds()
				_refresh_live()


## The sunbeams and the fire follow the house lights; the fire flickers; the sound keeps playing.
func _process(delta: float) -> void:
	super._process(delta)
	_time += delta
	_run_clock(delta)
	if not is_equal_approx(_level, _last_level):
		_last_level = _level
		if _shaft_mat:
			_shaft_mat.set_shader_parameter("light_level", _level)
		_apply_sun_patches()
		_apply_art_level()
	_flicker_fire()
	_fill_ambience()


# ── Lights ───────────────────────────────────────────────────
## Sets each house light from its group's energy / range / colour (LAMP_ lights are children
## named "Light", so the group comes from the parent's name) and records the new base energy.
func _tune_lights() -> void:
	for l in _house_lights:
		var owner_name := String(l.get_parent().name) if l.name == &"Light" else String(l.name)
		var o := l as OmniLight3D
		if o == null:
			continue
		if owner_name.contains("Lantern"):
			o.light_energy = lantern_energy
			o.omni_range = lantern_range
			o.light_color = lantern_color
			o.light_volumetric_fog_energy = 0.6
		elif owner_name.contains("Neon"):
			o.light_energy = neon_energy
			o.omni_range = neon_range
			o.light_color = neon_color
			_neon_lights.append(o)
		_base_energy[l] = o.light_energy
		o.light_energy = float(_base_energy[l]) * _level


## "forge_neon" (AppState.DEFAULTS, 0..3): scales the glow of the NEON_MATERIALS and the cyan
## wash lights. With "forge_neon_bloom" off the glow is also capped at NO_BLOOM_GLOW, under
## the brightness where bloom starts. Room._process then keeps dimming them with the house
## lights from the new value.
func _apply_neon() -> void:
	var amount := clampf(float(AppState.get_setting("forge_neon")), 0.0, 3.0)
	var top := INF if bool(AppState.get_setting("forge_neon_bloom")) else NO_BLOOM_GLOW
	_scale_glow(NEON_MATERIALS, amount * neon_strength, top)
	for o in _neon_lights:
		_base_energy[o] = neon_energy * amount
		o.light_energy = neon_energy * amount * _level
	_apply_art_level()          # the "Light strip" art frames follow this slider too


## Sets the glow of every glow material named in `names` to its own brightness times amount,
## but never brighter than `top` (energy times the emission colour's brightest channel).
func _scale_glow(names: PackedStringArray, amount: float, top: float = INF) -> void:
	for g in _glow:
		var m := g["mat"] as BaseMaterial3D
		if names.has(m.resource_name):
			var peak := maxf(maxf(m.emission.r, m.emission.g), maxf(m.emission.b, 0.01))
			g["energy"] = minf(float(g["base"]) * amount, top / peak)
			m.emission_energy_multiplier = float(g["energy"]) * _level


# ── The screen's shape ───────────────────────────────────────
## Swaps the TVScreen mesh for one moved, resized and bent from the "forge_screen_x / _y /
## _size / _bend" settings (AppState.DEFAULTS). Called from _ready (before RoomHost reads the
## screen) and again whenever one of the four changes.
## The model's rectangle is thin along the mesh's own Z and faces +Z (the audience), with
## UV (0, 0) at its top left as the audience sees it; the new mesh keeps all of that, so the
## app's screen material works on it unchanged. It is a strip of SCREEN_COLUMNS columns along
## an arc: Bend x screen_bend_degrees is half the angle the arc turns through. The picture's
## width along the arc stays the same, and the arc is always in front of the wall: bent
## inwards (concave) the edges come forward, bent outwards (convex) the middle does.
func _shape_screen() -> void:
	var screen := find_screen()
	if screen == null or screen.mesh == null:
		return
	if not _screen_has_box:
		_screen_box = screen.mesh.get_aabb()
		_screen_has_box = true
	var box := _screen_box
	# size first (so it fits the alcove), then the place (so it stays inside it)
	var fit := minf(screen_area.size.x / box.size.x, screen_area.size.y / box.size.y)
	var k := clampf(float(AppState.get_setting("forge_screen_size")), 0.2, fit)
	var w := box.size.x * k
	var h := box.size.y * k
	var mid := box.get_center()
	var cx := clampf(mid.x + float(AppState.get_setting("forge_screen_x")),
		screen_area.position.x + w * 0.5, screen_area.end.x - w * 0.5)
	var cy := clampf(mid.y + float(AppState.get_setting("forge_screen_y")),
		screen_area.position.y + h * 0.5, screen_area.end.y - h * 0.5)
	var z0 := box.end.z                     # the model's screen surface (just off the wall)
	var bend := clampf(float(AppState.get_setting("forge_screen_bend")), -1.0, 1.0)
	var half_angle := absf(bend) * deg_to_rad(screen_bend_degrees)
	var flat := half_angle < 0.002
	var radius := 0.0 if flat else (w * 0.5) / half_angle
	var deepest := 0.0 if flat else radius * (1.0 - cos(half_angle))   # how far the arc's ends are from its middle
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for i in SCREEN_COLUMNS + 1:
		var t := float(i) / SCREEN_COLUMNS          # 0 = the audience's left edge, 1 = right
		var a := (t * 2.0 - 1.0) * half_angle       # this column's angle round the arc
		var x := (t - 0.5) * w
		var z := z0
		var n := Vector3(0.0, 0.0, 1.0)
		if not flat:
			x = radius * sin(a)
			var depth := radius * (1.0 - cos(a))    # 0 in the middle, `deepest` at the edges
			if bend > 0.0:
				z = z0 + depth                      # concave: the edges come towards the audience
				n = Vector3(-sin(a), 0.0, cos(a))
			else:
				z = z0 + deepest - depth            # convex: the middle comes towards the audience
				n = Vector3(sin(a), 0.0, cos(a))
		verts.append(Vector3(cx + x, cy + h * 0.5, z))
		verts.append(Vector3(cx + x, cy - h * 0.5, z))
		norms.append(n)
		norms.append(n)
		uvs.append(Vector2(t, 0.0))
		uvs.append(Vector2(t, 1.0))
		if i < SCREEN_COLUMNS:
			var v := i * 2                          # this column's top; +1 = its bottom, +2 / +3 = the next column's
			# clockwise as the audience sees it (Redot's front face)
			idx.append_array(PackedInt32Array([v, v + 2, v + 3, v, v + 3, v + 1]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	screen.mesh = mesh


# ── Alcove art ───────────────────────────────────────────────
## A frame (four bars) and a canvas at every ART_n marker (the middle of an alcove's back wall,
## +Z facing into the room). They live under _fx so they aren't counted as the room's meshes.
func _build_art() -> void:
	_art_frame_mat = StandardMaterial3D.new()
	_apply_art_frame()
	for n in range(1, ART_COUNT + 1):
		var marker := find_child("ART_%d" % n, true, false) as Node3D
		if marker == null:
			continue
		var root := Node3D.new()
		root.name = "ArtFrame%d" % n
		_fx.add_child(root)
		root.global_transform = Transform3D(marker.global_basis.orthonormalized(), marker.global_position)
		var canvas := MeshInstance3D.new()
		canvas.name = "Canvas"
		canvas.mesh = QuadMesh.new()
		canvas.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(canvas)
		var bars: Array[MeshInstance3D] = []
		for b in 4:
			var bar := MeshInstance3D.new()
			bar.name = "Bar%d" % b
			bar.mesh = BoxMesh.new()
			bar.material_override = _art_frame_mat
			root.add_child(bar)
			bars.append(bar)
		var a := {"n": n, "root": root, "canvas": canvas, "bars": bars, "tex": null, "path": ""}
		_art.append(a)
		_load_art(a)


## "forge_art_frame" (AppState.DEFAULTS): what the shared frame material looks like.
## "none" hides the bars (see _apply_art).
func _apply_art_frame() -> void:
	var m := _art_frame_mat
	m.albedo_texture = null
	m.emission_enabled = false
	m.metallic = 1.0
	m.roughness = 0.35
	m.uv1_triplanar = false
	match String(AppState.get_setting("forge_art_frame")):
		"steel":
			m.albedo_color = Color(0.62, 0.65, 0.7)
			m.roughness = 0.3
		"wood":
			m.albedo_color = Color(0.3, 0.18, 0.09)
			m.metallic = 0.0
			m.roughness = 0.7
		"granite":
			m.albedo_color = Color(1.6, 1.6, 1.6)     # a shade lighter than the walls, so it reads as a frame
			m.albedo_texture = GRANITE
			m.uv1_triplanar = true      # the bars have no useful UVs of their own
			m.metallic = 0.0
			m.roughness = 0.16
		"neon":
			m.albedo_color = Color(0.05, 0.12, 0.14)
			m.metallic = 0.0
			m.emission_enabled = true
			m.emission = Color(0.3, 0.9, 1.0)
		_:
			m.albedo_color = Color(0.8, 0.62, 0.28)    # brass
	_apply_art_level()


## What follows the house lights and the Light strips slider in the art: the "Light strip"
## frame's glow and the holograms' brightness. Called when either changes.
func _apply_art_level() -> void:
	if _art_frame_mat == null:
		return
	var strips := clampf(float(AppState.get_setting("forge_neon")), 0.0, 3.0)
	var glow := art_neon_energy * strips
	if not bool(AppState.get_setting("forge_neon_bloom")):
		glow = minf(glow, NO_BLOOM_GLOW)
	_art_frame_mat.emission_energy_multiplier = glow * _level
	for a in _art:
		var sm := (a["canvas"] as MeshInstance3D).material_override as ShaderMaterial
		if sm:
			sm.set_shader_parameter("level", _level)


## Picks frame a's picture: the file in its "forge_art_n" setting, or the built-in poster when
## that is blank. A file is read and decoded off the main thread, like a podium picture
## (core/presenters/presenter.gd), because an animated GIF can take a moment.
func _load_art(a: Dictionary) -> void:
	var n := int(a["n"])
	var path := String(AppState.get_setting("forge_art_%d" % n)).strip_edges()
	a["path"] = path
	if path == "":
		var poster := ART_BUILTIN % ((n - 1) % ART_POSTERS + 1)
		a["tex"] = load(poster) if ResourceLoader.exists(poster) else null
		_apply_art(a)
		return
	var bytes := PictureFile.read_file(path)
	if bytes.is_empty():
		@warning_ignore("integer_division")
		EventBus.status_message.emit("Alcove art %d: couldn't read that picture (png, jpg, webp or gif, up to %d MB)." % [n, PictureFile.MAX_BYTES / (1024 * 1024)], true)
		return
	var out: Array = [null]
	var task := WorkerThreadPool.add_task(func() -> void: out[0] = PictureFile.texture_from_bytes(bytes), false, "alcove art")
	_finish_art.call_deferred(task, a, path, out)


## Main thread, after the decode: show the picture unless another was asked for meanwhile.
func _finish_art(task: int, a: Dictionary, path: String, out: Array) -> void:
	WorkerThreadPool.wait_for_task_completion(task)
	if not is_inside_tree() or path != String(a["path"]):
		return
	if out[0] == null:
		EventBus.status_message.emit("Alcove art %d: that picture couldn't be decoded." % int(a["n"]), true)
		return
	a["tex"] = out[0]
	_apply_art(a)


## Sizes frame a's canvas to its picture (the picture's own shape, as big as fits art_max_size),
## puts the four bars round it and gives the canvas the material for "forge_art_style":
## "picture" = flat on the wall and lit by the room (with a little glow of its own so it still
## reads when the lights are down), "hologram" = art_holo.gdshader, floating off the wall.
func _apply_art(a: Dictionary) -> void:
	var canvas := a["canvas"] as MeshInstance3D
	var tex := a["tex"] as Texture2D
	canvas.visible = tex != null
	var size := art_max_size
	if tex != null and tex.get_height() > 0:
		var shape := float(tex.get_width()) / float(tex.get_height())
		size = Vector2(minf(art_max_size.x, art_max_size.y * shape), 0.0)
		size.y = size.x / shape
	(canvas.mesh as QuadMesh).size = size
	var holo := String(AppState.get_setting("forge_art_style")) == "hologram"
	if holo:
		var sm := ShaderMaterial.new()
		sm.shader = ART_HOLO_SHADER
		sm.set_shader_parameter("picture", tex)
		sm.set_shader_parameter("tint", art_holo_tint)
		sm.set_shader_parameter("level", _level)
		sm.set_shader_parameter("flicker", 0.0 if bool(AppState.get_setting("photosensitive_safe")) else 1.0)
		canvas.material_override = sm
		canvas.position = Vector3(0.0, 0.0, art_holo_float)
	else:
		var pm := StandardMaterial3D.new()
		pm.albedo_texture = tex
		pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR    # cut-out pictures keep their outline
		pm.roughness = 0.6
		pm.emission_enabled = true
		pm.emission_texture = tex
		pm.emission = Color(1.0, 1.0, 1.0)
		pm.emission_energy_multiplier = 0.18
		canvas.material_override = pm
		canvas.position = Vector3(0.0, 0.0, 0.012)
	# the bars: top, bottom, left, right, overlapping at the corners
	var fw := art_frame_width
	var bars: Array = a["bars"]
	var framed := String(AppState.get_setting("forge_art_frame")) != "none"
	var spans: Array[Vector2] = [Vector2(size.x + fw * 2.0, fw), Vector2(size.x + fw * 2.0, fw), Vector2(fw, size.y), Vector2(fw, size.y)]
	var spots: Array[Vector2] = [Vector2(0.0, (size.y + fw) * 0.5), Vector2(0.0, -(size.y + fw) * 0.5),
		Vector2(-(size.x + fw) * 0.5, 0.0), Vector2((size.x + fw) * 0.5, 0.0)]
	for b in 4:
		var bar := bars[b] as MeshInstance3D
		bar.visible = framed
		(bar.mesh as BoxMesh).size = Vector3(spans[b].x, spans[b].y, art_frame_depth)
		bar.position = Vector3(spots[b].x, spots[b].y, art_frame_depth * 0.5)


# ── The fire ─────────────────────────────────────────────────
## Flames at both FIRE_ markers and the light in front of the firebox. The markers sit at the
## bottom centre of the flames with +Z facing into the room.
func _build_fire() -> void:
	var main := find_child("FIRE_Main", true, false) as Node3D
	var slot := find_child("FIRE_Slot", true, false) as Node3D
	if main:
		# three rectangles crossing in the middle, so the fire has body from every side
		for k in 3:
			_add_flame(main, flame_size, deg_to_rad(-60.0 + 60.0 * k), float(k))
		_fire_light = OmniLight3D.new()
		_fire_light.name = "FireLight"
		_fire_light.light_color = fire_light_color
		_fire_light.omni_range = fire_light_range
		_fire_light.omni_attenuation = 1.2
		_fire_light.shadow_enabled = false
		_fire_light.light_volumetric_fog_energy = 0.8
		add_child(_fire_light)
		_fire_light.global_position = main.global_position + main.global_basis.z * 1.0 + Vector3.UP * 0.8
	if slot:
		_add_flame(slot, slot_flame_size, 0.0, 5.0)


## One upright flame rectangle at marker, turned by yaw (radians) round the vertical; seed_value
## makes its flames move differently from the others'.
func _add_flame(marker: Node3D, size: Vector2, yaw: float, seed_value: float) -> void:
	var quad := QuadMesh.new()
	quad.size = size
	var mat := ShaderMaterial.new()
	mat.shader = FIRE_SHADER
	mat.set_shader_parameter("seed", seed_value)
	var mi := MeshInstance3D.new()
	mi.name = "FireFlame"
	mi.mesh = quad
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fx.add_child(mi, true)     # true: keeps a readable name (FireFlame, FireFlame2 ...)
	# QuadMesh: centred, facing +Z, UV.y 0 at the top: the shader wants 0 at the logs, so the
	# rectangle is turned upside down (and UV.x mirrored, which a flame doesn't mind)
	var b := marker.global_basis.orthonormalized().rotated(Vector3.UP, yaw)
	mi.global_transform = Transform3D(Basis(-b.x, -b.y, b.z), marker.global_position + Vector3.UP * size.y * 0.5)
	_fire_mats.append(mat)
	_fire_meshes.append(mi)


## "forge_fire" (AppState.DEFAULTS, 0..2): the flames, the embers' glow and (through
## _flicker_fire) the light. 0 hides the flames.
func _apply_fire() -> void:
	var amount := clampf(float(AppState.get_setting("forge_fire")), 0.0, 2.0)
	for m in _fire_mats:
		m.set_shader_parameter("amount", amount)
	for mi in _fire_meshes:
		mi.visible = amount > 0.005
	_scale_glow(FIRE_MATERIALS, amount)


## Called every frame: the fire light's energy from the Fire slider and the house light level,
## wavering a little (two slow sine waves, never a strobe; steady in photosensitive-safe mode).
func _flicker_fire() -> void:
	if _fire_light == null:
		return
	var amount := clampf(float(AppState.get_setting("forge_fire")), 0.0, 2.0)
	_fire_light.visible = amount > 0.005
	if not _fire_light.visible:
		return
	var waver := 1.0
	if fire_flicker > 0.0 and not bool(AppState.get_setting("photosensitive_safe")):
		waver += fire_flicker * (0.6 * sin(_time * 5.3) + 0.4 * sin(_time * 8.9 + 1.7))
	_fire_light.light_energy = fire_light_energy * amount * lerpf(fire_dimmed, 1.0, _level) * waver


# ── Time of day, sky and sunbeams ────────────────────────────
func _is_compatibility_renderer() -> bool:
	return RenderingServer.get_rendering_device() == null    # only the GL renderer has none


## The slanted windows' glass (material Sky_Glass in the model) becomes clear glass the sky
## shows through. It is one of the scene's glow_materials only so that Room hands us the copy
## that is actually on the meshes; its glow is switched off here.
func _setup_glass() -> void:
	for g in _glow:
		var m := g["mat"] as BaseMaterial3D
		if m.resource_name == "Sky_Glass":
			_glass_mat = m
			g["energy"] = 0.0
			g["base"] = 0.0
			m.emission_enabled = false
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.roughness = 0.05
			m.metallic = 0.0


## One reflection probe over the whole hall, so the polished granite mirrors the lights and
## inlays round it. Drawn once when the room loads (it does not follow the fire or the clock).
func _build_probe() -> void:
	var probe := ReflectionProbe.new()
	probe.name = "Reflections"
	probe.size = probe_size
	probe.interior = true                 # no sky in the reflections: this is indoors
	probe.box_projection = true
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.ambient_mode = ReflectionProbe.AMBIENT_DISABLED     # the ambient light stays the Environment's
	probe.intensity = probe_intensity
	probe.max_distance = probe_size.length()
	add_child(probe)
	probe.position = probe_center


## Called every frame. Moves the clock on while "forge_day_minutes" is above 0, and redraws
## the sky, the ambient light and the beams when the hour has moved by time_step, or when the
## app swapped the Environment (a graphics setting changed).
func _run_clock(delta: float) -> void:
	if _retired:
		return
	var day_minutes := float(AppState.get_setting("forge_day_minutes"))
	if day_minutes > 0.0:
		_hour = fposmod(_hour + delta * 24.0 / (day_minutes * 60.0), 24.0)
	var env := get_world_3d().environment if is_inside_tree() else null
	var env_id := env.get_instance_id() if env else 0
	if absf(_hour - _hour_drawn) >= time_step or env_id != _env_drawn:
		_hour_drawn = _hour
		_env_drawn = env_id
		_apply_time(env)


## The hour the room's clock shows now, 0..24 (for tests; "forge_time" only says where it started).
func get_hour() -> float:
	return _hour


## Everything that follows the hour (_hour, 0..24; 6 = sunrise, 12 = noon, 18 = sunset).
## The sun climbs from the left wall's side (the room's -X), passes high over the hall and
## sets on the right; the moon is opposite it. Sets the sky shader's uniforms, the ambient
## light and the window glass, then the beams: from the sun while it is up, from the moon at
## night, through the windows on the side the light comes from.
## env = the Environment in use; it is only touched when it is this room's own (its sky uses
## forge_sky.gdshader), never another room's.
func _apply_time(env: Environment) -> void:
	var a := (_hour - 6.0) / 12.0 * PI
	var sun := Vector3(-cos(a), sin(a) * 0.92, -sun_lean).normalized()      # pointing AT the sun
	var moon := Vector3(-sun.x, -sun.y * 0.9 + 0.08, sun_lean).normalized()
	var day := smoothstep(-0.12, 0.22, sun.y)
	var dusk := (1.0 - smoothstep(0.0, 0.4, absf(sun.y))) * smoothstep(-0.3, -0.05, sun.y)
	if env and env.sky and env.sky.sky_material is ShaderMaterial and (env.sky.sky_material as ShaderMaterial).shader == SKY_SHADER:
		var sky := env.sky.sky_material as ShaderMaterial
		var turn := global_basis.orthonormalized()                   # the sky shader works in world space
		sky.set_shader_parameter("sun_dir", turn * sun)
		sky.set_shader_parameter("moon_dir", turn * moon)
		sky.set_shader_parameter("day", day)
		sky.set_shader_parameter("dusk", dusk)
		sky.set_shader_parameter("exposure", sky_exposure)
		sky.set_shader_parameter("twinkle", 0.0 if bool(AppState.get_setting("photosensitive_safe")) else 1.0)
		env.ambient_light_color = night_ambient.lerp(day_ambient, day)
		env.ambient_light_energy = lerpf(night_ambient_energy, day_ambient_energy, day)
	if _glass_mat:
		_glass_mat.albedo_color = night_glass.lerp(day_glass, day)
	# the light through the windows
	var travel := Vector3.ZERO
	_beam_strength = 0.0
	if sun.y > 0.04:
		travel = -sun
		_beam_strength = smoothstep(0.04, 0.25, sun.y)
		_beam_color = Color(1.0, 0.5, 0.22).lerp(shaft_color, smoothstep(0.1, 0.5, sun.y))
	elif moon.y > 0.1:
		travel = -moon
		_beam_strength = moon_strength * smoothstep(0.1, 0.3, moon.y)
		_beam_color = moon_color
	# straight overhead no light gets in through the side windows
	_beam_strength *= clampf(absf(travel.x) * 2.2, 0.0, 1.0)
	_rebuild_beams(travel)
	_apply_sun_rays()


## Makes the (empty) beam and floor patch meshes and remembers every window pane the light can
## come through. The marker's X axis runs along the hall and its -Z axis up the slanted glass
## (see build_markers in the generator); _rebuild_beams() fills the meshes in.
func _build_sunbeams() -> void:
	var inv := global_transform.affine_inverse()
	for n in find_children("SHAFT_Sky*", "Node3D", true, false):
		var xf := inv * (n as Node3D).global_transform
		if String(n.name).begins_with("SHAFT_SkyR"):
			_panes_right.append(xf)
		else:
			_panes_left.append(xf)
	if _panes_left.is_empty() and _panes_right.is_empty():
		return
	var mat := ShaderMaterial.new()
	mat.shader = SHAFT_SHADER
	mat.set_shader_parameter("color", shaft_color)
	mat.set_shader_parameter("intensity", shaft_intensity)
	mat.set_shader_parameter("light_level", _level)
	mat.set_shader_parameter("dust_amount", 0.8)
	# the Compatibility renderer has no depth texture for spatial shaders in every version,
	# so the soft fade into geometry is only used on Forward+ / Mobile
	mat.set_shader_parameter("depth_fade", not _is_compatibility_renderer())
	var screen := find_screen()
	if screen:
		var box := screen.get_aabb()
		var sxf := screen.global_transform
		# the main screen's rectangle, so the shader keeps the beams from washing over the picture
		mat.set_shader_parameter("screen_c", sxf * box.get_center())
		mat.set_shader_parameter("screen_x", sxf.basis * Vector3(box.size.x * 0.5, 0.0, 0.0))
		mat.set_shader_parameter("screen_y", sxf.basis * Vector3(0.0, box.size.y * 0.5, 0.0))
	var mi := MeshInstance3D.new()
	mi.name = "Beams"
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fx.add_child(mi)
	_shafts = mi
	_shaft_mat = mat
	# the patches: the barred-window picture added onto the floor
	_patch_mat = StandardMaterial3D.new()
	_patch_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_patch_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_patch_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_patch_mat.albedo_texture = SUN_PATCH
	var pmi := MeshInstance3D.new()
	pmi.name = "Patches"
	pmi.material_override = _patch_mat
	pmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fx.add_child(pmi)
	_patches = pmi


## Builds the beams for light travelling along `travel` (the room's space; zero = none): one
## beam per pane on the side the light comes from: the pane's outline pushed along the light
## down to the floor (four side faces, UV.y 0 at the glass and 1 at the floor, as
## sun_shaft.gdshader expects), plus a flat patch of light where it lands. Only rebuilt when
## the direction has changed enough to see.
func _rebuild_beams(travel: Vector3) -> void:
	if _shafts == null:
		return
	var side := 0
	if travel.y < -0.02 and absf(travel.x) > 0.03 and _beam_strength > 0.0:
		side = -1 if travel.x > 0.0 else 1       # light travelling right came in on the left
	var dir := Vector3.ZERO
	if side != 0:
		# keep a low sun's beams on the floor: no flatter than beam_max_slant across per metre down
		dir = Vector3(travel.x, minf(travel.y, -absf(travel.x) / beam_max_slant), travel.z).normalized()
	if side == _beam_side and dir.distance_to(_beam_dir) < 0.004:
		return
	_beam_side = side
	_beam_dir = dir
	if side == 0:
		_shafts.mesh = null
		_patches.mesh = null
		return
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var pverts := PackedVector3Array()
	var puvs := PackedVector2Array()
	for xf: Transform3D in (_panes_left if side < 0 else _panes_right):
		var hx := xf.basis.x.normalized() * skylight_half.x
		var hy := -xf.basis.z.normalized() * skylight_half.y
		var c := xf.origin
		var rim: Array[Vector3] = [c - hx - hy, c + hx - hy, c + hx + hy, c - hx + hy]
		var land: Array[Vector3] = []
		for p in rim:
			land.append(p + dir * (p.y / -dir.y))      # where this corner's ray meets the floor (y = 0)
		for i in 4:
			var j := (i + 1) % 4
			var nrm := (rim[j] - rim[i]).cross(land[i] - rim[i]).normalized()
			var quad: Array[Vector3] = [rim[i], rim[j], land[j], rim[i], land[j], land[i]]
			var quv: Array[Vector2] = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 0), Vector2(1, 1), Vector2(0, 1)]
			for k in 6:
				verts.append(quad[k])
				norms.append(nrm)
				uvs.append(quv[k])
		# the patch: 2 cm above the floor so it never flickers against it
		var lift := Vector3.UP * 0.02
		var pq: Array[Vector3] = [land[0], land[1], land[2], land[0], land[2], land[3]]
		var pu: Array[Vector2] = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 0), Vector2(1, 1), Vector2(0, 1)]
		for k in 6:
			pverts.append(pq[k] + lift)
			puvs.append(pu[k])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_shafts.mesh = mesh
	var parrays := []
	parrays.resize(Mesh.ARRAY_MAX)
	parrays[Mesh.ARRAY_VERTEX] = pverts
	parrays[Mesh.ARRAY_TEX_UV] = puvs
	var pmesh := ArrayMesh.new()
	pmesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, parrays)
	_patches.mesh = pmesh


## "sun_rays" (AppState.DEFAULTS, 0..2) times shaft_intensity times what the sun or moon gives
## right now (_beam_strength, _beam_color from _apply_time); 0 hides the beams and patches.
func _apply_sun_rays() -> void:
	if _shafts == null:
		return
	var amount := clampf(float(AppState.get_setting("sun_rays")), 0.0, 2.0) * _beam_strength
	_shafts.visible = amount > 0.005 and _shafts.mesh != null
	_patches.visible = _shafts.visible
	_shaft_mat.set_shader_parameter("intensity", shaft_intensity * amount)
	_shaft_mat.set_shader_parameter("color", _beam_color)
	_apply_sun_patches()


## The floor patches' brightness: Light rays times patch_strength times the sun's or moon's
## strength times the house light level.
func _apply_sun_patches() -> void:
	if _patch_mat == null:
		return
	var amount := clampf(float(AppState.get_setting("sun_rays")), 0.0, 2.0) * _beam_strength
	var k := patch_strength * amount * _level
	_patch_mat.albedo_color = Color(_beam_color.r * k, _beam_color.g * k, _beam_color.b * k)


# ── Small live screens ───────────────────────────────────────
## Builds the three small screens at their markers (LIVE_SCREENS): a dark bezel with the
## picture on its front, facing the marker's +Z. The floor screen also gets a mast and sits on
## a body that _move_lift() slides up out of the floor; the marker is on the floor under it.
## The wall screens' markers are at the middle of the picture.
func _build_live_screens() -> void:
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.03, 0.032, 0.04)
	dark.metallic = 0.8
	dark.roughness = 0.4
	for i in LIVE_SCREENS.size():
		var marker := find_child(String(LIVE_SCREENS[i][0]), true, false) as Node3D
		if marker == null:
			continue
		var lift := bool(LIVE_SCREENS[i][1])
		var root := Node3D.new()
		root.name = "LiveScreen%d" % (i + 1)
		_fx.add_child(root)
		root.global_transform = Transform3D(marker.global_basis.orthonormalized(), marker.global_position)
		var home := root.transform                 # where the model puts it (_place_wall_screens moves it from here)
		var body := root
		var mid := Vector3.ZERO                    # the middle of the picture, in the body's space
		if lift:
			body = Node3D.new()
			body.name = "Body"
			root.add_child(body)
			mid = Vector3(0.0, lift_height + live_screen_size.y * 0.5, 0.0)
			var mast := MeshInstance3D.new()
			mast.name = "Mast"
			var mast_mesh := BoxMesh.new()
			mast_mesh.size = Vector3(0.34, lift_height + 0.2, 0.16)
			mast.mesh = mast_mesh
			mast.material_override = dark
			mast.position = Vector3(0.0, (lift_height + 0.2) * 0.5 - 0.1, -0.02)
			body.add_child(mast)
		var bezel := MeshInstance3D.new()
		bezel.name = "Bezel"
		var bezel_mesh := BoxMesh.new()
		bezel_mesh.size = Vector3(live_screen_size.x + 0.14, live_screen_size.y + 0.14, 0.08)
		bezel.mesh = bezel_mesh
		bezel.material_override = dark
		bezel.position = mid
		body.add_child(bezel)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var panel := MeshInstance3D.new()
		panel.name = "Picture"
		panel.mesh = QuadMesh.new()
		panel.material_override = mat
		panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		panel.position = mid + Vector3(0.0, 0.0, 0.045)
		body.add_child(panel)
		var a := {"n": i + 1, "lift": lift, "root": root, "body": body, "panel": panel, "mat": mat, "path": "", "pic": null, "home": home}
		_live.append(a)
		_load_live_picture(a)
	_move_lift(false)
	_place_wall_screens()
	_request_feeds()
	_refresh_live()


## Hangs the two wall screens where their sliders say, measured from the spot the model gives
## them (a["home"]): "forge_live_n_x" / "_y" metres right / up along the wall, "_size" (1.0 =
## as built), "_tilt" degrees (+ leans the top towards the seats) and "_turn" degrees (+ turns
## the face to the audience's right). With "forge_live_align" ticked the upper right screen
## (3) takes the upper left one's (2) numbers as a mirror image: same height, size and tilt,
## the opposite sideways move and turn. Called when the screens are built and whenever a
## forge_live_ setting changes. The screen's local axes: x = the audience's right, y = up,
## z = out of the wall towards the seats.
func _place_wall_screens() -> void:
	var align := bool(AppState.get_setting("forge_live_align"))
	for a in _live:
		if bool(a["lift"]):
			continue
		var n := int(a["n"])
		var mirror := align and n == 3
		var from := 2 if mirror else n
		var side := -1.0 if mirror else 1.0
		var get_f := func(part: String) -> float: return float(AppState.get_setting("forge_live_%d_%s" % [from, part]))
		var turn := Basis(Vector3.UP, deg_to_rad(side * float(get_f.call("turn"))))
		var tilt := Basis(Vector3.RIGHT, deg_to_rad(float(get_f.call("tilt"))))
		var size: float = clampf(float(get_f.call("size")), 0.2, 3.0)
		var move := Transform3D((turn * tilt).scaled(Vector3.ONE * size), Vector3(side * float(get_f.call("x")), float(get_f.call("y")), 0.0))
		(a["root"] as Node3D).transform = (a["home"] as Transform3D) * move


## "forge_lift_up": slides the floor screen up out of the floor or back down into it (the floor
## hides it once it is under). animate = false puts it straight where it belongs (room load).
func _move_lift(animate: bool) -> void:
	for a in _live:
		if not bool(a["lift"]):
			continue
		var body := a["body"] as Node3D
		var down := -(lift_height + live_screen_size.y + 0.3)
		var target := 0.0 if bool(AppState.get_setting("forge_lift_up")) else down
		if _lift_tween and _lift_tween.is_valid():
			_lift_tween.kill()
		if not animate:
			body.position.y = target
		else:
			_lift_tween = create_tween()
			_lift_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			_lift_tween.tween_property(body, "position:y", target, lift_seconds * absf(target - body.position.y) / absf(down))
	_claim_webcam()


## ScreenFeed's pictures (EventBus): remembered by source name, then shown where they belong.
func _on_webcam_texture(tex: Texture2D) -> void:
	_feed_tex["webcam"] = tex
	_refresh_live()


func _on_screen_texture(tex: Texture2D) -> void:
	_feed_tex["screen"] = tex
	_refresh_live()


func _on_presenter_texture(n: int, tex: Texture2D) -> void:
	_feed_tex["podium%d" % n] = tex
	_refresh_live()


## ExtraFeeds' picture for one of this room's slots ("forge_live_n"): a screen's own NDI
## source, Spout sender or stream address.
func _on_extra_texture(slot: String, tex: Texture2D) -> void:
	_feed_tex[slot] = tex
	_refresh_live()


## EventBus.room_changed (RoomHost finished loading a room, this one or its replacement).
## ExtraFeeds stops every feed that isn't asked for again shortly after a room change, so ask
## again a frame later (unless this room is the one that just left).
func _on_fh_room_changed(_room_id: String) -> void:
	if not _retired:
		_request_feeds.call_deferred()


## Asks ExtraFeeds (core/extra_feeds.gd, through EventBus.extra_feed_requested) for each small
## screen's own feed: slot "forge_live_n", kind = its source when that is ndi / spout / stream,
## address = "forge_live_n_address". Any other source stops the slot. Called when the screens
## are built, after a room change and whenever a forge_live_ setting changes.
func _request_feeds() -> void:
	if _retired or not is_inside_tree():
		return
	for a in _live:
		var n := int(a["n"])
		var src := String(AppState.get_setting("forge_live_%d_source" % n))
		var own := src in OWN_FEEDS
		EventBus.extra_feed_requested.emit("forge_live_%d" % n, src if own else "",
			String(AppState.get_setting("forge_live_%d_address" % n)) if own else "")


## Gives every small screen the picture its "forge_live_n_source" setting asks for ("off"
## hides the whole screen). A source with no picture yet shows a dark panel. The picture keeps
## its own shape inside live_screen_size.
func _refresh_live() -> void:
	for a in _live:
		var src := String(AppState.get_setting("forge_live_%d_source" % int(a["n"])))
		(a["root"] as Node3D).visible = src != "off"
		var tex: Texture2D = a["pic"] if src == "picture" else _feed_tex.get("forge_live_%d" % int(a["n"]) if src in OWN_FEEDS else src)
		var mat := a["mat"] as StandardMaterial3D
		mat.albedo_texture = tex
		mat.albedo_color = Color(1.0, 1.0, 1.0) if tex else Color(0.015, 0.02, 0.035)
		var size := live_screen_size
		if tex and tex.get_height() > 0:
			var shape := float(tex.get_width()) / float(tex.get_height())
			size = Vector2(minf(live_screen_size.x, live_screen_size.y * shape), 0.0)
			size.y = size.x / shape
		((a["panel"] as MeshInstance3D).mesh as QuadMesh).size = size
	_claim_webcam()


## While a small screen shows the webcam (the floor screen only counts when raised), the app is
## told the room has a webcam screen, so the corner webcam picture steps aside (it does that
## for rooms with a webcam frame, when "Show webcam in the room" is ticked). The overlay only
## looks again when a webcam picture is announced, so one is asked for when the answer changes.
func _claim_webcam() -> void:
	var showing := false
	for a in _live:
		var src := String(AppState.get_setting("forge_live_%d_source" % int(a["n"])))
		if src == "webcam" and (not bool(a["lift"]) or bool(AppState.get_setting("forge_lift_up"))):
			showing = true
	if showing == _webcam_claimed and AppState.room_has_webcam_frame() == showing:
		return
	_webcam_claimed = showing
	AppState.set_room_has_webcam_frame(showing)
	EventBus.feed_textures_requested.emit.call_deferred()


## Reads screen a's picture file ("forge_live_n_picture") off the main thread, like the alcove art.
func _load_live_picture(a: Dictionary) -> void:
	var n := int(a["n"])
	var path := String(AppState.get_setting("forge_live_%d_picture" % n)).strip_edges()
	if path == String(a["path"]):
		return
	a["path"] = path
	a["pic"] = null
	if path == "":
		return
	var bytes := PictureFile.read_file(path)
	if bytes.is_empty():
		@warning_ignore("integer_division")
		EventBus.status_message.emit("Small screen %d: couldn't read that picture (png, jpg, webp or gif, up to %d MB)." % [n, PictureFile.MAX_BYTES / (1024 * 1024)], true)
		return
	var out: Array = [null]
	var task := WorkerThreadPool.add_task(func() -> void: out[0] = PictureFile.texture_from_bytes(bytes), false, "small screen picture")
	_finish_live_picture.call_deferred(task, a, path, out)


## Main thread, after the decode: keep the picture unless another was asked for meanwhile.
func _finish_live_picture(task: int, a: Dictionary, path: String, out: Array) -> void:
	WorkerThreadPool.wait_for_task_completion(task)
	if not is_inside_tree() or path != String(a["path"]):
		return
	if out[0] == null:
		EventBus.status_message.emit("Small screen %d: that picture couldn't be decoded." % int(a["n"]), true)
		return
	a["pic"] = out[0]
	_refresh_live()


# ── Sound ────────────────────────────────────────────────────
## Called every frame: tops the generator buffer up with the fire: a soft low roar (filtered
## noise) with a crackle now and then (a short burst that dies away). Louder with a bigger fire.
func _fill_ambience() -> void:
	if _amb_playback == null:
		return
	var n := _amb_playback.get_frames_available()
	if n <= 0:
		return
	var amount := clampf(float(AppState.get_setting("forge_fire")), 0.0, 2.0)
	var buf := PackedVector2Array()
	buf.resize(n)
	for i in n:
		var w := _rng.randf() * 2.0 - 1.0
		_lp += (w - _lp) * 0.04
		if _rng.randf() < 0.00035 * amount:          # about eight crackles a second at 100%
			_pop = 0.4 + _rng.randf() * 0.6
		_pop *= 0.992
		var s := (_lp * 1.6 + w * _pop * 0.5) * fire_loudness * amount
		buf[i] = Vector2(s, s * 0.9)
	_amb_playback.push_buffer(buf)
