extends Node2D
## The burrow entrance in the forest.
##
## Sits at the burrow package's `burrow_entrance_x` on the forest map. When the
## rabbit is close it shows "E — Enter the burrow"; pressing E fades out and
## switches to the separate burrow scene. The entrance is marked with a soft
## blue-white glow plus a few drifting fireflies, so it reads in the dark
## without adding or changing any artwork.

const DEFAULT_TARGET := "res://scenes/burrow_inside.tscn"

@export var entrance_x := 400.0
@export var interact_radius := 26.0
## Where the packet says the rabbit wakes up / returns outside.
@export var nest_x := 300.0
@export var exit_spawn_x := 410.0
## The floor height at the entrance.
@export var floor_y := 147.0
## Scene this entrance leads to. There are two holes in the game: the one in the
## forest leads to the burrow's outside map, and the one on that map leads into
## the room. `scene_for("<map scene name>")` gives the right one.
@export var target_scene := ""
## Where the hole leads FROM each map:
##   outdoor world ...... into the burrow room
##   burrow room ........ out into the outdoor world
@export var forest_target := "res://scenes/burrow_inside.tscn"
@export var outside_target := "res://scenes/main.tscn"
@export var inside_target := "res://scenes/main.tscn"
## Which supplied key prompt to show next to the hole, per map.
@export var forest_key := "enter"
@export var outside_key := "enter"
@export var inside_key := "exit"


## Which map the game is on: "forest" (the outdoor world) or "burrow_inside".
## Uses the scene file path, which is unique, rather than the root node name.
func current_map() -> String:
	var scene := get_tree().current_scene
	if scene == null:
		return ""
	if scene.scene_file_path.ends_with("main.tscn"):
		return "forest"
	return "burrow_inside"


## The scene this particular entrance should load, based on which map it is on.
## Route: the outdoor world → the burrow room, and back out again.
func scene_for(map_name: String) -> String:
	if target_scene != "":
		return target_scene
	match map_name:
		"forest":
			return forest_target
		"burrow_inside":
			return inside_target
		_:
			return outside_target


func key_for(map_name: String) -> String:
	match map_name:
		"forest":
			return forest_key
		"burrow_inside":
			return inside_key
		_:
			return outside_key

@onready var prompt: Control = $Ui/Prompt
@onready var fade: ColorRect = $Ui/FadeRect

var _rabbit: CharacterBody2D
var _busy := false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_rabbit = get_parent().get_node("Rabbit")
	prompt.visible = false

	if GameState.returning_from_burrow:
		# Came back out of the burrow: stand next to the entrance, not at spawn.
		GameState.returning_from_burrow = false
		_rabbit.global_position = Vector2(exit_spawn_x, floor_y)

	_build_entrance_glow()
	_fade_in()


func _fade_in() -> void:
	fade.color.a = 1.0
	var tween := create_tween()
	tween.tween_property(fade, "color:a", 0.0, 0.7)


## Soft glow marking the hole, plus a few fireflies drawn to it.
func _build_entrance_glow() -> void:
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	var glow_tex: Texture2D = load("res://fireflies/firefly_glow.png")
	var pool_tex: Texture2D = load("res://fireflies/firefly_pool.png")

	# A dark mouth for the hole, so the entrance reads as an opening rather than
	# just a glow. Drawn from the same glow texture squashed into an oval, kept
	# hard-edged (not additive) to stay in the pixel-art palette.
	var mouth := Sprite2D.new()
	mouth.texture = pool_tex
	mouth.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	# Sized to cover the transparent hole that the artwork leaves at the entrance,
	# so the player never sees the unpainted clear colour through it.
	mouth.position = Vector2(entrance_x, floor_y - 15.0)
	mouth.scale = Vector2(3.4, 3.4)
	mouth.modulate = Color(0.06, 0.06, 0.11, 1.0)
	mouth.z_index = 83
	add_child(mouth)

	# Cool light spilling out of it.
	var spill := Sprite2D.new()
	spill.texture = pool_tex
	spill.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	spill.material = add
	spill.position = Vector2(entrance_x, floor_y - 7.0)
	spill.scale = Vector2(2.6, 2.0)
	spill.modulate = Color(0.55, 0.72, 1.0, 0.40)
	spill.z_index = 88
	add_child(spill)

	for i in 5:
		var f := Sprite2D.new()
		f.texture = glow_tex
		f.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		f.material = add
		f.position = Vector2(entrance_x + _rng.randf_range(-16.0, 16.0),
			floor_y - _rng.randf_range(4.0, 26.0))
		f.scale = Vector2.ONE * _rng.randf_range(1.0, 1.6)
		f.modulate = Color(0.85, 0.92, 1.0, _rng.randf_range(0.25, 0.5))
		f.z_index = 88
		add_child(f)


func _process(_delta: float) -> void:
	if _busy:
		prompt.visible = false
		return
	var near := absf(_rabbit.global_position.x - entrance_x) <= interact_radius
	if near:
		prompt.show_key(key_for(current_map()))
	else:
		prompt.hide_prompt()
	# Q goes in and out of the burrow; E is for taking and sleeping.
	if near and Input.is_action_just_pressed("enter_exit"):
		await _enter()


func _enter() -> void:
	_busy = true
	prompt.visible = false
	_rabbit.input_locked = true
	GameState.entering_burrow = true
	GameState.forest_spawn_x = exit_spawn_x

	var tween := create_tween()
	tween.tween_property(fade, "color:a", 1.0, 0.55)
	await tween.finished
	get_tree().change_scene_to_file(scene_for(current_map()))
