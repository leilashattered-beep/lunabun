extends Control
## The whole Lunabun interface, built in code so there is no scene to wire up:
##
##   * MAIN MENU      - shown at start-up, over the animated forest
##   * PAUSE MENU     - ESC while playing
##   * SETTINGS       - from either menu
##   * HOW TO PLAY    - the controls, in Russian
##   * CONFIRMATIONS  - exiting, and returning to the main menu
##
## It is registered as an autoload, so gameplay scenes need no changes: this
## node decides for itself whether ESC means "open the menu" or "resume", and it
## pauses the tree while a menu is up.
##
## All visible text is Russian, as requested. Style: smooth dark-blue plates with
## a thin border, a soft glow and a little moon next to the selected row, drawn
## with a clean Cyrillic system font at a comfortable size.

const MAIN_SCENE := "res://scenes/main_menu.tscn"
const START_SCENE := "res://scenes/burrow_inside.tscn"

# The interface is laid out for a 1280x720 window in real pixels, so text is
# rasterised at full resolution and stays crisp. U is that design scale.
const U := 4.0
const TITLE_SIZE := 34
const LABEL_SIZE := 19
const HINT_SIZE := 14
const BODY_SIZE := 15
const ROW_HEIGHT := 36
const ROW_WIDTH := 370
const ROW_GAP := 10
## Marks the selected row - a crescent, the game's own motif.
const ROW_PAD := "\u2007"
const ROW_MARK := "\u263D"

## Families tried in order for the interface, if the supplied face cannot load.
const FONT_NAMES := ["Georgia", "Segoe UI", "Times New Roman", "Arial"]
## The face supplied for the game.
const VIDEO_PATH := "res://ui/menu_bg.ogv"
const FONT_PATH := "res://ui/fonts/Ametist.ttf"
## The display face for the menu choices. It is caps-only, which is why the
## button captions are set in capitals.
const FONT_BUTTON_PATH := "res://ui/fonts/GLIWA_TYPE.otf"
const FONT_ITALIC_PATH := "res://ui/fonts/Ametist.ttf"

# Palettes: night blues with a pale moonlight accent.
const COL_BG := Color(0.06, 0.08, 0.16, 0.30)
const COL_BG_SEL := Color(0.20, 0.28, 0.48, 0.62)
const COL_BORDER := Color(0.35, 0.45, 0.70, 0.85)
const COL_BORDER_SEL := Color(0.72, 0.82, 1.0, 1.0)
const COL_TEXT := Color(0.80, 0.85, 0.95)
## The dark edge behind menu letters.
const DARK_EDGE := Color(0.02, 0.03, 0.07, 0.92)
const EDGE_SIZE := 5
const COL_TEXT_SEL := Color(1.0, 0.99, 0.92)
const COL_DIM := Color(0.45, 0.50, 0.62)
const COL_ACCENT := Color(0.85, 0.92, 1.0)

enum View { NONE, MAIN, PAUSE, SETTINGS, HOWTO, CONFIRM_EXIT, CONFIRM_QUIT }

var _view := View.NONE
var _stack: Array[int] = []
var _from_pause := false
var _rows: Array[Button] = []
var _index := 0
var _rows_box: Control
var _rows_backdrop: ColorRect
var _title: Label
var _subtitle: Label
var _footer: Label
var _panel: PanelContainer
var _panel_box: VBoxContainer
var _video: VideoStreamPlayer
var _glow: Sprite2D
var _confirm_action := ""
var _toast: Label
## The interface canvas: keeps the UI off the game camera and at native scale.
var _layer: CanvasLayer
## Control root inside that canvas - it carries the theme, so the font reaches
## every label and button without setting it on each one.
var _root: Control
## Shared interface font, created once and handed to every widget.
var _font: Font
var _font_italic_cache: Font
var _font_button_cache: Font


func _font_get() -> Font:
	if _font == null:
		# The supplied Jun face first; if it is missing, fall back to a system
		# face that also carries Cyrillic.
		if ResourceLoader.exists(FONT_PATH):
			_font = load(FONT_PATH)
		else:
			var f := SystemFont.new()
			f.font_names = FONT_NAMES
			f.allow_system_fallback = true
			f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
			_font = f
	return _font


## Italic companion, used for the small notes.
func _font_italic() -> Font:
	if _font_italic_cache == null:
		if ResourceLoader.exists(FONT_ITALIC_PATH):
			_font_italic_cache = load(FONT_ITALIC_PATH)
		else:
			_font_italic_cache = _font_get()
	return _font_italic_cache


## Shows or hides the whole interface (the canvas has its own visibility).
func _ui_visible(v: bool) -> void:
	visible = v
	if _layer != null:
		_layer.visible = v

# Confirmation window text differs depending on where it was opened from.
var _confirm_yes := "Да"
var _confirm_no := "Нет"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# The interface lives on its own canvas layer: that keeps it out of the game
	# camera's way and renders it at full window resolution, so text is sharp.
	_layer = CanvasLayer.new()
	_layer.layer = 200
	add_child(_layer)

	# Everything is parented to this Control so the theme (and so the font)
	# reaches every widget by inheritance.
	_root = Control.new()
	_root.size = Vector2(1280.0, 720.0)
	var th := Theme.new()
	# The display face for the whole menu; the readable font sits behind it as a
	# fallback, and the game itself is untouched.
	th.default_font = _font_button()
	th.default_font_size = LABEL_SIZE
	# A dark edge on the letters keeps them off the glass behind them.
	# Deliberately small: a heavy outline reads as a cartoon, not a pane.
	th.set_color("font_outline_color", "Label", DARK_EDGE)
	th.set_constant("outline_size", "Label", EDGE_SIZE)
	th.set_color("font_outline_color", "Button", DARK_EDGE)
	th.set_constant("outline_size", "Button", EDGE_SIZE)
	_root.theme = th
	_layer.add_child(_root)

	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_ui_visible(false)

	_build_background()
	_build_header()
	_build_rows()
	_build_footer()
	_build_panel()

	# Start on the main menu, unless a game scene is already running.
	await get_tree().process_frame
	if _in_game():
		_apply_view(View.NONE)
	else:
		open_main_menu()


func _in_game() -> bool:
	var s := get_tree().current_scene
	if s == null:
		return false
	var p := s.scene_file_path
	return p.ends_with("main.tscn") or p.ends_with("burrow_inside.tscn")


## Records the rabbit's spot so a save (or ПРОДОЛЖИТЬ) can put it back.
func _remember_player() -> void:
	var s := get_tree().current_scene
	if s == null or not _in_game():
		return
	var rabbit := s.get_node_or_null("Rabbit")
	if rabbit == null:
		return
	GameState.scene_path = s.scene_file_path
	GameState.rabbit_x = rabbit.global_position.x
	GameState.has_progress = true


# ------------------------------------------------------------------ building
func _build_background() -> void:
	# The supplied clip already IS the title screen: it carries the Lunabun
	# lettering, the rabbit and the burrow.
	#
	# It is played straight from the original file, in its own 1280x720, by a
	# VideoStreamPlayer. Nothing is extracted, resized, re-encoded or filtered:
	# the source video is what reaches the screen.
	_video = VideoStreamPlayer.new()
	_video.stream = load(VIDEO_PATH)
	_video.loop = true
	_video.expand = true
	_video.size = Vector2(1280.0, 720.0)
	_video.autoplay = true
	_video.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_video)
	_video.play()

	# Kept only as a handle the selection pulse can lean on; invisible, so the
	# clip keeps its own brightness.
	_glow = Sprite2D.new()
	_glow.visible = false
	_root.add_child(_glow)


func _build_header() -> void:
	# The animated clip already carries the LUNABUN lettering, so no title is
	# drawn over it - only the small hint about keys, at the bottom.
	_title = Label.new()
	_title.visible = false
	_root.add_child(_title)

	_subtitle = Label.new()
	_subtitle.visible = false
	_root.add_child(_subtitle)


func _build_rows() -> void:
	# A soft dark panel behind the column, so the small plates stay readable over
	# the bright parts of the clip. It only sits behind the buttons - the clip
	# itself keeps its own brightness.
	_rows_backdrop = ColorRect.new()
	_rows_backdrop.color = Color(0.02, 0.03, 0.06, 0.0)
	_rows_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_rows_backdrop)

	_rows_box = Control.new()
	# Left side of the screen, a little below the vertical middle.
	_rows_box.position = Vector2(96.0, 296.0)
	_rows_box.add_theme_constant_override("separation", ROW_GAP)
	_rows_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_rows_box)


func _build_footer() -> void:
	_footer = Label.new()
	_footer.add_theme_font_size_override("font_size", HINT_SIZE)
	_footer.add_theme_color_override("font_color", COL_DIM)
	_footer.add_theme_color_override("font_outline_color", Color(0.05, 0.07, 0.14, 0.9))
	_footer.add_theme_constant_override("outline_size", 3)
	_footer.position = Vector2(96.0, 632.0)
	_footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_footer)

	_toast = Label.new()
	_toast.add_theme_font_size_override("font_size", HINT_SIZE)
	_toast.add_theme_color_override("font_color", COL_ACCENT)
	_toast.add_theme_color_override("font_outline_color", Color(0.05, 0.07, 0.14, 0.95))
	_toast.add_theme_constant_override("outline_size", 3)
	_toast.position = Vector2(96.0, 572.0)
	_toast.visible = false
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_toast)


func _build_panel() -> void:
	_panel = PanelContainer.new()
	_panel.position = Vector2(180.0, 96.0)
	_panel.custom_minimum_size = Vector2(820.0, 0.0)
	# Built for the glass shader: a transparent middle, and a wide border that
	# blends into it. That gradient is the refraction band.
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.60, 0.70, 0.94, 0.0)
	sb.border_color = Color(0.60, 0.70, 0.94, 1.0)
	sb.border_blend = true
	sb.set_border_width_all(20)
	sb.set_corner_radius_all(24)
	sb.shadow_color = Color(0.02, 0.03, 0.08, 0.20)
	sb.shadow_size = 6
	sb.set_content_margin_all(38)
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_panel)

	_panel_box = VBoxContainer.new()
	_panel_box.add_theme_constant_override("separation", 6)
	_panel.add_child(_panel_box)
	_panel.visible = false


# ------------------------------------------------------------- row creation
func _clear_rows() -> void:
	for r in _rows:
		r.queue_free()
	_rows.clear()
	_index = 0


func _add_row(label_text: String, action: Callable, enabled := true) -> Button:
	var b := Button.new()
	b.text = label_text.to_upper()
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", LABEL_SIZE)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(ROW_WIDTH, ROW_HEIGHT)
	b.add_theme_font_override("font", _font_button())
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	if not enabled:
		b.disabled = true
	var caption := label_text.to_upper()
	b.set_meta("caption", caption)
	b.text = ROW_PAD + "  " + caption
	b.pressed.connect(action)
	b.mouse_entered.connect(func() -> void: _select(_rows.find(b)))
	_rows_box.add_child(b)
	_float_rows()
	_rows.append(b)
	_style_row(b, false, enabled)
	return b


## Dark blue plate with a thin border; the selected row gets a brighter border,
## a brighter label and a little moon to its left.
func _style_row(b: Button, selected: bool, enabled := true) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_BG_SEL if selected else COL_BG
	# Fully rounded ends, which turns the plate into a pill.
	sb.set_corner_radius_all(ROW_HEIGHT / 2)
	sb.border_color = COL_BORDER_SEL if selected else COL_BORDER
	sb.set_border_width_all(2)
	sb.set_content_margin_all(3)
	sb.content_margin_left = 10
	sb.content_margin_right = 6
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	b.add_theme_stylebox_override("pressed", sb)
	b.add_theme_stylebox_override("disabled", sb)
	var col := COL_DIM if not enabled else (COL_TEXT_SEL if selected else COL_TEXT)
	b.add_theme_color_override("font_color", col)
	b.add_theme_color_override("font_hover_color", col)
	b.add_theme_color_override("font_disabled_color", COL_DIM)
	b.add_theme_color_override("font_pressed_color", col)


func _select(i: int) -> void:
	if _rows.is_empty():
		return
	_index = wrapi(i, 0, _rows.size())
	for k in _rows.size():
		var b := _rows[k]
		var sel := k == _index
		_style_row(b, sel, not b.disabled)
		# The padding character has the same width as the marker, so the caption
		# stays exactly where it is and only the little moon appears.
		b.text = (ROW_MARK if sel else ROW_PAD) + "  " + _row_label(b)
	# The selected plate brightens a touch, as if the light leaned towards it.
	var chosen := _rows[_index]
	var t := create_tween()
	t.tween_property(chosen, "modulate", Color(1.12, 1.14, 1.20), 0.08)
	t.tween_property(chosen, "modulate", Color(1, 1, 1), 0.16)


## The button's own caption, without the selection marker.
func _row_label(b: Button) -> String:
	return b.get_meta("caption", b.text)


func _set_caption(b: Button, caption: String) -> void:
	b.set_meta("caption", caption)
	b.text = (ROW_MARK if _rows.find(b) == _index else ROW_PAD) + "  " + caption


# ------------------------------------------------------------------- views
func _first_enabled() -> int:
	for i in _rows.size():
		if not _rows[i].disabled:
			return i
	return 0


func open_main_menu() -> void:
	get_tree().paused = false
	_view = View.MAIN
	_stack.clear()
	_from_pause = false
	_show_base(true)
	_clear_rows()
	_add_row("Новая игра", _on_new_game)
	_add_row("Продолжить", _on_continue, GameState.has_save())
	_add_row("Настройки", _on_settings)
	_add_row("Как играть", _on_howto)
	_add_row("Выход", _on_exit)
	_footer.text = "A / D ИЛИ СТРЕЛКИ — ВЫБОР     E ИЛИ ENTER — ПОДТВЕРДИТЬ"
	_rows_box.position = Vector2(96.0, 296.0)
	_finish_rows()
	_ui_visible(true)
	_hide_game_rabbit()
	if not GameState.has_save():
		_toast_text("Нет сохранения", 2.0)


## The main menu must never show the player's rabbit: the animated clip carries
## its own rabbit, and if a gameplay scene were ever left in the tree its rabbit
## would sit behind the menu. This makes sure nothing named "Rabbit" is drawn.
func _hide_game_rabbit() -> void:
	for node in get_tree().root.find_children("*", "Node2D", true, false):
		if node.name == "Rabbit" and not is_ancestor_of(node):
			(node as Node2D).visible = false


func open_pause_menu() -> void:
	_view = View.PAUSE
	_stack.clear()
	_from_pause = true
	get_tree().paused = true
	# Remember where the rabbit is, so ПРОДОЛЖИТЬ and СОХРАНИТЬ ИГРУ know.
	_remember_player()
	_show_base(true)
	_clear_rows()
	_add_row("Продолжить", _on_resume)
	_add_row("Настройки", _on_settings)
	_add_row("Как играть", _on_howto)
	_add_row("Сохранить игру", _on_save)
	_add_row("Выйти в главное меню", _on_quit_to_menu)
	_footer.text = "ESC — ПРОДОЛЖИТЬ ИГРУ"
	_rows_box.position = Vector2(96.0, 104.0)
	_finish_rows()
	_ui_visible(true)


func _finish_rows() -> void:
	_index = _first_enabled()
	_select(_index)
	_rows_box.visible = true
	_panel.visible = false
	_toast.visible = false
	_fit_backdrop()


## Sizes the dark panel behind the buttons to exactly cover them.
func _fit_backdrop() -> void:
	var n := _rows.size()
	if n <= 0:
		_rows_backdrop.visible = false
		return
	var h := n * ROW_HEIGHT + (n - 1) * ROW_GAP
	_rows_backdrop.position = _rows_box.position - Vector2(14, 14)
	_rows_backdrop.size = Vector2(ROW_WIDTH + 28, h + 28)
	_rows_backdrop.visible = _rows_box.visible


func _show_base(on: bool) -> void:
	_video.visible = on
	# The clip loops with no gap; it is only paused while a game is running.
	_video.paused = not on
	if on and not _video.is_playing():
		_video.play()
	_glow.visible = false
	_rows_box.visible = on
	_rows_backdrop.visible = on
	_title.visible = false
	_subtitle.visible = false
	_footer.visible = on
	_ui_visible(on)


## Closes the interface completely so nothing is drawn over the game.
func close() -> void:
	_view = View.NONE
	_show_base(false)
	_panel.visible = false
	_toast.visible = false
	_ui_visible(false)
	get_tree().paused = false


func _apply_view(v: View) -> void:
	_view = v
	match v:
		View.NONE:
			close()
		View.SETTINGS:
			_show_base(true)
			_rows_box.visible = false
			_footer.text = "ESC — НАЗАД"
			_build_settings_panel()
			_ui_visible(true)
		View.HOWTO:
			_show_base(true)
			_rows_box.visible = false
			_footer.text = "ESC — НАЗАД"
			_build_howto_panel()
			_ui_visible(true)


# ------------------------------------------------------------------ panels
func _panel_lines(text: String, size := BODY_SIZE, col := COL_TEXT) -> void:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_constant_override("line_spacing", 8)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	_panel_box.add_child(l)


func _panel_row(text: String, value_text := "") -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_size_override("font_size", BODY_SIZE)
	l.add_theme_color_override("font_color", COL_TEXT)
	row.add_child(l)
	if value_text != "":
		var v := Label.new()
		v.text = value_text.to_upper()
		v.add_theme_font_size_override("font_size", BODY_SIZE)
		v.add_theme_color_override("font_color", COL_ACCENT)
		row.add_child(v)
	return row


func _panel_title(text: String) -> void:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_size_override("font_size", LABEL_SIZE + 1)
	l.add_theme_color_override("font_color", COL_TEXT_SEL)
	_panel_box.add_child(l)


func _panel_button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text.to_upper()
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", BODY_SIZE)
	b.custom_minimum_size = Vector2(460.0, 34.0)
	b.pressed.connect(action)
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_BG
	sb.border_color = COL_BORDER
	sb.set_border_width_all(2)
	sb.set_content_margin_all(8)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	b.add_theme_stylebox_override("pressed", sb)
	b.add_theme_color_override("font_color", COL_TEXT)
	b.add_theme_color_override("font_hover_color", COL_TEXT_SEL)
	_panel_box.add_child(b)
	return b


func _panel_clear() -> void:
	for c in _panel_box.get_children():
		c.queue_free()


func _bar(value: float) -> String:
	var filled := int(round(value * 8.0))
	return "\u25AE".repeat(filled) + "\u25AF".repeat(8 - filled)


func _build_settings_panel() -> void:
	_panel_clear()
	_panel.visible = true
	# Liquid glass over the menu video.
	Look.glass(_panel, 22.0, 0.80)
	_panel_title("Настройки")
	# One label for the values, then the buttons: a single label lays out
	# reliably at this tiny size, where many thin rows did not.
	# Real sliders, the way a modern settings screen works: drag with the
	# mouse or nudge with the arrow keys, with the level shown as a percentage.
	_slider_row("Громкость музыки", GameState.music_volume,
		func(v: float) -> void: GameState.set_music_volume(v))
	_slider_row("Яркость", GameState.brightness,
		func(v: float) -> void: GameState.set_brightness(v))
	_slider_row("Громкость звуков", GameState.sfx_volume,
		func(v: float) -> void: GameState.set_sfx_volume(v))
	_panel_button("Полный экран: вкл / выкл", func() -> void: _toggle_fullscreen())
	_panel_button("Назад", _back)


func _nudge_music(d: float) -> void:
	GameState.set_music_volume(GameState.music_volume + d)
	_build_settings_panel()


func _nudge_sfx(d: float) -> void:
	GameState.set_sfx_volume(GameState.sfx_volume + d)
	_build_settings_panel()


func _toggle_fullscreen() -> void:
	GameState.set_fullscreen(not GameState.fullscreen)
	_build_settings_panel()


func _build_howto_panel() -> void:
	_panel_clear()
	_panel.visible = true
	_panel_title("Как играть — управление")
	# One multi-line label keeps the block compact and easy to read at this size.
	_panel_lines("A / D — движение влево / вправо\n" +
		"Пробел — прыжок\n" +
		"E — взять предмет / говорить\n" +
		"E — войти / выйти\n" +
		"E — лечь спать", LABEL_SIZE - 3, COL_TEXT)
	_panel_lines("E зависит от места: у предмета — взять,\nу норы — войти / выйти, у лежанки — спать.",
		HINT_SIZE, COL_DIM)
	_panel_button("Назад", _back)


func _build_confirm_panel(text: String) -> void:
	_panel_clear()
	_panel.visible = true
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_size_override("font_size", LABEL_SIZE)
	l.add_theme_color_override("font_color", COL_TEXT_SEL)
	_panel_box.add_child(l)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_panel_box.add_child(row)
	var yes := Button.new()
	yes.text = _confirm_yes.to_upper()
	yes.focus_mode = Control.FOCUS_NONE
	yes.add_theme_font_size_override("font_size", LABEL_SIZE)
	yes.custom_minimum_size = Vector2(150.0, 34.0)
	yes.pressed.connect(func() -> void: _confirm_yes_action())
	var no := Button.new()
	no.text = _confirm_no.to_upper()
	no.focus_mode = Control.FOCUS_NONE
	no.add_theme_font_size_override("font_size", LABEL_SIZE)
	no.custom_minimum_size = Vector2(150.0, 34.0)
	no.pressed.connect(_back)
	for b in [yes, no]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = COL_BG
		sb.border_color = COL_BORDER
		sb.set_border_width_all(2)
		sb.set_content_margin_all(3)
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", sb)
		b.add_theme_stylebox_override("pressed", sb)
		b.add_theme_color_override("font_color", COL_TEXT)
		b.add_theme_color_override("font_hover_color", COL_TEXT_SEL)
		row.add_child(b)


# ----------------------------------------------------------------- actions
func _on_new_game() -> void:
	# Hide the whole interface first: otherwise the menu keeps drawing over the
	# game that is about to load, and the locations look like they vanished.
	close()
	GameState.start_new_game()


func _on_continue() -> void:
	if not GameState.continue_game():
		_toast_text("Нет сохранения", 2.0)


func _on_settings() -> void:
	_stack.push_back(_view)
	_apply_view(View.SETTINGS)


func _on_howto() -> void:
	_stack.push_back(_view)
	_apply_view(View.HOWTO)


func _on_save() -> void:
	if GameState.save_game():
		_toast_text("Игра сохранена", 2.0)


func _on_resume() -> void:
	close()


func _on_exit() -> void:
	_stack.push_back(_view)
	_view = View.CONFIRM_EXIT
	_show_base(true)
	_build_confirm_panel("Выйти из игры?")
	_confirm_action = "exit"


func _on_quit_to_menu() -> void:
	_stack.push_back(_view)
	_view = View.CONFIRM_QUIT
	_show_base(true)
	_build_confirm_panel("Вернуться в главное меню?")
	_confirm_action = "menu"


func _confirm_yes_action() -> void:
	match _confirm_action:
		"exit":
			get_tree().quit()
		"menu":
			get_tree().paused = false
			get_tree().change_scene_to_file(MAIN_SCENE)


func _back() -> void:
	var previous: int = _stack.pop_back() if not _stack.is_empty() else View.MAIN
	match previous:
		View.MAIN:
			open_main_menu()
		View.PAUSE:
			open_pause_menu()
		_:
			_apply_view(previous)


func _toast_text(text: String, seconds: float) -> void:
	_toast.text = text.to_upper()
	_toast.visible = true
	_toast.modulate.a = 1.0
	var t := create_tween()
	t.tween_interval(seconds)
	t.tween_property(_toast, "modulate:a", 0.0, 0.5)
	t.tween_callback(func() -> void: _toast.visible = false)


# ------------------------------------------------------------------- input
## Input is polled rather than handled as events: it behaves the same for a real
## keyboard, for gamepads and for scripted input, and it works while the tree is
## paused because this node is set to always process.
func _process(_delta: float) -> void:
	_float_rows()
	if Input.is_action_just_pressed("ui_cancel"):
		_on_escape()
		return
	if not _layer.visible:
		return

	if Input.is_action_just_pressed("enter_exit") and _rows_box.visible:
		_activate()
		return

	if _rows_box.visible and not _rows.is_empty():
		if Input.is_action_just_pressed("ui_down") or Input.is_action_just_pressed("move_right"):
			_step(1)
		elif Input.is_action_just_pressed("ui_up") or Input.is_action_just_pressed("move_left"):
			_step(-1)
		elif Input.is_action_just_pressed("ui_accept") or Input.is_action_just_pressed("interact"):
			_activate()


func _activate() -> void:
	if _rows.is_empty():
		return
	var b := _rows[_index]
	if not b.disabled:
		b.pressed.emit()


func _step(direction: int) -> void:
	if _rows.is_empty():
		return
	var i := _index
	for _n in _rows.size():
		i = wrapi(i + direction, 0, _rows.size())
		if not _rows[i].disabled:
			break
	_select(i)


func _on_escape() -> void:
	match _view:
		View.NONE:
			if _in_game():
				open_pause_menu()
		View.MAIN:
			pass  # already at the top level of the menu
		View.PAUSE:
			_on_resume()
		View.SETTINGS, View.HOWTO:
			_back()
		View.CONFIRM_EXIT, View.CONFIRM_QUIT:
			_back()


## The buttons drift gently, each on its own phase and speed, so the menu feels
## alive rather than printed on the screen.
func _float_rows() -> void:
	if _rows.is_empty() or _rows_box == null:
		return
	var t := Time.get_ticks_msec() / 1000.0
	for i in _rows.size():
		var bob := sin(t * 0.9 + float(i) * 1.1) * 4.0
		_rows[i].position = Vector2(0.0, float(i) * (ROW_HEIGHT + ROW_GAP) + bob)


## One settings row: a caption, a real slider, and the level in percent.
func _slider_row(caption: String, value: float, apply: Callable) -> void:
	var label := Label.new()
	label.text = "%s — %d%%" % [caption.to_upper(), int(round(value * 100.0))]
	label.add_theme_font_size_override("font_size", BODY_SIZE)
	label.add_theme_color_override("font_color", COL_TEXT)
	_panel_box.add_child(label)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = value
	slider.custom_minimum_size = Vector2(520.0, 26.0)
	slider.focus_mode = Control.FOCUS_ALL
	slider.value_changed.connect(func(v: float) -> void:
		apply.call(v)
		label.text = "%s — %d%%" % [caption.to_upper(), int(round(v * 100.0))])

	# A slim rounded track, so the slider matches the rest of the interface.
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.11, 0.13, 0.24, 0.95)
	track.set_corner_radius_all(7)
	track.content_margin_top = 8.0
	track.content_margin_bottom = 8.0
	slider.add_theme_stylebox_override("slider", track)
	_panel_box.add_child(slider)


## The face used for the menu buttons, with the readable font behind it so a
## glyph the display face does not have can never come out blank.
func _font_button() -> Font:
	if _font_button_cache == null:
		if ResourceLoader.exists(FONT_BUTTON_PATH):
			var face := load(FONT_BUTTON_PATH) as Font
			if face != null:
				var chain: Array[Font] = [_font_get()]
				face.fallbacks = chain
				_font_button_cache = face
		if _font_button_cache == null:
			_font_button_cache = _font_get()
	return _font_button_cache
