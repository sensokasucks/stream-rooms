class_name StyleEditor
extends Window
## The Style editor: how the chat audience's speech bubbles and silhouettes look, with a live
## preview. Opened by the Audience tab's "Style editor..." button (ControlPanel._open_style_editor),
## as its own OS window while the panel is docked so it never shows on stream.
##
## Every change applies at once: bubbles are saved to "audience_bubble_style" (and
## "audience_bubble_theme" becomes "custom"), silhouettes to "audience_silhouette". The streamer's
## own presets live in "audience_saved_styles", and the Groups tab's looks for mods, VIPs, subs and
## each platform in "audience_style_groups". AudienceStyle (core/audience/audience_style.gd) reads
## them all; this window only edits them.

## Sample chatters in the preview: name, colour, message parts (the same parts SpeechBubble gets
## from AudienceManager.message_parts: text, {tint} and {reply_to, quote} markers).
const SAMPLES: Array = [
	["Nova", Color(0.95, 0.4, 0.4), ["Hi chat! The new room looks great 🎉"]],
	["Pixel_Pete", Color(0.35, 0.7, 1.0), [{"tint": "paid"}, "Super Chat: keep it up!"]],
	["Mia", Color(0.5, 0.95, 0.45), [{"tint": "highlighted"}, {"reply_to": "Nova", "quote": "Hi chat!"}, "Hello hello"]],
]
## Metadata of the Groups tab's "Random mix..." item (never a look name: those can't hold MIX_SEP).
const MIX_ITEM: String = "|mix|"
## Preview scale of the bubbles and silhouettes (they're drawn at full bubble / picture size).
const PREVIEW_BUBBLE_SCALE: float = 0.55
const PREVIEW_FIGURE_SCALE: float = 0.5

## The styles being edited: full styles (AudienceStyle.merge_bubble / merge_figure).
var _bubble: Dictionary = {}
var _fig: Dictionary = {}
## Controls that show a style value, by style key, so loading a preset can update them all.
var _bubble_ctrls: Dictionary = {}
var _fig_ctrls: Dictionary = {}
## True while controls are being filled in from a style (their change signals are ignored then).
var _filling: bool = false
var _preview_bubbles: Array[SpeechBubble] = []
var _preview_figures: Array[TextureRect] = []
var _preview_heads: Array[Control] = []
var _bubble_presets: OptionButton
var _fig_presets: OptionButton
var _custom_rows: Array[Control] = []    # the picture-spot sliders (only for your own picture)
## Groups tab: group -> [bubble OptionButton, silhouette OptionButton] (refilled when presets change).
var _group_picks: Dictionary = {}
var _file_dialog: FileDialog
var _many_dialog: FileDialog        # "Add many pictures..." (several files at once)
var _confirm: ConfirmationDialog


func _init() -> void:
	visible = false       # hidden until popup_centered(): force_native can only change while hidden
	title = "Audience style editor"
	min_size = Vector2i(920, 640)
	size = Vector2i(980, 700)
	wrap_controls = false
	transient = true
	exclusive = false
	close_requested.connect(queue_free)
	add_to_group("keyboard_panel")       # hotkeys stay off while typing in here


func _ready() -> void:
	_bubble = AudienceStyle.bubble().duplicate()
	_fig = AudienceStyle.figure().duplicate()
	var bg := Panel.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var split := HBoxContainer.new()
	split.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 10)
	split.add_theme_constant_override("separation", 12)
	add_child(split)
	var tabs := TabContainer.new()
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.custom_minimum_size = Vector2(440, 0)
	split.add_child(tabs)
	tabs.add_child(_build_bubble_page())
	tabs.add_child(_build_figure_page())
	tabs.add_child(_build_groups_page())
	split.add_child(_build_preview())
	_fill_controls()
	_refresh_preview()


# ── Bubbles page ────────────────────────────────────────────
func _build_bubble_page() -> Control:
	var v := _page("Bubbles")
	var pr := HBoxContainer.new()
	v.add_child(pr)
	_bubble_presets = OptionButton.new()
	_bubble_presets.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bubble_presets.tooltip_text = "Start from a ready-made look (Light and Dark are the Audience tab's Bubble colours), or one you saved."
	_bubble_presets.item_selected.connect(_on_bubble_preset)
	pr.add_child(_label("Preset"))
	pr.add_child(_bubble_presets)
	pr.add_child(_tip(_btn("Save as...", func() -> void: _ask_name("bubble")), "Keep the look you have now as a preset of your own, under a name you pick."))
	pr.add_child(_tip(_btn("Delete", func() -> void: _delete_preset("bubble")), "Delete the picked preset of your own (asks first). The ready-made ones can't be deleted."))
	_fill_bubble_presets()
	var shapes: Array = [[-1, "Each chatter's own"]]
	for k: int in AudienceStyle.BUBBLE_SHAPES.keys():
		shapes.append([k, AudienceStyle.BUBBLE_SHAPES[k]])
	v.add_child(_b_option("shape", "Shape", shapes, "Each chatter's own: everyone keeps the shape picked from their name (so the bubbles differ). Or one shape for everyone."))
	v.add_child(_b_slider("roundness", "Corner roundness", 0.0, 60.0, 1.0, "%d", "How round the corners of the box shapes are. 0 = square corners."))
	v.add_child(_b_option("tail", "Tail", [["left", "Left"], ["middle", "Middle"], ["right", "Right"], ["none", "No tail"]], "Where the pointer under the bubble sits."))
	v.add_child(_heading("Colours"))
	v.add_child(_b_color("fill", "Fill", true, "The bubble's colour. Lower the A (alpha) slider in the picker to make it see-through."))
	v.add_child(_b_slider("fill_mix", "Chatter colour in fill", 0.0, 0.6, 0.01, "%d%%", "How much of each chatter's colour mixes into the fill. 0 = the same fill for everyone.", 100.0))
	v.add_child(_b_color("text", "Text", false, "The colour of the message."))
	v.add_child(_b_mode_color("name_mode", "name_color", "Name", "The chatter's name on top: in their own colour (made darker or lighter so it reads on the fill), or one colour for everyone."))
	v.add_child(_b_mode_color("outline_mode", "outline_color", "Outline", "The line around the bubble: in the chatter's colour, or one colour for everyone."))
	v.add_child(_b_slider("outline", "Outline width", 0.0, 16.0, 0.5, "%.1f", "How thick the line around the bubble is. 0 = no line."))
	v.add_child(_b_color("paid", "Paid", true, "Super Chats, Kicks and Bits (with the Audience tab's Colour paid and highlighted messages on)."))
	v.add_child(_b_color("highlighted", "Highlighted", true, "Twitch messages highlighted with channel points (with Colour paid and highlighted messages on)."))
	v.add_child(_heading("Text"))
	v.add_child(_b_slider("text_size", "Text size", 16.0, 56.0, 1.0, "%d", "Size of the message text. The name, replies and emotes grow and shrink with it."))
	v.add_child(_b_check("bold", "Bold letters", "Thicker letters, easier to read from far away."))
	v.add_child(_b_slider("width", "Text width", 200.0, 640.0, 10.0, "%d", "How wide the text gets before it wraps to a new line. Narrower = taller bubbles."))
	return v.get_parent().get_parent() as Control


# ── Silhouettes page ────────────────────────────────────────
func _build_figure_page() -> Control:
	var v := _page("Silhouettes")
	var pr := HBoxContainer.new()
	v.add_child(pr)
	_fig_presets = OptionButton.new()
	_fig_presets.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fig_presets.tooltip_text = "Silhouette looks you saved."
	_fig_presets.item_selected.connect(_on_fig_preset)
	pr.add_child(_label("Saved"))
	pr.add_child(_fig_presets)
	pr.add_child(_tip(_btn("Save as...", func() -> void: _ask_name("silhouette")), "Keep this silhouette look as a preset of your own, under a name you pick."))
	pr.add_child(_tip(_btn("Delete", func() -> void: _delete_preset("silhouette")), "Delete the picked saved look (asks first)."))
	_fill_fig_presets()
	var shapes: Array = []
	for k: String in AudienceStyle.FIGURE_SHAPES.keys():
		shapes.append([k, AudienceStyle.FIGURE_SHAPES[k]])
	shapes.append(["custom", "My own picture"])
	v.add_child(_f_option("shape", "Shape", shapes, "The figure everyone sits as. My own picture needs Use my own picture first."))
	var own := HBoxContainer.new()
	v.add_child(own)
	own.add_child(_label(""))
	own.add_child(_tip(_btn("Use my own picture...", _pick_picture), "Pick a picture (PNG, JPG or WebP) from your PC. A see-through PNG works best; a picture with no see-through parts is read as a dark shape on a light background. It's cut to size and saved with Stream Rooms' settings."))
	own.add_child(_tip(_btn("Add many pictures...", _pick_many), "Pick several pictures at once. Each one is saved as a look of your own (named after its file), ready for the Groups tab's Random mix... The audience doesn't change until you use them."))
	own.add_child(_tip(_btn("Back to classic", func() -> void:
		_fig = AudienceStyle.merge_figure({})
		_apply_figure(true)), "The original head-and-shoulders silhouette, in the chatter's colour."))
	v.add_child(_f_option("paint", "Painted", [["chatter", "In the chatter's colour"], ["fixed", "One colour for everyone"],
		["picture", "The picture's own colours"]],
		"In the chatter's colour: a dark body with an outline in their colour (like the classic look). One colour: the same, in the colour below. The picture's own colours: only for your own picture, shown as it is."))
	v.add_child(_f_color("color", "Colour", "The colour for Painted: One colour for everyone."))
	v.add_child(_f_slider("brightness", "Brightness", 0.4, 1.6, 0.05, "%d%%", "Darker or brighter silhouettes (name tags keep their colour).", 100.0))
	v.add_child(_f_slider("size", "Size", 0.7, 1.4, 0.05, "%d%%", "How big the silhouettes are. Name tags and bubbles move up with them.", 100.0))
	v.add_child(_f_check("crowd", "The filler crowd uses it too", "Filler people (Lecture Hall tiers, balcony, gallery) take the same shape and size. Off: they stay the classic silhouette."))
	v.add_child(_heading("Where the chatter's picture sits (your own picture)"))
	for row: Control in [
			_f_slider("head_x", "Across", 0.0, 1.0, 0.01, "%d%%", "Left to right: where the middle of the chatter's profile picture goes on your picture.", 100.0),
			_f_slider("head_y", "Down", 0.0, 1.0, 0.01, "%d%%", "Top to bottom: where the middle of the chatter's profile picture goes.", 100.0),
			_f_slider("head_r", "Picture size", 0.05, 0.5, 0.01, "%d%%", "How big the chatter's round profile picture is (a share of the picture's width).", 100.0)]:
		v.add_child(row)
		_custom_rows.append(row)
	v.add_child(_hint("Chatter pictures only show with the Audience tab's Chatter pictures on."))
	return v.get_parent().get_parent() as Control


# ── Groups page ─────────────────────────────────────────────
## A bubble and a silhouette look per group. Everyone else (and any group left on "Main style")
## gets what the Bubbles and Silhouettes tabs set.
func _build_groups_page() -> Control:
	var v := _page("Groups")
	v.add_child(_hint("Give mods, VIPs, subscribers or one platform their own look. Save a look in the Bubbles or Silhouettes tab first (Save as..., or Add many pictures...), then pick it here. Someone in more than one group gets the first one in this list that has a look set (a mod who subscribes gets the Mods look). Everyone else covers whoever is left. Random mix... gives each chatter in the group one of several silhouettes, and they keep it every time they chat."))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	v.add_child(grid)
	grid.add_child(_heading("Group"))
	grid.add_child(_heading("Bubble"))
	grid.add_child(_heading("Silhouette"))
	for g: String in AudienceStyle.GROUPS.keys():
		var l := _label(String(AudienceStyle.GROUPS[g]))
		l.custom_minimum_size = Vector2(110, 0)
		grid.add_child(l)
		var picks: Array[OptionButton] = []
		for kind: String in ["bubble", "silhouette"]:
			var ob := OptionButton.new()
			ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			ob.fit_to_longest_item = false
			ob.tooltip_text = "The %s look for %s. Main style = the same as everyone else." % [kind, String(AudienceStyle.GROUPS[g])]
			ob.item_selected.connect(func(i: int) -> void:
				if _filling:
					return
				var look := String(ob.get_item_metadata(i))
				if look == MIX_ITEM:
					_fill_group_picks()           # (shows the group's current look until the mix is picked)
					_ask_mix(g)
					return
				AudienceStyle.set_group_look(g, kind, look))
			grid.add_child(ob)
			picks.append(ob)
		_group_picks[g] = picks
	_fill_group_picks()
	return v.get_parent().get_parent() as Control


## Fills the Groups tab's lists (main style, built-in looks, saved looks) and selects each group's look.
func _fill_group_picks() -> void:
	_filling = true
	var looks := AudienceStyle.group_looks()
	for g: String in _group_picks.keys():
		var now: Dictionary = looks.get(g, {}) if looks.get(g) is Dictionary else {}
		for k in 2:
			var kind := "bubble" if k == 0 else "silhouette"
			var ob: OptionButton = (_group_picks[g] as Array)[k]
			ob.clear()
			ob.add_item("Main style")
			ob.set_item_metadata(0, "")
			var names := AudienceStyle.bubble_preset_names() if kind == "bubble" else AudienceStyle.figure_look_names()
			for n in names:
				var shown := n
				if kind == "silhouette" and AudienceStyle.FIGURE_SHAPES.has(n):
					shown = String(AudienceStyle.FIGURE_SHAPES[n])
				elif AudienceStyle.saved(kind).has(n):
					shown = "%s (mine)" % n
				ob.add_item(shown)
				ob.set_item_metadata(ob.item_count - 1, n)
				if String(now.get(kind, "")) == n:
					ob.select(ob.item_count - 1)
			if kind == "silhouette":
				var cur := String(now.get(kind, ""))
				if cur.contains(AudienceStyle.MIX_SEP):
					ob.add_item("Mix of %d" % cur.split(AudienceStyle.MIX_SEP, false).size())
					ob.set_item_metadata(ob.item_count - 1, cur)
					ob.select(ob.item_count - 1)
				ob.add_item("Random mix...")
				ob.set_item_metadata(ob.item_count - 1, MIX_ITEM)
			if String(now.get(kind, "")) == "":
				ob.select(0)
	_filling = false


## "Random mix...": ticks for every silhouette look; the group's chatters each get one of the ticked
## ones (AudienceStyle.figure_for picks it from their name). Fewer than two ticked = no mix.
func _ask_mix(group: String) -> void:
	var looks := AudienceStyle.group_looks()
	var cur := String((looks.get(group, {}) as Dictionary).get("silhouette", "")) if looks.get(group) is Dictionary else ""
	var ticked := cur.split(AudienceStyle.MIX_SEP, false)
	var d := ConfirmationDialog.new()
	d.title = "Random mix for %s" % String(AudienceStyle.GROUPS[group])
	d.ok_button_text = "Use this mix"
	d.exclusive = false
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(320, 300)
	var box := VBoxContainer.new()
	sc.add_child(box)
	box.add_child(_hint("Tick the silhouettes to mix. Each chatter gets one of them and keeps it."))
	var checks: Dictionary = {}       # look name -> CheckBox
	for n in AudienceStyle.figure_look_names():
		var c := CheckBox.new()
		c.text = String(AudienceStyle.FIGURE_SHAPES.get(n, n))
		c.tooltip_text = "Put this silhouette in the mix."
		c.button_pressed = ticked.has(n)
		box.add_child(c)
		checks[n] = c
	d.add_child(sc)
	d.confirmed.connect(func() -> void:
		var picked := PackedStringArray()
		for n: String in checks.keys():
			if (checks[n] as CheckBox).button_pressed:
				picked.append(n)
		if picked.size() == 1:
			AudienceStyle.set_group_look(group, "silhouette", picked[0])
		elif picked.size() > 1:
			AudienceStyle.set_group_look(group, "silhouette", AudienceStyle.MIX_SEP.join(picked))
		_fill_group_picks()
		d.queue_free())
	d.canceled.connect(d.queue_free)
	add_child(d)
	d.popup_centered()


# ── Preview ─────────────────────────────────────────────────
## The preview: three sample bubbles (plain, paid, highlighted reply) and three silhouettes in
## sample chatter colours, drawn with the styles being edited.
func _build_preview() -> Control:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(420, 0)
	box.add_child(_heading("Preview"))
	var stage := ColorRect.new()
	stage.color = Color(0.11, 0.12, 0.16)
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.clip_contents = true
	stage.tooltip_text = "How the bubbles and silhouettes look with these settings. Changes also show in the room straight away."
	box.add_child(stage)
	for i in SAMPLES.size():
		var b := SpeechBubble.new()
		b.scale = Vector2.ONE * PREVIEW_BUBBLE_SCALE
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stage.add_child(b)
		_preview_bubbles.append(b)
	for i in SAMPLES.size():
		var t := TextureRect.new()
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE     # (so it can be drawn smaller than the picture)
		t.stretch_mode = TextureRect.STRETCH_SCALE
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stage.add_child(t)
		_preview_figures.append(t)
		var head := Panel.new()          # where the chatter's picture goes: a light circle
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.85, 0.85, 0.9, 0.85)
		sb.set_corner_radius_all(200)
		head.add_theme_stylebox_override("panel", sb)
		head.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stage.add_child(head)
		_preview_heads.append(head)
	box.add_child(_hint("The light circles are where chatters' profile pictures go."))
	return box


## Redraws the preview from _bubble and _fig. Called after every change.
func _refresh_preview() -> void:
	if _preview_bubbles.is_empty():
		return
	var y := 12.0
	for i in SAMPLES.size():
		var b := _preview_bubbles[i]
		b.style_override = _bubble
		var px := b.set_content(String(SAMPLES[i][0]), (SAMPLES[i][2] as Array).duplicate(), SAMPLES[i][1], i, {})
		b.position = Vector2(12.0 + i * 24.0, y)
		y += px.y * PREVIEW_BUBBLE_SCALE + 6.0
	var tex := AudienceStyle.figure_texture(_fig)
	var head := AudienceStyle.figure_head(_fig)
	var k := PREVIEW_FIGURE_SCALE * float(_fig["size"])
	var stage_w := (_preview_figures[0].get_parent() as Control).size.x
	if stage_w > 0.0:
		k = minf(k, (stage_w - 30.0) / (3.0 * tex.get_width()))     # three side by side always fit
	var fig_size := Vector2(tex.get_width(), tex.get_height()) * k
	var base_y := maxf(y + 10.0, 420.0)
	for i in SAMPLES.size():
		var t := _preview_figures[i]
		t.texture = tex
		t.size = fig_size
		t.position = Vector2(10.0 + i * (fig_size.x + 6.0), base_y + (AudienceStyle.FIGURE_H * PREVIEW_FIGURE_SCALE - fig_size.y))
		t.modulate = AudienceStyle.figure_tint(SAMPLES[i][1], _fig)
		var h := _preview_heads[i]
		h.size = Vector2.ONE * head.z * 2.0 * k
		h.position = t.position + Vector2(head.x, head.y) * k - h.size * 0.5
		h.visible = bool(AppState.get_setting("audience_avatars"))
	for row in _custom_rows:
		row.visible = String(_fig["shape"]) == "custom"


# ── Applying ────────────────────────────────────────────────
## A bubble value changed: save it as the custom style and switch the bubbles to it.
func _apply_bubble() -> void:
	AppState.set_setting("audience_bubble_style", JSON.stringify(_jsonable(_bubble)))
	AppState.set_setting("audience_bubble_theme", "custom")
	_refresh_preview()


## A silhouette value changed: save it (the room redraws its audience). refill: also update the
## controls (after a preset or a picture import changed several values at once).
func _apply_figure(refill: bool = false) -> void:
	_fig = AudienceStyle.merge_figure(_fig)
	AppState.set_setting("audience_silhouette", JSON.stringify(_jsonable(_fig)))
	if refill:
		_fill_controls()
	_refresh_preview()


## A style with Color values written as "rrggbbaa" text, so it can go into a JSON setting.
func _jsonable(style: Dictionary) -> Dictionary:
	var out := {}
	for k: String in style.keys():
		out[k] = (style[k] as Color).to_html(true) if style[k] is Color else style[k]
	return out


## Puts the edited styles' values into the controls (without applying anything).
func _fill_controls() -> void:
	_filling = true
	for k: String in _bubble_ctrls.keys():
		_set_ctrl(_bubble_ctrls[k], _bubble, k)
	for k: String in _fig_ctrls.keys():
		_set_ctrl(_fig_ctrls[k], _fig, k)
	_filling = false


func _set_ctrl(c: Control, style: Dictionary, key: String) -> void:
	if c is OptionButton:
		var ob := c as OptionButton
		for i in ob.item_count:
			if str(ob.get_item_metadata(i)) == str(style[key]):
				ob.select(i)
	elif c is HSlider:
		(c as HSlider).value = float(style[key]) * float(c.get_meta("scale", 1.0))
	elif c is CheckBox:
		(c as CheckBox).button_pressed = bool(style[key])
	elif c is ColorPickerButton:
		(c as ColorPickerButton).color = AudienceStyle.color_of(style, key)


# ── Presets ─────────────────────────────────────────────────
func _fill_bubble_presets() -> void:
	_bubble_presets.clear()
	_bubble_presets.add_item("Pick a preset...")
	_bubble_presets.set_item_metadata(0, "")
	for n in AudienceStyle.bubble_preset_names():
		_bubble_presets.add_item(n if AudienceStyle.BUBBLE_PRESETS.has(n) else "%s (mine)" % n)
		_bubble_presets.set_item_metadata(_bubble_presets.item_count - 1, n)
	_bubble_presets.select(0)


func _fill_fig_presets() -> void:
	_fig_presets.clear()
	_fig_presets.add_item("Pick a saved look..." if not AudienceStyle.figure_preset_names().is_empty() else "(none saved yet)")
	_fig_presets.set_item_metadata(0, "")
	for n in AudienceStyle.figure_preset_names():
		_fig_presets.add_item(n)
		_fig_presets.set_item_metadata(_fig_presets.item_count - 1, n)
	_fig_presets.select(0)


## A bubble preset picked. Light and Dark set the Audience tab's Bubble colours back to them
## (so the room looks exactly as it did before the editor); the rest become the custom style.
func _on_bubble_preset(i: int) -> void:
	var preset_name := String(_bubble_presets.get_item_metadata(i))
	if preset_name == "":
		return
	_bubble = AudienceStyle.bubble_preset(preset_name)
	if preset_name in ["Light", "Dark"] and not AudienceStyle.saved("bubble").has(preset_name):
		AppState.set_setting("audience_bubble_theme", preset_name.to_lower())
		_refresh_preview()
	else:
		_apply_bubble()
	_fill_controls()


func _on_fig_preset(i: int) -> void:
	var preset_name := String(_fig_presets.get_item_metadata(i))
	var own := AudienceStyle.saved("silhouette")
	if preset_name == "" or not own.get(preset_name) is Dictionary:
		return
	_fig = AudienceStyle.merge_figure(own[preset_name])
	_apply_figure(true)


## "Save as...": a small popup asks for the name, then the look is saved under it.
func _ask_name(kind: String) -> void:
	var d := AcceptDialog.new()
	d.title = "Save this look"
	d.ok_button_text = "Save"
	d.exclusive = false
	var box := VBoxContainer.new()
	box.add_child(_label("Name for it:"))
	var edit := LineEdit.new()
	edit.custom_minimum_size = Vector2(260, 0)
	edit.max_length = 40
	edit.tooltip_text = "The name it gets in the preset list. Saving under a name that's already yours replaces that one."
	box.add_child(edit)
	d.add_child(box)
	d.register_text_enter(edit)
	d.confirmed.connect(func() -> void:
		var preset_name := edit.text.strip_edges()
		if preset_name != "":
			AudienceStyle.save_preset(kind, preset_name, _jsonable(_bubble if kind == "bubble" else _fig))
			if kind == "bubble":
				_fill_bubble_presets()
			else:
				_fill_fig_presets()
			_fill_group_picks()
			EventBus.status_message.emit("Look saved: %s." % preset_name, false)
		d.queue_free())
	d.canceled.connect(d.queue_free)
	add_child(d)
	d.popup_centered()
	edit.grab_focus()


## "Delete": removes the picked preset of your own, after asking.
func _delete_preset(kind: String) -> void:
	var ob := _bubble_presets if kind == "bubble" else _fig_presets
	var preset_name := String(ob.get_item_metadata(ob.selected)) if ob.selected >= 0 else ""
	if preset_name == "" or not AudienceStyle.saved(kind).has(preset_name):
		EventBus.status_message.emit("Pick one of your own saved looks first.", false)
		return
	if _confirm != null and is_instance_valid(_confirm):
		_confirm.queue_free()
	_confirm = ConfirmationDialog.new()
	_confirm.title = "Delete this look?"
	_confirm.dialog_text = "\"%s\" is deleted from your saved looks. What the audience looks like now stays as it is (a group using it goes back to the main style)." % preset_name
	_confirm.ok_button_text = "Delete"
	_confirm.exclusive = false
	_confirm.confirmed.connect(func() -> void:
		AudienceStyle.save_preset(kind, preset_name, {})
		if kind == "bubble":
			_fill_bubble_presets()
		else:
			_fill_fig_presets()
		_fill_group_picks())
	add_child(_confirm)
	_confirm.popup_centered()


# ── Your own picture ────────────────────────────────────────
func _pick_picture() -> void:
	if _file_dialog == null:
		_file_dialog = FileDialog.new()
		_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_file_dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; Pictures"])
		_file_dialog.use_native_dialog = true
		_file_dialog.title = "Pick a silhouette picture"
		_file_dialog.file_selected.connect(_on_picture_picked)
		add_child(_file_dialog)
	_file_dialog.popup_centered_ratio(0.6)


## "Add many pictures...": a file dialog that takes several pictures at once.
func _pick_many() -> void:
	if _many_dialog == null:
		_many_dialog = FileDialog.new()
		_many_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
		_many_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_many_dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; Pictures"])
		_many_dialog.use_native_dialog = true
		_many_dialog.title = "Pick silhouette pictures"
		_many_dialog.files_selected.connect(_on_many_picked)
		add_child(_many_dialog)
	_many_dialog.popup_centered_ratio(0.6)


## Called by the many-pictures dialog (and tests): imports each picture and saves it as a look of
## your own named after its file (the main silhouette's colour, brightness and size, the picture's
## head spot guessed). They show in the Saved list and the Groups tab, ready for a random mix.
func _on_many_picked(paths: PackedStringArray) -> void:
	var added := 0
	var all := AudienceStyle._parse(String(AppState.get_setting("audience_saved_styles")))
	var mine: Dictionary = all.get("silhouette", {}) if all.get("silhouette") is Dictionary else {}
	for path in paths:
		var file := AudienceStyle.import_picture(path)
		if file == "":
			continue
		var f := _jsonable(_fig)
		var head := AudienceStyle.guess_head(file)
		f["shape"] = "custom"
		f["file"] = file
		f["head_x"] = head.x
		f["head_y"] = head.y
		f["head_r"] = head.z
		mine[path.get_file().get_basename().replace(AudienceStyle.MIX_SEP, " ").strip_edges().left(40)] = f
		added += 1
	all["silhouette"] = mine
	AppState.set_setting("audience_saved_styles", JSON.stringify(all))      # (one save for the lot)
	_fill_fig_presets()
	_fill_group_picks()
	if added < paths.size():
		EventBus.status_message.emit("Added %d of %d pictures (the others couldn't be read)." % [added, paths.size()], true)
	else:
		EventBus.status_message.emit("Added %d pictures as saved looks. Use them in the Groups tab (Random mix...)." % added, false)


## Called by the file dialog (and tests): imports the picture and switches the silhouettes to it.
func _on_picture_picked(path: String) -> void:
	var saved := AudienceStyle.import_picture(path)
	if saved == "":
		EventBus.status_message.emit("That picture couldn't be read (or it's empty). Try a PNG.", true)
		return
	var head := AudienceStyle.guess_head(saved)
	_fig["shape"] = "custom"
	_fig["file"] = saved
	_fig["head_x"] = head.x
	_fig["head_y"] = head.y
	_fig["head_r"] = head.z
	_apply_figure(true)
	EventBus.status_message.emit("Your picture is the audience's silhouette now. Move the chatter picture spot under the Silhouettes tab if needed.", false)


# ── Small widget helpers (bound to the edited style, not to settings) ──
## A scrolling page for the tab container; returns the VBox to fill (page = its grandparent).
func _page(page_title: String) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.name = page_title
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var m := MarginContainer.new()
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.add_theme_constant_override("margin_right", 10)
	sc.add_child(m)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.add_child(v)
	return v


func _b_option(key: String, text: String, items: Array, tip: String) -> Control:
	return _option_row(key, text, items, tip, _bubble_ctrls, func(val: Variant) -> void:
		_bubble[key] = val
		_apply_bubble())


func _f_option(key: String, text: String, items: Array, tip: String) -> Control:
	return _option_row(key, text, items, tip, _fig_ctrls, func(val: Variant) -> void:
		if key == "shape" and String(val) == "custom" and String(_fig["file"]) == "":
			EventBus.status_message.emit("Pick a picture with Use my own picture first.", false)
			_fill_controls()
			return
		_fig[key] = val
		_apply_figure())


func _b_slider(key: String, text: String, lo: float, hi: float, step: float, fmt: String, tip: String, scale_by: float = 1.0) -> Control:
	return _slider_row(key, text, lo, hi, step, fmt, tip, scale_by, _bubble_ctrls, func(val: float) -> void:
		if key in ["text_size", "width"]:
			_bubble[key] = int(val)
		else:
			_bubble[key] = val
		_apply_bubble())


func _f_slider(key: String, text: String, lo: float, hi: float, step: float, fmt: String, tip: String, scale_by: float = 1.0) -> Control:
	return _slider_row(key, text, lo, hi, step, fmt, tip, scale_by, _fig_ctrls, func(val: float) -> void:
		_fig[key] = val
		_apply_figure())


func _b_check(key: String, text: String, tip: String) -> Control:
	var c := CheckBox.new()
	c.text = text
	c.tooltip_text = tip
	c.toggled.connect(func(on: bool) -> void:
		if not _filling:
			_bubble[key] = on
			_apply_bubble())
	_bubble_ctrls[key] = c
	return c


func _f_check(key: String, text: String, tip: String) -> Control:
	var c := CheckBox.new()
	c.text = text
	c.tooltip_text = tip
	c.toggled.connect(func(on: bool) -> void:
		if not _filling:
			_fig[key] = on
			_apply_figure())
	_fig_ctrls[key] = c
	return c


func _b_color(key: String, text: String, alpha: bool, tip: String) -> Control:
	return _color_row(key, text, alpha, tip, _bubble_ctrls, func(c: Color) -> void:
		_bubble[key] = c.to_html(true)
		_apply_bubble())


func _f_color(key: String, text: String, tip: String) -> Control:
	return _color_row(key, text, false, tip, _fig_ctrls, func(c: Color) -> void:
		_fig[key] = c.to_html(true)
		_apply_figure())


## "Chatter's colour / one colour" picker plus the colour, for the name and outline.
func _b_mode_color(mode_key: String, color_key: String, text: String, tip: String) -> Control:
	var h := _option_row(mode_key, text, [["chatter", "Chatter's colour"], ["fixed", "One colour:"]], tip, _bubble_ctrls,
		func(val: Variant) -> void:
			_bubble[mode_key] = val
			_apply_bubble()) as HBoxContainer
	var b := _picker(color_key, false, tip, _bubble_ctrls, func(c: Color) -> void:
		_bubble[color_key] = c.to_html(true)
		_bubble[mode_key] = "fixed"        # picking a colour means using it
		_fill_controls()
		_apply_bubble())
	h.add_child(b)
	return h


func _option_row(key: String, text: String, items: Array, tip: String, ctrls: Dictionary, on_pick: Callable) -> Control:
	var h := HBoxContainer.new()
	h.add_child(_label(text))
	var ob := OptionButton.new()
	ob.tooltip_text = tip
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for it: Array in items:
		ob.add_item(String(it[1]))
		ob.set_item_metadata(ob.item_count - 1, it[0])
	ob.item_selected.connect(func(i: int) -> void:
		if not _filling:
			on_pick.call(ob.get_item_metadata(i)))
	ctrls[key] = ob
	h.add_child(ob)
	return h


func _slider_row(key: String, text: String, lo: float, hi: float, step: float, fmt: String, tip: String,
		scale_by: float, ctrls: Dictionary, on_change: Callable) -> Control:
	var h := HBoxContainer.new()
	h.add_child(_label(text))
	var s := HSlider.new()
	s.min_value = lo * scale_by
	s.max_value = hi * scale_by
	s.step = step * scale_by
	s.tooltip_text = tip
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.set_meta("scale", scale_by)
	var num := Label.new()
	num.custom_minimum_size = Vector2(52, 0)
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	s.value_changed.connect(func(val: float) -> void:
		num.text = fmt % val
		if not _filling:
			on_change.call(val / scale_by))
	ctrls[key] = s
	h.add_child(s)
	h.add_child(num)
	return h


func _color_row(key: String, text: String, alpha: bool, tip: String, ctrls: Dictionary, on_change: Callable) -> Control:
	var h := HBoxContainer.new()
	h.add_child(_label(text))
	h.add_child(_picker(key, alpha, tip, ctrls, on_change))
	return h


func _picker(key: String, alpha: bool, tip: String, ctrls: Dictionary, on_change: Callable) -> ColorPickerButton:
	var b := ColorPickerButton.new()
	b.edit_alpha = alpha
	b.tooltip_text = tip
	b.custom_minimum_size = Vector2(90, 24)
	b.color_changed.connect(func(c: Color) -> void:
		if not _filling:
			on_change.call(c))
	ctrls[key] = b
	return b


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(150, 0)
	return l


func _heading(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color(1.0, 0.7, 0.3))
	return l


func _hint(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(200, 0)
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	return l


func _btn(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	return b


func _tip(c: Control, text: String) -> Control:
	c.tooltip_text = text
	return c
