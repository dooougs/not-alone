# Blender models for the mod's graphics

Every entity sprite and icon in `graphics/` is rendered from a script in this
folder. Each script builds its model, saves a `.blend` beside itself for
anyone who wants to open it, and writes the PNGs at the size and path the
prototypes in `data.lua` already use.

| Script | Writes |
|---|---|
| `habitat.py` | `graphics/entity/habitat.png`, `graphics/icons/habitat.png` |
| `iron_habitat.py` | `graphics/entity/iron-habitat.png`, `graphics/icons/iron-habitat.png` |
| `outpost.py` | `graphics/entity/outpost.png`, `graphics/icons/outpost.png` |
| `cloner.py` | `graphics/entity/cloner.png`, `graphics/icons/cloner.png` |
| `command_tool.py` | `graphics/icons/command-tool-shortcut-56.png`, `-24.png` |

`habitat_model.py` holds the layout that both Habitats share, so the wooden
and iron versions stay the same building in two materials.
`factorio_kit.py` holds everything else they share.

## Running

With Blender 4.2 or newer:

    blender -b -P image-builder/blender/habitat.py

or with the `bpy` module from PyPI (`pip install bpy pillow numpy`, which
needs the Python version that `bpy` release targets):

    python image-builder/blender/render_all.py          # everything
    python image-builder/blender/render_all.py cloner.py

Environment variables: `FA_SAMPLES` (default 128) and `FA_SUPERSAMPLE`
(default 4) trade quality for speed, so `FA_SAMPLES=24 FA_SUPERSAMPLE=2` is a
quick preview. Add `--no-render` to only build and save the `.blend`. A full
render takes about 5 minutes per model on 4 CPU cores.

## How the renders match Factorio

* **Camera.** Orthographic, looking north, pitched 41.4° from straight down.
  That foreshortens ground depth to 0.75 and height to 0.66, which is what
  the vanilla assembler, furnace and chest in `image-builder/assets` show.
  1 Blender unit is 1 tile. `render_entity()` takes the sprite's
  `width`/`scale`/`shift` from the prototype and frames the camera so the
  model's footprint lands on the entity's tiles in game.
* **Light.** A warm key sun from the upper left casts shadows to the lower
  right, with a cool sky fill and a weak bounce. AgX tone mapping keeps the
  palette muted.
* **Shadow.** A shadow catcher bakes the ground shadow and contact darkening
  into the sprite's alpha. Where the frame would cut the shadow off, it is
  faded out so it never ends in a hard line.
* **Materials.** `weathered()` gives metal and paint grime in crevices
  (ambient occlusion), worn bright edges (bevel normal against the true
  normal), mottling and rust patches. `wood()` gives grain with per-plank
  tint. Wooden surfaces are modelled board by board with `board()` and
  `arc_board()`, with real gaps, butt joints and slight warp, so the
  Habitat's roof, clapboard walls, door and steps are individual planks. `palette()` is the shared set every model uses.
* **Resolution and filtering.** Sprites are 64 px per tile at `scale = 0.5`,
  the same density as vanilla's high-res sprites. Each is rendered at 4x and
  downscaled with premultiplied alpha, so edges blend smoothly instead of
  picking up a dark jagged fringe. Nothing is sharpened afterwards.
* **Icons.** Rendered from the same angle without the ground shadow and
  cropped tight. Item icons are 64 px with 4 mipmap levels in one 120x64 file
  (64, 32, 16, 8), laid out like `base/graphics/icons`. Factorio reads the
  level count from the file, so `icon_size = 64` stays as it is. Shortcut
  icons stay single images at 56 and 24 px.
