extends Node2D
## Makes the repeating backdrop layers tile across the whole world.
##
## A ParallaxLayer is not repeated by default (`motion_mirroring` is zero), so a
## backdrop would slide off the screen once the camera has scrolled far enough.
##
## Only the *backdrop* layers are tiled. The "Main" and "Front" layers, and
## everything belonging to the hill, are single pieces of scenery: repeating them
## would stamp the burrow's hill over the forest, so they are left alone.

func _ready() -> void:
	_tile_all(self)


func _tile_all(node: Node) -> void:
	for child in node.get_children():
		if child is ParallaxLayer and _should_tile(child):
			var size := _content_size(child)
			if size.x > 0.0:
				child.motion_mirroring = size
		_tile_all(child)


## True only for the far/middle backdrops of the forest, which must repeat.
func _should_tile(layer: ParallaxLayer) -> bool:
	var n := layer.name
	if n.contains("Main") or n.contains("Front") or n.contains("Hill"):
		return false
	var parent := layer.get_parent()
	if parent != null and parent.name.contains("Hill"):
		return false
	return true


func _content_size(layer: ParallaxLayer) -> Vector2:
	for child in layer.get_children():
		if child is Sprite2D and (child as Sprite2D).texture != null:
			return (child as Sprite2D).texture.get_size()
	return Vector2.ZERO
