extends Node
## Autoload: game-wide state, save file and audio settings.
##
## Keeps the menu and the gameplay apart: the menu only talks to this singleton,
## and this singleton knows nothing about either scene.

const SAVE_PATH := "user://lunabun_save.json"

## Where the rabbit currently is, so ПРОДОЛЖИТЬ can put it back.
var has_progress := false
var scene_path := "res://scenes/burrow_inside.tscn"
var rabbit_x := 50.0
var has_slept := false

## Settings, mirrored into the audio buses.
var music_volume := 0.8
var sfx_volume := 0.8
var fullscreen := false
## 0.5 is neutral. The settings screen moves it.
var brightness := 0.5

# --- flags used while moving between scenes -------------------------------
var entering_burrow := false
var leaving_burrow := false
var returning_from_burrow := false
var forest_spawn_x := 300.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_apply_settings()
	load_game()


# ---------------------------------------------------------------- progress
func remember_position(path: String, x: float) -> void:
	scene_path = path
	rabbit_x = x
	has_progress = true


## The story keeps its own progress; these two hand it over safely.
func _story_data() -> Dictionary:
	if Story == null:
		return {}
	return Story.to_save()


func _apply_story(data: Dictionary) -> void:
	if Story != null and typeof(data) == TYPE_DICTIONARY:
		Story.from_save(data)


func set_brightness(value: float) -> void:
	brightness = clampf(value, 0.0, 1.0)


func reset_progress() -> void:
	if Story != null:
		Story.reset()
	has_progress = false
	scene_path = "res://scenes/burrow_inside.tscn"
	rabbit_x = 50.0
	has_slept = false


func start_new_game() -> void:
	reset_progress()
	get_tree().paused = false
	get_tree().change_scene_to_file(scene_path)


func continue_game() -> bool:
	if not has_progress:
		return false
	load_game()
	get_tree().paused = false
	get_tree().change_scene_to_file(scene_path)
	return true


# -------------------------------------------------------------------- save
func save_game() -> bool:
	var data := {
		"scene_path": scene_path,
		"rabbit_x": rabbit_x,
		"has_slept": has_slept,
		"music_volume": music_volume,
		"sfx_volume": sfx_volume,
		"fullscreen": fullscreen,
		"brightness": brightness,
		"story": _story_data(),
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data, "  "))
	f.close()
	has_progress = true
	return true


func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return false
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	var d: Dictionary = parsed
	scene_path = str(d.get("scene_path", scene_path))
	rabbit_x = float(d.get("rabbit_x", rabbit_x))
	has_slept = bool(d.get("has_slept", has_slept))
	music_volume = float(d.get("music_volume", music_volume))
	sfx_volume = float(d.get("sfx_volume", sfx_volume))
	fullscreen = bool(d.get("fullscreen", fullscreen))
	brightness = float(d.get("brightness", brightness))
	has_progress = true
	# The story autoload may not exist yet while the game is booting, so it is
	# filled in on the next idle frame.
	_apply_story.call_deferred(d.get("story", {}))
	_apply_settings()
	return true


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


# ---------------------------------------------------------------- settings
func set_music_volume(v: float) -> void:
	music_volume = clampf(v, 0.0, 1.0)
	_apply_settings()


func set_sfx_volume(v: float) -> void:
	sfx_volume = clampf(v, 0.0, 1.0)
	_apply_settings()


func set_fullscreen(on: bool) -> void:
	fullscreen = on
	_apply_settings()


func _apply_settings() -> void:
	_set_bus("Music", music_volume)
	_set_bus("SFX", sfx_volume)
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	DisplayServer.window_set_mode(mode)


func _set_bus(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.0001)))
	AudioServer.set_bus_mute(idx, linear <= 0.001)
