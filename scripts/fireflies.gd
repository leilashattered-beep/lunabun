extends Node2D
## Fireflies and floating dust - the small lights that make the dark forest read
## as alive instead of simply black.
##
## The whole swarm is driven by one loop rather than one script per insect, so a
## hundred of them cost a single `_process` call per frame.
##
## Requirements this is built to meet:
##   * tiny points of light, never big glowing balls
##   * a gentle pulse, with a different phase and tempo for every one
##   * slow drifting, rising and bobbing - never mechanical
##   * depth: distant ones are smaller, dimmer and slower than near ones
##   * a soft halo around each, and optionally a small pool on the ground
##   * a few can drift around the rabbit without ever acting like a marker
##
## The forest package ships no firefly frames - its README suggests making them
## in Godot - so they are generated procedurally here. They never interact with
## the rabbit or the ground.

## How many lights are in this swarm.
@export var count := 110
## Total horizontal extent the swarm spreads over (ignored while following).
@export var world_width := 3200.0
## The small additive glow texture.
@export var glow_texture: Texture2D
## Optional wider texture used for the faint pool of light on the ground.
@export var pool_texture: Texture2D
## Share of the swarm that also throws a small pool on the ground (0 = none).
@export var pool_fraction := 0.0
## Lowest point a light may hover (world y, right above the ground).
@export var floor_y := 146.0
## Highest point a light may drift to (world y).
@export var ceiling_y := 42.0
## Base colour; each one is nudged slightly warmer or bluer than this.
@export var glow_color := Color(1.0, 0.95, 0.72)
## Brightest / dimmest point of the pulse. The fleet has to read against a very
## dark scene, but the dim phase really does fade away.
@export var peak_alpha := 0.85
@export var dim_alpha := 0.10
## Smallest / largest light, as a multiplier on the glow texture.
@export var min_size := 0.35
@export var max_size := 0.9
## How fast they rise, and how far they wander sideways / up and down.
@export var rise_min := 1.2
@export var rise_max := 5.0
@export var drift_x := 12.0
@export var drift_y := 4.5
## Keep the swarm biased towards the lower air, where the rabbit walks.
@export var low_bias := 2.0

## Optional node a few of the lights gather around - the rabbit, normally.
@export var follow_path: NodePath
## How many of the swarm drift around that node.
@export var follow_count := 0
## How far from it they are allowed to stray.
@export var follow_radius := 90.0
## How quickly the pool under a light fades to nothing at the edges.
@export var pool_alpha := 0.22

var _sprites: Array[Sprite2D] = []
var _pools: Array[Sprite2D] = []
var _phase := PackedFloat32Array()
var _tempo := PackedFloat32Array()
var _base_x := PackedFloat32Array()
var _rise := PackedFloat32Array()
var _swing_x := PackedFloat32Array()
var _swing_y := PackedFloat32Array()
## 0 = far away, 1 = close to the camera. Drives size, brightness and speed.
var _depth := PackedFloat32Array()
## Slow wander each following light adds on top of the target's position.
var _wander := PackedFloat32Array()
## A much slower cycle on top of the pulse: lights drift away into the dark and
## come back, so the swarm never looks like a fixed set of dots.
var _life_phase := PackedFloat32Array()
var _life_tempo := PackedFloat32Array()

var _rng := RandomNumberGenerator.new()
var _follow: Node2D


func _ready() -> void:
	if glow_texture == null:
		push_warning("Fireflies: no glow_texture assigned, nothing will be drawn.")
		return
	_rng.randomize()
	if follow_path != NodePath():
		_follow = get_node_or_null(follow_path) as Node2D
	_spawn_all()
	set_process(true)


func _process(delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	# The target may be assigned after this swarm entered the tree, so it is
	# picked up here as soon as the path is set.
	if _follow == null and follow_path != NodePath():
		_follow = get_node_or_null(follow_path) as Node2D
	var target_x := NAN
	if _follow != null and is_instance_valid(_follow):
		target_x = _follow.global_position.x - global_position.x

	for i in _sprites.size():
		var light := _sprites[i]
		var depth := _depth[i]

		# The ones that gather around the rabbit hold a loose, slowly wandering
		# position beside it: they drift, they never lock on like a marker.
		if i < follow_count and not is_nan(target_x):
			_wander[i] += delta * sin(t * 0.23 + _phase[i]) * 9.0
			_wander[i] = clampf(_wander[i], -follow_radius, follow_radius)
			_base_x[i] = target_x + _wander[i]

		# Slow rise towards the canopy, looping back down to the ground. The
		# sinusoidal terms are re-evaluated from the base values every frame, so
		# the swarm never accumulates rounding drift.
		var y := light.position.y - _rise[i] * delta
		if y < ceiling_y:
			y = floor_y
			_base_x[i] = clampf(_base_x[i] + _rng.randf_range(-90.0, 90.0),
				0.0, world_width) if follow_count == 0 else _base_x[i]

		# Two sine terms at unrelated tempos per axis, so the path never repeats
		# in a way the eye can lock on to: the insect wanders rather than orbits.
		var wander_x := sin(t * _tempo[i] + _phase[i]) * _swing_x[i] \
			+ sin(t * _tempo[i] * 0.37 + _phase[i] * 2.1) * _swing_x[i] * 0.6
		var wander_y := sin(t * _tempo[i] * 1.7 + _phase[i] * 1.3) * _swing_y[i] \
			+ sin(t * _tempo[i] * 0.53 + _phase[i] * 0.8) * _swing_y[i] * 0.8

		light.position = Vector2(_base_x[i] + wander_x, y + wander_y)

		# The pulse: dim, bright, dim. Additive blending means alpha is also how
		# much light is thrown, so this is the flicker.
		var pulse := 0.5 + 0.5 * sin(t * _tempo[i] * 1.4 + _phase[i] * 2.0)
		# And a far slower life cycle over the top: each one fades into the
		# darkness for a while and then comes back.
		var life := 0.5 + 0.5 * sin(t * _life_tempo[i] + _life_phase[i])
		life = smoothstep(0.0, 1.0, clampf(life * 1.7 - 0.35, 0.0, 1.0))
		light.modulate.a = (lerpf(dim_alpha, peak_alpha, pulse)
			* lerpf(0.45, 1.0, depth) * life)

		# The small pool it throws on the ground below.
		if i < _pools.size() and _pools[i] != null:
			var pool := _pools[i]
			pool.position = Vector2(light.position.x, floor_y + 1.0)
			pool.modulate.a = light.modulate.a * pool_alpha


func _spawn_all() -> void:
	var pool_budget := int(round(float(count) * pool_fraction))
	for i in count:
		var light := Sprite2D.new()
		light.texture = glow_texture
		light.centered = true
		light.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR

		# Depth: 0 is far away, 1 is close. It sets how large, how bright and how
		# briskly the light moves, which is what gives the swarm its depth.
		var depth := pow(_rng.randf(), 0.7)
		var size := _rng.randf_range(min_size, max_size) * lerpf(0.6, 1.25, depth)
		light.scale = Vector2(size, size)
		# Slight per-light colour variation: warmer, or blue-white.
		var tint := glow_color.lerp(Color(0.74, 0.86, 1.0), _rng.randf_range(0.0, 0.55))
		light.modulate = Color(tint.r, tint.g, tint.b, 0.0)

		var x := _rng.randf_range(0.0, world_width)
		var y := lerpf(ceiling_y, floor_y, pow(_rng.randf(), low_bias))
		light.position = Vector2(x, y)
		add_child(light)

		if i < pool_budget and pool_texture != null:
			var pool := Sprite2D.new()
			pool.texture = pool_texture
			pool.centered = true
			pool.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			pool.scale = Vector2(size * 3.4, size * 1.5)
			pool.z_index = -1
			pool.modulate = Color(tint.r, tint.g, tint.b, 0.0)
			add_child(pool)
			_pools.append(pool)

		_sprites.append(light)
		_depth.append(depth)
		_phase.append(_rng.randf_range(0.0, TAU))
		_tempo.append(_rng.randf_range(0.45, 1.5) * lerpf(0.7, 1.15, depth))
		_base_x.append(x)
		_rise.append(_rng.randf_range(rise_min, rise_max) * lerpf(0.55, 1.1, depth))
		_swing_x.append(_rng.randf_range(drift_x * 0.25, drift_x))
		_swing_y.append(_rng.randf_range(drift_y * 0.25, drift_y))
		_wander.append(_rng.randf_range(-follow_radius, follow_radius))
		_life_phase.append(_rng.randf_range(0.0, TAU))
		_life_tempo.append(_rng.randf_range(0.05, 0.22))
