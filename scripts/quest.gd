extends Node
## Autoload: everything the player can walk up to and interact with in the
## forest - the moon shards, the notes left behind, the forest's inhabitants,
## the black rabbit and the Heart of the Forest with its final choice.
##
## The chapter list in scripts/story.gd maps onto the level the project already
## has; nothing here builds new locations, it places one thing at a time along
## the walk the player already takes, so the story is discovered by exploring.

# How far the black spirit wanders while the shards are still missing.
const BLACK_PATROL := Vector2(2500.0, 3450.0)
const BLACK_SPEED := 16.0
## Where it waits in the burrow once every shard is found.
const BLACK_WAITING := Vector2(150.0, 132.0)
const TALK_RANGE := 40.0
const THING_RANGE := 26.0

## What stands where along the forest. The order is the order of the chapters.
const THINGS := [
	{ "kind": "note", "id": "tracks", "x": 300.0, "y": 140.0 },
	{ "kind": "shard", "x": 380.0, "y": 136.0 },
	{ "kind": "person", "who": "firefly", "x": 480.0, "y": 128.0 },
	{ "kind": "note", "id": "sign", "x": 700.0, "y": 140.0 },
	{ "kind": "shard", "x": 900.0, "y": 136.0 },
	{ "kind": "note", "id": "lamp", "x": 1080.0, "y": 138.0 },
	{ "kind": "person", "who": "owl", "x": 1180.0, "y": 96.0 },
	{ "kind": "note", "id": "river", "x": 1205.0, "y": 138.0 },
	{ "kind": "note", "id": "book", "x": 1500.0, "y": 140.0 },
	{ "kind": "shard", "x": 1650.0, "y": 136.0 },
	{ "kind": "person", "who": "fox", "x": 1900.0, "y": 134.0 },
	{ "kind": "shard", "x": 2150.0, "y": 136.0 },
	{ "kind": "note", "id": "statue", "x": 2400.0, "y": 138.0 },
	{ "kind": "person", "who": "spirit", "x": 2700.0, "y": 120.0 },
	{ "kind": "shard", "x": 2750.0, "y": 136.0 },
	{ "kind": "person", "who": "black", "x": 3000.0, "y": 132.0 },
	{ "kind": "shard", "x": 3300.0, "y": 136.0 },
	{ "kind": "heart", "which": "light", "x": 3360.0, "y": 128.0 },
	{ "kind": "heart", "which": "balance", "x": 3392.0, "y": 128.0 },
	{ "kind": "heart", "which": "secret", "x": 3424.0, "y": 128.0 },
	{ "kind": "person", "who": "keeper", "x": 3520.0, "y": 130.0 },
]

var _spawned := false
var _taken := {}
var _things: Array = []
var _glow_tex: Texture2D
var _sfx := {}
var _prompt: Control
var _prompt_layer: CanvasLayer
## The wandering spirit, and the entry the prompt measures distance against.
var _black: AnimatedSprite2D
var _black_entry: Dictionary = {}
var _black_dir := 1.0
## The things that live in the burrow instead of the forest.
var _burrow_things: Array = []
var _burrow_spawned := false
var _forest_holder: Node2D
var _burrow_holder: Node2D
var _hud: CanvasLayer
var _counter: Label
var _flash: Label
var _heart_core: Sprite2D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_glow_tex = load("res://fireflies/firefly_glow.png")
	for name in ["amulet_ready", "land"]:
		var path := "res://audio/sfx/%s.wav" % name
		if ResourceLoader.exists(path):
			_sfx[name] = load(path)
	_build_hud()


func _process(delta: float) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var forest := scene.scene_file_path.ends_with("main.tscn")
	var burrow := scene.scene_file_path.ends_with("burrow_inside.tscn")
	if not forest and not burrow:
		# Leaving must take the prompt with it, or it hangs on screen.
		if _prompt != null and is_instance_valid(_prompt):
			_prompt.visible = false
		return
	# A change of scene frees the old holders, so the old list has to go.
	if _spawned and (_forest_holder == null or not is_instance_valid(_forest_holder)):
		_spawned = false
		_things.clear()
	if _burrow_spawned and (_burrow_holder == null or not is_instance_valid(_burrow_holder)):
		_burrow_spawned = false
		_burrow_things.clear()
	if forest and not _spawned and scene.is_node_ready():
		_spawn(scene)
	if burrow and not _burrow_spawned and scene.is_node_ready() \
			and Story.shards >= Story.SHARD_TOTAL:
		_spawn_burrow(scene)
	if not _spawned and not _burrow_spawned:
		return
	if forest:
		_patrol(delta)

	_update_heart()
	_update_hud()
	# While someone is talking the world waits.
	if Story.is_open() or Story.ending != "":
		_prompt.visible = false
		return
	_tick_proximity(delta)


# ------------------------------------------------------------------ spawning
func _spawn(scene: Node) -> void:
	_spawned = true
	var holder := Node2D.new()
	holder.name = "StoryWorld"
	scene.add_child(holder)
	_forest_holder = holder
	for spec in THINGS:
		var entry := _build(holder, spec)
		_things.append(entry)
		if entry["kind"] == "person" and entry["spec"]["who"] == "black":
			_black_entry = entry
	# The prompt sits UNDER the night overlay, so it reads as part of the world
	# instead of floating above every layer.
	_prompt_layer = CanvasLayer.new()
	_prompt_layer.layer = 99
	add_child(_prompt_layer)
	_prompt = load("res://scenes/key_prompt.tscn").instantiate()
	_prompt_layer.add_child(_prompt)
	_prompt.visible = false


func _build(holder: Node2D, spec: Dictionary) -> Dictionary:
	var kind: String = spec["kind"]
	var colour := _colour_for(spec)
	var halo := Sprite2D.new()
	halo.texture = _glow_tex
	halo.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	halo.position = Vector2(spec["x"], spec["y"])
	halo.material = _additive()
	halo.modulate = Color(colour.r, colour.g, colour.b, 0.0)
	holder.add_child(halo)

	var core := Sprite2D.new()
	core.texture = _glow_tex
	core.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	core.position = Vector2(spec["x"], spec["y"])
	core.material = _additive()
	core.modulate = Color(1.0, 1.0, 1.0, 0.0)
	holder.add_child(core)

	# The shards are crescents of moonlight, taken from the supplied set.
	if kind == "shard":
		var crescent := load("res://ghosts/shard_crescent.png") as Texture2D
		if crescent != null:
			core.texture = crescent
			core.scale = Vector2(1.0, 1.0)

	var size := 4.0
	var pulse := 0.0
	match kind:
		"shard":
			size = 5.0
			pulse = 0.45
		"note":
			size = 3.2
			pulse = 0.25
		"person":
			size = 6.5
			pulse = 0.3
		"heart":
			size = 9.0
			pulse = 0.2
	halo.scale = Vector2(size, size)
	core.scale = Vector2(size * 0.32, size * 0.32)

	# Everyone the rabbit meets is a ghost, cut from the supplied ghost pack.
	# The pack's own artwork is used as it is - only the tint differs.
	if kind == "person":
		var who: String = spec["who"]
		if who == "black":
			# The black spirit comes from its own pack. That strip is twelve
			# frames of animation, so it floats instead of standing still.
			var frames := load("res://ghosts/black_spirit_frames.tres") as SpriteFrames
			if frames != null:
				var spirit := AnimatedSprite2D.new()
				spirit.sprite_frames = frames
				spirit.animation = &"Float"
				spirit.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
				spirit.position = Vector2(spec["x"], spec["y"] - 14.0)
				spirit.modulate = Color(0.34, 0.38, 0.46)
				holder.add_child(spirit)
				spirit.play(&"Float")
				_black = spirit
		else:
			var art := load("res://ghosts/ghost_%s.png" % _ghost_for(who)) as Texture2D
			if art != null:
				var ghost := Sprite2D.new()
				ghost.texture = art
				ghost.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
				ghost.position = Vector2(spec["x"], spec["y"] + 14.0)
				ghost.scale = Vector2(0.8, 0.8)
				# The pack is drawn almost black, so it is lifted a little to read
				# against the night.
				ghost.modulate = Color(0.62, 0.66, 0.82)
				holder.add_child(ghost)


	var entry := {
		"spec": spec, "kind": kind, "halo": halo, "core": core,
		"phase": randf() * TAU, "base": Vector2(spec["x"], spec["y"]),
	}
	if kind == "heart":
		entry["base"] = Vector2(spec["x"], spec["y"])
		if spec["which"] == "light":
			_heart_core = halo
	return entry


func _colour_for(spec: Dictionary) -> Color:
	match spec["kind"]:
		"shard":
			return Color(0.88, 0.94, 1.0)
		"note":
			return Color(0.80, 0.74, 0.52)
		"heart":
			return Color(1.0, 0.98, 0.86)
		_:
			return Story.PEOPLE[spec["who"]]["colour"]


# ------------------------------------------------------------------ each frame
## The Heart of the Forest: the sphere itself grows with every shard brought.
func _update_heart() -> void:
	if _heart_core == null or not is_instance_valid(_heart_core):
		return
	var power := float(Story.shards) / float(Story.SHARD_TOTAL)
	_heart_core.scale = Vector2(lerpf(5.0, 22.0, power), lerpf(5.0, 22.0, power))
	_heart_core.modulate = Color(1.0, 0.99, 0.90, lerpf(0.25, 0.85, power))
	for entry in _things:
		if entry["kind"] != "heart":
			continue
		var which: String = entry["spec"]["which"]
		var shown := false
		if Story.ending == "":
			if which == "secret":
				shown = Story.knows_the_whole_story()
			else:
				shown = Story.shards >= 1
		entry["halo"].visible = shown
		entry["core"].visible = shown


## What is close enough to use, and the little prompt that says so.
func _tick_proximity(delta: float) -> void:
	var scene := get_tree().current_scene
	var rabbit := scene.get_node_or_null("Rabbit") as CharacterBody2D
	if rabbit == null:
		return

	var best := 1e9
	var near: Dictionary = {}
	var active: Array = _things if _spawned else _burrow_things
	for entry in active:
		var here := entry["base"] as Vector2
		var d: float = absf(rabbit.global_position.x - here.x)
		var wanted := d
		# The heart's choice lights only count once they are shown.
		if entry["kind"] == "heart" and not (entry["halo"] as Sprite2D).visible:
			continue
		if entry["kind"] == "person":
			d = absf(rabbit.global_position.x - here.x)
			if d > TALK_RANGE:
				continue
			wanted = d
		elif d > THING_RANGE:
			continue
		if wanted < best:
			best = wanted
			near = entry

		# A slow breath, so nothing looks pasted on.
		var pulse := 0.7 + 0.3 * sin(Time.get_ticks_msec() / 1000.0 + entry["phase"])
		var base_alpha := 0.55
		if entry["kind"] == "shard":
			base_alpha = 0.8
		elif entry["kind"] == "note":
			base_alpha = 0.4
		(entry["halo"] as Sprite2D).modulate.a = base_alpha * pulse

	if near.is_empty():
		_prompt.visible = false
		return
	_prompt.visible = true
	if near["kind"] == "person" or near["kind"] == "heart":
		_prompt.call("show_key", "talk")
	else:
		_prompt.call("show_key", "take")

	if Input.is_action_just_pressed("interact") or Input.is_action_just_pressed("talk"):
		_use(near)


# ------------------------------------------------------------------ interacting
func _use(entry: Dictionary) -> void:
	var spec: Dictionary = entry["spec"]
	match entry["kind"]:
		"shard":
			_take_shard(entry)
		"note":
			var id: String = spec["id"]
			var first := Story.found_note(id)
			var note: Dictionary = Story.NOTES[id]
			if first:
				_say("", note["lines"], str(note["name"]))
				_announce("записка найдена  %d / %d" % [Story.notes.size(), Story.NOTES.size()])
				_fade_out(entry)
			else:
				_say("", note["lines"], str(note["name"]))
		"person":
			var who: String = spec["who"]
			Story.mark_met(who)
			var lines: Array = Story.PEOPLE[who]["lines"]
			if who == "black" and Story.met_black and Story.ending == "":
				Story.tell(who, lines)
			else:
				Story.tell(who, lines)
		"heart":
			_heart(spec["which"])


func _heart(which: String) -> void:
	if which == "secret":
		Story.finale("light")
		return
	if Story.shards < Story.SHARD_TOTAL and which == "light":
		Story.tell("", ["Сфера почти погасла.",
			"Каждый осколок вернёт ей часть света.",
			"Найдено: %d из %d." % [Story.shards, Story.SHARD_TOTAL],
			"Приходи, когда соберёшь больше."])
		return
	Story.finale(which)


func _take_shard(entry: Dictionary) -> void:
	var here := entry["base"] as Vector2
	if _taken.has(here):
		return
	_taken[here] = true
	var total := Story.found_shard()
	_fade_out(entry)
	# The find is answered by the rabbit itself: a cold bloom opens behind it.
	# Not on its fur - the light is put behind the silhouette on purpose.
	var rabbit := get_tree().current_scene.get_node_or_null("Rabbit")
	if rabbit != null and rabbit.has_method("flash_backlight"):
		rabbit.call("flash_backlight")
	_announce("осколок лунного света  %d / %d" % [total, Story.SHARD_TOTAL])
	if _sfx.has("amulet_ready"):
		_play(_sfx["amulet_ready"])
	# The pendant answers straight away, which is the whole point of the shards.
	Story.tell("", ["Осколок холодный — и всё же тёплый.",
		"Кулон стал ярче."])


func _say(speaker: String, lines: Array, title := "") -> void:
	Story.tell(speaker, lines)


## Signs that have been used fade to a faint memory of themselves.
func _fade_out(entry: Dictionary) -> void:
	var halo: Sprite2D = entry["halo"]
	var core: Sprite2D = entry["core"]
	var t := create_tween()
	t.tween_property(halo, "modulate:a", 0.12, 0.5)
	t.parallel().tween_property(core, "modulate:a", 0.0, 0.5)


func _announce(text: String) -> void:
	_flash.text = text
	_flash.visible = true
	_flash.modulate.a = 1.0
	var t := create_tween()
	t.tween_interval(2.2)
	t.tween_property(_flash, "modulate:a", 0.0, 0.7)
	t.tween_callback(func() -> void: _flash.visible = false)


func _play(stream: AudioStream) -> void:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = linear_to_db(maxf(GameState.sfx_volume, 0.0001)) - 4.0
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


# ------------------------------------------------------------------ interface
func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.layer = 172
	add_child(_hud)

	var root := Control.new()
	root.size = Vector2(1280.0, 720.0)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(root)

	_counter = Label.new()
	_counter.position = Vector2(900.0, 40.0)
	_counter.size = Vector2(340.0, 30.0)
	_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_counter.add_theme_font_size_override("font_size", 18)
	_counter.add_theme_color_override("font_color", Color(0.86, 0.90, 1.0))
	_counter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_counter)

	_flash = Label.new()
	_flash.position = Vector2(760.0, 74.0)
	_flash.size = Vector2(480.0, 30.0)
	_flash.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_flash.add_theme_font_size_override("font_size", 20)
	_flash.add_theme_color_override("font_color", Color(0.94, 0.94, 1.0))
	_flash.visible = false
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_flash)


func _update_hud() -> void:
	var scene := get_tree().current_scene
	var here := scene != null and scene.scene_file_path.ends_with("main.tscn")
	_hud.visible = here
	if not here:
		return
	_counter.text = "осколки %d / %d      записки %d / %d" % [
		Story.shards, Story.SHARD_TOTAL, Story.notes.size(), Story.NOTES.size()]


func _additive() -> CanvasItemMaterial:
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return mat


## Which ghost from the supplied pack plays a given character.
func _ghost_for(who: String) -> String:
	match who:
		"firefly":
			return "sweety"
		"owl":
			return "beaned"
		"fox":
			return "punky"
		"spirit":
			return "dandy"
		"keeper":
			return "ghoulish"
		"black":
			return "screeching"
	return "sweety"


## Walks the black spirit up and down the level on its own. Once every shard has
## been found it stops wandering and waits in the burrow instead.
func _patrol(delta: float) -> void:
	if _black == null or not is_instance_valid(_black):
		return
	if Story.shards >= Story.SHARD_TOTAL:
		# Its part is over: it is not out here any more.
		_black.visible = false
		return
	_black.visible = true
	var here := _black.position
	here.x += BLACK_SPEED * _black_dir * delta
	if here.x >= BLACK_PATROL.y:
		here.x = BLACK_PATROL.y
		_black_dir = -1.0
	elif here.x <= BLACK_PATROL.x:
		here.x = BLACK_PATROL.x
		_black_dir = 1.0
	_black.position = here
	_black.scale.x = absf(_black.scale.x) * _black_dir
	if not _black_entry.is_empty():
		_black_entry["base"] = here


## Once all the shards are gathered the spirit is waiting inside the burrow.
func _spawn_burrow(scene: Node) -> void:
	_burrow_spawned = true
	_burrow_holder = Node2D.new()
	_burrow_holder.name = "BlackSpiritWaiting"
	scene.add_child(_burrow_holder)
	var spec := {
		"kind": "person", "who": "black",
		"x": BLACK_WAITING.x, "y": BLACK_WAITING.y,
	}
	_burrow_things.append(_build(_burrow_holder, spec))
	print("[quest] the black spirit is waiting in the burrow")
