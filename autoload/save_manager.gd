extends Node
## SaveManager: persists AppState settings to user://settings.cfg.
## Saves are debounced so dragging a slider doesn't write the file every frame.

const PATH: String = "user://settings.cfg"
const SECTION: String = "settings"
const SAVE_DELAY: float = 0.75

var _timer: Timer


func _ready() -> void:
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.wait_time = SAVE_DELAY
	_timer.timeout.connect(save_now)
	add_child(_timer)
	load_settings()
	EventBus.setting_changed.connect(_on_setting_changed)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	var saved: Dictionary = {}
	for key in cfg.get_section_keys(SECTION) if cfg.has_section(SECTION) else PackedStringArray():
		saved[key] = cfg.get_value(SECTION, key)
	AppState.apply_saved_settings(saved)


func save_now() -> void:
	var cfg := ConfigFile.new()
	var all := AppState.get_all_settings()
	for key in all.keys():
		cfg.set_value(SECTION, key, all[key])
	var err := cfg.save(PATH)
	if err != OK:
		push_warning("Could not save settings (%d)" % err)


func _on_setting_changed(_key: String, _value: Variant) -> void:
	_timer.start()


func _exit_tree() -> void:
	if _timer and not _timer.is_stopped():
		save_now()
