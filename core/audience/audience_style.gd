class_name AudienceStyle
extends RefCounted
## The look of the chat audience: how speech bubbles are drawn and which silhouette people
## sit as. The Style editor (ui/style_editor.gd) edits these; SpeechBubble, AudienceView and
## CrowdLayer read them. Static only, nothing to instance.
##
## Settings (AppState):
##   - audience_bubble_theme: "light" / "dark" use the built-in Light / Dark bubble presets,
##     "custom" uses the JSON in audience_bubble_style (what the Style editor saves).
##   - audience_silhouette: JSON of the silhouette style ("" = the classic bust).
##   - audience_saved_styles: JSON {"bubble": {name: style}, "silhouette": {name: style}},
##     the streamer's own presets.
##   - audience_style_groups: JSON {group: {"bubble": preset name, "silhouette": look name}}:
##     group looks (mods, VIPs, subs, each platform; GROUPS) on top of the main style.
## A style is a Dictionary of JSON-friendly values (colours are "rrggbbaa" strings); missing keys
## take the defaults below, so older or hand-written styles still work.

## Every bubble style key, with the Light look's value (the bubbles as they were before the editor).
## Sizes are bubble pixels (AudienceView turns pixels into metres).
const BUBBLE_DEFAULTS: Dictionary = {
	"shape": -1,              # -1 = each chatter's own (from their name), else one of BUBBLE_SHAPES
	"fill": "fffffff7",       # body colour (alpha = how see-through)
	"fill_mix": 0.07,         # share of the chatter's colour mixed into the fill (0..1)
	"text": "141419ff",       # message text colour
	"name_mode": "chatter",   # name colour: "chatter" (their colour, darker/lighter to read on the fill) | "fixed"
	"name_color": "202020ff", # name colour when name_mode is "fixed"
	"outline": 5.0,           # outline width (0 = none)
	"outline_mode": "chatter",  # outline colour: "chatter" | "fixed"
	"outline_color": "000000ff",
	"text_size": 30,          # message text size; the name is 80% of it, emotes grow with it
	"bold": false,            # thicker letters
	"roundness": 26.0,        # corner radius of the box shapes
	"tail": "left",           # where the tail sits under the bubble: left | middle | right | none
	"width": 380,             # widest the text gets before it wraps
	"paid": "ffedadf7",       # Super Chats / Kicks / Bits fill (with "Colour paid and highlighted messages")
	"highlighted": "dbccfff7",  # Twitch highlighted messages fill
}
## Bubble shapes: number -> panel label. SpeechBubble._shape_points draws each; AudienceManager's
## BUBBLE_STYLES (the "each chatter's own" pick) only covers 0..3 so existing chatters keep theirs.
const BUBBLE_SHAPES: Dictionary = {0: "Rounded box", 1: "Oval", 2: "Slanted box", 3: "Pinched box", 4: "Cloud"}
const TAIL_SPOTS: Dictionary = {"left": 0.2, "middle": 0.5, "right": 0.8}

## Built-in bubble presets (only the keys that differ from BUBBLE_DEFAULTS). Light and Dark are
## what the Audience tab's "Bubble colours" picks; keep their fills in sync with SpeechBubble.TINT_FILLS.
const BUBBLE_PRESETS: Dictionary = {
	# (Light and Dark as exact colours, the same values the bubbles had before the editor)
	"Light": {"fill": Color(1, 1, 1, 0.97), "text": Color(0.08, 0.08, 0.1),
		"paid": Color(1.0, 0.93, 0.68, 0.97), "highlighted": Color(0.86, 0.8, 1.0, 0.97)},
	"Dark": {"fill": Color(0.1, 0.1, 0.12, 0.95), "text": Color(0.93, 0.93, 0.95),
		"paid": Color(0.42, 0.32, 0.05, 0.96), "highlighted": Color(0.4, 0.31, 0.68, 0.96)},
	"Comic": {"outline": 8.0, "outline_mode": "fixed", "outline_color": "111111ff", "bold": true,
		"fill_mix": 0.0, "fill": "ffffffff", "text_size": 32},
	"Neon": {"fill": "0b0b14e6", "fill_mix": 0.12, "text": "f4f4ffff", "outline": 4.0, "bold": true,
		"paid": "4d3a00eb", "highlighted": "3a1f70eb", "roundness": 40.0},
	"Glass": {"fill": "1e2230a0", "fill_mix": 0.2, "text": "ffffffff", "outline": 2.0, "tail": "middle",
		"paid": "6b5410b4", "highlighted": "4c3a8cb4"},
	"Paper": {"shape": 0, "fill": "f6eed8fa", "fill_mix": 0.0, "text": "3b2a1aff", "outline": 3.0,
		"outline_mode": "fixed", "outline_color": "6b4f2eff", "roundness": 6.0, "name_mode": "fixed",
		"name_color": "7a3b12ff"},
	"Minimal": {"shape": 0, "fill": "ffffffe6", "fill_mix": 0.0, "outline": 0.0, "tail": "middle",
		"roundness": 16.0, "text_size": 28},
	"Thought cloud": {"shape": 4, "fill_mix": 0.04, "outline": 4.0},
}

## Every silhouette style key, with the classic look's value.
const FIGURE_DEFAULTS: Dictionary = {
	"shape": "classic",       # one of FIGURE_SHAPES, or "custom" (a picture from the streamer's PC)
	"file": "",               # custom: the imported picture in user://silhouettes/ (see import_picture)
	"paint": "chatter",       # "chatter": dark body, rim in the chatter's colour | "fixed": the same in "color"
	                          # | "picture": a custom picture's own colours
	"color": "8fa3c8ff",      # body colour when paint is "fixed"
	"brightness": 1.0,        # multiplies the colour (0.4..1.6)
	"size": 1.0,              # multiplies the bust height (0.7..1.4)
	"head_x": 0.5,            # custom: where the chatter's picture sits, as a share of the width...
	"head_y": 0.3,            # ...and of the height (centre)...
	"head_r": 0.2,            # ...and its radius as a share of the width
	"crowd": true,            # the filler crowd uses the same shape (and size)
}
## Built-in silhouettes: id -> panel label. All are 256 x 320 pixels like silhouette.png: a dark
## body (40/255 grey) with a white rim, so the sprite's colour tints the body a little and the rim fully.
const FIGURE_SHAPES: Dictionary = {"classic": "Classic", "round": "Big head", "broad": "Broad shoulders",
	"hood": "Hoodie", "ears": "Cat ears", "bun": "Hair bun", "bot": "Robot"}
## Where each built-in shape's head is (pixels): x, y and the radius inside the rim, for the chatter's picture.
const FIGURE_HEADS: Dictionary = {"classic": Vector3(128, 94, 56), "round": Vector3(128, 100, 70),
	"broad": Vector3(128, 96, 46), "hood": Vector3(128, 116, 46), "ears": Vector3(128, 108, 52),
	"bun": Vector3(128, 108, 50), "bot": Vector3(128, 104, 46)}
const FIGURE_W: int = 256
const FIGURE_H: int = 320
## Rim width (pixels) of drawn and imported silhouettes, like silhouette.png's.
const RIM_PX: float = 5.0
## Body grey of drawn and imported silhouettes (silhouette.png's 40/255).
const BODY_GREY: float = 40.0 / 255.0
const CLASSIC_TEX: Texture2D = preload("res://core/audience/silhouette.png")
## Where imported pictures are kept (one normalised copy plus its silhouette version each).
const PICTURE_DIR: String = "user://silhouettes/"

## Groups that can have their own look, in the order they win: a mod who is also a sub gets the
## mods' look (for each of bubble / silhouette, the first of their groups that has one set).
## Roles come from AudienceManager.roles_of, platforms from AudienceManager.platform_group.
## "all" matches everyone, so it is the last stop before the main style.
const GROUPS: Dictionary = {"mod": "Mods", "vip": "VIPs", "sub": "Subscribers", "kick": "Kick",
	"twitch": "Twitch", "youtube": "YouTube", "other": "Other chat", "all": "Everyone else"}
## Separates the looks of a random mix in a group's silhouette value ("ears|bot|My cat").
## Saved look names can't contain it (save_preset takes it out).
const MIX_SEP: String = "|"

# Caches: the merged style for the raw setting text it came from, and textures by id.
static var _bubble_key: String = "(none yet)"
static var _bubble: Dictionary = {}
static var _figure_key: String = "(none yet)"
static var _figure: Dictionary = {}
static var _textures: Dictionary = {}
## Group looks by "kind|name", valid while the settings they're made from stay the same (_group_stamp).
static var _group_cache: Dictionary = {}
static var _group_stamp: String = "(none yet)"


# ── Bubbles ─────────────────────────────────────────────────
## The bubble style in use now (a merged copy; don't change it). Called by SpeechBubble for every
## bubble it lays out, so it's cached until audience_bubble_theme / audience_bubble_style change.
static func bubble() -> Dictionary:
	var theme := String(AppState.get_setting("audience_bubble_theme"))
	var raw := String(AppState.get_setting("audience_bubble_style")) if theme == "custom" else ""
	var key := theme + "|" + raw
	if key != _bubble_key:
		_bubble_key = key
		match theme:
			"custom":
				_bubble = merge_bubble(_parse(raw))
			"dark":
				_bubble = merge_bubble(BUBBLE_PRESETS["Dark"])
			_:
				_bubble = merge_bubble(BUBBLE_PRESETS["Light"])
	return _bubble


## A complete bubble style: BUBBLE_DEFAULTS with the given keys on top (values checked and clamped,
## since a style can come from a hand-edited settings file). Colours may be "rrggbbaa" text or,
## in the built-in presets, Color values; color_of() reads both.
static func merge_bubble(over: Dictionary) -> Dictionary:
	var s := BUBBLE_DEFAULTS.duplicate()
	for k: String in over.keys():
		if s.has(k) and typeof(over[k]) in [TYPE_STRING, TYPE_FLOAT, TYPE_INT, TYPE_BOOL, TYPE_COLOR]:
			s[k] = over[k]
	s["shape"] = clampi(int(s["shape"]), -1, BUBBLE_SHAPES.size() - 1)
	s["fill_mix"] = clampf(float(s["fill_mix"]), 0.0, 1.0)
	s["outline"] = clampf(float(s["outline"]), 0.0, 16.0)
	s["text_size"] = clampi(int(s["text_size"]), 16, 56)
	s["roundness"] = clampf(float(s["roundness"]), 0.0, 60.0)
	s["width"] = clampi(int(s["width"]), 200, 640)
	s["bold"] = bool(s["bold"])
	if not TAIL_SPOTS.has(String(s["tail"])) and String(s["tail"]) != "none":
		s["tail"] = "left"
	return s


## The bubble preset names the Style editor lists: built-in ones, then the streamer's own.
static func bubble_preset_names() -> PackedStringArray:
	var out := PackedStringArray(BUBBLE_PRESETS.keys())
	for n: String in saved("bubble").keys():
		if not out.has(n):
			out.append(n)
	return out


## A preset by name as a full style (built-in or saved; {} if there is none by that name).
static func bubble_preset(preset_name: String) -> Dictionary:
	var own := saved("bubble")
	if own.has(preset_name) and own[preset_name] is Dictionary:
		return merge_bubble(own[preset_name])
	if BUBBLE_PRESETS.has(preset_name):
		return merge_bubble(BUBBLE_PRESETS[preset_name])
	return {}


# ── Silhouettes ─────────────────────────────────────────────
## The silhouette style in use now (a merged copy; don't change it). Cached until
## audience_silhouette changes.
static func figure() -> Dictionary:
	var raw := String(AppState.get_setting("audience_silhouette"))
	if raw != _figure_key:
		_figure_key = raw
		_figure = merge_figure(_parse(raw))
	return _figure


## A complete silhouette style: FIGURE_DEFAULTS with the given keys on top, checked and clamped.
static func merge_figure(over: Dictionary) -> Dictionary:
	var s := FIGURE_DEFAULTS.duplicate()
	for k: String in over.keys():
		if s.has(k) and typeof(over[k]) in [TYPE_STRING, TYPE_FLOAT, TYPE_INT, TYPE_BOOL]:
			s[k] = over[k]
	var shape := String(s["shape"])
	if shape != "custom" and not FIGURE_SHAPES.has(shape):
		s["shape"] = "classic"
	if shape == "custom" and not String(s["file"]).begins_with(PICTURE_DIR):
		s["shape"] = "classic"       # only pictures this app imported (never any path on the PC)
	if not String(s["paint"]) in ["chatter", "fixed", "picture"]:
		s["paint"] = "chatter"
	s["brightness"] = clampf(float(s["brightness"]), 0.4, 1.6)
	s["size"] = clampf(float(s["size"]), 0.7, 1.4)
	s["head_x"] = clampf(float(s["head_x"]), 0.0, 1.0)
	s["head_y"] = clampf(float(s["head_y"]), 0.0, 1.0)
	s["head_r"] = clampf(float(s["head_r"]), 0.05, 0.5)
	s["crowd"] = bool(s["crowd"])
	return s


## The silhouette picture for a style. A custom picture that can't be read falls back to classic.
## Built-in shapes are drawn once (about a tenth of a second each) and kept.
static func figure_texture(f: Dictionary) -> Texture2D:
	var shape := String(f.get("shape", "classic"))
	if shape == "classic":
		return CLASSIC_TEX
	var id := shape
	if shape == "custom":
		# "picture" paint shows the picture itself; otherwise its silhouette version (dark body, white rim)
		id = String(f["file"]) if String(f.get("paint", "")) == "picture" else String(f["file"]).replace(".png", "_shape.png")
	if _textures.has(id):
		return _textures[id]
	var tex: Texture2D = null
	if shape == "custom":
		var img := Image.load_from_file(id)
		if img != null and not img.is_empty():
			tex = ImageTexture.create_from_image(img)
	else:
		tex = ImageTexture.create_from_image(_draw_shape(shape))
	if tex == null:
		return CLASSIC_TEX
	_textures[id] = tex
	return tex


## Where the chatter's picture goes on the silhouette: Vector3(x, y, radius) in texture pixels.
static func figure_head(f: Dictionary) -> Vector3:
	var shape := String(f.get("shape", "classic"))
	if shape == "custom":
		return Vector3(float(f["head_x"]) * FIGURE_W, float(f["head_y"]) * FIGURE_H, float(f["head_r"]) * FIGURE_W)
	return FIGURE_HEADS.get(shape, FIGURE_HEADS["classic"])


## The colour a seated chatter's silhouette is painted (AudienceView's sprite modulate).
## chatter: the chatter's colour; the speaking boost and seat fades are applied on top by the view.
static func figure_tint(chatter: Color, f: Dictionary) -> Color:
	var b := float(f.get("brightness", 1.0))
	var c := chatter
	match String(f.get("paint", "chatter")):
		"fixed":
			c = _color(f, "color")
		"picture":
			c = Color.WHITE
	return Color(c.r * b, c.g * b, c.b * b, c.a)


## The silhouette preset names: built-in shapes are not presets (they're picked by shape), so this
## is only the streamer's own saved ones.
static func figure_preset_names() -> PackedStringArray:
	return PackedStringArray(saved("silhouette").keys())


## Imports a picture from the PC as a custom silhouette. It's cut to its visible part, fitted into
## 256 x 320 standing on the bottom edge, and saved twice in user://silhouettes/: as it is, and as a
## silhouette (dark body + white rim, so it takes the chatter's colour like the built-in ones).
## A picture without any see-through pixels is read as dark shape on a light background.
## Returns the saved path to put in the style's "file", or "" when it couldn't be read.
## Called by the Style editor's "Use my own picture..." file dialog. Takes about a second.
static func import_picture(path: String) -> String:
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		return ""
	img.convert(Image.FORMAT_RGBA8)
	if img.get_width() > 1024 or img.get_height() > 1024:
		var k := 1024.0 / maxf(img.get_width(), img.get_height())
		img.resize(maxi(1, int(img.get_width() * k)), maxi(1, int(img.get_height() * k)), Image.INTERPOLATE_BILINEAR)
	if not img.detect_alpha():
		_alpha_from_dark(img)
	var used := img.get_used_rect()
	if used.size.x < 4 or used.size.y < 4:
		return ""
	var part := img.get_region(used)
	var k := minf(float(FIGURE_W) / used.size.x, float(FIGURE_H) / used.size.y)
	part.resize(maxi(1, int(used.size.x * k)), maxi(1, int(used.size.y * k)), Image.INTERPOLATE_LANCZOS)
	var out := Image.create_empty(FIGURE_W, FIGURE_H, false, Image.FORMAT_RGBA8)
	out.blit_rect(part, Rect2i(Vector2i.ZERO, part.get_size()),
		Vector2i((FIGURE_W - part.get_width()) / 2, FIGURE_H - part.get_height()))
	DirAccess.make_dir_recursive_absolute(PICTURE_DIR)
	var base := path.get_file().get_basename().to_lower().validate_filename().replace(" ", "_").left(40)
	var dest := PICTURE_DIR + (base if base != "" else "picture") + ".png"
	if out.save_png(dest) != OK or _outline_version(out).save_png(dest.replace(".png", "_shape.png")) != OK:
		return ""
	_textures.erase(dest)
	_textures.erase(dest.replace(".png", "_shape.png"))
	return dest


## Where an imported picture's head probably is: the middle of its top part. The Style editor
## sets head_x / head_y / head_r from this right after an import; the streamer can move it.
static func guess_head(file: String) -> Vector3:
	var img := Image.load_from_file(file)
	if img == null or img.is_empty():
		return Vector3(0.5, 0.3, 0.2)
	var top := img.get_used_rect().position.y
	var r := 0.19 * FIGURE_W
	return Vector3(0.5, (top + r * 1.15) / FIGURE_H, 0.19)


# ── Group looks ─────────────────────────────────────────────
## The group looks setting: group -> {"bubble": name, "silhouette": name} (blank / missing = main style).
static func group_looks() -> Dictionary:
	return _parse(String(AppState.get_setting("audience_style_groups")))


## Sets one group's look of one kind ("bubble" / "silhouette"); "" = back to the main style.
## Called by the Style editor's Groups tab.
static func set_group_look(group: String, kind: String, look: String) -> void:
	var all := group_looks()
	var g: Dictionary = all.get(group, {}) if all.get(group) is Dictionary else {}
	if look == "":
		g.erase(kind)
	else:
		g[kind] = look
	if g.is_empty():
		all.erase(group)
	else:
		all[group] = g
	AppState.set_setting("audience_style_groups", JSON.stringify(all))


## The look name a seated chatter gets for one kind, or "" for the main style. member: as
## AudienceManager.get_seat_member gives it (its "roles" and "platform").
static func group_look(member: Dictionary, kind: String) -> String:
	var all := group_looks()
	if all.is_empty():
		return ""
	var roles := String(member.get("roles", "")).split(",", false)
	var platform := String(member.get("platform", "other"))
	for g: String in GROUPS.keys():
		if not (roles.has(g) or g == platform or g == "all"):
			continue
		var looks: Variant = all.get(g)
		if looks is Dictionary and String((looks as Dictionary).get(kind, "")) != "":
			return String(looks[kind])
	return ""


## A seated chatter's bubble style when their group has one, else {} (= the main style, so the
## bubble follows Light / Dark / custom as usual). AudienceView sets it as the bubble's style_override.
static func bubble_for(member: Dictionary) -> Dictionary:
	var look := group_look(member, "bubble")
	if look == "":
		return {}
	return _cached("bubble|" + look, func() -> Dictionary: return bubble_preset(look))


## A seated chatter's silhouette style: their group's saved look, a built-in shape (the main style
## with that shape), or the main style. A random mix (looks joined by MIX_SEP) gives each chatter
## one of its looks, picked from their name so they keep it every time they chat.
static func figure_for(member: Dictionary) -> Dictionary:
	var look := group_look(member, "silhouette")
	if look == "":
		return figure()
	if look.contains(MIX_SEP):
		var mix := look.split(MIX_SEP, false)
		if mix.is_empty():
			return figure()
		look = mix[absi(hash(String(member.get("name", "")).to_lower())) % mix.size()]
	return _cached("silhouette|" + look, func() -> Dictionary:
		var own := saved("silhouette")
		if own.get(look) is Dictionary:
			return merge_figure(own[look])
		if FIGURE_SHAPES.has(look):
			var f := figure().duplicate()
			f["shape"] = look
			return f
		return figure())


## The silhouette choices for a group: built-in shapes (by id) and saved looks (by name).
static func figure_look_names() -> PackedStringArray:
	var out := PackedStringArray(FIGURE_SHAPES.keys())
	out.append_array(figure_preset_names())
	return out


static func _cached(key: String, make: Callable) -> Dictionary:
	var stamp := "%s|%s|%s|%s|%s" % [AppState.get_setting("audience_style_groups"), AppState.get_setting("audience_saved_styles"),
		AppState.get_setting("audience_silhouette"), AppState.get_setting("audience_bubble_theme"), AppState.get_setting("audience_bubble_style")]
	if stamp != _group_stamp:
		_group_stamp = stamp
		_group_cache.clear()
	if not _group_cache.has(key):
		_group_cache[key] = make.call()
	return _group_cache[key]


# ── Saved presets ───────────────────────────────────────────
## The streamer's own presets of one kind ("bubble" or "silhouette"): name -> style.
static func saved(kind: String) -> Dictionary:
	var all := _parse(String(AppState.get_setting("audience_saved_styles")))
	return all.get(kind, {}) if all.get(kind) is Dictionary else {}


## Saves (or with style = {} deletes) one of the streamer's own presets.
static func save_preset(kind: String, preset_name: String, style: Dictionary) -> void:
	preset_name = preset_name.replace(MIX_SEP, " ").strip_edges()
	var all := _parse(String(AppState.get_setting("audience_saved_styles")))
	var mine: Dictionary = all.get(kind, {}) if all.get(kind) is Dictionary else {}
	if style.is_empty():
		mine.erase(preset_name)
	else:
		mine[preset_name] = style
	all[kind] = mine
	AppState.set_setting("audience_saved_styles", JSON.stringify(all))


# ── Helpers ─────────────────────────────────────────────────
## A colour value from a style ("rrggbbaa" text or a Color); black when it isn't a colour.
static func color_of(style: Dictionary, key: String) -> Color:
	return _color(style, key)


static func _color(style: Dictionary, key: String) -> Color:
	if style.get(key) is Color:
		return style[key]
	var t := String(style.get(key, ""))
	return Color.html(t) if Color.html_is_valid(t) else Color.BLACK


## JSON text -> Dictionary ({} for blank or broken text).
static func _parse(raw: String) -> Dictionary:
	if raw.strip_edges() == "":
		return {}
	var v: Variant = JSON.parse_string(raw)
	return v if v is Dictionary else {}


## A picture with no see-through pixels: dark pixels become the shape, light ones the background.
static func _alpha_from_dark(img: Image) -> void:
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			c.a = clampf((0.75 - c.get_luminance()) * 4.0, 0.0, 1.0)
			img.set_pixel(x, y, c)


## The silhouette version of an imported picture: same outline, dark body, white rim RIM_PX wide
## inside the edge (found by shrinking the shape: a pixel is rim if a see-through pixel is near).
static func _outline_version(src: Image) -> Image:
	var w := src.get_width()
	var h := src.get_height()
	var r := int(RIM_PX)
	var solid := PackedByteArray()
	solid.resize(w * h)
	for y in h:
		for x in w:
			solid[y * w + x] = 1 if src.get_pixel(x, y).a > 0.5 else 0
	# shrink across, then down (a square window): inner = solid with no gap within r pixels
	var across := PackedByteArray()
	across.resize(w * h)
	for y in h:
		for x in w:
			var ok := 1
			for dx in range(-r, r + 1):
				var xx := x + dx
				if xx < 0 or xx >= w or solid[y * w + xx] == 0:
					ok = 0
					break
			across[y * w + x] = ok
	var out := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var a := src.get_pixel(x, y).a
			if a <= 0.0:
				continue
			var inner := true
			for dy in range(-r, r + 1):
				var yy := y + dy
				if yy < 0 or yy >= h or across[yy * w + x] == 0:
					inner = false
					break
			var g := BODY_GREY if inner else 1.0
			out.set_pixel(x, y, Color(g, g, g, a))
	return out


## Draws a built-in silhouette (FIGURE_SHAPES) from simple shapes. Each layer is filled dark with
## a white rim, later layers on top; edges are smoothed over one pixel.
static func _draw_shape(shape: String) -> Image:
	var data := PackedByteArray()
	data.resize(FIGURE_W * FIGURE_H * 4)
	data.fill(0)
	for y in FIGURE_H:
		for x in FIGURE_W:
			var p := Vector2(x + 0.5, y + 0.5)
			var col := 0.0
			var alpha := 0.0
			var ds := _layers(shape, p)
			for l in ds.size():
				var d: float = ds[l]
				if d > 1.0:
					continue
				if d > -RIM_PX - 2.0:
					# near the edge: divide by the slope so the rim is the same width everywhere
					# (joined and stretched shapes give distances that are off by up to half)
					var gx: float = _layers(shape, p + Vector2(1, 0))[l] - d
					var gy: float = _layers(shape, p + Vector2(0, 1))[l] - d
					d /= clampf(Vector2(gx, gy).length(), 0.3, 3.0)
				var a := clampf(0.5 - d, 0.0, 1.0)
				if a <= 0.0:
					continue
				var rim := clampf(d + RIM_PX + 0.5, 0.0, 1.0)     # 1 within RIM_PX of the edge
				var g := lerpf(BODY_GREY, 1.0, rim)
				col = lerpf(col, g, a) if alpha > 0.0 else g
				alpha = maxf(alpha, a)
			if alpha > 0.0:
				var i := (y * FIGURE_W + x) * 4
				var v := int(round(col * 255.0))
				data[i] = v
				data[i + 1] = v
				data[i + 2] = v
				data[i + 3] = int(round(alpha * 255.0))
	return Image.create_from_data(FIGURE_W, FIGURE_H, false, Image.FORMAT_RGBA8, data)


## Signed distances (pixels; negative inside) of one built-in shape's layers at p, bottom layer first.
## Shoulders sit low enough to leave a neck gap under the head, like the classic bust.
static func _layers(shape: String, p: Vector2) -> Array[float]:
	var shoulders := _ellipse(p, Vector2(128, 352), Vector2(122, 160))
	match shape:
		"round":     # a big round head on narrow shoulders
			return [_ellipse(p, Vector2(128, 362), Vector2(100, 150)), _circle(p, Vector2(128, 100), 76.0)]
		"broad":     # small head, wide square-ish shoulders
			return [_round_box(p, Vector2(128, 300), Vector2(128, 110), 70.0), _circle(p, Vector2(128, 96), 52.0)]
		"hood":      # a hood joined to the shoulders, the face inside it
			var hood := _smooth_union(_ellipse(p, Vector2(128, 112), Vector2(82, 94)), shoulders, 22.0)
			return [hood, _circle(p, Vector2(128, 118), 52.0)]
		"ears":      # pointed ears on top of the head
			var head := _circle(p, Vector2(128, 110), 58.0)
			var left := _polygon(p, [Vector2(76, 92), Vector2(78, 26), Vector2(124, 58)])
			var right := _polygon(p, [Vector2(180, 92), Vector2(178, 26), Vector2(132, 58)])
			return [shoulders, _smooth_union(head, minf(left, right), 10.0)]
		"bun":       # a round bun on top of the head
			return [shoulders, _smooth_union(_circle(p, Vector2(128, 110), 56.0), _circle(p, Vector2(128, 42), 28.0), 18.0)]
		"bot":       # boxy head with an antenna, square shoulders
			var head := _round_box(p, Vector2(128, 104), Vector2(62, 56), 14.0)
			var stick := _round_box(p, Vector2(128, 36), Vector2(4, 16), 2.0)
			var ball := _circle(p, Vector2(128, 18), 12.0)
			return [_round_box(p, Vector2(128, 292), Vector2(112, 96), 30.0), minf(head, minf(stick, ball))]
	return [shoulders, _circle(p, Vector2(128, 94), 61.0)]


## Joins two shapes with a rounded fillet k pixels wide where they meet (a plain minf leaves a sharp notch).
static func _smooth_union(a: float, b: float, k: float) -> float:
	var h := clampf(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
	return lerpf(b, a, h) - k * h * (1.0 - h)


static func _circle(p: Vector2, c: Vector2, r: float) -> float:
	return p.distance_to(c) - r


## Close enough to a true distance near the edge, which is all the smoothing and rim need.
static func _ellipse(p: Vector2, c: Vector2, r: Vector2) -> float:
	var q := (p - c) / r
	return (q.length() - 1.0) * minf(r.x, r.y)


static func _round_box(p: Vector2, c: Vector2, half: Vector2, rad: float) -> float:
	var q := (p - c).abs() - half + Vector2(rad, rad)
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - rad


## Distance to a closed polygon (any winding).
static func _polygon(p: Vector2, v: Array[Vector2]) -> float:
	var d := (p - v[0]).length_squared()
	var s := 1.0
	var j := v.size() - 1
	for i in v.size():
		var e := v[j] - v[i]
		var w := p - v[i]
		var b := w - e * clampf(w.dot(e) / e.length_squared(), 0.0, 1.0)
		d = minf(d, b.length_squared())
		var c1 := p.y >= v[i].y
		var c2 := p.y < v[j].y
		var c3 := e.x * w.y > e.y * w.x
		if (c1 and c2 and c3) or (not c1 and not c2 and not c3):
			s = -s
		j = i
	return s * sqrt(d)
