extends Node
## Autoload: the story of Lunabun.
##
## Holds the whole narrative - the opening, what every inhabitant and every
## found object says, the moon shards, the two keepers and the three endings -
## plus the dialogue box, the progress flags and the save/load of that progress.
##
## The rule the design asks for is followed everywhere here: nobody explains the
## mystery. The player assembles it from short lines, notes and the world.

# ------------------------------------------------------------------ opening
const INTRO := []

## The chapters, in the order the player lives them.
const CHAPTERS := [
	"Тьма", "Первый свет", "Заброшенная деревня", "Туманная река",
	"Светящаяся роща", "Заброшенная часовня", "Чёрный зайчик", "Сердце леса",
]

# ------------------------------------------------------------------ who talks
const PEOPLE := {
	"firefly": {
		"name": "Блуждающий огонёк",
		"colour": Color(1.0, 0.95, 0.70),
		"lines": [],
	},
	"owl": {
		"name": "Ночной дух",
		"colour": Color(0.78, 0.84, 1.0),
		"lines": [],
	},
	"fox": {
		"name": "Старый дух",
		"colour": Color(1.0, 0.72, 0.48),
		"lines": [],
	},
	"spirit": {
		"name": "Лесной дух",
		"colour": Color(0.72, 1.0, 0.86),
		"lines": [],
	},
	"keeper": {
		"name": "Хранитель норы",
		"colour": Color(0.84, 0.93, 1.0),
		"lines": [],
	},
	"black": {
		"name": "Чёрный дух",
		"colour": Color(0.58, 0.64, 0.74),
		"lines": [],
	},
}

# ------------------------------------------------------------------ what is left
const NOTES := {
	"tracks": {
		"name": "Странные следы",
		"lines": [],
	},
	"sign": {
		"name": "Старая табличка",
		"lines": [],
	},
	"lamp": {
		"name": "Старый фонарь",
		"lines": [],
	},
	"river": {
		"name": "Отражение в воде",
		"lines": [],
	},
	"book": {
		"name": "Старая записная книжка",
		"lines": [],
	},
	"statue": {
		"name": "Старые изображения",
		"lines": [],
	},
}

## Endings, and what the game says at the very end.
const ENDINGS := {
	"light": {
		"title": "СВЕТ",
		"lines": [],
		"note": "Светлый хранитель и чёрный дух стоят вместе под луной.",
	},
	"balance": {
		"title": "РАВНОВЕСИЕ",
		"lines": [],
		"note": "Теперь в лесу живут и свет, и тьма.",
	},
	"secret": {
		"title": "СВЕТ И ТЬМА",
		"lines": [],
		"note": "Оба хранителя вместе под восстановленной луной.",
	},
}

const SHARD_TOTAL := 6

# ------------------------------------------------------------------ progress
var intro_seen := false
var shards := 0
var notes := {}
var met_black := false
var saw_images := false
var choice := ""
var ending := ""

var _layer: CanvasLayer
var _box: PanelContainer
var _name: Label
var _text: Label
var _hint: Label
var _end_title: Label
var _end_note: Label
var _queue: Array = []
var _speaker := ""
var _open := false
var _locked_by_me := false
var _ending_shown := false
## Which scene the dialogue was opened in.
var _scene_path := ""
## The camera height the rabbit is normally framed at.
var _cam_rest_y := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	set_process(true)


func _process(_delta: float) -> void:
	# A conversation never survives a change of place: if the scene moves on
	# underneath it, it is closed.
	var scene := get_tree().current_scene
	var here: String = ""
	if scene != null:
		here = scene.scene_file_path
	if _open and here != _scene_path:
		_scene_path = here
		_close()
		return
	_scene_path = here
	# The dialogue owns the input while it is up. R, E, Enter and Space all move
	# it on, and Escape leaves at once - never being able to get out of a
	# conversation is the one thing that must not happen.
	if _open:
		if Input.is_action_just_pressed("ui_cancel"):
			_close()
		elif (Input.is_action_just_pressed("talk")
				or Input.is_action_just_pressed("interact")
				or Input.is_action_just_pressed("ui_accept")):
			advance()
	if _open and not _locked_by_me:
		_lock(true)
	elif not _open and _locked_by_me:
		_lock(false)


func _lock(locked: bool) -> void:
	_locked_by_me = locked
	# The camera comes in closer while the rabbit is talking to someone.
	_zoom_camera(locked)
	var scene := get_tree().current_scene
	if scene == null:
		return
	var rabbit := scene.get_node_or_null("Rabbit")
	if rabbit != null and rabbit.get("input_locked") != null:
		rabbit.input_locked = locked


# ------------------------------------------------------------------ the amulet
## 0 = almost dead, 4 = full moonlight. Drives how brightly the pendant burns.
func pendant_power() -> int:
	if shards <= 0:
		return 0
	return clampi(1 + int(floor(float(shards - 1) / float(SHARD_TOTAL - 1) * 3.0)), 0, 4)


func total_found() -> int:
	var n := shards + notes.size()
	if met_black:
		n += 1
	return n


## Everything the true ending needs.
func knows_the_whole_story() -> bool:
	return shards >= SHARD_TOTAL and notes.size() >= NOTES.size() \
		and met_black and saw_images


# ------------------------------------------------------------------ progress
func found_shard() -> int:
	shards = clampi(shards + 1, 0, SHARD_TOTAL)
	return shards


func found_note(id: String) -> bool:
	if notes.has(id):
		return false
	notes[id] = true
	if id == "statue":
		saw_images = true
	return true


func note_seen(id: String) -> bool:
	return notes.has(id)


func mark_met(who: String) -> bool:
	if who == "black":
		met_black = true
	return true


## Called by the Heart of the Forest. `which` is "light" or "balance".
func finale(which: String) -> void:
	choice = which
	# The true ending is earned, not offered: it needs the whole story.
	if which == "light" and knows_the_whole_story():
		ending = "secret"
	else:
		ending = which
	var data: Dictionary = ENDINGS[ending]
	tell("", data["lines"])
	_show_ending_title(str(data["title"]), str(data["note"]))


# ------------------------------------------------------------------ the box
func _build_ui() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 175
	_layer.visible = false
	add_child(_layer)

	var root := Control.new()
	root.size = Vector2(1280.0, 720.0)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(root)

	_box = PanelContainer.new()
	_box.position = Vector2(90.0, 520.0)
	_box.custom_minimum_size = Vector2(1100.0, 150.0)
	var sb := StyleBoxFlat.new()
	# Same stylebox recipe as the menu panel, for the same shader.
	sb.bg_color = Color(0.60, 0.70, 0.94, 0.0)
	sb.border_color = Color(0.60, 0.70, 0.94, 1.0)
	sb.border_blend = true
	sb.set_border_width_all(18)
	sb.set_corner_radius_all(20)
	sb.shadow_color = Color(0.02, 0.03, 0.08, 0.20)
	sb.shadow_size = 5
	sb.set_content_margin_all(34)
	_box.add_theme_stylebox_override("panel", sb)
	# Liquid glass for the dialogue box too.
	Look.glass(_box, 20.0, 0.80)
	root.add_child(_box)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	_box.add_child(col)

	_name = Label.new()
	_name.add_theme_font_size_override("font_size", 20)
	_name.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.07, 0.92))
	_name.add_theme_constant_override("outline_size", 5)
	col.add_child(_name)

	_text = Label.new()
	_text.add_theme_font_size_override("font_size", 26)
	_text.add_theme_color_override("font_color", Color(0.97, 0.96, 0.92))
	# The same small dark edge the menus use, for the same reason.
	_text.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.07, 0.92))
	_text.add_theme_constant_override("outline_size", 5)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(1040.0, 0.0)
	col.add_child(_text)

	_hint = Label.new()
	_hint.text = "E / Enter — дальше,   ESC — закрыть"
	_hint.add_theme_font_size_override("font_size", 16)
	_hint.add_theme_color_override("font_color", Color(0.55, 0.62, 0.78))
	col.add_child(_hint)

	# The closing card, over a dark screen.
	_end_title = Label.new()
	_end_title.position = Vector2(0.0, 300.0)
	_end_title.size = Vector2(1280.0, 60.0)
	_end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_end_title.add_theme_font_size_override("font_size", 46)
	_end_title.add_theme_color_override("font_color", Color(0.88, 0.92, 1.0))
	_end_title.visible = false
	root.add_child(_end_title)

	_end_note = Label.new()
	_end_note.position = Vector2(0.0, 370.0)
	_end_note.size = Vector2(1280.0, 40.0)
	_end_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_end_note.add_theme_font_size_override("font_size", 22)
	_end_note.add_theme_color_override("font_color", Color(0.62, 0.68, 0.86))
	_end_note.visible = false
	root.add_child(_end_note)


## Starts a conversation. `speaker` is a key of PEOPLE, or "" for narration.
func tell(speaker: String, lines: Array) -> void:
	if lines.is_empty():
		return
	_speaker = speaker
	_queue = lines.duplicate()
	_open = true
	_layer.visible = true
	_show_next()


func is_open() -> bool:
	return _open


func advance() -> void:
	if not _open:
		return
	if _queue.is_empty():
		_close()
	else:
		_show_next()


func _show_next() -> void:
	var entry: Dictionary = PEOPLE.get(_speaker, {})
	_name.text = str(entry.get("name", ""))
	_name.visible = _speaker != ""
	_name.add_theme_color_override("font_color", entry.get("colour", Color.WHITE))
	_text.text = str(_queue.pop_front())
	_end_title.visible = false
	_end_note.visible = false


func _close() -> void:
	_open = false
	_layer.visible = false
	_queue.clear()
	# Once the ending has been read out, the card stays up and the game returns
	# to the title screen by itself.
	if ending != "":
		_keep_ending_up()


func _show_ending_title(title: String, note: String) -> void:
	_end_title.text = title
	_end_note.text = note
	_ending_shown = true


func _keep_ending_up() -> void:
	if not _ending_shown:
		return
	_layer.visible = true
	_end_title.visible = true
	_end_note.visible = true
	# A dark closing screen, then back to the title.
	var fade := ColorRect.new()
	fade.color = Color(0.02, 0.02, 0.05, 0.0)
	fade.size = Vector2(1280.0, 720.0)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade.z_index = -1
	_layer.add_child(fade)
	var t := create_tween()
	t.tween_property(fade, "color:a", 0.72, 1.6)
	await get_tree().create_timer(7.0).timeout
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


## The screen comes to the rabbit, not the rabbit to the screen.
##
## The camera normally leans ahead of the rabbit so the player can see where it
## is going. While a conversation is up that lean is dropped and the camera eases
## onto the rabbit itself, so the framing slides over without the character
## growing a single pixel.
func _zoom_camera(closer: bool) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var rabbit := scene.get_node_or_null("Rabbit")
	if rabbit == null:
		return
	var cam := rabbit.get_node_or_null("Camera2D") as Camera2D
	if cam == null:
		return
	if rabbit.get("lead_enabled") != null:
		rabbit.lead_enabled = not closer
	# Only the sideways lean is dropped. The camera's own height is what frames
	# the rabbit, so it is kept and lifted by a few pixels during the talk.
	if closer:
		_cam_rest_y = cam.position.y
	var want := Vector2(0.0, _cam_rest_y - 7.0) if closer else Vector2(0.0, _cam_rest_y)
	var t := create_tween()
	t.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(cam, "position", want, 0.7)


# ------------------------------------------------------------------ saving
func to_save() -> Dictionary:
	return {
		"intro_seen": intro_seen,
		"shards": shards,
		"notes": notes.keys(),
		"met_black": met_black,
		"saw_images": saw_images,
		"choice": choice,
		"ending": ending,
	}


func from_save(d: Dictionary) -> void:
	intro_seen = bool(d.get("intro_seen", intro_seen))
	shards = int(d.get("shards", shards))
	for id in d.get("notes", []):
		notes[str(id)] = true
	met_black = bool(d.get("met_black", met_black))
	saw_images = bool(d.get("saw_images", saw_images))
	choice = str(d.get("choice", choice))
	ending = str(d.get("ending", ending))


func reset() -> void:
	intro_seen = false
	shards = 0
	notes.clear()
	met_black = false
	saw_images = false
	choice = ""
	ending = ""
	_ending_shown = false
	_close()
