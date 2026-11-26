extends RefCounted
## The Lakeside Campfire's detailed trees, drawn at three levels of detail for frame rate.
## Called by campfire_builder.gd (_build_detailed_plants), which says where every tree stands;
## campfire_room.gd keeps the levels pointed at the camera (update_eye). Everything here is
## static: no instance of this exists.
##
## The trees themselves are Blender models (models/trees.glb, written by models/make_trees.py,
## after Sen's Blender forest tutorial): real branching trunks and limbs with leaf and needle
## "cards". Each species comes twice: _lod0 (everything) and _lod1 (no small branches, a third
## as many cards, bigger). make_trees.py also photographed each one from eight sides into
## textures/impostor_color.png / impostor_normal.png, and a far tree is just that picture on
## one square turned to the camera (camp_impostor.gdshader).
##
## How a tree picks its level: every level of every species is a MultiMesh holding the trees
## of one square patch of ground (LEVELS: small patches for the full trees, big ones for the
## light trees and the pictures, so there are few draw calls). The shaders fold away each tree whose distance
## from the camera is outside its level's band (in each tree's MultiMesh custom data, .g = from
## and .b = to, in metres from the material's `lod_eye`), so each tree is drawn at exactly one
## level and switches on its own. (Not an instance uniform: camp_prop.gdshader is on hundreds of
## the room's meshes, and every one of them would take a slot of the engine's small table.)
## The patches let Redot skip whole MultiMeshes that are far outside a band (their visibility
## range), so the GPU does not even look at most of the full trees far away. Each level has its
## own patches: whether a tree shows depends only on its own distance, never on its patch.
##
## Surfaces in trees.glb by material name (make_trees.py; change both together):
##   trunk -> the plant materials' "trunk" (camp_prop.gdshader, bark by UV.x)
##   needles_fir, needles_pine, twigs_oak, twigs_maple, twigs_birch -> LEAF_MATERIAL below

const MODELS := "res://rooms/campfire/models/trees.glb"
const IMPOSTOR_SHADER := preload("res://rooms/campfire/camp_impostor.gdshader")
const FOLIAGE_SHADER := preload("res://rooms/campfire/camp_foliage.gdshader")
const TEX := "res://rooms/campfire/textures/"

## The species, in the impostor sheets' row order (make_trees.py SPECIES).
const SPECIES: PackedStringArray = ["fir", "young_fir", "pine", "oak", "maple", "birch"]
## Which plant material (the builder's plant_mats keys) each card material in trees.glb gets.
const LEAF_MATERIAL: Dictionary = {"needles_fir": "fir", "needles_pine": "pine",
	"twigs_oak": "leaves", "twigs_maple": "leaves_maple", "twigs_birch": "leaves_birch"}
## The twig pictures make_trees.py draws, for the leafy species' card materials.
const TWIG_PICTURE: Dictionary = {"leaves": "twig_oak.png", "leaves_maple": "twig_maple.png", "leaves_birch": "twig_birch.png"}
## Where the levels change, in metres from the camera: full trees up to LOD1_FROM, the light
## ones up to IMPOSTOR_FROM, pictures beyond.
const LOD1_FROM: float = 16.0
const IMPOSTOR_FROM: float = 34.0
## The levels: [node name prefix, patch size in metres, band from, band to]. A bigger patch means
## fewer draw calls but more trees the GPU looks at and folds away; the full trees are the
## heavy ones, so theirs are small. The bands travel in MultiMesh custom data, which the
## Compatibility renderer keeps as half floats: keep them below 65000.
const LEVELS: Array = [["Full", 12.0, 0.0, LOD1_FROM], ["Light", 32.0, LOD1_FROM, IMPOSTOR_FROM], ["Far", 48.0, IMPOSTOR_FROM, 60000.0]]
## Must match make_trees.py IMPOSTOR_FRAMES and IMP_HALF.
const IMPOSTOR_FRAMES: int = 8
const IMPOSTOR_HALF: float = 0.6


## Makes the materials the Blender trees need on top of the builder's plant materials
## (campfire_trees.gd materials()) and puts them into the same dictionary:
##   leaves, leaves_maple, leaves_birch   now show the small-leaved twig pictures (the Blender
##                                         trees' twig cards are a fraction of the old cards' size)
##   impostor                             the far trees (camp_impostor.gdshader)
## Fir, pine and trunk stay as they are. Only the Lakeside Campfire calls this: the other rooms
## that borrow campfire_trees.gd keep its own leaf cards.
static func add_materials(mats: Dictionary) -> void:
	for key: String in TWIG_PICTURE:
		var m := mats[key] as ShaderMaterial
		m.set_shader_parameter("card", load(TEX + String(TWIG_PICTURE[key])))
		m.set_shader_parameter("tint", Color(1.0, 1.0, 1.0))
	var imp := ShaderMaterial.new()
	imp.shader = IMPOSTOR_SHADER
	imp.set_shader_parameter("color_sheet", load(TEX + "impostor_color.png"))
	imp.set_shader_parameter("normal_sheet", load(TEX + "impostor_normal.png"))
	imp.set_shader_parameter("frames", float(IMPOSTOR_FRAMES))
	imp.set_shader_parameter("rows", float(SPECIES.size()))
	imp.set_shader_parameter("half_size", IMPOSTOR_HALF)
	var leafy := PackedFloat32Array()
	for s in SPECIES:
		leafy.append(1.0 if s in ["oak", "maple", "birch"] else 0.0)
	imp.set_shader_parameter("leafy", leafy)
	mats["impostor"] = imp


## The meshes from trees.glb with the room's materials on them: species -> [lod0, lod1].
## Copies, so the imported file is never changed.
static func meshes(mats: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var scene := load(MODELS) as PackedScene
	if scene == null:
		push_warning("campfire_forest: %s did not load" % MODELS)
		return out
	var root := scene.instantiate()
	for species in SPECIES:
		var pair: Array[Mesh] = []
		for lod in 2:
			var mi := root.find_child("%s_lod%d" % [species, lod], true, false) as MeshInstance3D
			if mi == null:
				push_warning("campfire_forest: %s_lod%d is missing from trees.glb" % [species, lod])
				root.free()
				return {}
			var mesh := mi.mesh.duplicate() as ArrayMesh
			for s in mesh.get_surface_count():
				var mat_name := mesh.surface_get_material(s).resource_name if mesh.surface_get_material(s) else ""
				mat_name = mat_name.get_slice(".", 0)
				var key := "trunk" if mat_name == "trunk" else String(LEAF_MATERIAL.get(mat_name, "fir"))
				mesh.surface_set_material(s, mats[key])
			pair.append(mesh)
		out[species] = pair
	root.free()
	return out


## The far trees' one square, 1 unit across: camp_impostor.gdshader moves its corners, so only
## its UVs and its bounds matter (the bounds are the whole picture, so the camera's culling is right).
static func impostor_mesh() -> ArrayMesh:
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-0.5, 0, 0), Vector3(0.5, 0, 0), Vector3(0.5, 1, 0), Vector3(-0.5, 1, 0)])
	arr[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK, Vector3.BACK])
	arr[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)])
	arr[Mesh.ARRAY_COLOR] = PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE])
	arr[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var h := IMPOSTOR_HALF
	mesh.custom_aabb = AABB(Vector3(-h, 0.0, -h), Vector3(2.0 * h, 2.0 * h, 2.0 * h))
	return mesh


## Builds one group of trees (a holder node, built hidden like the builder's other detailed
## groups). `trees`: species -> [Array[Transform3D] where each stands and how big, PackedColorArray
## each one's tint]. `kit`: meshes(). Returns the holder.
##
## Inside: for each level (LEVELS) one Node3D per patch ("Full_x_z", "Light_x_z", "Far_x_z",
## placed at the patch's middle). A Full or Light patch holds a MultiMeshInstance3D per species
## ("Oak"); a Far patch one for all its pictures ("Trees"). Each has its band (also kept as its
## "lod_band" metadata, for the test) and a visibility range half a patch's diagonal wider than
## the band, so whole patches far outside it are skipped.
static func build(parent: Node3D, holder_name: String, trees: Dictionary, kit: Dictionary, mats: Dictionary) -> Node3D:
	var holder := Node3D.new()
	holder.name = holder_name
	holder.visible = false
	parent.add_child(holder)
	if kit.is_empty():
		return holder
	var far_mesh := impostor_mesh()
	for level in LEVELS.size():
		var prefix: String = LEVELS[level][0]
		var size: float = LEVELS[level][1]
		var band := Vector2(float(LEVELS[level][2]), float(LEVELS[level][3]))
		var reach := size * 0.75                 # a little more than half a patch's diagonal
		# patch -> species -> [spots, tints]
		var cells: Dictionary = {}
		for species: String in trees:
			var spots: Array = trees[species][0]
			var tints: PackedColorArray = trees[species][1]
			for i in spots.size():
				var xf: Transform3D = spots[i]
				var key := Vector2i(floori(xf.origin.x / size), floori(xf.origin.z / size))
				if not cells.has(key):
					cells[key] = {}
				var cell: Dictionary = cells[key]
				if not cell.has(species):
					var none: Array[Transform3D] = []
					cell[species] = [none, PackedColorArray()]
				(cell[species][0] as Array[Transform3D]).append(xf)
				var t: PackedColorArray = cell[species][1]
				t.append(tints[i])
				cell[species][1] = t             # (a PackedColorArray is copied when read out of an Array)
		for key: Vector2i in cells:
			var node := Node3D.new()
			node.name = "%s_%d_%d" % [prefix, key.x, key.y]
			var mid := Vector3((float(key.x) + 0.5) * size, 0.0, (float(key.y) + 0.5) * size)
			node.position = mid
			holder.add_child(node)
			var cell: Dictionary = cells[key]
			var far_spots: Array[Transform3D] = []
			var far_tints := PackedColorArray()
			var far_rows := PackedFloat32Array()
			for species: String in cell:
				var local: Array[Transform3D] = []
				for xf: Transform3D in cell[species][0]:
					local.append(Transform3D(xf.basis, xf.origin - mid))
				var tints: PackedColorArray = cell[species][1]
				if level < 2:
					_level(node, species.to_pascal_case(), (kit[species] as Array)[level], local, tints, PackedFloat32Array(), band, reach)
				else:
					far_spots.append_array(local)
					far_tints.append_array(tints)
					for i in local.size():
						far_rows.append(float(SPECIES.find(species)))
			if level == 2:
				var far := _level(node, "Trees", far_mesh, far_spots, far_tints, far_rows, band, reach)
				far.material_override = mats["impostor"]
	return holder


## One level of one species in one patch: a MultiMesh of `mesh` at `spots` (relative to the
## patch's node), tinted `tints`. Custom data: r = `rows[i]` (impostors only: the tree's row in
## the picture sheets), g / b = `band` (from / to, metres). `reach`: how much wider the node's
## visibility range is than the band.
static func _level(node: Node3D, node_name: String, mesh: Mesh, spots: Array[Transform3D], tints: PackedColorArray,
		rows: PackedFloat32Array, band: Vector2, reach: float) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = spots.size()
	for i in spots.size():
		mm.set_instance_transform(i, spots[i])
		mm.set_instance_color(i, tints[i])
		mm.set_instance_custom_data(i, Color(rows[i] if not rows.is_empty() else 0.0, band.x, band.y, 0.0))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	mmi.set_meta("lod_band", band)
	mmi.visibility_range_begin = maxf(0.0, band.x - reach)
	mmi.visibility_range_end = band.y + reach
	node.add_child(mmi)
	return mmi


## Points every level at the camera: sets lod_eye on the materials the levels use. Called by
## campfire_room.gd when the camera has moved (not every frame).
static func update_eye(mats: Dictionary, eye: Vector3) -> void:
	for key: String in ["trunk", "fir", "pine", "leaves", "leaves_maple", "leaves_birch", "impostor"]:
		var m := mats.get(key) as ShaderMaterial
		if m:
			m.set_shader_parameter("lod_eye", eye)
