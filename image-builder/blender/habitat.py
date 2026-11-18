"""Renders the wooden Habitat sprite and icon.

Run with Blender:   blender -b -P image-builder/blender/habitat.py
or with the bpy module:   python image-builder/blender/habitat.py

Writes graphics/entity/habitat.png (cropped to the model; its size and shift go to
  image-builder/blender/sprites/*.json and prototypes/entity_sprites.lua) and
graphics/icons/habitat.png (64x64). The model itself is in habitat_model.py.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import factorio_kit as k  # noqa: E402
import habitat_model  # noqa: E402

scene = habitat_model.build("wood")
k.render_entity(scene, "habitat", entity_path=k.entity_path("habitat"),
                icon_paths=[(k.icon_path("habitat"), 64)], footprint=4)
