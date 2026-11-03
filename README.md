# Lunabun

**Автор:** Кочанова Лейла — 2 курс, группа 2063

**The game starts on the main menu**, over the animated forest clip you supplied.
`ui/menu_bg` holds its 90 frames: the clip is 3 s at 30 fps and is itself 640x360
upscaled x2 to 1280x720, so it is decoded with `scale=640:360:flags=neighbor`
and stored losslessly — the pixel blocks stay exact and nothing is resampled or
colour-corrected. `AnimatedSprite2D` draws it at scale 0.5 with a Nearest filter,
so the frames arrive on the 320x180 screen exactly as they are in the video, and
loop with no gap. Nothing is drawn over the clip except the menu buttons: the
clip already carries the Lunabun lettering and the rabbit. From the menu:

```
ГЛАВНОЕ МЕНЮ  (scenes/main_menu.tscn)
   ├─ НОВАЯ ИГРА ......... begin in the burrow, progress reset
   ├─ ПРОДОЛЖИТЬ ......... load the save; dimmed with "Нет сохранения" if none
   ├─ НАСТРОЙКИ .......... music / sound volume, fullscreen
   ├─ КАК ИГРАТЬ ......... the controls, in Russian
   └─ ВЫХОД .............. asks "Выйти из игры?" first
OUTDOOR WORLD  (scenes/main.tscn, 3842 px)  ← the forest, with the burrow hill
BURROW ROOM    (scenes/burrow_inside.tscn)  ← one screen, with the sleeping nest
```

Pressing **ESC** while playing opens the pause menu (gameplay is paused, the
rabbit stops): `ПРОДОЛЖИТЬ`, `НАСТРОЙКИ`, `КАК ИГРАТЬ`, `СОХРАНИТЬ ИГРУ`
(shows "Игра сохранена") and `ВЫЙТИ В ГЛАВНОЕ МЕНЮ` (asks "Вернуться в главное
меню?"). ESC again closes it and play resumes; inside a window ESC goes back one
step. Leaving for the main menu never deletes the save.

## Music

`scripts/music.gd` is an autoload that plays one looping melody per place, so no
location has to call anything - it reads the current scene and switches by
itself:

| Where | Track |
| --- | --- |
| Main menu and the forest (`main_menu.tscn`, `main.tscn`) | `audio/clavier-music-ambient-video-game-music-438767.mp3` |
| The burrow (`burrow_inside.tscn`) | `audio/musicword-forest-song-306506.mp3` |

Both files are the supplied MP3s, played as delivered - nothing is re-encoded.
They loop forever, keep playing while a menu pauses the game (the player is set
to `PROCESS_MODE_ALWAYS`), and their level follows the Громкость музыки setting
in НАСТРОЙКИ live.

## Source artwork is never modified

All background layers are kept **byte-for-byte identical to the supplied
packages**. Verified against `forest_layers_godot.zip` and
`burrow_layers_godot.zip` by SHA256 - 14 of 14 files match, none were resized,
re-encoded or compressed:

| Layer | Original size |
| --- | --- |
| `01_sky.png` | 320x180 |
| `02_far.png` | 670x180 |
| `03_mid.png` | 1188x180 |
| `04_back.png` | 1908x180 |
| `05_main.png` | 3204x180 |
| `06_front.png` | 4212x180 |
| `in_01_room.png`, `in_02_front.png` | 320x180 |
| `out_01_sky.png` | 320x180 |
| `out_02_far.png` | 362x180 |
| `out_03_mid.png` | 420x180 |
| `out_04_back.png` | 500x180 |
| `out_05_main.png` | 644x180 |
| `out_06_front.png` | 756x180 |

In other words the artwork really is 180 px tall and up to 4212 px wide; that is
its original resolution, and the game uses every pixel of it.

**Quality is a display setting, not a file setting.** `default_texture_filter`
is `0` (Nearest), so each source pixel is drawn as a crisp whole block - sharp,
never smoothed. Change that one value to `1` if smooth filtering is ever wanted
instead; the artwork itself is untouched either way.

## Menu background video

The title screen plays the supplied clip **directly** through a
`VideoStreamPlayer` (`ui/menu_bg.ogv`, Ogg Theora, 1280x720 - the clip's own
resolution, no frame extraction, no resizing, no lossy pass). It loops
continuously and is only paused while a game is running.


The game renders at **1280x720** (`window/stretch/mode = "canvas_items"`), not at a
tiny internal resolution scaled up.

The artwork is authored on a 320x180 canvas, so the world is shown through a
**4x `Camera2D` zoom**: the same framing as before, but rasterised at four times
the size. Filtering is **Linear** (`default_texture_filter = 1`) instead of
Nearest, so that enlarged image comes out smooth and clean rather than as giant
square pixels. Nothing about the layout, sizes or the rabbit changed - only how
the image is sampled.

Two consequences of that setup are handled explicitly:

* a `CanvasLayer` is **not** moved or scaled by the `Camera2D`, so the burrow's
  room artwork (which ships inside CanvasLayers) is scaled by 4 in
  `scripts/burrow_inside.gd`; `ParallaxBackground` handles the zoom by itself;
* the interface lives on its own `CanvasLayer` at layer 100 and is laid out in
  real 1280x720 pixels, so text is rasterised at full resolution and stays sharp.

## Interface font

The menus no longer use a blocky pixel font. They use a `SystemFont`
(`scripts/menu_ui.gd`) that tries Georgia, then Segoe UI, Times New Roman and
Arial - all of them carry Cyrillic - with `allow_system_fallback` on, so Russian
text renders correctly and readably. Sizes are 46 px for headings, 24 px for
buttons and 17-19 px for notes.

## Background coverage

Every parallax layer is tiled across the whole level by
`scripts/tile_parallax.gd`, which is attached to the root of `main.tscn`.

This matters because Godot's `ParallaxLayer` does **not** repeat by default:
`motion_mirroring` is zero, so a layer's texture is drawn once and, once the
camera has scrolled far enough, that layer slides off the screen and leaves a
bare strip behind.

**Only the far/middle backdrops are tiled.** The `Main` and `Front` layers - the
ground and the foreground - and every layer belonging to the hill are single
pieces of scenery; repeating them stamped the burrow's hill over the forest, so
the script skips any layer named `Main`, `Front` or `Hill`, or sitting under a
`Hill*` background.

The level was audited by walking the camera from x=0 to the right limit and
measuring, at each step, how many pixels were left unpainted (transparent, or
the clear colour). It came back **0.0% empty everywhere**. Two real gaps were
found and fixed:

* the camera limit used to reach x=3842 while the hill artwork ends at x=3848,
  so the last ~150 px of the world showed a bare strip — the camera is now
  limited to 3688 and the rabbit to 3676, which keeps the view inside the art;
* `out_05_main.png` leaves a transparent hole where the burrow entrance is
  (world x 3587..3620), which showed the unpainted clear colour. The dark
  opening drawn by `scripts/burrow_entrance.gd` now covers it.

The burrow room (`burrow_inside.tscn`) is a single screen and its artwork
(`in_01_room.png`, 320x180) is 100% opaque, so it is fully covered.

## Camera

`Camera2D` is a child of the rabbit, so it follows it horizontally with no
vertical freedom (the rabbit always stays on the ground). Limits are matched to
the artwork, and `limit_left = 0`, `limit_right = 3688`, so the camera never
shows anything outside the designed level.

## Menu system

`scripts/menu_ui.gd` is registered as an autoload, so no gameplay scene had to be
changed to get a pause menu: it decides for itself whether ESC means "open" or
"resume", and it keeps processing while the tree is paused. Input is polled
(`is_action_just_pressed`) rather than handled as events, which behaves the same
for the keyboard, a gamepad and scripted input.

* Everything is built in code — small dark-blue plates with a thin border
  (112x12 px), a pale moon (`\u263D`) marking the selected row, a soft glow that
  leans towards the choice. The unselected rows are padded with a same-width
  box-drawing character, so the caption never shifts sideways when the selection
  or the mouse moves.
* **Starting a game always calls `MenuUI.close()` first.** Without that the menu
  keeps drawing over the scene that is loading and the locations look like they
  vanished — the interface is hidden and the clip stopped until the main menu is
  opened again.
* All visible text is Russian, as asked. The interface is a `Control` on the
  320x180 viewport, so it scales with the game and keeps clean pixel edges.
* `scripts/game_state.gd` holds progress, the save file
  (`user://lunabun_save.json`) and the audio/fullscreen settings.

### Controls

| Key | Action |
| --- | --- |
| `A` / `D` (or `←` / `→`) | walk left / right |
| `Q` | go through a hole or door — into the burrow, and back out |
| `E` | take / sleep, and wake up again |
| `R` | talk |
| `ESC` | pause menu while playing, back one step inside a menu |


### How the two packages were joined

Both packages ship their ground layer with `motion_scale = 1`, i.e. drawn
directly in world space, so they line up by simply placing the hill at x = 3204:

* `scenes/main.tscn` instances `forest_layers/forest_parallax.tscn` untouched and
  adds the hill's layers next to it — `HillFar/HillMid/HillBack/HillMain` in a
  `ParallaxBackground` on layer −1 and `HillFront` on layer 1, each with
  `motion_offset = (3204, -2)`. The −2 px makes the two floor lines meet.
* `scenes/ground_collision.tscn` is generated as ONE line across both maps by
  `_tools/make_combined_ground.py`: the forest heightmap followed by the hill's,
  blended at the joint and slope-limited, so the surface is continuous and the
  rabbit never catches on a step.
* The hill's own sky is not used (the forest sky already covers the world); the
  rest of the hill's layers keep their intended depths and parallax speeds.

| Location | Scene | Contents |
| --- | --- | --- |
| Outdoor world | `scenes/main.tscn` | forest (0…3203) + burrow hill (3204…3847) as one map |
| Burrow room | `scenes/burrow_inside.tscn` | one screen inside from `burrow_layers`, with the sleeping nest |

### Controls

| Key | Action |
| --- | --- |
| `A` / `D` (or `←` / `→`) | walk left / right |
| `Q` | go through a hole or door — into the burrow, and back out |
| `E` | take / sleep, and wake up again |
| `R` | talk |

### Interactions

The prompt that appears is the supplied key-cap art from `ui/keys/`
(`take.png`, `enter.png`, `exit.png`, `talk.png`, `sleep.png`), shown centred
near the bottom of the screen by `scripts/key_prompt.gd`:

* **Q войти** — at the hole in the hill (x=3604) → the burrow room
* **Q выйти** — at the door inside the room (x=34) → back outdoors
* **E лечь спать** — at the nest (x=254); **E** again wakes the rabbit
* **R говорить** — by the crystal shelf in the room (x=66) says a line of text

The source prompt images were drawn on a 12x grid, so they were downsampled
with NEAREST to single art pixels and then to 26 px tall, which keeps the edges
crisp at the game's resolution.

### The sleep sequence

Pressing E at the nest plays out by itself:

1. the rabbit walks the last step to the nest and hops in a small arc onto it,
2. it curls up (rotated onto its side) on the moss,
3. the room dims to 55 % over about a second,
4. it sleeps for `sleep_seconds` (3.5 s by default) with the screen dark,
5. it wakes on its own, hops back down to the floor and control returns.

`GameState.has_slept` is set, `scripts/game_state.gd` being the autoload that
carries state across scene changes.

## The burrow room

`scenes/burrow_inside.tscn` keeps the package's layer order untouched:

```
BurrowInside (Node2D)
├── RoomLayers   ← burrow_layers/burrow_inside.tscn, instanced unchanged
│                  (Room on canvas layer -1, Front on canvas layer 1)
├── Floor        ← StaticBody2D, floor at y=150
├── Rabbit       ← same controller as in the forest
└── Ui           ← CanvasLayer 100: interaction prompt + fade rect
```

The rabbit walks x=30…290 on a floor at y=150, using the same `scripts/rabbit.gd`
as the forest. That script is shared: each location sets `walk_limits` and
`floor_range` on it, so one controller works on all three maps.

The outside map gets the same treatment: `scenes/burrow_outside_ground.tscn` is
its floor (built from `burrow_data.json`, one continuous slope-limited line) and
`scripts/burrow_outside.gd` adds the glow, sets the walk range and decides
whether the rabbit wakes in the nest (x=300) or steps out of the hole (x=410).

### Glow and mood

Both burrow maps build the lighting their package README lists as *not shipped*,
using additive sprites (`fireflies/firefly_glow.png`, `firefly_pool.png`) — the
artwork itself is untouched:

* outside: warm light in the leaf nest, cool light spilling from the hole, the
  lamp, two glowing plants and drifting fireflies;
* inside: a warm pool and halo over the nesting place, a small glow on the wall
  lamp, a cool shaft from the window pooling on the floor, and a few fireflies.

# Forest scene

Forest parallax background + white rabbit + Idle/Walk + A/D movement + ground
collision + fireflies lighting the path + dark night mood.

## Run it

Open the `lunabun` folder as a Godot 4.7 project and press **F5**
(main scene is already set to `res://scenes/main.tscn`).

> If Godot refuses to open the folder: **Project Manager → Import →** pick
> `C:\Users\User\Desktop\Lunabun\lunabun\project.godot` (the folder that
> contains `project.godot`, not the `Lunabun` folder around it). Use Godot
> **4.7** — older versions cannot open this project. If anything looks broken
> after an update, delete the `.godot` folder; Godot rebuilds it on next open
> and your art is untouched.

Controls:

| Key | Action |
| --- | --- |
| `A` / `←` | walk left (sprite flips) |
| `D` / `→` | walk right (sprite flips) |
| nothing | Idle animation |

There is no jump and no vertical movement — the rabbit stays on the ground.
The walkable area is the whole world: **x = 8 … 3192** (the camera stops at the
level edges). Walking speed is 55 px/s, and the rabbit follows the floor height
from your `ground_heights.json` as it goes (at x=400 it stands at y=146, at
x=1000 at y=149).

## Scene layout (`res://scenes/main.tscn`)

```
Lunabun (Node2D)
├── Rabbit (CharacterBody2D)      position (400, 147), layer 2, mask 1
│   ├── AnimatedSprite2D          scale 0.22, offset (4, -44), Nearest filter
│   ├── CollisionShape2D          54 x 26 box, its bottom edge on the feet
│   └── Camera2D                  follows the rabbit, limits 0..3200 / 0..180
├── Ground              ← res://scenes/ground_collision.tscn (from your JSON)
├── ForestParallax      ← your res://forest_layers/forest_parallax.tscn, unchanged
├── LightPools          ← res://scenes/light_pools.tscn   (warm light on the path)
├── MushroomGlow        ← res://scenes/mushroom_glow.tscn (blue glow on mushrooms)
├── AmbientFlies        ← res://scenes/ambient_flies.tscn (fireflies in the air)
├── PathFlies           ← res://scenes/path_flies.tscn    (fireflies over the path)
└── Atmosphere          ← res://scenes/atmosphere.tscn    (canvas layer 100, darkness)
```

### The rabbit's sprite offset matters

The 192x160 rabbit frames have 6-7 px of empty canvas below the feet. An
`AnimatedSprite2D` draws that canvas centred on the node, so with no offset the
visible feet landed about **16 px below the node origin** — which on the bridge
put them at y=163, exactly the water surface, while the deck top is y=150. That
is why the rabbit looked like it was standing in the water, and (with the
correction over-applied) too high above the ground. `offset = (4, -44)` settles
the feet onto the visible ground, resting slightly into the surface. Values are
in source-art pixels and are multiplied by the sprite scale, so the visible shift
is `offset * 0.22`; the measured mapping is
`feet row = origin + (offset.y + 72.6) * 0.22`, i.e. **a change of 4.55 in
`offset.y` moves the rabbit one screen pixel**. The collision line itself comes
from `ground_heights.json`; the artwork's painted ground wanders a few pixels
either side of that line, so the sprite offset is the knob to use if a particular
stretch still looks like the rabbit is hovering. Below about `-40` the feet start
sinking visibly into the ground, above about `-73` the rabbit floats again.

The rabbit genuinely follows the terrain: the floor is a continuous slope-limited
profile, so its Y tracks `ground_heights.json` as it walks (146.0 → 149.0 → 150.0
on the bridge → 145.0 after it) instead of moving in a straight line, and the
bridge is simply the part of that profile that runs across the deck at y=150.

Draw order, bottom to top:

1. `ForestParallax / Background` (canvas layer −1) — moon, far/mid/back trees,
   `05_main.png` (ground, bushes, bridge, chapel, glowing mushrooms).
2. Rabbit and the ground.
3. `ForestParallax / Foreground` (canvas layer 1) — `06_front.png` trunks, drawn
   over the rabbit so it walks behind the front trees.
4. Light pools (z 85), ambient fireflies (z 85) and path fireflies (z 86) — in
   front of the forest but behind the front trunks, so they still pass behind
   the nearest trees.
5. Darkness overlay (canvas layer 100) — multiplies the whole picture down.

## Lighting

Three separate systems, each with its own scene and all values exported for
tweaking in the Inspector:

| Node | Scene | What it does |
| --- | --- | --- |
| `LightPools` | `scenes/light_pools.tscn` | 30 flattened warm glows breathing and sliding along the walkway — this is what makes the road readable |
| `MushroomGlow` | `scenes/mushroom_glow.tscn` | cool blue-white halo + ground pool on the glowing mushrooms already painted in `05_main.png` |
| `PathFlies` | `scenes/path_flies.tscn` | 46 bright fireflies hovering low over the path (y 112…143), short rise |
| `AmbientFlies` | `scenes/ambient_flies.tscn` | 90 dimmer fireflies scattered through the air up to the canopy |

### Mushroom glow

The mushrooms are **your artwork, untouched**. `mushroom_glow.gd` reads
`forest_layers/mushroom_spots.json` — the positions of the blue caps detected in
`05_main.png` — and drops a stepped blue-white halo (9x9 `mushrooms/mushroom_halo.png`)
plus a faint ground pool (17x17 `mushrooms/mushroom_pool.png`) on each of the 9
main clusters, using additive blending so they light what is behind them. Each
one breathes on its own slow tempo with a second, faster shimmer on top, so the
light never blinks in unison. Knobs: `halo_strength`, `pool_strength`,
`halo_scale`, `min_halo` / `max_halo`, `merge_distance`, `min_pixels`.

All three use the tiny additive textures in `res://fireflies/`:
`firefly_glow.png` (7x7) and `firefly_pool.png` (13x13, squashed flat for the
ground light). Additive blending means they glow through the darkness; they are
still multiplied by the top overlay, so their exported colours already account
for that.

Main knobs:

* `LightPools`: `count`, `strength`, `light_color`, `min_size` / `max_size`,
  `squash` / `stretch` (how flat the pool is), `ground_y`.
* `PathFlies` / `AmbientFlies`: `count`, `glow_color`, `peak_alpha` / `dim_alpha`,
  `min_size` / `max_size`, `floor_y` / `ceiling_y`, `rise_min` / `rise_max`.
* `Atmosphere / Darkness`: one `ColorRect` in *Multiply* blend, colour
  `(0.52, 0.57, 0.76)`. Measured against the original render this halves the
  brightness (≈0.5 red, 0.57 green, 0.75 blue) and pushes it blue. Raise that
  colour for a lighter scene, lower it for a blacker one.

The forest package has no firefly frames — its own README suggests making them
in Godot — so nothing here replaces or redraws your art. The blue and purple
glowing discs in the background are part of your `05_main.png`, not added here.

## Assets used (nothing was redrawn or replaced)

* `res://forest_layers/*` — the six layers, `forest_parallax.tscn`,
  `ground_heights.json`, `hiding_spots.json`, `README.txt`, copied verbatim.
* `res://rabbit/idle/idle_01.png` — Idle animation (1 frame, 1 FPS).
* `res://rabbit/walk/walk_01..08.png` — Walk animation (8 frames, 10 FPS).

The supplied spritesheets and the extra `Run` frames were not needed; only the
individual `idle`/`walk` PNGs are referenced. All frames share the same
192 x 160 canvas, so switching animation never makes the rabbit hop or jitter.

## Files created by this setup

* `res://scripts/rabbit.gd` — horizontal movement, flip, Idle/Walk switching.
* `res://scripts/fireflies.gd` — one firefly swarm (used twice).
* `res://scripts/light_pools.gd` — the pools of light on the path.
* `res://fireflies/firefly_glow.png`, `fireflies/firefly_pool.png` — glow art.
* `res://rabbit/idle/idle_frames.tres`, `res://rabbit/walk/walk_frames.tres`.
* `res://scenes/main.tscn`, `atmosphere.tscn`, `light_pools.tscn`,
  `ambient_flies.tscn`, `path_flies.tscn`.
* `res://scenes/ground_collision.tscn` — the floor. It is a **single**
  `CollisionPolygon2D` in *segments* mode: one continuous line built from
  `ground_heights.json` (y 145..155 across all 3200 px) and smoothed by a slope
  limiter so no piece of it is steeper than 18.4°, deviating from your heightmap
  by at most 0.67 px. That shape matters — see the note below.

### Why the floor is one line and not a row of boxes

The heightmap is a staircase whose steps are 1 px tall but only a couple of
pixels apart. Any collision built from separate boxes puts a small vertical
**wall** at every join (the end cap of the higher box), and a grounded
`CharacterBody2D` walking uphill slams into it and stops dead. That was the
"the rabbit gets stuck on one section and cannot walk further" bug, and it was
reproduced and then fixed by actually walking the level in-engine: the rabbit
now crosses x = 8 → 3192 in one run with no stalls. If you ever regenerate this
file, keep it as one continuous surface.

## Project settings

* Viewport 320 x 180, window 1280 x 720, stretch mode `viewport` (integer
  pixel-perfect scaling, no blur).
* Default texture filter = **Nearest**; the rabbit sprite also sets
  `texture_filter = Nearest` locally.
* Input actions `move_left` (A, ←) and `move_right` (D, →).
* No forced rendering driver: the project uses Godot's default (Vulkan here).
  The old `rendering_device/driver.windows="d3d12"` line was removed because the
  Intel Iris Xe D3D12 driver kept crashing the editor with `0x887a0005`
  (device removed).

## Not included (by request)

No enemies, combat, inventory, dialogue, quests or other mechanics.
