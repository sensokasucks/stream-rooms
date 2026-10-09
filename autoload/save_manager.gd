extends Node
## SaveManager: persists AppState settings to user://settings.cfg
## (user://settings_<profile>.cfg when started with --mp-profile, see AppState.get_settings_path).
## Saves are debounced so dragging a slider doesn't write the file every frame.
## A save writes a new file next to the old one and then swaps it in, keeping the previous one
## as settings.cfg.bak: a crash in the middle of a save can't leave a cut-off settings file (that
## would quietly bring back every default). Loading falls back to the .bak if the file is broken.

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
	var path := AppState.get_settings_path()
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		# missing (first start) or broken: try the copy from the save before
		cfg = ConfigFile.new()
		if not FileAccess.file_exists(path + ".bak") or cfg.load(path + ".bak") != OK:
			return
		push_warning("Settings file couldn't be read; using the backup from the save before.")
	var saved: Dictionary = {}
	for key in cfg.get_section_keys(SECTION) if cfg.has_section(SECTION) else PackedStringArray():
		saved[key] = cfg.get_value(SECTION, key)
	AppState.apply_saved_settings(saved)


func save_now() -> void:
	var cfg := ConfigFile.new()
	var all := AppState.get_all_settings()
	for key in all.keys():
		cfg.set_value(SECTION, key, all[key])
	var path := AppState.get_settings_path()
	var tmp := path + ".tmp"
	var err := cfg.save(tmp)
	if err != OK:
		push_warning("Could not save settings (%d)" % err)
		return
	var abs_path := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(abs_path + ".bak")
		DirAccess.rename_absolute(abs_path, abs_path + ".bak")
	err = DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), abs_path)
	if err != OK:
		push_warning("Could not save settings (%d)" % err)


func _on_setting_changed(_key: String, _value: Variant) -> void:
	_timer.start()


func _exit_tree() -> void:
	if _timer and not _timer.is_stopped():
		save_now()
