extends Node
## Autoload: the moon amulet, and the living forest around it.
##
## The amulet is the hero's tool, so this is the heart of the game rather than a
## visual effect. While it is awake the forest changes: the ordinary world goes
## cold and violet, and what is hidden becomes visible - signs on the trees,
## secret symbols and traces of magic. Then the amulet goes quiet and has to
## recharge, so the player has to choose when to look.
##
## It also puts the forest's inhabitants in the world: the owl, the fox, the
## spirits and the keeper, each of whom knows one part of the mystery and can be
## talked to with R.

## How long the vision lasts and how long the amulet then needs to recover.
const VISION_TIME := 4.5
const RECHARGE_TIME := 7.5
## Radius within which the rabbit can speak to someone, and gather a sign.
const TALK_RANGE := 46.0
const SIGN_RANGE := 30.0

## The hidden signs, spread along the whole forest. The kind only changes the
## colour, since the artwork is the same soft glow.
const SIGNS := [
	Vector2(360, 140), Vector2(700, 132), Vector2(1050, 138),
	Vector2(1420, 130), Vector2(1760, 140), Vector2(2130, 134),
	Vector2(2470, 138), Vector2(2830, 130), Vector2(3220, 140),
]

## The inhabitants now live in scripts/quest.gd, together with the shards,
## the notes and the Heart of the Forest.
const SPIRITS := []

var active := false
## Seconds left in the current phase; 0 while the amulet sits ready.
var _clock := 0.0
var _spawned := false
## How many of the amulet's own hidden signs have been gathered.
var found := 0

var _vision: ColorRect
var _hud: CanvasLayer
var _charge: ColorRect
var _counter: Label
var _flash: Label
var _prompt: Control
var _signs: Array = []
var _spirits: Array = []
var _glow_tex: Texture2D
var _sfx := {}
var _ambient: AudioStreamPlayer
var _music_was := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_glow_tex = load("res://fireflies/firefly_glow.png")
	for name in ["amulet", "amulet_ready"]:
		var path := "res://audio/sfx/%s.wav" % name
		if ResourceLoader.exists(path):
			_sfx[name] = load(path)
	_ambient = AudioStreamPlayer.new()
	_ambient.name = "ForestWind"
	_ambient.stream = load("res://audio/sfx/ambient_forest.wav")
	_ambient.volume_db = -20.0
	_ambient.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_ambient)
	_build_hud()
	_build_prompt()


# ------------------------------------------------------------------ per frame
func _process(delta: float) -> void:
	_tick_ambient()
	var scene := get_tree().current_scene
	if scene == null:
		return
	var forest := scene.scene_file_path.ends_with("main.tscn")
	if forest and not _spawned and scene.is_node_ready():
		_spawn_world(scene)

	if not forest:
		# The violet wash of the magical world belongs to the forest. It used to be
		# left on when the player went inside, tinting the whole burrow and every
		# prompt in it, because nothing animated it back.
		if _vision != null:
			_vision.color.a = move_toward(_vision.color.a, 0.0, delta * 4.0)
		return

	_tick_amulet(delta)
	_tick_people(scene)


## The wind bed only exists out in the forest.
func _tick_ambient() -> void:
	var scene := get_tree().current_scene
	var forest := scene != null and scene.scene_file_path.ends_with("main.tscn")
	if forest and not _ambient.playing:
		_ambient.play()
	elif not forest and _ambient.playing:
		_ambient.stop()
	if _ambient.playing:
		_ambient.volume_db = linear_to_db(maxf(GameState.sfx_volume, 0.0001)) - 14.0


func _tick_amulet(delta: float) -> void:
	# While a conversation is up the amulet sleeps, and story.gd drives it.
	if Story.is_open():
		_vision.color.a = move_toward(_vision.color.a, 0.0, delta * 2.0)
		_update_hud()
		return

	_set_locked(false)

	if active:
		_clock -= delta
		if _clock <= 0.0:
			_end_vision()
	elif _clock > 0.0:
		_clock -= delta
		if _clock <= 0.0 and _sfx.has("amulet_ready"):
			_play(_sfx["amulet_ready"])
	elif Input.is_action_just_pressed("amulet"):
		_start_vision()

	_vision.color.a = move_toward(_vision.color.a, 1.0 if active else 0.0, delta * 1.6)

	# The signs glow only while the amulet is awake, and are gathered by walking
	# close to them - that is the little puzzle of the forest.
	var rabbit := _rabbit()
	if rabbit == null:
		return
	for entry in _signs:
		var sprite: Sprite2D = entry["sprite"]
		var want := 0.0
		if not entry["found"]:
			want = 0.95 if active else 0.0
		elif active:
			want = 0.25
		sprite.modulate.a = move_toward(sprite.modulate.a, want, delta * 1.8)
		if active and not entry["found"] \
				and absf(rabbit.global_position.x - sprite.global_position.x) < SIGN_RANGE:
			_gather(entry)

	_update_hud()


## Who is close enough to talk to, and the prompt that says so.
func _tick_people(_scene: Node) -> void:
	# The people, the shards and the notes are handled by scripts/quest.gd.
	return
	var rabbit := _rabbit()
	if rabbit == null:
		return
	var near: Dictionary = {}
	var best := TALK_RANGE
	for entry in _spirits:
		var sprite: Sprite2D = entry["sprite"]
		var d: float = absf(rabbit.global_position.x - sprite.global_position.x)
		if d < best:
			best = d
			near = entry
		# A slow breath so they read as alive.
		var pulse := 0.72 + 0.28 * sin(Time.get_ticks_msec() / 900.0 + entry["phase"])
		sprite.modulate.a = pulse

	if near.is_empty():
		_prompt.visible = false
		return
	_prompt.visible = true
	if Input.is_action_just_pressed("talk") or Input.is_action_just_pressed("interact"):
		var who: String = near["who"]
		var first := Story.mark_met(who)
		var lines: Array = Story.LINES[who]["lines"]
		# The first meeting is the full introduction; afterwards they only have a
		# short word, which is how the forest stays a little withholding.
		if first:
			Story.tell(who, lines)
		else:
			Story.tell(who, [lines[lines.size() - 1]])
		_prompt.visible = false


# ------------------------------------------------------------------ the world
func _spawn_world(scene: Node) -> void:
	_spawned = true
	var holder := Node2D.new()
	holder.name = "AmuletWorld"
	scene.add_child(holder)

	for point in SIGNS:
		_signs.append(_add_sign(holder, point))

	for spec in SPIRITS:
		_spirits.append(_add_spirit(holder, spec))


func _add_sign(holder: Node2D, at: Vector2) -> Dictionary:
	var sprite := Sprite2D.new()
	sprite.texture = _glow_tex
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	sprite.position = at
	sprite.scale = Vector2(3.4, 3.4)
	sprite.z_index = -1
	sprite.material = _additive()
	# A violet-blue sigil, the colour of the amulet's own light.
	sprite.modulate = Color(0.52, 0.80, 0.96, 0.0)
	holder.add_child(sprite)

	var core := Sprite2D.new()
	core.texture = _glow_tex
	core.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	core.position = at
	core.scale = Vector2(1.1, 1.1)
	core.z_index = 0
	core.material = _additive()
	core.modulate = Color(0.86, 0.95, 1.0, 0.0)
	holder.add_child(core)

	var entry := { "sprite": sprite, "core": core, "found": false }
	sprite.set_meta("core", core)
	return entry


func _add_spirit(holder: Node2D, spec: Dictionary) -> Dictionary:
	var who: String = spec["who"]
	var colour: Color = Story.LINES[who]["colour"]

	var halo := Sprite2D.new()
	halo.texture = _glow_tex
	halo.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	halo.position = Vector2(spec["x"], spec["y"])
	halo.scale = Vector2(6.0, 6.0)
	halo.material = _additive()
	halo.modulate = Color(colour.r, colour.g, colour.b, 0.6)
	holder.add_child(halo)

	var core := Sprite2D.new()
	core.texture = _glow_tex
	core.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	core.position = Vector2(spec["x"], spec["y"])
	core.scale = Vector2(2.0, 2.0)
	core.material = _additive()
	core.modulate = Color(1.0, 1.0, 1.0, 0.85)
	holder.add_child(core)

	return { "sprite": halo, "who": who, "phase": randf() * TAU }


func _gather(entry: Dictionary) -> void:
	entry["found"] = true
	found += 1
	var total := found
	if _sfx.has("amulet_ready"):
		_play(_sfx["amulet_ready"])
	_flash.text = "знак найден  %d / %d" % [total, SIGNS.size()]
	_flash.visible = true
	var t := create_tween()
	t.tween_interval(1.8)
	t.tween_callback(func() -> void: _flash.visible = false)
	var core: Sprite2D = entry["sprite"].get_meta("core")
	core.modulate.a = 1.0


# ------------------------------------------------------------------- the amulet
func _start_vision() -> void:
	active = true
	_clock = VISION_TIME
	if _sfx.has("amulet"):
		_play(_sfx["amulet"])
	# The ordinary world cools down while the amulet is awake, which is the
	# contrast between the everyday forest and the magical one.
	_vision.color = Color(0.34, 0.52, 0.74, _vision.color.a)
	_flash.text = "амулет пробудился"
	_flash.visible = true
	_flash.modulate.a = 1.0
	var t := create_tween()
	t.tween_interval(1.2)
	t.tween_property(_flash, "modulate:a", 0.0, 0.8)
	t.tween_callback(func() -> void: _flash.visible = false)


func _end_vision() -> void:
	active = false
	_clock = RECHARGE_TIME


func _play(stream: AudioStream) -> void:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.bus = "Master"
	p.volume_db = linear_to_db(maxf(GameState.sfx_volume, 0.0001)) - 4.0
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


func _rabbit() -> CharacterBody2D:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	return scene.get_node_or_null("Rabbit") as CharacterBody2D


func _set_locked(locked: bool) -> void:
	var rabbit := _rabbit()
	if rabbit != null and rabbit.get("input_locked") != null:
		rabbit.input_locked = locked


# ------------------------------------------------------------------- interface
func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.layer = 170
	add_child(_hud)

	var root := Control.new()
	root.size = Vector2(1280.0, 720.0)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(root)

	var back := ColorRect.new()
	back.color = Color(0.05, 0.06, 0.12, 0.55)
	back.position = Vector2(44.0, 40.0)
	back.size = Vector2(220.0, 12.0)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(back)

	_charge = ColorRect.new()
	_charge.color = Color(0.80, 0.86, 1.0, 0.95)
	_charge.position = Vector2(44.0, 40.0)
	_charge.size = Vector2(220.0, 12.0)
	_charge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_charge)

	var label := Label.new()
	label.text = "амулет  —  F"
	label.position = Vector2(44.0, 12.0)
	label.add_theme_font_size_override("font_size", 17)
	label.add_theme_color_override("font_color", Color(0.72, 0.78, 0.95))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(label)

	_counter = Label.new()
	_counter.position = Vector2(44.0, 60.0)
	_counter.add_theme_font_size_override("font_size", 17)
	_counter.add_theme_color_override("font_color", Color(0.74, 0.87, 1.0))
	_counter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_counter)

	_flash = Label.new()
	_flash.position = Vector2(44.0, 90.0)
	_flash.add_theme_font_size_override("font_size", 20)
	_flash.add_theme_color_override("font_color", Color(0.90, 0.94, 1.0))
	_flash.visible = false
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_flash)

	# The violet wash of the magical world. It must never swallow the mouse.
	_vision = ColorRect.new()
	_vision.size = Vector2(1280.0, 720.0)
	_vision.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
	_vision.material = mat
	_vision.color = Color(0.34, 0.52, 0.74, 0.0)
	root.add_child(_vision)


## The amulet never asks the player for anything, so it owns no prompt at all.
##
## It used to build one and show "R - говорить" once, on start-up. Nothing ever
## hid it again, so it stayed pinned to the screen for the whole game and, sitting
## on layer 170, it covered every other prompt and interaction. The inhabitants
## and the objects own the only prompt now (scripts/quest.gd).
func _build_prompt() -> void:
	pass


func _update_hud() -> void:
	if _counter != null:
		_counter.text = "знаки: %d / %d" % [found, SIGNS.size()]
	if _charge != null:
		var ratio := 1.0
		if active:
			ratio = 1.0
		elif _clock > 0.0:
			ratio = 1.0 - _clock / RECHARGE_TIME
		_charge.size.x = 220.0 * clampf(ratio, 0.0, 1.0)
		_charge.color = Color(0.68, 0.92, 1.0, 0.95) if active else Color(0.80, 0.86, 1.0, 0.95)


func _additive() -> CanvasItemMaterial:
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return mat
