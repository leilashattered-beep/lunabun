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
## Where it waits in the burrow once every shard is found. Kept clear of the
## table and the nest, in the open floor before it.
const BLACK_WAITING := Vector2(112.0, 132.0)
const TALK_RANGE := 40.0
const THING_RANGE := 26.0
## Walk this close to the waiting ghost and the transformation begins.
const ENDING_RANGE := 42.0
## The black rabbit the ghost turns into: the supplied character, upscaled 4x
## from the 48x48 pack with cleaned edges and a light sharpen. It turns to face
## the player and is drawn a little smaller than the hero.
const BLACK_RABBIT_WEST := "res://rabbit/black/black_west.png"
const BLACK_RABBIT_EAST := "res://rabbit/black/black_east.png"
const BLACK_RABBIT_SCALE := 0.18

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
## Full-screen black used by the automatic return to the burrow.
var _fade_layer: CanvasLayer
var _fade_rect: ColorRect
## The last meeting in the burrow: the ghost changes before it can be talked to.
var _ending_started := false


## True while a shard, note, animal or the heart is close enough to use. The
## burrow door reads this so one key press never does two things at once.
func has_nearby_thing() -> bool:
	return _prompt != null and _prompt.visible


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_glow_tex = load("res://fireflies/firefly_glow.png")
	for name in ["amulet", "amulet_ready", "land"]:
		var path := "res://audio/sfx/%s.wav" % name
		if ResourceLoader.exists(path):
			_sfx[name] = load(path)
	_build_hud()
	_ensure_prompt()


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
		_ending_started = false
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
	# The last meeting is a cut-scene: walking up to the waiting ghost starts
	# the transformation before any prompt or key press.
	if burrow and _tick_ending(scene):
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
	_ensure_prompt()


## Built once, in `_ready`, and kept on the autoload: the burrow can be the
## first scene (a new game), where the forest's `_spawn` never runs.
func _ensure_prompt() -> void:
	if _prompt != null and is_instance_valid(_prompt):
		return
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
	var body: Node2D = null
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
				body = spirit
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
	if body != null:
		entry["body"] = body
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
		if entry.get("hidden", false):
			continue
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


# --------------------------------------------------------------- the last meeting
## True once the ending has begun, so the normal prompts stay out of its way.
func _tick_ending(scene: Node) -> bool:
	if _ending_started:
		return true
	if Story.ending != "" or Story.shards < Story.SHARD_TOTAL:
		return false
	if _burrow_things.is_empty():
		return false
	var entry: Dictionary = {}
	for thing in _burrow_things:
		if thing["kind"] == "person" and thing["spec"]["who"] == "black":
			entry = thing
			break
	if entry.is_empty():
		return false
	var rabbit := scene.get_node_or_null("Rabbit") as CharacterBody2D
	if rabbit == null:
		return false
	var here: Vector2 = entry["base"]
	if absf(rabbit.global_position.x - here.x) > ENDING_RANGE:
		return false
	_begin_ending(entry)
	return true


## The waiting ghost comes apart in a bloom of blue light and becomes the black
## rabbit from the supplied pack. Then the final conversation starts on its own.
func _begin_ending(entry: Dictionary) -> void:
	if _ending_started:
		return
	_ending_started = true
	if _prompt != null and is_instance_valid(_prompt):
		_prompt.visible = false
	var scene := get_tree().current_scene
	var rabbit := scene.get_node_or_null("Rabbit") as CharacterBody2D \
		if scene != null else null
	if rabbit != null:
		rabbit.input_locked = true
	Story.mark_met("black")

	var here: Vector2 = entry["base"]
	var ghost := entry.get("body") as AnimatedSprite2D
	var halo: Sprite2D = entry["halo"]
	var core: Sprite2D = entry["core"]
	var holder: Node2D = halo.get_parent()
	var face_left := rabbit != null and rabbit.global_position.x <= here.x

	if _sfx.has("amulet"):
		_play(_sfx["amulet"])

	# A soft blue flare opens where the ghost stands.
	var flare := Sprite2D.new()
	flare.texture = _glow_tex
	flare.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	flare.material = _additive()
	flare.position = Vector2(here.x, here.y - 14.0)
	flare.scale = Vector2(2.4, 2.4)
	flare.modulate = Color(0.70, 0.84, 1.0, 0.0)
	holder.add_child(flare)
	var flare_t := create_tween()
	flare_t.tween_property(flare, "modulate:a", 0.85, 0.16)
	flare_t.parallel().tween_property(flare, "scale", Vector2(8.0, 8.0), 0.9) \
		.set_trans(Tween.TRANS_SINE)
	flare_t.tween_property(flare, "modulate:a", 0.0, 0.5)
	flare_t.tween_callback(flare.queue_free)

	# Motes drift off the ghost as it loses its shape.
	for i in 12:
		var mote := Sprite2D.new()
		mote.texture = _glow_tex
		mote.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		mote.material = _additive()
		var mx := here.x + randf_range(-18.0, 18.0)
		var my := here.y - 14.0 + randf_range(-22.0, 10.0)
		mote.position = Vector2(mx, my)
		mote.scale = Vector2.ONE * randf_range(0.5, 1.2)
		mote.modulate = Color(0.62, 0.80, 1.0, 0.8)
		holder.add_child(mote)
		var mote_t := create_tween().set_parallel(true)
		mote_t.tween_property(mote, "position:y", my - randf_range(18.0, 42.0),
			randf_range(0.7, 1.3))
		mote_t.tween_property(mote, "position:x", mx + randf_range(-14.0, 14.0), 1.0)
		mote_t.tween_property(mote, "modulate:a", 0.0, randf_range(0.8, 1.3))
		mote_t.chain().tween_callback(mote.queue_free)

	# The ghost pulls itself apart and goes out.
	var out := create_tween().set_parallel(true)
	if ghost != null:
		out.tween_property(ghost, "modulate:a", 0.0, 0.7)
		out.tween_property(ghost, "scale", Vector2(1.2, 1.2), 0.7)
		out.tween_property(ghost, "position:y", ghost.position.y - 6.0, 0.7)
	out.tween_property(halo, "modulate:a", 0.0, 0.7)
	out.tween_property(core, "modulate:a", 0.0, 0.7)
	await get_tree().create_timer(0.55).timeout
	if ghost != null and is_instance_valid(ghost):
		ghost.visible = false

	# The black rabbit takes its place, on the floor of the nest room.
	var glow := Sprite2D.new()
	glow.texture = _glow_tex
	glow.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	glow.material = _additive()
	glow.position = Vector2(here.x, 146.0)
	glow.scale = Vector2(2.8, 2.8)
	glow.modulate = Color(0.52, 0.68, 1.0, 0.0)
	holder.add_child(glow)

	var path := BLACK_RABBIT_WEST if face_left else BLACK_RABBIT_EAST
	var art := load(path) as Texture2D
	var body := Sprite2D.new()
	body.texture = art
	body.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var target := Vector2(BLACK_RABBIT_SCALE, BLACK_RABBIT_SCALE)
	# The 192 px clean-up holds the same feet line as the player's sprite.
	body.position = Vector2(here.x, 145.5)
	body.scale = target * 0.86
	body.modulate = Color(1.0, 1.0, 1.0, 0.0)
	holder.add_child(body)
	var in_t := create_tween().set_parallel(true)
	in_t.tween_property(body, "modulate:a", 1.0, 0.55)
	in_t.tween_property(body, "scale", target, 0.55)
	in_t.tween_property(glow, "modulate:a", 0.30, 0.7)
	if _sfx.has("amulet_ready"):
		_play(_sfx["amulet_ready"])
	await in_t.finished

	# A slow breath, so he is alive while the last words are spoken.
	var bob := body.create_tween().set_loops()
	bob.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	bob.tween_property(body, "position:y", 144.5, 1.8)
	bob.tween_property(body, "position:y", 145.5, 1.8)

	await get_tree().create_timer(0.45).timeout
	Story.final_scene()


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
			if who == "black":
				# Once every shard is back, the black rabbit waits in the
				# burrow; walking up to it starts the transformation.
				if entry.get("in_burrow", false) \
						and Story.shards >= Story.SHARD_TOTAL:
					_begin_ending(entry)
					return
				Story.mark_met(who)
				Story.tell(who, Story.black_lines())
			else:
				var first := Story.mark_met(who)
				var person: Dictionary = Story.PEOPLE[who]
				Story.tell(who, person["first"] if first else person["again"])
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
	# The forest's story has to be read before its last piece of light can be
	# carried home, otherwise the finale would arrive without the notes.
	if Story.shards + 1 >= Story.SHARD_TOTAL and not Story.all_notes_found():
		Story.tell("", [
			"Последний осколок не отзывается.",
			"Сначала прочитай все записки: %d из %d." % [
				Story.notes.size(), Story.NOTES.size()],
			"Лес должен рассказать свою историю до конца.",
		])
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
	# The last shard pulls the rabbit home by itself.
	if total >= Story.SHARD_TOTAL:
		await _return_to_burrow()


## Fades the forest out and puts the rabbit in the burrow, where the black
## rabbit is already waiting, instead of making the player walk all the way back.
func _return_to_burrow() -> void:
	# Let the shard's own line be read first.
	while Story.is_open():
		await get_tree().process_frame
	var scene := get_tree().current_scene
	var rabbit := scene.get_node_or_null("Rabbit") if scene != null else null
	if rabbit != null and rabbit.get("input_locked") != null:
		rabbit.input_locked = true
	if _prompt != null and is_instance_valid(_prompt):
		_prompt.visible = false
	_fade_layer.visible = true
	_fade_rect.color.a = 0.0
	var t := create_tween()
	t.tween_property(_fade_rect, "color:a", 1.0, 0.8)
	await t.finished
	GameState.entering_burrow = true
	get_tree().change_scene_to_file("res://scenes/burrow_inside.tscn")
	# The burrow fades itself in; this black is only the cover for the cut.
	await get_tree().process_frame
	await get_tree().process_frame
	_fade_rect.color.a = 0.0
	_fade_layer.visible = false


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

	# Above everything, including the HUD: the automatic trip home covers the
	# whole screen, so the change of place is never a hard cut.
	_fade_layer = CanvasLayer.new()
	_fade_layer.layer = 200
	_fade_layer.visible = false
	add_child(_fade_layer)
	_fade_rect = ColorRect.new()
	_fade_rect.size = Vector2(1280.0, 720.0)
	_fade_rect.color = Color(0.01, 0.01, 0.03, 0.0)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_layer.add_child(_fade_rect)


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
		"keeper":
			return "dandy"
		"firefly":
			return "beaned"
		"fox":
			return "ghoulish"
		"owl":
			return "punky"
		"spirit":
			return "sweety"
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
		if not _black_entry.is_empty():
			_black_entry["hidden"] = true
		return
	_black.visible = true
	if not _black_entry.is_empty():
		_black_entry["hidden"] = false
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
	var entry := _build(_burrow_holder, spec)
	entry["in_burrow"] = true
	_burrow_things.append(entry)
	print("[quest] the black spirit is waiting in the burrow")
