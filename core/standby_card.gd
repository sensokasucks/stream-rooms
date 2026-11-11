class_name StandbyCard
extends Node3D
## A "please stand by" test card shown over the main screen, for rooms that use one instead of
## the red stage curtain (RoomInfo.standby_card holds the picture; the Forge Hall is the first).
## RoomHost attaches it in place of StageCurtain and it keeps the same contract with the rest
## of the app, so B / Shift+B, the Room tab's Curtain controls, Stream Core's !curtain and a
## co-stream all work unchanged:
##   - "closed" (AppState.is_curtain_closed) = the card is showing. EventBus.curtain_changed
##     fades it in or out; style "instant" skips the fade, "reveal" is treated as a plain open.
##   - AppState.set_curtain_present / set_curtain_covering are told the same things the curtain
##     tells them (covering mutes the stream sound and swaps the screen's light on the room).
##   - Settings used: curtain_enabled (off = no card), curtain_speed (fade speed) and
##     curtain_sign (a line of text across the bottom of the card, "" = none). The curtain's
##     colour and sound settings do nothing here.
## The card is drawn on a copy of the screen's own mesh, a few centimetres in front of it, so
## it follows a screen that was moved, resized or bent (rooms/forge_hall/forge_hall_room.gd).

## Distance in front of the screen (metres).
@export var offset: float = 0.03
## The dim light the card throws on the room while it is up (handed to
## AppState.set_curtain_present, read by ScreenLights). A cool grey, like a TV on a test card.
@export var room_glow: Color = Color(0.16, 0.18, 0.22)
## Seconds to fade fully in / out at curtain_speed 1.0.
@export var fade_time: float = 0.7

var _mesh: MeshInstance3D
var _mat: StandardMaterial3D
var _label: Label3D
var _shown: float = 0.0            # 0 = hidden, 1 = fully showing; tweened
var _tween: Tween


## screen: the room's main screen; card: the picture (RoomInfo.standby_card). Called once by
## RoomHost. Starts in the state AppState already has (closed stays closed across room changes).
func setup(screen: MeshInstance3D, card: Texture2D) -> void:
	global_transform = screen.global_transform
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.albedo_texture = card
	_mesh = MeshInstance3D.new()
	_mesh.name = "Card"
	_mesh.mesh = screen.mesh            # the same shape (and UVs) as the screen
	_mesh.material_override = _mat
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# the screen faces its own +Z (the audience): sit just in front of it
	_mesh.position = Vector3(0.0, 0.0, offset)
	add_child(_mesh)
	var box := screen.get_aabb()
	_label = Label3D.new()
	_label.name = "Sign"
	_label.pixel_size = box.size.y / 900.0          # the sign's letters: about 1/12 of the card's height
	_label.font_size = 72
	_label.outline_size = 24
	_label.outline_modulate = Color(0.0, 0.0, 0.0)
	_label.shaded = false
	_label.width = box.size.x * 0.9 / _label.pixel_size
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.position = Vector3(box.get_center().x, box.position.y + box.size.y * 0.1, box.end.z + offset + 0.05)
	add_child(_label)
	_update_sign()
	_shown = 1.0 if AppState.is_curtain_closed() else 0.0
	_apply()
	_refresh_enabled()
	AppState.set_curtain_covering(AppState.is_curtain_closed() and visible)


func _ready() -> void:
	EventBus.curtain_changed.connect(_on_curtain)
	EventBus.setting_changed.connect(_on_setting_changed)


## Leaving with the room: tell AppState there is no card any more.
func _exit_tree() -> void:
	EventBus.curtain_changed.disconnect(_on_curtain)
	EventBus.setting_changed.disconnect(_on_setting_changed)
	AppState.set_curtain_present(self, false)


## 0 = hidden, 1 = fully showing (for tests).
func get_shown_amount() -> float:
	return _shown


## EventBus.curtain_changed from AppState: closed = show the card. "Covering" is set as soon as
## the card starts to appear and cleared as soon as it starts to go, like the curtain.
func _on_curtain(closed: bool, style: String) -> void:
	if not visible:
		return
	if _tween and _tween.is_valid():
		_tween.kill()
	AppState.set_curtain_covering(closed)
	var target := 1.0 if closed else 0.0
	var speed := clampf(float(AppState.get_setting("curtain_speed")), 0.25, 4.0)
	var dur := fade_time / speed * absf(target - _shown)
	if style == "instant" or dur < 0.05:
		_shown = target
		_apply()
		return
	_tween = create_tween()
	_tween.tween_method(func(v: float) -> void:
		_shown = v
		_apply(), _shown, target, dur)


## Shows the card at its current strength (it is not drawn at all while fully hidden).
func _apply() -> void:
	_mat.albedo_color = Color(1.0, 1.0, 1.0, _shown)
	_mesh.visible = _shown > 0.002
	_label.visible = _mesh.visible and _label.text != ""
	_label.modulate = Color(1.0, 1.0, 1.0, _shown)
	_label.outline_modulate = Color(0.0, 0.0, 0.0, _shown)


func _on_setting_changed(key: String, _value: Variant) -> void:
	if key == "curtain_enabled":
		_refresh_enabled()
	elif key == "curtain_sign":
		_update_sign()
		_apply()


## "curtain_enabled" off: no card in this room, and a closed curtain opens (as StageCurtain does).
func _refresh_enabled() -> void:
	var on := bool(AppState.get_setting("curtain_enabled"))
	visible = on
	AppState.set_curtain_present(self, on, room_glow)
	if not on and AppState.is_curtain_closed():
		AppState.set_curtain(false, "instant")


## "curtain_sign": the text across the bottom of the card (chat-safe: it may come from Core).
func _update_sign() -> void:
	_label.text = SafeText.clean(String(AppState.get_setting("curtain_sign")).strip_edges())
