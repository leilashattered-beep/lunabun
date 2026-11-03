extends Node2D
## Soft pools of light that the path fireflies cast onto the walkway.
##
## Each pool is the flat oval "firefly_pool.png" texture drawn additively just
## above the ground, slowly sliding along the path and breathing in and out.
## The effect is what actually makes the road readable in the dark; the bright
## fireflies themselves are placed on top of these pools by path_flies.tscn.

## How many pools exist across the whole world.
@export var count := 34
## Total horizontal extent the pools are spread over.
@export var world_width := 3200.0
## The flat oval glow texture.
@export var pool_texture: Texture2D
## World y the pools sit at (just above the ground surface).
@export var ground_y := 147.0
## Overall strength of the light. Multiplied by each pool's own pulse.
@export var strength := 0.5
## Warm colour of the light on the ground.
@export var light_color := Color(1.0, 0.93, 0.7)
## Smallest / largest pool, as a multiplier on the glow texture.
@export var min_size := 0.9
@export var max_size := 2.1
## How flat the glow is squashed onto the ground. The round glow texture is
## stretched on X and compressed on Y so it reads as light lying on the path.
@export var squash := 0.34
@export var stretch := 1.6
## How far a pool slides along the path while it breathes.
@export var slide := 16.0

var _sprites: Array[Sprite2D] = []
var _phase := PackedFloat32Array()
var _tempo := PackedFloat32Array()
var _base_x := PackedFloat32Array()
var _swing := PackedFloat32Array()

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	if pool_texture == null:
		push_warning("LightPools: no pool_texture assigned, nothing will be drawn.")
		return
	_rng.randomize()
	_spawn_all()
	set_process(true)


func _process(_delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for i in _sprites.size():
		var pool := _sprites[i]
		var phase := _phase[i]
		var tempo := _tempo[i]
		pool.position.x = _base_x[i] + sin(t * tempo * 0.6 + phase) * _swing[i]
		# Breathe between roughly a third and full strength - never fully dark,
		# so the path stays readable while still feeling alive.
		var breathe := 0.45 + 0.55 * (0.5 + 0.5 * sin(t * tempo + phase * 1.7))
		pool.modulate.a = strength * breathe


func _spawn_all() -> void:
	for i in count:
		var pool := Sprite2D.new()
		pool.texture = pool_texture
		pool.centered = true
		pool.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		pool.z_index = -1  # ground light goes under the fireflies

		var size := _rng.randf_range(min_size, max_size)
		pool.scale = Vector2(size * stretch, size * squash)
		pool.modulate = light_color

		pool.position = Vector2(_rng.randf_range(0.0, world_width), ground_y)
		add_child(pool)

		_sprites.append(pool)
		_phase.append(_rng.randf_range(0.0, TAU))
		_tempo.append(_rng.randf_range(0.5, 1.3))
		_base_x.append(pool.position.x)
		_swing.append(_rng.randf_range(slide * 0.3, slide))
