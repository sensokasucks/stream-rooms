@tool
class_name AudienceRow
extends Marker3D
## A row of audience seats for the chat audience. Put it on the seat surface of the
## first seat; seats run along the node's local +X. Either set count + spacing, or list
## each seat's X offset in `offsets` (for uneven rows). Seats right where a CAM_ marker
## sits are skipped automatically, so the audience never blocks a camera.
## Single seats can also come from Blender as empties named AUDIENCE_<anything>.

@export var count: int = 6
@export var spacing: float = 0.6
## If not empty, one seat per value (metres along local X); count/spacing are ignored.
@export var offsets: PackedFloat32Array = []
## Size of the silhouettes in this row (1 = adult).
@export var seat_scale: float = 1.0


func get_seat_transforms() -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	var xs: Array[float] = []
	if offsets.is_empty():
		for i in maxi(count, 0):
			xs.append(i * spacing)
	else:
		for x in offsets:
			xs.append(x)
	for x in xs:
		var t := global_transform * Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * seat_scale), Vector3(x, 0, 0))
		out.append(t)
	return out
