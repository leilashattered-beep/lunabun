extends Node2D
## Inside of the burrow: one screen, the rabbit's home.
##
## Layer order comes from the package and is preserved: `Room` sits on canvas
## layer -1 (behind the player) and `Front` on canvas layer 1 (roots and earth
## drawn over the player). Nothing is flattened into a single image.
##
## The package's README lists the glow it does not ship - the lamp, the warm
## sleeping corner, the shaft of light from the window - so those are added here
## as additive sprites and a ColorRect. The pixel art itself is untouched.

## The room is the only separate location: its door leads out into the single
## outdoor world (the forest, with the burrow's hill at its far end).
const OUTSIDE_SCENE := "res://scenes/main.tscn"
## The artwork is authored on a 320x180 canvas and the game is shown through a
## 4x camera zoom at 1280x720, so CanvasLayer-based art has to be scaled to match.
const UI_SCALE := 4.0

@export var floor_y := 150.0
@export var door_x := 34.0
@export var bed_x := 254.0
@export var walk_min_x := 30.0
@export var walk_max_x := 290.0
@export var bed_lie_y := 126.0
@export var door_spawn_x := 50.0
@export var interact_radius := 26.0
## How long the rabbit sleeps before waking by itself.
@export var sleep_seconds := 3.5

@onready var rabbit: CharacterBody2D = $Rabbit
@onready var prompt: Control = $Ui/Prompt
@onready var fade: ColorRect = $Ui/FadeRect
@onready var line: Label = $Ui/Line

var _sleeping := false
var _busy := false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	prompt.hide_prompt()
	line.visible = false
	fade.color = Color(0.02, 0.02, 0.06, 0.0)

	# The room artwork ships inside CanvasLayers, and a CanvasLayer is not moved
	# or scaled by the Camera2D. The game is shown through a 4x camera zoom, so
	# those layers are scaled to match here - otherwise the room would sit in a
	# small corner of the 1280x720 window.
	_scale_art_layers()

	rabbit.walk_limits = Vector2(walk_min_x, walk_max_x)
	rabbit.floor_range = Vector2(floor_y - 1.0, floor_y + 1.0)
	rabbit.global_position = Vector2(door_spawn_x, floor_y)
	# The nest is a raised surface: the rabbit can hop onto it and stand there.
	rabbit.platform_x = Vector2(bed_x - 30.0, bed_x + 20.0)
	rabbit.platform_y = bed_lie_y + 8.0

	_build_lighting()
	_open_with_the_story()
	# Coming in from the forest: fade up from black so the change of place reads
	# as stepping through the entrance rather than a hard cut.
	_fade_in()


func _scale_art_layers() -> void:
	_scale_layers_in(self)


## Scaled recursively: the room art sits inside the imported instance, not as a
## direct child of this scene.
func _scale_layers_in(node: Node) -> void:
	for child in node.get_children():
		if child is CanvasLayer and (child as CanvasLayer).layer < 100:
			(child as CanvasLayer).scale = Vector2(UI_SCALE, UI_SCALE)
		_scale_layers_in(child)


func _fade_in() -> void:
	fade.color.a = 1.0
	var tween := create_tween()
	tween.tween_property(fade, "color:a", 0.0, 0.7)


## The glow the package leaves to the engine. Additive sprites, so it stays
## pixel light and never looks like a modern blur.
func _build_lighting() -> void:
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	var glow_tex: Texture2D = load("res://fireflies/firefly_glow.png")
	var pool_tex: Texture2D = load("res://fireflies/firefly_pool.png")

	# Warm light over the sleeping nest: this is what makes it feel safe.
	_add_glow(add, pool_tex, Vector2(bed_x - 8.0, floor_y - 3.0),
		Vector2(5.2, 2.0), Color(1.0, 0.80, 0.48, 0.30), 85)
	_add_glow(add, glow_tex, Vector2(bed_x - 16.0, floor_y - 13.0),
		Vector2(3.2, 3.2), Color(1.0, 0.86, 0.56, 0.45), 88)

	# Small steady lamp glow further along the wall.
	_add_glow(add, glow_tex, Vector2(150.0, 96.0), Vector2(3.4, 3.4),
		Color(1.0, 0.84, 0.52, 0.55), 88)

	# Cool light falling in from the window, pooled on the floor.
	_add_glow(add, pool_tex, Vector2(196.0, floor_y - 5.0), Vector2(3.4, 4.2),
		Color(0.70, 0.85, 1.0, 0.22), 80)

	# A few dim fireflies indoors, matching the forest's mood.
	for i in 7:
		var f := Sprite2D.new()
		f.texture = glow_tex
		f.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		f.material = add
		f.position = Vector2(_rng.randf_range(40.0, 300.0), _rng.randf_range(70.0, 145.0))
		f.scale = Vector2.ONE * _rng.randf_range(1.1, 1.8)
		f.modulate = Color(1.0, 0.95, 0.75, _rng.randf_range(0.18, 0.40))
		f.z_index = 86
		add_child(f)


func _add_glow(material: CanvasItemMaterial, tex: Texture2D, pos: Vector2,
		scale_v: Vector2, tint: Color, z: int) -> void:
	var s := Sprite2D.new()
	s.texture = tex
	s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	s.material = material
	s.position = pos
	s.scale = scale_v
	s.modulate = tint
	s.z_index = z
	add_child(s)


func _process(_delta: float) -> void:
	if _busy:
		return
	var x := rabbit.global_position.x
	var near_bed := absf(x - bed_x) <= interact_radius + 6.0
	var near_door := absf(x - door_x) <= interact_radius

	if _sleeping:
		# Waking is asleep-only, so show the same "sleep" key art.
		prompt.show_key("sleep")
	elif near_bed:
		prompt.show_key("sleep")
	elif near_door:
		prompt.show_key("exit")
	else:
		prompt.hide_prompt()

	# Polled rather than handled as an event: this works identically for real
	# input, for gamepads and for scripted input in tests.
	# E sleeps and wakes, Q goes out of the door, R talks.
	if Input.is_action_just_pressed("enter_exit") and not _sleeping and near_door:
		await _leave()
		return
	if not Input.is_action_just_pressed("interact"):
		return
	if _sleeping:
		if near_bed:
			await _wake()
		return
	if near_bed:
		await _sleep()

## Shows a short spoken line for a moment. Enough to make R — говорить mean
## something without adding a dialogue system.
func _say(text: String) -> void:
	line.text = text
	line.visible = true
	line.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_interval(1.6)
	tween.tween_property(line, "modulate:a", 0.0, 0.6)
	tween.tween_callback(func(): line.visible = false)


## Hops onto the sleeping place, curls up, the room goes dark, and after a
## couple of seconds the rabbit wakes by itself.
func _sleep() -> void:
	_busy = true
	prompt.hide_prompt()
	rabbit.input_locked = true
	rabbit.velocity = Vector2.ZERO
	rabbit.play_idle()
	# The rabbit leaves the floor to get onto the nest, so the Y clamp that
	# keeps it on the ground has to stand down for the duration.
	rabbit.clamp_to_floor = false

	# Settle the rabbit just beside the nest and face it towards the bed.
	var approach := create_tween()
	approach.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	approach.tween_property(rabbit, "global_position:x", bed_x - 14.0, 0.35)
	approach.parallel().tween_property(rabbit.sprite, "rotation_degrees", 0.0, 0.2)
	await approach.finished

	# The hop: a small arc onto the nest, in two frames like a real hop.
	rabbit.play_walk()
	var hop := create_tween()
	hop.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	hop.tween_property(rabbit, "global_position:x", bed_x - 2.0, 0.42)
	hop.parallel().tween_property(rabbit, "global_position:y", bed_lie_y - 12.0, 0.21)
	await hop.finished
	var drop := create_tween()
	drop.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	drop.tween_property(rabbit, "global_position:y", bed_lie_y, 0.21)
	await drop.finished

	# Lie down on the moss and put the screen out. The rabbit is NOT turned over:
	# it keeps its normal pose on the nest and only the screen fades.
	rabbit.lying_down = true
	rabbit.play_sleep()
	var curl := create_tween()
	curl.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	curl.tween_property(fade, "color:a", 1.0, 0.9)
	await curl.finished

	_sleeping = true
	GameState.has_slept = true

	# Calm night pause, then wake up on its own.
	for i in int(sleep_seconds * 60.0):
		await get_tree().physics_frame
	_busy = false
	await _wake()


func _wake() -> void:
	_busy = true
	prompt.hide_prompt()
	rabbit.input_locked = true
	rabbit.lying_down = false
	rabbit.play_idle()

	var uncurl := create_tween()
	uncurl.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	uncurl.tween_property(rabbit.sprite, "rotation_degrees", 0.0, 0.4)
	uncurl.parallel().tween_property(fade, "color:a", 0.0, 0.7)
	await uncurl.finished

	# Hop back down to the floor.
	var hop := create_tween()
	hop.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	hop.tween_property(rabbit, "global_position:y", floor_y - 12.0, 0.2)
	await hop.finished
	var land := create_tween()
	land.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	land.tween_property(rabbit, "global_position:y", floor_y, 0.2)
	await land.finished

	rabbit.play_idle()
	rabbit.clamp_to_floor = true
	_sleeping = false
	_busy = false
	rabbit.input_locked = false


## Fades out and hands control back to the forest.
func _leave() -> void:
	_busy = true
	prompt.hide_prompt()
	rabbit.input_locked = true
	var tween := create_tween()
	tween.tween_property(fade, "color:a", 1.0, 0.55)
	await tween.finished
	# Tell the outdoor world to put the rabbit next to the hole it came out of.
	GameState.returning_from_burrow = true
	get_tree().change_scene_to_file(OUTSIDE_SCENE)


## The game opens on the story: the rabbit wakes, and the first thing it says to
## itself is that the moon is gone. It plays by itself, so the opening never
## depends on the player finding the right button.
func _open_with_the_story() -> void:
	if Story.intro_seen:
		return
	Story.intro_seen = true
	await get_tree().create_timer(1.1).timeout
	Story.tell("", Story.INTRO)
