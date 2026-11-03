extends Control
## The prompt that says what the rabbit can do here.
##
## It used to show key-cap artwork; it is plain text now, so the wording can say
## exactly what will happen rather than relying on a picture of a button.

## Which action the prompt is for, and the line that describes it.
const LINES := {
	"take": "E — взять",
	"enter": "Q — войти",
	"exit": "Q — выйти",
	"talk": "R — говорить",
	"sleep": "E — лечь спать",
	"wake": "E — проснуться",
}

const TEXT_SIZE := 19
const BOX_WIDTH := 520.0
const BOX_HEIGHT := 30.0

## Which action to show: take / enter / exit / talk / sleep / wake.
@export var key := "take"
## Distance from the bottom of the screen, in real pixels.
@export var bottom_margin := 44.0

@onready var icon: TextureRect = $Icon

var _label: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The key-cap pictures are no longer used anywhere.
	if icon != null:
		icon.visible = false
		var mat := CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_MIX
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", TEXT_SIZE)
	_label.add_theme_color_override("font_color", Color(0.94, 0.96, 1.0))
	_label.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.07, 0.95))
	_label.add_theme_constant_override("outline_size", 8)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.size = Vector2(BOX_WIDTH, BOX_HEIGHT)
	add_child(_label)
	show_key(key)


## Switch which line is shown. Safe to call every frame with the same key.
func show_key(which: String) -> void:
	if which == "" or not LINES.has(which):
		visible = false
		return
	_label.text = str(LINES[which])
	visible = true
	_centre()


func hide_prompt() -> void:
	visible = false


## Kept centred horizontally and just above the bottom of the screen.
func _centre() -> void:
	var vp := get_viewport_rect().size
	if vp.x <= 0.0:
		return
	size = Vector2(BOX_WIDTH, BOX_HEIGHT)
	_label.size = Vector2(BOX_WIDTH, BOX_HEIGHT)
	position = Vector2(round((vp.x - BOX_WIDTH) * 0.5),
		round(vp.y - bottom_margin - BOX_HEIGHT))
