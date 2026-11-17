extends Node
## Route 22 Cruise's billboards: boards along the road showing pictures from a set Sen picks
## (friends' promo pictures), in six shapes. Used by r22_trip.gd: every road piece
## (r22_pieces.gd) has a couple of billboard spots, and fill() decides, each time a piece comes
## up over the horizon, which spots get a board, in which shape and with which picture.
##
## Settings (Room tab > Billboards; each PC's own pictures, the rest shared in a co-stream):
##   r22_bb_folder     a folder of pictures on this PC (PNG, JPG, WebP, GIF). Empty = the
##                     "billboards" folder in the app's data folder (opened by the Open folder tip).
##   r22_bb_core       names of pictures in Stream Core's Stored files, comma-separated; they are
##                     downloaded from Core (its /media/<name> address) and join the set. Picked
##                     (and uploaded) on Core's Setup > Stream Rooms > Room & sound page, which
##                     draws this setting as a picture picker (fridge-stream-core
##                     admin/rooms-setup.js MEDIA_PICKS); in the game it is a plain text box.
##   r22_bb_amount     "How common", 0..100: 40 = about one board every 15 s at 50 km/h, 100 = one
##                     every 6 s, 0 = none.
##   r22_bb_order      "shuffle" (a shuffled round of the set, then another) or "order" (as listed:
##                     the folder's files by name, then Core's in the order typed).
##   r22_bb_lit        lamps light the boards at night.
##   r22_bb_filler     made-up roadside ads (textures/ad_*.png) while the set is empty.
##   r22_bb_classic, _monopole, _wooden, _rooftop, _neon, _trailer   which shapes can turn up:
##     classic two-post board with a catwalk and lamps, a tall single-pole board, a weathered
##     wooden sign, a board on the roof of an old roadside stop, a board with a neon arrow, and an
##     old trailer parked in the dirt with the picture on its side.
## Every board shows its picture on both faces, angled a little towards the road, so it reads
## from the cameras looking ahead and the ones looking back.
## The whole picture shows: each board is built to its picture's shape (wide, square or tall,
## inside the shape's largest size, BOX), and nothing of the board stands in front of the
## picture: posts stop under its bottom edge, the lamps hang out from its top edge (anything
## below and in front of a board hides part of it when seen from the road below).

const Geo := preload("res://rooms/route22/r22_geo.gd")
const PICTURE_SHADER := preload("res://rooms/route22/r22_picture.gdshader")
const ADS: PackedStringArray = ["ad_rock_shop", "ad_jerky", "ad_diner", "ad_motel", "ad_arch", "ad_candy", "ad_services", "ad_canyon"]
const SHAPES: PackedStringArray = ["classic", "monopole", "wooden", "rooftop", "neon", "trailer"]
## The default picture folder (when r22_bb_folder is empty) and where Core's pictures are kept.
const DEFAULT_FOLDER := "user://billboards"
const CORE_FOLDER := "user://billboards_core"
## Most pictures read from the folder (the first ones by name).
const MAX_PICTURES: int = 40
## Boards per road piece expected at How common = 100 (a piece is 80 m, so at 50 km/h a piece
## passes every 5.8 s: 0.96 boards a piece = one every 6 s; at 40, one every 15 s).
const PER_PIECE_AT_100: float = 0.96
## The largest picture each shape carries (width, height in metres): a board is as big as fits
## in this with its picture's own shape (_picture_size).
const BOX: Dictionary = {"classic": Vector2(8.4, 4.6), "monopole": Vector2(7.2, 4.2), "wooden": Vector2(5.0, 3.0),
	"rooftop": Vector2(5.4, 3.0), "neon": Vector2(5.6, 3.4), "trailer": Vector2(6.4, 2.2)}
## The narrowest and the widest board built (width / height). A picture taller or wider than
## this has its middle cut to fit (_fit); every other picture shows whole.
const ASPECT_MIN: float = 0.7
const ASPECT_MAX: float = 3.4

## The set's pictures were (re)loaded: r22_trip.gd refills the boards in view.
signal pictures_changed

var _kit: Dictionary
var _pictures: Array[Texture2D] = []
var _filler: Array[Texture2D] = []
var _shape_cache: Dictionary = {}       # "shape:picture shape" -> {"mesh", "faces", "size", "lamps", "faded"}
var _active: Array[ShaderMaterial] = [] # the picture materials of the boards in view
var _order: Array[int] = []             # shuffle: the current round's picture order
var _next: int = 0                      # which picture the next board gets
var _rng := RandomNumberGenerator.new()
var _downloads: Dictionary = {}         # Core picture name -> HTTPRequest
var _checked: Dictionary = {}           # Core picture names already asked for this run (set of names)


func setup(kit: Dictionary) -> void:
	_kit = kit
	name = "Billboards"
	_rng.randomize()
	for ad in ADS:
		_filler.append(load(Geo.TEX + ad + ".png") as Texture2D)
	DirAccess.make_dir_recursive_absolute(DEFAULT_FOLDER)
	reload()
	EventBus.setting_changed.connect(_on_setting_changed)


func _exit_tree() -> void:
	if EventBus.setting_changed.is_connected(_on_setting_changed):
		EventBus.setting_changed.disconnect(_on_setting_changed)


func _on_setting_changed(key: String, _v: Variant) -> void:
	if key in ["r22_bb_folder", "r22_bb_core", "r22_bb_order", "r22_bb_filler"]:
		reload()


## How many pictures the set has (not counting the filler ads).
func picture_count() -> int:
	return _pictures.size()


## The folder pictures are read from (r22_bb_folder, else DEFAULT_FOLDER).
static func folder() -> String:
	var f := String(AppState.get_setting("r22_bb_folder")).strip_edges()
	return f if f != "" else DEFAULT_FOLDER


## Reads the set again: the folder's pictures (by name), then Core's (in the order chosen in
## Core). A Core picture already fetched shows at once from its copy here; each one is also
## asked for again once per run (_checked), so a picture replaced or deleted in Core's Stored
## files follows, and the set is read again when something new arrives.
func reload() -> void:
	_pictures.clear()
	var dir := folder()
	var names := PackedStringArray()
	var da := DirAccess.open(dir)
	if da:
		for f in da.get_files():
			if f.get_extension().to_lower() in ["png", "jpg", "jpeg", "webp", "gif"]:
				names.append(f)
	names.sort()
	for f in names:
		if _pictures.size() >= MAX_PICTURES:
			break
		var tex := PictureFile.texture_from_bytes(PictureFile.read_file(dir.path_join(f)))
		if tex:
			_pictures.append(tex)
	for stored in core_names():
		var here := _core_file(stored)
		if here != "":
			var tex := PictureFile.texture_from_bytes(PictureFile.read_file(here))
			if tex:
				_pictures.append(tex)
		if not _checked.has(stored):
			_download(stored)
	_order.clear()
	_next = 0
	pictures_changed.emit()


## The Core picture names typed in r22_bb_core (comma or newline separated, "media:" allowed).
static func core_names() -> PackedStringArray:
	var out := PackedStringArray()
	for part in String(AppState.get_setting("r22_bb_core")).replace("\n", ",").split(",", false):
		var n := part.strip_edges().trim_prefix("media:")
		if n != "" and not out.has(n):
			out.append(n)
	return out


## The downloaded copy of a Core picture, or "" if it isn't here yet.
func _core_file(stored: String) -> String:
	var safe := stored.to_lower().validate_filename().replace(" ", "_")
	for ext in ["png", "jpg", "webp", "gif"]:
		var p := CORE_FOLDER.path_join(safe + "." + ext)
		if FileAccess.file_exists(p):
			return p
	return ""


## Fetches one Core stored picture (/media/<name>) and keeps it in CORE_FOLDER. Core saying
## "no such file" (404: deleted or renamed there) removes the copy here; the same picture as the
## copy here changes nothing; anything else (Core closed...) keeps the copy.
func _download(stored: String) -> void:
	if _downloads.has(stored):
		return
	var req := HTTPRequest.new()
	req.body_size_limit = PictureFile.MAX_BYTES
	add_child(req)
	_downloads[stored] = req
	req.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
		_downloads.erase(stored)
		req.queue_free()
		var old := _core_file(stored)
		if result == HTTPRequest.RESULT_SUCCESS and code == 404:
			_checked[stored] = true
			if old != "":
				DirAccess.remove_absolute(old)
				reload()
			return
		var kind := PictureFile.kind_of(body)
		if result != HTTPRequest.RESULT_SUCCESS or code != 200 or kind == "":
			push_warning("Route 22 billboard: Core picture %s could not be fetched (%d / %d)" % [stored, result, code])
			return
		_checked[stored] = true
		if old != "" and FileAccess.get_file_as_bytes(old) == body:
			return
		if old != "":
			DirAccess.remove_absolute(old)     # (it may have another file type now)
		DirAccess.make_dir_recursive_absolute(CORE_FOLDER)
		var safe := stored.to_lower().validate_filename().replace(" ", "_")
		var fa := FileAccess.open(CORE_FOLDER.path_join(safe + "." + kind), FileAccess.WRITE)
		if fa:
			fa.store_buffer(body)
			fa.close()
			reload())
	if req.request(ChatFeed.core_url("/media/" + stored.uri_encode())) != OK:
		_downloads.erase(stored)
		req.queue_free()


## The picture the next board shows: from the set (shuffled or in order), else a filler ad (if
## Filler ads is on), else null (no board).
func _take_picture() -> Texture2D:
	if _pictures.is_empty():
		if not bool(AppState.get_setting("r22_bb_filler")):
			return null
		return _filler[_rng.randi() % _filler.size()]
	if String(AppState.get_setting("r22_bb_order")) == "order":
		var t := _pictures[_next % _pictures.size()]
		_next += 1
		return t
	if _order.is_empty() or _next >= _order.size():
		var last := _order[_order.size() - 1] if not _order.is_empty() else -1
		_order.clear()
		for i in _pictures.size():
			_order.append(i)
		_order.shuffle()
		# never the same picture twice in a row across rounds
		if _order.size() > 1 and _order[0] == last:
			_order.reverse()
		_next = 0
	var pick := _pictures[_order[_next]]
	_next += 1
	return pick


## The shapes switched on (Room tab > Billboards shape ticks).
static func shapes_on() -> PackedStringArray:
	var out := PackedStringArray()
	for s in SHAPES:
		if bool(AppState.get_setting("r22_bb_" + s)):
			out.append(s)
	return out


## Puts boards on a road piece that has just come up: holder = the piece's "Boards" node (its
## old boards are removed first), k = the piece's number along the trip (so every PC's dice
## agree on where boards stand), slots = [[position, side (+1 right / -1 left)], ...] in the
## piece's space.
func fill(holder: Node3D, k: int, slots: Array) -> void:
	clear(holder)
	var amount := clampf(float(AppState.get_setting("r22_bb_amount")), 0.0, 100.0)
	var shapes := shapes_on()
	if amount <= 0.0 or shapes.is_empty() or slots.is_empty():
		return
	var chance := amount / 100.0 * PER_PIECE_AT_100 / float(slots.size())
	for i in slots.size():
		var dice := RandomNumberGenerator.new()
		dice.seed = hash(Vector2i(k, i)) + 2201
		if dice.randf() >= chance:
			continue
		var tex := _take_picture()
		if tex == null:
			return
		var slot: Array = slots[i]
		var shape := shapes[dice.randi() % shapes.size()]
		_place(holder, shape, slot[0], float(slot[1]), tex, dice)


## Removes the boards from a piece (it went out of view, or the set changed).
func clear(holder: Node3D) -> void:
	for c in holder.get_children():
		for m: ShaderMaterial in c.get_meta("mats", []):
			_active.erase(m)
		c.queue_free()


## Called every frame by r22_trip.gd: the boards' pictures get the shared uniforms (bend, wet...)
## the prop material has, and their lamps light at night when "Lit at night" is on.
func tick(night: float) -> void:
	var pm := _kit["prop"] as ShaderMaterial
	var lit := night * 1.2 if bool(AppState.get_setting("r22_bb_lit")) else 0.0
	var keys: Array[String] = ["travel", "bend", "hill", "wet", "cloud_shadow", "cloud_drift", "detail", "bend_start"]
	var vals: Array = []
	for key in keys:
		vals.append(pm.get_shader_parameter(key))
	for m in _active:
		for i in keys.size():
			if vals[i] != null:
				m.set_shader_parameter(keys[i], vals[i])
		m.set_shader_parameter("lit", lit)


## One board of a shape at `at` (the board's foot, piece space) beside the road on `side`.
func _place(holder: Node3D, shape: String, at: Vector3, side: float, tex: Texture2D, dice: RandomNumberGenerator) -> void:
	var info := _shape(shape, float(tex.get_width()) / maxf(float(tex.get_height()), 1.0))
	var root := Node3D.new()
	root.name = "Board_" + shape
	holder.add_child(root)
	root.position = at
	# boards stand across the road, turned about 15 degrees to face it; the trailer lies along it
	var face_road := -side * deg_to_rad(15.0 + dice.randf() * 10.0)
	if shape == "trailer":
		face_road = -side * deg_to_rad(70.0)
	root.rotation = Vector3(0.0, face_road, 0.0)
	var body := MeshInstance3D.new()
	body.name = "Frame"
	body.mesh = info["mesh"]
	body.material_override = _kit["neon"] if shape == "neon" else _kit["prop"]
	body.extra_cull_margin = 40.0
	root.add_child(body)
	if shape == "neon":
		# the arrow's tubes are their own mesh with the neon material; the frame is plain
		body.material_override = _kit["prop"]
		var tubes := MeshInstance3D.new()
		tubes.name = "Neon"
		tubes.mesh = info["neon_mesh"]
		tubes.material_override = _kit["neon"]
		tubes.extra_cull_margin = 40.0
		tubes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(tubes)
		for p: Vector3 in info["neon_glows"]:
			Geo.add_glow(_kit, root, p, Color(2.2, 0.5, 0.9), 2.2, true)
	var size: Vector2 = info["size"]
	var m := ShaderMaterial.new()
	m.shader = PICTURE_SHADER
	m.set_shader_parameter("picture", tex)
	m.set_shader_parameter("crop", _fit(tex, size))
	m.set_shader_parameter("faded", float(info["faded"]))
	m.set_shader_parameter("cloud_noise", Geo.SKY_NOISE)
	m.set_shader_parameter("rock_noise", Geo.ROCK_NOISE)
	_active.append(m)
	root.set_meta("mats", [m])
	for xf: Transform3D in info["faces"]:
		var q := QuadMesh.new()
		q.size = size
		var mi := MeshInstance3D.new()
		mi.name = "Picture"
		mi.mesh = q
		mi.material_override = m
		mi.extra_cull_margin = 40.0
		root.add_child(mi)
		mi.transform = xf
	for p: Vector3 in info["lamps"]:
		Geo.add_glow(_kit, root, p, Color(1.5, 1.35, 1.0), 0.9)


## The picture's size on a board of `shape` (width, height in metres) for a picture `aspect`
## (width / height) wide: the largest of that shape that fits in the shape's BOX. The aspect is
## held between ASPECT_MIN and ASPECT_MAX and rounded to 0.05 steps, so boards of nearly the
## same shape share one mesh.
static func _picture_size(shape: String, aspect: float) -> Vector2:
	var box: Vector2 = BOX[shape]
	var a := snappedf(clampf(aspect, ASPECT_MIN, ASPECT_MAX), 0.05)
	var w := minf(box.x, box.y * a)
	return Vector2(w, w / a)


## Which part of a picture fills a board of `size` (width, height). The board has the picture's
## own shape (_picture_size), so this is the whole picture (bar a sliver from the rounding);
## only one taller or wider than a board can be gets its middle cut to fit, so nothing is
## squashed. Returns the shader's crop (x, y, w, h in UV).
static func _fit(tex: Texture2D, size: Vector2) -> Vector4:
	var tw := float(tex.get_width())
	var th := float(tex.get_height())
	if tw <= 0.0 or th <= 0.0:
		return Vector4(0.0, 0.0, 1.0, 1.0)
	var board := size.x / size.y
	var pic := tw / th
	if pic > board:
		var w := board / pic
		return Vector4((1.0 - w) * 0.5, 0.0, w, 1.0)
	var h := pic / board
	return Vector4(0.0, (1.0 - h) * 0.5, 1.0, h)


## The frame mesh of a shape for a picture `aspect` (width / height) wide (built once per shape
## and picture shape), where its picture faces go (two, back to back), the picture's size, its
## lamps, and how faded the picture looks.
## Rule for every shape: nothing stands in front of a picture face. Posts end at the picture's
## bottom edge (inside the frame's rim), lamps reach out from the top edge, and whatever sits
## below a board (catwalk, roof, wheels) stays close under it, so it can't cover the picture
## from a camera down on the road.
func _shape(shape: String, aspect: float) -> Dictionary:
	var size := _picture_size(shape, aspect)
	var cache_key := "%s:%.2f" % [shape, size.x / size.y]
	if _shape_cache.has(cache_key):
		return _shape_cache[cache_key]
	var b := Geo.Buf.new()
	var faces: Array[Transform3D] = []
	var lamps: Array[Vector3] = []
	var faded := 0.0
	var info: Dictionary = {}
	var steel := Color(0.42, 0.42, 0.44)
	var back := Basis(Vector3.UP, PI)
	var half := size * 0.5
	match shape:
		"classic":
			# two steel posts, the board, a catwalk under it, four lamps on arms over its top
			var y := 5.7 + half.y                      # the picture's middle; its bottom edge 5.7 m up
			b.mat = Geo.MAT_RUST
			for sx: float in [-1.0, 1.0]:
				b.rod(Vector3(sx * half.x * 0.65, -0.5, 0.0), Vector3(sx * half.x * 0.65, y - half.y, 0.0), 0.2, 8, steel)
			b.mat = Geo.MAT_PAINT
			b.block(Vector3(0.0, y, 0.0), Vector3(size.x + 0.3, size.y + 0.3, 0.25), Color(0.25, 0.25, 0.27))
			b.mat = Geo.MAT_RUST
			# (the catwalk is narrow and half a metre under the picture: out of the way from below)
			b.block(Vector3(0.0, y - half.y - 0.5, 0.0), Vector3(size.x, 0.06, 0.9), steel)
			_top_lamps(b, lamps, 4, half.x - 1.0, y + half.y, 0.13, steel)
			faces.append(Transform3D(Basis.IDENTITY, Vector3(0.0, y, 0.14)))
			faces.append(Transform3D(back, Vector3(0.0, y, -0.14)))
		"monopole":
			# a tall single pole with the board on top, three lamps over it
			var y := 10.0 + half.y
			b.mat = Geo.MAT_RUST
			b.cyl(Transform3D(Basis.IDENTITY, Vector3(0.0, -0.5, 0.0)), 0.45, 0.35, y - half.y + 0.5, 12, steel)
			b.mat = Geo.MAT_PAINT
			b.block(Vector3(0.0, y, 0.0), Vector3(size.x + 0.3, size.y + 0.3, 0.3), Color(0.2, 0.2, 0.22))
			_top_lamps(b, lamps, 3, half.x - 1.2, y + half.y, 0.15, steel)
			faces.append(Transform3D(Basis.IDENTITY, Vector3(0.0, y, 0.16)))
			faces.append(Transform3D(back, Vector3(0.0, y, -0.16)))
		"wooden":
			# a weathered, slightly leaning wooden sign on three posts; its picture sun-bleached
			faded = 0.7
			var y := 1.3 + half.y
			var lean := Basis(Vector3.FORWARD, deg_to_rad(2.5))
			b.mat = Geo.MAT_WOOD
			for sx: float in [-0.84, 0.0, 0.84]:
				b.rod(Vector3(sx * half.x, -0.4, 0.0), lean * Vector3(sx * half.x, y - half.y, 0.0), 0.11, 6, Color(0.5, 0.42, 0.34))
			b.box(Transform3D(lean, Vector3(0.0, y, 0.0)), Vector3(size.x + 0.3, size.y + 0.3, 0.12), Color(0.55, 0.47, 0.38))
			faces.append(Transform3D(lean, lean * Vector3(0.0, y, 0.07)))
			faces.append(Transform3D(lean * back, lean * Vector3(0.0, y, -0.07)))
		"rooftop":
			# an old roadside stop (a small flat-roofed shack) with the board on legs on its roof,
			# high enough that the roof's edge doesn't cover the picture from the road
			Geo.building(b, Vector3(0.0, 0.0, 0.0), Vector3(5.0, 2.8, 3.4), 0.0, Color(0.78, 0.68, 0.55), Color(0.4, 0.3, 0.25), false, 2, true)
			var y := 3.9 + half.y
			b.mat = Geo.MAT_RUST
			for sx: float in [-0.8, 0.8]:
				b.rod(Vector3(sx * half.x, 2.8, 0.0), Vector3(sx * half.x, y - half.y, 0.0), 0.07, 5, steel)
				# a brace from each leg down to the roof, behind and in front
				for sz: float in [-1.0, 1.0]:
					b.rod(Vector3(sx * half.x, y - half.y - 0.1, 0.0), Vector3(sx * half.x, 2.8, sz * 1.0), 0.04, 4, steel)
			b.mat = Geo.MAT_PAINT
			b.block(Vector3(0.0, y, 0.0), Vector3(size.x + 0.25, size.y + 0.25, 0.15), Color(0.25, 0.25, 0.27))
			_top_lamps(b, lamps, 2, half.x - 1.1, y + half.y, 0.08, steel)
			faces.append(Transform3D(Basis.IDENTITY, Vector3(0.0, y, 0.09)))
			faces.append(Transform3D(back, Vector3(0.0, y, -0.09)))
		"neon":
			# a board on two posts with a big bent neon arrow pointing down at it from the side
			# (the arrow stays above the picture's top edge)
			var y := 2.9 + half.y
			var top := y + half.y
			var pole_x := -(half.x + 1.8)
			b.mat = Geo.MAT_RUST
			for sx: float in [-0.7, 0.7]:
				b.rod(Vector3(sx * half.x, -0.4, 0.0), Vector3(sx * half.x, y - half.y, 0.0), 0.12, 6, steel)
			b.mat = Geo.MAT_PAINT
			b.block(Vector3(0.0, y, 0.0), Vector3(size.x + 0.3, size.y + 0.3, 0.2), Color(0.15, 0.12, 0.2))
			var tubes := Geo.Buf.new()
			tubes.mat = Geo.MAT_LIGHT
			var pink := Color(1.0, 0.3, 0.6)
			var tip := Vector3(0.0, top + 0.9, 0.3)
			var path: Array[Vector3] = [Vector3(pole_x, top + 2.1, 0.3), Vector3(-1.2, top + 2.1, 0.3), tip]
			var path2: Array[Vector3] = [tip, tip + Vector3(-0.9, -0.2, 0.0)]
			var path3: Array[Vector3] = [tip, tip + Vector3(-0.15, 0.9, 0.0)]
			var glows: Array[Vector3] = []
			for line: Array[Vector3] in [path, path2, path3]:
				for i in line.size() - 1:
					tubes.rod(line[i], line[i + 1], 0.07, 6, pink)
					glows.append(line[i].lerp(line[i + 1], 0.5))
			b.mat = Geo.MAT_RUST
			b.rod(Vector3(pole_x, -0.4, 0.0), Vector3(pole_x, top + 2.3, 0.0), 0.1, 6, steel)
			b.rod(Vector3(pole_x, top + 2.1, 0.0), Vector3(pole_x, top + 2.1, 0.3), 0.04, 4, steel)
			info["neon_mesh"] = tubes.to_mesh()
			info["neon_glows"] = glows
			faces.append(Transform3D(Basis.IDENTITY, Vector3(0.0, y, 0.11)))
			faces.append(Transform3D(back, Vector3(0.0, y, -0.11)))
		"trailer":
			# an old box trailer parked in the dirt, the picture painted on both its long sides
			# (the wheels are tucked under the body, below the picture)
			var cream := Color(0.82, 0.78, 0.7)
			b.mat = Geo.MAT_RUST
			b.block(Vector3(0.0, 1.95, 0.0), Vector3(2.4, 2.6, 7.0), cream)
			b.mat = Geo.MAT_PAINT
			for z: float in [-2.4, 2.4]:
				for sx: float in [-1.0, 1.0]:
					b.cyl(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(sx * 1.2, 0.42, z)), 0.42, 0.42, 0.3, 10, Color(0.06, 0.06, 0.06))
			b.block(Vector3(0.0, 0.6, -4.0), Vector3(0.15, 0.15, 1.2), steel)
			# a picture face on each long side (its quad turned to lie along the trailer)
			var side_turn := Basis(Vector3.UP, PI * 0.5)
			faces.append(Transform3D(side_turn, Vector3(1.22, 2.0, 0.0)))
			faces.append(Transform3D(side_turn * back, Vector3(-1.22, 2.0, 0.0)))
	b.mat = Geo.MAT_PAINT
	info["mesh"] = b.to_mesh()
	info["faces"] = faces
	info["lamps"] = lamps
	info["size"] = size
	info["faded"] = faded
	if not info.has("neon_glows"):
		info["neon_glows"] = [] as Array[Vector3]
	_shape_cache[cache_key] = info
	return info


## A row of `count` lamps on short arms reaching out over a board's top edge (y = top) on its
## front face, spread from -reach to +reach across it; `face_z` is how far the face stands out.
## Each lamp's spot is added to `lamps` (the glare squares _place puts there).
static func _top_lamps(b: Geo.Buf, lamps: Array[Vector3], count: int, reach: float, top: float, face_z: float, steel: Color) -> void:
	for i in count:
		var x := lerpf(-reach, reach, float(i) / float(maxi(count - 1, 1)))
		b.mat = Geo.MAT_RUST
		b.rod(Vector3(x, top + 0.1, face_z), Vector3(x, top + 0.35, face_z + 0.75), 0.03, 4, steel)
		b.mat = Geo.MAT_LIGHT
		b.block(Vector3(x, top + 0.35, face_z + 0.8), Vector3(0.3, 0.12, 0.2), Color(1.0, 0.9, 0.7))
		lamps.append(Vector3(x, top + 0.3, face_z + 0.95))
