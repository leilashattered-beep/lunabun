extends CharacterBody2D
## Luna the rabbit - side-scrolling quadruped controller.
##
## Movement is horizontal only (A / D). There is no gravity: Y stays locked on
## the floor and the ground collision below the scene keeps the rabbit from
## falling through. Space makes it hop.
##
## The hop lifts the *sprite* in an arc while the body stays on the floor. That
## way the rabbit still follows slopes and bridges while airborne, and nothing
## can leave the level.
##
## The same node is used in the forest and in the burrow. Each location sets
## `walk_limits` (how far left/right the rabbit may go) and `floor_range` (the
## band its Y is clamped to), so the controller works on both maps.

const SPEED := 55.0
const ACCELERATION := 420.0
const FRICTION := 520.0
## How high and how long the hop is. High enough to reach the sleeping place.
const JUMP_HEIGHT := 28.0
const JUMP_TIME := 0.5

## The shard bloom behind the rabbit: how long it takes to open and die away,
## and the moonlight colour it is made of.
const BACKLIGHT_TIME := 0.9
const BACKLIGHT_COLOUR := Color(0.82, 0.91, 1.0)

## Idle / standing frames (1 frame) taken from the idle PNG.
@export var idle_frames: SpriteFrames
## Walk cycle (8 frames) taken from the walking PNGs.
@export var walk_frames: SpriteFrames
## Hop: take-off, two airborne frames and the landing crouch.
@export var jump_frames: SpriteFrames
## Optional sleeping pose. When empty the rabbit just holds its idle pose.
@export var sleep_frames: SpriteFrames

## Horizontal range the rabbit may walk in (set by the location).
var walk_limits := Vector2(8.0, 3192.0)
## Y band the rabbit is clamped to (set by the location). A safety net so it can
## never leave the level whatever happens with the collision.
var floor_range := Vector2(143.0, 157.0)
## While true the rabbit ignores input (used during scene transitions and sleep).
var input_locked := false
## While true the rabbit is curled up in its sleeping place.
var lying_down := false
## While true Y is clamped to `floor_range`. Locations turn this off for scripted
## moves that leave the floor - hopping onto the sleeping place, for example,
## would otherwise be pulled straight back down by the clamp.
var clamp_to_floor := true

## A raised surface the location lets the rabbit hop onto - its sleeping place.
## `platform_x` is the x range and `platform_y` the height of its top; left as
## ZERO/ZERO by locations that have nothing to climb on.
var platform_x := Vector2.ZERO
var platform_y := 0.0
## True while the rabbit is standing on that raised surface.
var on_platform := false

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

var _facing := 1
## Where the sprite sits when grounded, so the hop can lift it and put it back.
var _base_offset := Vector2.ZERO
## Progress through the hop, or -1 while grounded.
var _jump_t := -1.0
## Height the current hop started from, so it lands back on the same surface.
var _jump_from_y := 0.0
## True while the rabbit is dropping off the edge of the platform.
var _falling := false
## Footstep timing and the loaded little sounds.
const STEP_INTERVAL := 0.34
var _step_clock := 0.0
var _step_flip := false
var _sfx := {}
var _rng := RandomNumberGenerator.new()
var _camera: Camera2D
## Turned off while the rabbit is talking, so the camera can sit
## on it instead of leaning ahead.
var lead_enabled := true
## The two lights that grow with the story.
var _pendant: Sprite2D
var _pool: Sprite2D
## The cold bloom that opens behind the rabbit when a moon shard is taken.
var _backlight: Node2D
var _backlight_flash: Sprite2D
var _backlight_halo: Sprite2D
var _backlight_core: Sprite2D
var _backlight_pool: Sprite2D
## The tweens of the bloom currently playing, so a new find can cut the old one.
var _backlight_tweens: Array[Tween] = []


func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_GROUNDED
	# There is no gravity here, so the rabbit would drift off the floor instead
	# of sticking to it; snapping keeps it planted while it walks.
	floor_snap_length = 8.0
	floor_stop_on_slope = false

	velocity = Vector2.ZERO
	_base_offset = sprite.offset
	_load_sounds()

	if idle_frames != null:
		sprite.sprite_frames = idle_frames
	_add_pendant_glow()
	_add_firefly_friends()
	_play(&"Idle")


## A few fireflies drift around the rabbit, so the dark opens up as it walks.
##
## They are ordinary members of the swarm: they wander on a loose leash beside
## the rabbit, fly past it and fade in and out. They are not markers - the
## swarm is added to the level, not to the rabbit, so it stays in world space.
func _add_firefly_friends() -> void:
	var packed := load("res://scenes/firefly_friends.tscn") as PackedScene
	if packed == null:
		return
	var host := get_parent()
	if host == null:
		return
	var swarm: Node2D = packed.instantiate()
	# The swarm hovers over whatever floor this location has.
	if "floor_y" in swarm:
		swarm.floor_y = floor_range.x
	if "ceiling_y" in swarm:
		swarm.ceiling_y = maxf(floor_range.x - 96.0, 20.0)
	# The scene root is still filling in its children while this runs, so the
	# swarm joins the level on the next idle frame; only then do both nodes share
	# a tree, which is what the follow path needs.
	host.add_child.call_deferred(swarm)
	_attach_follow.call_deferred(swarm)


func _attach_follow(swarm: Node2D) -> void:
	if is_instance_valid(swarm) and swarm.is_inside_tree() and "follow_path" in swarm:
		swarm.follow_path = swarm.get_path_to(self)


## The rabbit carries a piece of moonlight: a soft white-blue glow that follows
## its silhouette, so it is always readable in the dark.
##
## Two things make it work:
##
##  * the sprite itself is brightened, because the night overlay multiplies
##    everything under it - without this the white fur would read as grey;
##  * a few additive halos are laid over the body, the head, the tail and the
##    paws, plus a small pool on the ground and a brighter point at the pendant.
##
## All of them are children of the sprite, so they follow the animation, the
## facing flip and the hop with no extra work. Sizes are in the sprite's own
## frame (130x128, so 1 frame pixel = 0.3 world pixels), chosen from the glow
## texture, whose bright core is about 43% of its extent.
func _add_pendant_glow() -> void:
	# The moonlit aura belongs to the forest. Inside the burrow the rabbit keeps
	# its normal look, so the glow is simply not built there.
	if not _outdoors():
		sprite.modulate = Color(1.12, 1.14, 1.20)
		return

	# The night overlay darkens the rabbit along with the scenery; this lifts the
	# white fur back up. Kept deliberately modest: pushed too far the fur blows
	# out to flat white and the rabbit loses its outline.
	var power := Story.pendant_power()
	sprite.modulate = Color(0.98 + 0.03 * power, 1.0 + 0.03 * power, 1.06 + 0.04 * power)

	# NOTE: there is deliberately no white halo around the body. A glow wrapped
	# around the rabbit reads as a white outline; the light is carried by the
	# lantern below instead, which falls on the world rather than on the rabbit.
	# Only the pendant keeps a small lit point of its own.
	# The pendant is the progress bar of the whole story: every moon shard
	# makes it bigger and brighter, and the player sees it happen.
	var scale_up := 2.2 + 1.0 * power
	var pendant := _halo("PendantGlow", Vector2(0.0, 24.0),
		Vector2(scale_up, scale_up), 0.30 + 0.20 * power, 2)
	_pendant = pendant

	# The lantern the rabbit carries: warm light that falls on the ground and on
	# whatever is close by. Because the scenery is only darkened, adding light on
	# top brings the artwork back into view, so the forest opens up as the rabbit
	# walks. Both are children of the body, so they stay on the floor during a
	# hop.
	_light_around("LanternBubble", Vector2(0.0, -2.0), Vector2(8.0, 8.0), 0.05 + 0.05 * power, -2)
	var pool := _light_around("LanternPool", Vector2(0.0, 22.0), Vector2(5.0, 2.0), 0.14 + 0.10 * power, -3)
	_pool = pool
	# A second, much wider and fainter pool, so the light dies away gradually
	# instead of stopping at the edge of the bright one.
	var halo_pool := _light_around("LanternFalloff", Vector2(0.0, 24.0),
		Vector2(9.0, 3.4), 0.09, -4)

	# A very slow, very slight breath - never a flash.
	var t := create_tween().set_loops()
	t.tween_property(pendant, "modulate:a", 1.25, 2.6)
	t.tween_property(pendant, "modulate:a", 0.85, 2.6)
	var t2 := create_tween().set_loops()
	t2.tween_property(pool, "modulate:a", 0.62, 2.6)
	t2.tween_property(pool, "modulate:a", 0.40, 2.6)


## Called the moment a moon shard is picked up.
##
## The light opens BEHIND the rabbit, never on the fur: its own sprite is left
## exactly as it is, and a cold moonlit bloom swells on the side of its back,
## with a splash of the same light on the ground. For a heartbeat the rabbit
## reads as lit from behind, then the night closes over it again.
##
## The bloom is drawn behind the rabbit's body AND behind the lantern it
## carries, so it can only be seen spilling out around the silhouette rather
## than washing over it.
func flash_backlight() -> void:
	_build_backlight()
	# If a bloom is already running, the new one starts from the top instead of
	# fighting it for the same sprites.
	for t in _backlight_tweens:
		if t != null and t.is_valid():
			t.kill()
	_backlight_tweens.clear()
	# "Behind" means behind the back: the bloom opens on the side the rabbit is
	# not facing and drifts a little further that way as it grows.
	var back := -float(_facing)
	# A wide, faint lift of the air first, so the whole spot brightens. It is
	# quicker than the rest: a pulse at the moment of the find, then gone.
	_burst(_backlight_flash, Color(0.72, 0.84, 1.0, 0.5),
		Vector2(5.0, 5.0), Vector2(24.0, 24.0),
		Vector2(back * 4.0, -14.0), Vector2(back * 18.0, -16.0), BACKLIGHT_TIME * 0.55)
	_burst(_backlight_halo, Color(BACKLIGHT_COLOUR, 1.0),
		Vector2(2.6, 2.6), Vector2(17.0, 17.0),
		Vector2(back * 2.0, -16.0), Vector2(back * 14.0, -18.0), BACKLIGHT_TIME)
	_burst(_backlight_core, Color(0.97, 1.0, 1.0, 1.0),
		Vector2(1.4, 1.4), Vector2(8.0, 8.0),
		Vector2(back * 2.0, -14.0), Vector2(back * 9.0, -15.0), BACKLIGHT_TIME * 0.8)
	# A splash of the same light on the grass, so the bloom belongs to the world
	# instead of floating in the air.
	_burst(_backlight_pool, Color(0.80, 0.90, 1.0, 0.6),
		Vector2(1.2, 0.6), Vector2(8.0, 3.2),
		Vector2(back * 2.0, 22.0), Vector2(back * 12.0, 23.0), BACKLIGHT_TIME)


## Builds the four bloom sprites once, on first use. They are children of the
## rabbit, so they follow the walk, the hop and the camera with no bookkeeping.
func _build_backlight() -> void:
	if _backlight != null and is_instance_valid(_backlight):
		return
	_backlight = Node2D.new()
	_backlight.name = "ShardBacklight"
	# Below every other light the rabbit has, and below the sprite itself.
	_backlight.z_index = -6
	add_child(_backlight)
	_backlight_flash = _backlight_sprite("Flash", "res://fireflies/firefly_glow.png")
	_backlight_halo = _backlight_sprite("Halo", "res://fireflies/firefly_glow.png")
	_backlight_core = _backlight_sprite("Core", "res://fireflies/firefly_glow.png")
	_backlight_pool = _backlight_sprite("Pool", "res://fireflies/firefly_pool.png")


## One additive sprite of the bloom. Smooth filtering keeps it a soft glow even
## though the source texture is tiny.
func _backlight_sprite(sprite_name: String, path: String) -> Sprite2D:
	var s := Sprite2D.new()
	s.name = sprite_name
	s.texture = load(path)
	s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	s.material = _additive()
	s.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_backlight.add_child(s)
	return s


## Opens one layer of the bloom: the glow lights up almost at once, then fades
## while it grows, so it feels like a flash of light rather than a fade-in.
func _burst(sprite: Sprite2D, colour: Color, from_scale: Vector2, to_scale: Vector2,
		from_pos: Vector2, to_pos: Vector2, duration: float) -> void:
	sprite.position = from_pos
	sprite.scale = from_scale
	sprite.modulate = Color(colour.r, colour.g, colour.b, 0.0)

	var grow := create_tween()
	grow.set_parallel(true)
	grow.tween_property(sprite, "scale", to_scale, duration) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	grow.tween_property(sprite, "position", to_pos, duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	var light := create_tween()
	light.tween_property(sprite, "modulate:a", colour.a, 0.06)
	light.tween_property(sprite, "modulate:a", 0.0, duration * 0.85)
	_backlight_tweens.append(grow)
	_backlight_tweens.append(light)


## A soft pool of light belonging to the body rather than the sprite, so it stays
## on the floor while the rabbit hops. Drawn with smooth filtering: a gentle
## glow, not a pixelated disc.
func _light_around(light_name: String, where: Vector2, size: Vector2,
		alpha: float, z: int) -> Sprite2D:
	var light := Sprite2D.new()
	light.name = light_name
	light.texture = load("res://fireflies/firefly_pool.png")
	light.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	light.position = where
	light.scale = size
	light.z_index = z
	light.material = _additive()
	light.modulate = Color(1.0, 0.90, 0.72, alpha)
	add_child(light)
	return light


## True while the rabbit is out in the forest rather than inside the burrow.
## The moonlit aura is only for the forest; the room keeps its own warm lamps.
func _outdoors() -> bool:
	var scene := get_tree().current_scene
	if scene == null:
		return true
	return not scene.scene_file_path.ends_with("burrow_inside.tscn")


## One soft additive halo in the sprite's own frame coordinates.
func _halo(halo_name: String, where: Vector2, size: Vector2,
		alpha: float, z: int) -> Sprite2D:
	var halo := Sprite2D.new()
	halo.name = halo_name
	halo.texture = load("res://fireflies/firefly_glow.png")
	halo.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	halo.position = where
	halo.scale = size
	halo.z_index = z
	halo.material = _additive()
	halo.modulate = Color(1.0, 0.92, 0.76, alpha)
	sprite.add_child(halo)
	return halo


func _additive() -> CanvasItemMaterial:
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return mat


## True while the rabbit is in the air.
func is_jumping() -> bool:
	return _jump_t >= 0.0


func _physics_process(delta: float) -> void:
	var axis := 0.0 if (input_locked or lying_down) else _input_axis()

	if is_zero_approx(axis):
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)
	else:
		velocity.x = move_toward(velocity.x, axis * SPEED, ACCELERATION * delta)
		_face(axis)

	# Horizontal only: the body stays on the ground at all times, the hop just
	# lifts the drawing.
	velocity.y = 0.0
	move_and_slide()

	global_position.x = clampf(global_position.x, walk_limits.x, walk_limits.y)
	if clamp_to_floor and _jump_t < 0.0:
		_apply_floor(delta)

	if _jump_t >= 0.0:
		_tick_jump(delta)
		return
	if lying_down:
		return

	# Space starts a hop, while standing still or in the middle of a walk, but
	# never while sleeping or being moved by a location.
	if not (input_locked or lying_down) and Input.is_action_just_pressed("jump"):
		_start_jump()
		return

	_play(&"Walk" if not is_zero_approx(axis) else &"Idle")

	# Footsteps while walking: quiet, slightly irregular, and only on the ground.
	_update_pendant()
	if _jump_t < 0.0 and not is_zero_approx(axis) and not lying_down:
		_step_clock += delta
		if _step_clock >= STEP_INTERVAL:
			_step_clock = 0.0
			_step_flip = not _step_flip
			_play_sfx("step_1" if _step_flip else "step_2", -24.0, 0.14)
	else:
		_step_clock = STEP_INTERVAL * 0.7


## The pendant and the lantern grow with every moon shard, so the progress
## of the whole story is visible on the rabbit itself.
func _update_pendant() -> void:
	if not _outdoors():
		return
	var power := Story.pendant_power()
	if _pendant != null and is_instance_valid(_pendant):
		var s := 2.2 + 1.0 * power
		_pendant.scale = Vector2(s, s)
		_pendant.modulate.a = 0.30 + 0.20 * power
	if _pool != null and is_instance_valid(_pool):
		_pool.modulate.a = 0.14 + 0.10 * power


## Loads the little sounds the rabbit makes. They are generated files, so a
## missing one is skipped rather than fatal.
func _load_sounds() -> void:
	for name in ["step_1", "step_2", "jump", "land"]:
		var path := "res://audio/sfx/%s.wav" % name
		if ResourceLoader.exists(path):
			_sfx[name] = load(path)


## One short sound, with a little pitch variety so repeats never sound stamped
## out, and its level following the Звуки setting.
func _play_sfx(name: String, volume_db := -6.0, pitch_spread := 0.0) -> void:
	if not _sfx.has(name):
		return
	var player := AudioStreamPlayer.new()
	player.stream = _sfx[name]
	player.volume_db = linear_to_db(maxf(GameState.sfx_volume, 0.0001)) + volume_db
	player.pitch_scale = 1.0 + _rng.randf_range(-pitch_spread, pitch_spread)
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(player)
	player.play()
	player.finished.connect(player.queue_free)


## Keeps the rabbit on the ground - or on the raised surface it hopped onto.
func _apply_floor(delta: float) -> void:
	if on_platform:
		if _over_platform():
			global_position.y = platform_y
			return
		# Walked off the edge: drop back down to the floor.
		on_platform = false
		_falling = true
	var target := clampf(global_position.y, floor_range.x, floor_range.y)
	if _falling:
		global_position.y = move_toward(global_position.y, target, 240.0 * delta)
		if is_equal_approx(global_position.y, target):
			_falling = false
	else:
		global_position.y = target


func _over_platform() -> bool:
	return (platform_x.y > platform_x.x
		and global_position.x >= platform_x.x
		and global_position.x <= platform_x.y)


## Used by a location that puts the rabbit on its sleeping place, so it stays
## there when it wakes up.
func set_on_platform(on: bool) -> void:
	on_platform = on
	if on:
		global_position.y = platform_y


func _start_jump() -> void:
	_jump_t = 0.0
	_jump_from_y = global_position.y
	on_platform = false
	_falling = false
	if jump_frames != null:
		sprite.sprite_frames = jump_frames
		if sprite.sprite_frames.has_animation(&"Jump"):
			sprite.play(&"Jump")


## Raises the body along a sine arc; it comes back down on its own.
func _tick_jump(delta: float) -> void:
	_jump_t += delta
	var progress := _jump_t / JUMP_TIME
	var arc := sin(clampf(progress, 0.0, 1.0) * PI) * JUMP_HEIGHT
	var feet := _jump_from_y - arc
	# On the way down, land on the raised surface if the rabbit is over it and
	# the hop was high enough to clear it.
	if progress > 0.35 and _jump_from_y > platform_y and feet <= platform_y and _over_platform():
		_land(true)
		return
	if progress >= 1.0:
		_land(false)
		return
	global_position.y = feet


func _land(on_surface: bool) -> void:
	_jump_t = -1.0
	sprite.offset = _base_offset
	if on_surface:
		on_platform = true
		global_position.y = platform_y
	_play_sfx("land", -7.0, 0.05)
	_squash()
	_lead_camera()
	_play(&"Idle")


## A brief squash on landing, which is most of what makes a hop feel physical.
func _squash() -> void:
	var base := absf(sprite.scale.y)
	var t := create_tween()
	t.tween_property(sprite, "scale:y", base * 0.84, 0.06)
	t.tween_property(sprite, "scale:y", base, 0.16)


## Leans the camera ahead of the rabbit, so it looks where it is going instead
## of sitting on its back.
func _lead_camera() -> void:
	if _camera == null or not lead_enabled:
		return
	var wanted := 16.0 * float(_facing)
	var t := create_tween()
	t.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_property(_camera, "position:x", wanted, 0.45)


## Played by a location when the rabbit curls up in its sleeping place.
func play_sleep() -> void:
	if sleep_frames != null:
		sprite.sprite_frames = sleep_frames
		if sprite.sprite_frames.has_animation(&"Sleep"):
			sprite.play(&"Sleep")
			return
	_play(&"Idle")


func play_idle() -> void:
	_play(&"Idle")


## Used while hopping onto or off the sleeping place.
func play_walk() -> void:
	_play(&"Walk")


func _input_axis() -> float:
	var axis := 0.0
	if Input.is_action_pressed("move_left"):
		axis -= 1.0
	if Input.is_action_pressed("move_right"):
		axis += 1.0
	return axis


## Flips the sprite horizontally. The rabbit art faces right by default.
func _face(direction: float) -> void:
	var wanted := signi(direction)
	if wanted == 0 or wanted == _facing:
		return
	_facing = wanted
	sprite.scale.x = absf(sprite.scale.x) * float(_facing)


func _play(animation: StringName) -> void:
	var wanted := _frames_for(animation)
	if wanted == null:
		return
	if sprite.sprite_frames != wanted:
		sprite.sprite_frames = wanted
	if sprite.animation != animation or not sprite.is_playing():
		sprite.play(animation)


func _frames_for(animation: StringName) -> SpriteFrames:
	match animation:
		&"Walk":
			return walk_frames
		&"Jump":
			return jump_frames if jump_frames != null else idle_frames
	return idle_frames
