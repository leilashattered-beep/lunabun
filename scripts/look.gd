extends Node
## Autoload: the look of the game.
##
## This used to carry a vignette, film grain and a glow environment. All three
## turned out to hurt: the vignette painted a smooth alpha gradient over a very
## dark picture, which showed up as bands, and the HDR pass behind it dropped the
## whole scene towards black. They are gone.
##
## What is left is the brightness the player controls, drawn with two flat
## overlays - flat, because a gradient over a night scene is exactly what bands -
## and the liquid-glass shader the panels use.

var _layer: CanvasLayer
var _dark: ColorRect
var _light: ColorRect
var _last := -1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	set_process(true)


func _process(_delta: float) -> void:
	_apply_brightness()


func _build() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 165
	_layer.name = "Look"
	add_child(_layer)

	var root := Control.new()
	root.size = Vector2(1280.0, 720.0)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(root)

	_dark = ColorRect.new()
	_dark.color = Color(0.0, 0.0, 0.0, 0.0)
	_dark.size = Vector2(1280.0, 720.0)
	_dark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_dark)

	# Brightening is additive, so it lifts the shadows instead of greying them.
	_light = ColorRect.new()
	_light.color = Color(1.0, 1.0, 1.0, 0.0)
	_light.size = Vector2(1280.0, 720.0)
	_light.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_light.material = mat
	root.add_child(_light)


## 0.5 is neutral. Below that a flat black veil comes in, above it a flat white
## lift, and nothing in between is a gradient, so nothing can band.
func _apply_brightness() -> void:
	var b: float = clampf(GameState.brightness, 0.0, 1.0)
	if is_equal_approx(b, _last):
		return
	_last = b
	if b < 0.5:
		_dark.color = Color(0.0, 0.0, 0.0, (0.5 - b) * 0.7)
		_light.color = Color(1.0, 1.0, 1.0, 0.0)
	else:
		_dark.color = Color(0.0, 0.0, 0.0, 0.0)
		_light.color = Color(1.0, 1.0, 1.0, (b - 0.5) * 0.45)


## Puts the supplied liquid-glass shader on a panel.
##
## The panel's own StyleBox does the shaping: its transparent middle is the flat
## part of the glass, and its wide, blended border is what refracts. The tint is
## the stylebox colour, which the shader multiplies into the backdrop.
func glass(node: CanvasItem, radius: float, alpha := 0.74,
		tint := Color(0.62, 0.72, 0.94)) -> void:
	if node == null or not ResourceLoader.exists("res://ui/glass_panel.gdshader"):
		return
	var mat := ShaderMaterial.new()
	mat.shader = load("res://ui/glass_panel.gdshader")
	mat.set_shader_parameter("brightness", 0.10)
	# Kept low on purpose: a strong colour fringe on a night scene is tiring,
	# a faint one is what makes the glass read as glass.
	mat.set_shader_parameter("chromatic_shift_amount", 0.08)
	mat.set_shader_parameter("bend_amount", 0.34)
	mat.set_shader_parameter("blur_amount", 2.6)
	mat.set_shader_parameter("grain_amount", 0.03)
	mat.set_shader_parameter("curve_light_blend", 0.0)
	mat.set_shader_parameter("rim_light_blend", 0.0)
	# The shader skips pixels whose colour equals this one, so it is set to a
	# colour no panel will ever be drawn in, leaving the glass always drawn.
	mat.set_shader_parameter("shadow_color", Color(0.5, 0.5, 0.5, 0.0))
	node.material = mat
