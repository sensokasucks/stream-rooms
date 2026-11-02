class_name SpeechBubble
extends Control
## A comic speech bubble drawn in 2D (rendered into a SubViewport by AudienceView).
## Its look comes from AudienceStyle.bubble() (Light / Dark / the custom style from Stream Core's
## Audience looks page; that page's preview copies the drawing below, so keep them alike):
## fill, text and name colours, outline in the speaker's colour (or a fixed one), the speaker's
## name on top, a tail. A Super Chat / Bits message is gold, a Twitch highlighted one purple.
## Shapes: 0 rounded box, 1 oval, 2 slanted box, 3 pinched box, 4 cloud (AudienceStyle.BUBBLE_SHAPES).
## The text is a RichTextLabel so chat emotes sit inline and wrap with the words;
## emoji use the system's colour emoji font.

# Sizes below are in bubble pixels (AudienceView turns pixels into metres with bubble_pixel_size).
# The text width, outline, text size and colours come from the bubble style; these are the rest.
## Space between the text and the edge of the body.
const PAD: float = 20.0
## How far the tail reaches below the body.
const TAIL_H: float = 30.0
## Sizes at the style's default text size (30); they grow and shrink with it.
const TEXT_SIZE: int = 30
const NAME_SIZE: int = 24
## Emote height inline with text, and when the message is only emotes.
const EMOTE_SIZE: int = 38
const EMOTE_ONLY_SIZE: int = 72
## Twitch "Gigantify an Emote": the message's last emote.
const EMOTE_GIANT_SIZE: int = 112
## The Light / Dark looks' colours (AudienceStyle.BUBBLE_PRESETS has the same values; kept here
## for the tests and anything that wants the plain colours).
const FILL: Color = Color(1, 1, 1, 0.97)
const TEXT_COLOR: Color = Color(0.08, 0.08, 0.1)
const DARK_FILL: Color = Color(0.1, 0.1, 0.12, 0.95)
const DARK_TEXT: Color = Color(0.93, 0.93, 0.95)
## Fills for messages that stand out, [light theme, dark theme]. Keep in sync with the Light and
## Dark presets' "paid" / "highlighted" in AudienceStyle.BUBBLE_PRESETS.
const TINT_FILLS: Dictionary = {
	"paid": [Color(1.0, 0.93, 0.68, 0.97), Color(0.42, 0.32, 0.05, 0.96)],
	"highlighted": [Color(0.86, 0.8, 1.0, 0.97), Color(0.4, 0.31, 0.68, 0.96)],
}
## Colour emoji fonts tried in order (Windows, macOS, Linux...), as the fallback of shared_font().
const EMOJI_FONTS: PackedStringArray = ["Segoe UI Emoji", "Apple Color Emoji", "Noto Color Emoji", "Twemoji Mozilla"]

## Cache for shared_font() and its bold version.
static var _font: Font
static var _bold_font: Font

## A style to draw with instead of the one in use ({} = AudienceStyle.bubble()). AudienceView sets
## a chatter's group look here (AudienceStyle.bubble_for). Must be a full style (AudienceStyle.merge_bubble).
var style_override: Dictionary = {}

var _color: Color = Color.WHITE
var _style: int = 0
var _fill: Color = FILL
var _outline_color: Color = Color.WHITE
var _outline: float = 5.0
var _roundness: float = 26.0
## Tail position along the bottom (0..1), or -1 for no tail.
var _tail_at: float = 0.2
## The bubble body and tail tip, in pixels, worked out by set_content() and drawn by _draw().
var _body: Rect2 = Rect2()
var _tail_tip: Vector2 = Vector2.ZERO
var _rtl: RichTextLabel


func _init() -> void:
	_rtl = RichTextLabel.new()
	_rtl.bbcode_enabled = false
	_rtl.fit_content = true
	_rtl.scroll_active = false
	_rtl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rtl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rtl.add_theme_font_override("normal_font", shared_font())
	_rtl.add_theme_font_size_override("normal_font_size", TEXT_SIZE)
	_rtl.add_theme_color_override("default_color", TEXT_COLOR)
	add_child(_rtl)


## Sets the content and resizes itself. parts: Strings and {"url", "name"} emotes.
## textures: url -> Texture2D for the emotes that are loaded (others show their name).
## style: the chatter's own shape (AudienceManager), used when the bubble style says "each chatter's own".
## Returns the pixel size the viewport needs.
func set_content(speaker: String, parts: Array, color: Color, style: int, textures: Dictionary) -> Vector2i:
	var st: Dictionary = style_override if not style_override.is_empty() else AudienceStyle.bubble()
	_color = color
	var fixed_shape := int(st["shape"])
	_style = clampi(style if fixed_shape < 0 else fixed_shape, 0, AudienceStyle.BUBBLE_SHAPES.size() - 1)
	_outline = float(st["outline"])
	_outline_color = color if String(st["outline_mode"]) == "chatter" else AudienceStyle.color_of(st, "outline_color")
	_roundness = float(st["roundness"])
	_tail_at = float(AudienceStyle.TAIL_SPOTS.get(String(st["tail"]), -1.0))
	var scale_text := float(st["text_size"]) / float(TEXT_SIZE)
	var max_w := float(st["width"])
	# leading marker parts: {tint} how it stands out, {reply_to, quote} who it answers
	var reply_to := ""
	var reply_quote := ""
	var tint := ""
	while not parts.is_empty() and parts[0] is Dictionary and not (parts[0] as Dictionary).has("url"):
		var mark: Dictionary = parts[0]
		if mark.has("reply_to"):
			reply_to = String(mark["reply_to"])
			reply_quote = String(mark.get("quote", ""))
		tint = String(mark.get("tint", tint))
		parts = parts.slice(1)
	if not bool(AppState.get_setting("audience_bubble_tints")):
		tint = ""         # (the marker still comes along for the bubble filter: drawn plain)
	var text_color := AudienceStyle.color_of(st, "text")
	var base_fill := AudienceStyle.color_of(st, "fill")
	# a dark fill gets lighter names (like the Dark look), a light one darker names
	var dark := base_fill.get_luminance() < 0.5
	_fill = base_fill.lerp(color, float(st["fill_mix"]))
	_fill.a = base_fill.a
	if tint in ["paid", "highlighted"]:
		_fill = AudienceStyle.color_of(st, tint)
	_rtl.add_theme_color_override("default_color", text_color)
	_rtl.add_theme_font_override("normal_font", bold_font() if bool(st["bold"]) else shared_font())
	_rtl.add_theme_font_size_override("normal_font_size", int(st["text_size"]))
	var emote_only := parts.size() <= 6 and parts.all(func(p: Variant) -> bool:
		return (p is Dictionary and textures.has(String(p.get("url", "")))) or (p is String and String(p).strip_edges() == ""))
	var h := int(round((EMOTE_ONLY_SIZE if emote_only else EMOTE_SIZE) * scale_text))
	var giant := -1           # Gigantify an Emote: the last emote is drawn big
	if tint == "gigantified":
		for k in range(parts.size() - 1, -1, -1):
			if parts[k] is Dictionary and textures.has(String((parts[k] as Dictionary).get("url", ""))):
				giant = k
				break
	_rtl.clear()
	var name_size := int(round(NAME_SIZE * scale_text))
	_rtl.push_font_size(name_size)
	var name_color := (color.lightened(0.4) if dark else color.darkened(0.45))
	if String(st["name_mode"]) == "fixed":
		name_color = AudienceStyle.color_of(st, "name_color")
	_rtl.push_color(name_color)
	_rtl.add_text(SafeText.clean(speaker))
	_rtl.pop()
	_rtl.pop()
	if reply_to != "":
		_rtl.newline()
		_rtl.push_font_size(name_size - 4)
		_rtl.push_color(text_color.lerp(color.lightened(0.2) if dark else color.darkened(0.2), 0.5))
		_rtl.add_text(SafeText.clean("↩ replying to " + reply_to + (": " + reply_quote.left(40) + ("…" if reply_quote.length() > 40 else "") if reply_quote != "" else "")))
		_rtl.pop()
		_rtl.pop()
	_rtl.newline()
	for k in parts.size():
		var p: Variant = parts[k]
		if p is Dictionary and (p as Dictionary).has("url"):
			var tex: Texture2D = textures.get(String(p["url"]))
			if tex:
				var eh := int(round(EMOTE_GIANT_SIZE * scale_text)) if k == giant else h
				var w := int(round(float(eh) * tex.get_width() / maxf(tex.get_height(), 1.0)))
				_rtl.add_image(tex, w, eh, Color.WHITE, INLINE_ALIGNMENT_CENTER, Rect2(), null, false, String(p["name"]))
			else:
				_rtl.add_text(SafeText.clean(String(p["name"])))
		else:
			_rtl.add_text(SafeText.clean(String(p)))
	# measure: lay out at full width, then shrink to what the text actually uses
	_rtl.size = Vector2(max_w, 0)
	_rtl.custom_minimum_size = Vector2(max_w, 0)
	var used_w := clampf(float(_rtl.get_content_width()), 60.0, max_w)
	_rtl.custom_minimum_size = Vector2(used_w + 2.0, 0)
	_rtl.size = Vector2(used_w + 2.0, 0)
	var used_h := float(_rtl.get_content_height())
	var inner := Vector2(used_w + 2.0, used_h)
	var grow := Vector2.ONE
	if _style == 1:
		grow = Vector2(1.36, 1.42)      # an oval needs room around the text
	elif _style == 4:
		grow = Vector2(1.42, 1.5)       # a cloud a little more, for its bumps
	var body_size := inner * grow + Vector2(PAD, PAD) * 2.0
	var margin := _outline + 4.0
	_body = Rect2(Vector2(margin, margin), body_size)
	_rtl.position = _body.get_center() - inner * 0.5
	_rtl.size = inner
	# no tail: the "tip" is just under the body, so AudienceView still places the bubble over the head
	_tail_tip = Vector2(_body.position.x + body_size.x * _tail_at, _body.end.y + TAIL_H) if _tail_at >= 0.0 \
		else Vector2(_body.get_center().x, _body.end.y + 4.0)
	var total := Vector2(_body.end.x + margin, _tail_tip.y + margin)
	size = total
	queue_redraw()
	return Vector2i(ceili(total.x), ceili(total.y))


## Where the tail points, in pixels from the top-left.
func get_tail_tip() -> Vector2:
	return _tail_tip


func _draw() -> void:
	if _body.size == Vector2.ZERO:
		return
	var body := _shape_points()
	# the tail's base: a stretch of the bottom edge just past the tip's side of the body
	var base_l := _body.position.x + _body.size.x * clampf(_tail_at + 0.04, 0.08, 0.78)
	var base_r := _body.position.x + _body.size.x * clampf(_tail_at + 0.22, 0.22, 0.92)
	if _tail_at > 0.6:      # a tail on the right leans the other way
		base_l = _body.position.x + _body.size.x * clampf(_tail_at - 0.22, 0.08, 0.78)
		base_r = _body.position.x + _body.size.x * clampf(_tail_at - 0.04, 0.22, 0.92)
	var tail := PackedVector2Array([
		Vector2(base_l, _body.end.y - _outline - 10.0),
		Vector2(base_r, _body.end.y - _outline - 10.0),
		_tail_tip])
	# outlines first, fills on top, so the tail joins the body without a seam
	if _outline > 0.0:
		var closed := body.duplicate()
		closed.append(body[0])
		draw_polyline(closed, _outline_color, _outline * 2.0, true)
		if _tail_at >= 0.0:
			var tail_outline := PackedVector2Array([tail[0] + Vector2(-2, 6), tail[2], tail[1] + Vector2(2, 6)])
			draw_polyline(tail_outline, _outline_color, _outline * 2.0, true)
	draw_colored_polygon(body, _fill)
	if _tail_at >= 0.0:
		draw_colored_polygon(tail, _fill)


## The bubble font (theme font + colour emoji fallback). Also used by the reaction effects,
## name tags and the chat windows, so there is one copy of it.
static func shared_font() -> Font:
	if _font == null:
		var emoji := SystemFont.new()
		emoji.font_names = EMOJI_FONTS
		var f := FontVariation.new()
		f.base_font = ThemeDB.fallback_font
		f.fallbacks = [emoji]
		_font = f
	return _font


## shared_font() with thicker letters, for bubble styles with "bold" on.
static func bold_font() -> Font:
	if _bold_font == null:
		var f := FontVariation.new()
		f.base_font = shared_font()
		f.variation_embolden = 0.7
		_bold_font = f
	return _bold_font


## Outline of the bubble body (no tail) for the current style, as a closed list of points.
func _shape_points() -> PackedVector2Array:
	var r := _body
	var pts := PackedVector2Array()
	match _style:
		1:   # oval
			for i in 48:
				var a := TAU * i / 48.0
				pts.append(r.get_center() + Vector2(cos(a) * r.size.x * 0.5, sin(a) * r.size.y * 0.5))
		2:   # slanted box: the top edge tilts
			var tilt := minf(r.size.y * 0.12, 14.0)
			pts = PackedVector2Array([r.position + Vector2(0, tilt), Vector2(r.end.x, r.position.y),
				r.end, Vector2(r.position.x, r.end.y)])
		3:   # pinched box: sides bow inward a little
			var n := 10
			var bow := minf(r.size.y, r.size.x) * 0.06
			for i in n + 1:
				var t := float(i) / n
				pts.append(Vector2(lerpf(r.position.x, r.end.x, t), r.position.y + sin(t * PI) * bow))
			for i in range(1, n + 1):
				var t := float(i) / n
				pts.append(Vector2(r.end.x - sin(t * PI) * bow * 0.6, lerpf(r.position.y, r.end.y, t)))
			for i in range(1, n + 1):
				var t := float(i) / n
				pts.append(Vector2(lerpf(r.end.x, r.position.x, t), r.end.y - sin(t * PI) * bow))
			for i in range(1, n):
				var t := float(i) / n
				pts.append(Vector2(r.position.x + sin(t * PI) * bow * 0.6, lerpf(r.end.y, r.position.y, t)))
		4:   # cloud: an oval with round bumps (|sin| makes the dips between them)
			for i in 120:
				var a := TAU * i / 120.0
				var bump := 1.0 + 0.07 * absf(sin(a * 6.0))
				pts.append(r.get_center() + Vector2(cos(a) * r.size.x * 0.5, sin(a) * r.size.y * 0.5) * bump / 1.07)
		_:   # rounded box ("roundness" from the style; 0 = square corners)
			var rad := minf(_roundness, minf(r.size.x, r.size.y) * 0.45)
			if rad < 1.0:
				return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
			var corners := [[r.position + Vector2(rad, rad), PI], [Vector2(r.end.x - rad, r.position.y + rad), PI * 1.5],
				[r.end - Vector2(rad, rad), 0.0], [Vector2(r.position.x + rad, r.end.y - rad), PI * 0.5]]
			for c: Array in corners:
				for k in 7:
					var a: float = float(c[1]) + PI * 0.5 * k / 6.0
					pts.append((c[0] as Vector2) + Vector2(cos(a), sin(a)) * rad)
	return pts
