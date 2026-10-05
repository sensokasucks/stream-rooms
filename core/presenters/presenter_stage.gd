class_name PresenterStage
extends Node3D
## Builds a Presenter at every PRESENTER_<n> marker of the room (attached by RoomHost,
## freed with the room) and tells the app how many podiums there are.

var _presenters: Array[Presenter] = []


## setups: Room.get_presenter_setups(); plane_size: Room.presenter_size.
func setup(setups: Array[Dictionary], plane_size: Vector2) -> void:
	for s in setups:
		var p := Presenter.new()
		add_child(p)
		p.setup(int(s["n"]), s["marker"], s.get("podium"), s.get("lamp"), plane_size)
		_presenters.append(p)
	EventBus.room_presenters_changed.emit(_presenters.size())


## The presenter on podium n, or null.
func get_presenter(n: int) -> Presenter:
	for p in _presenters:
		if p.number == n:
			return p
	return null


## presenter n -> Presenter, for every podium in the room.
func get_presenter_map() -> Dictionary:
	var out: Dictionary = {}
	for p in _presenters:
		out[p.number] = p
	return out
