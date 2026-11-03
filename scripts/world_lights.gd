extends Node2D
## Lights the outdoor map: the moon, the lamps, and every other bright thing the
## artwork already draws.
##
## Rather than hard-coding positions, each layer's own texture is scanned for
## small bright clusters - windows, crystals, flowers, bright stones, lamp glass -
## and a soft additive halo is put on each one. The moon is placed by hand,
## because it is large and unique.
##
## Artwork is only read here, never modified.

const GLOW := "res://fireflies/firefly_glow.png"
## How far the scenery artwork itself is darkened.
##
## The night overlay multiplies EVERYTHING under it, fireflies and glows
## included, so a strong overlay also flattens the lights. The real darkening is
## therefore applied to the art sprites here, and the overlay is left mild - the
## scenery ends up just as dark while the small lights keep their punch.
const ART_TINT := Color(0.44, 0.48, 0.62)
## Layers to scan, and how many lights may be added to each.
const SCAN := {
	"Mid": 6,
	"Back": 8,
	"Main": 10,
	"HillMain": 6,
}
## A pixel counts as a light source above this luminance.
const BRIGHT := 0.62
## Lights are kept at least this far apart, in the layer's own pixels.
const SPACING := 58.0

var _glow_tex: Texture2D


func _ready() -> void:
	_glow_tex = load(GLOW)
	_darken_art(get_parent())
	# The moon is gone from the sky, so nothing glows there any more. The sky
	# layer is shown from a copy of the artwork with the moon painted out; the
	# supplied 01_sky.png is left untouched on disk.
	_remove_the_moon()
	for layer_name in SCAN.keys():
		var layer := _layer(layer_name)
		if layer == null:
			continue
		var found := _bright_spots(layer, int(SCAN[layer_name]))
		for spot in found:
			_add_glow(layer, spot, 1.5, Color(1.0, 0.88, 0.62, 0.9))
		print("[lights] ", layer_name, ": ", found.size(), " огней")
	_add_dust()


## A faint shimmer of tiny blue motes, far dimmer and smaller than the fireflies.
func _add_dust() -> void:
	var packed := load("res://scenes/firefly_dust.tscn") as PackedScene
	if packed == null:
		return
	var dust: Node2D = packed.instantiate()
	add_child(dust)
	print("[lights] dust: ", dust.count, " motes")
	_add_glow_plants()


## A few tiny glowing plants along the walkable ground: a small bright core with
## a soft pool on the grass, easy to walk past and easy to miss.
func _add_glow_plants() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20240607
	var floor_line := 152.0
	var plants := 16
	for i in plants:
		var x := rng.randf_range(120.0, 3700.0)
		var pool := Sprite2D.new()
		pool.texture = load("res://fireflies/firefly_pool.png")
		pool.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		pool.position = Vector2(x, floor_line)
		pool.scale = Vector2(1.9, 0.9)
		pool.material = _additive_material()
		pool.modulate = Color(0.66, 0.94, 0.78, 0.34)
		add_child(pool)

		var core := Sprite2D.new()
		core.texture = _glow_tex
		core.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		core.position = Vector2(x, floor_line - 2.0)
		core.scale = Vector2(0.7, 0.7)
		core.material = _additive_material()
		core.modulate = Color(0.78, 1.0, 0.86, 0.7)
		add_child(core)

		# Very slow breathing, each one on its own timing.
		var period := rng.randf_range(2.4, 4.6)
		var t := core.create_tween().set_loops()
		t.tween_property(core, "modulate:a", 0.95, period)
		t.tween_property(core, "modulate:a", 0.35, period)
		var t2 := pool.create_tween().set_loops()
		t2.tween_property(pool, "modulate:a", 0.42, period)
		t2.tween_property(pool, "modulate:a", 0.16, period)
	print("[lights] glowing plants: ", plants)


func _additive_material() -> CanvasItemMaterial:
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return mat


## Darkens the scenery artwork itself, so the night does not have to be produced
## by an overlay that would also dim the lights.
func _darken_art(node: Node) -> void:
	for child in node.get_children():
		if child is ParallaxLayer:
			for inner in (child as Node).get_children():
				if inner is Sprite2D:
					(inner as Sprite2D).modulate = (inner as Sprite2D).modulate * ART_TINT
		_darken_art(child)


func _layer(layer_name: String) -> Node:
	# Searched from the scene root: find_child only looks below the node it is
	# called on, and these layers are siblings of this node.
	return get_parent().find_child(layer_name, true, false)


## Reads a layer's texture and returns the centres of its bright clusters.
func _bright_spots(layer: Node, limit: int) -> Array:
	var out: Array = []
	var sprite: Sprite2D = null
	for child in layer.get_children():
		if child is Sprite2D and (child as Sprite2D).texture != null:
			sprite = child
			break
	if sprite == null:
		return out
	var img := sprite.texture.get_image()
	if img == null:
		return out
	var step := 3
	var best: Array = []
	for y in range(0, img.get_height(), step):
		for x in range(0, img.get_width(), step):
			var c := img.get_pixel(x, y)
			if c.a < 0.35:
				continue
			var luma := (c.r * 0.3 + c.g * 0.6 + c.b * 0.1)
			if luma >= BRIGHT:
				best.append({"pos": Vector2(x, y), "luma": luma})
	best.sort_custom(func(a, b): return a.luma > b.luma)
	for cand in best:
		var keep := true
		for chosen in out:
			if (cand.pos as Vector2).distance_to(chosen) < SPACING:
				keep = false
				break
		if keep:
			out.append(cand.pos)
		if out.size() >= limit:
			break
	return out


## Puts one softly breathing halo on a layer, at a position in that layer's own
## artwork coordinates.
func _add_glow(layer: Node, where: Vector2, size: float, tint: Color) -> void:
	if layer == null:
		return
	var glow := Sprite2D.new()
	glow.texture = _glow_tex
	glow.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	glow.position = where
	glow.scale = Vector2(size, size)
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow.material = mat
	glow.modulate = tint
	layer.add_child(glow)

	# A slow breath, so the lights feel alive rather than painted on.
	var t := glow.create_tween().set_loops()
	t.tween_property(glow, "modulate:a", clampf(tint.a * 1.3, 0.0, 1.0), 1.8)
	t.tween_property(glow, "modulate:a", tint.a * 0.7, 1.8)


## Shows the sky from the copy of the artwork with the moon painted out, so the
## moon is gone from the background. The supplied PNG is never modified.
func _remove_the_moon() -> void:
	var alt := "res://forest_layers/alt/01_sky_nomoon.png"
	if not ResourceLoader.exists(alt):
		return
	var sky := _layer("Sky")
	if sky == null:
		return
	for child in sky.get_children():
		if child is Sprite2D:
			(child as Sprite2D).texture = load(alt)
