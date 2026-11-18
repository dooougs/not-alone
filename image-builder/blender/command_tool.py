"""Builds the command tool model and renders its shortcut icons.

A handheld field controller: a rubber-gripped steel base with a joystick
topped by a red knob, a couple of buttons, and a red team mate figure badge
on the front corner, so it reads as "give orders to your crew".

Run with Blender:   blender -b -P image-builder/blender/command_tool.py
or with the bpy module:   python image-builder/blender/command_tool.py

Writes graphics/icons/command-tool-shortcut-56.png and
graphics/icons/command-tool-shortcut-24.png.
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

import factorio_kit as k  # noqa: E402


def figure(loc, mat, s=1.0):
    loc = Vector(loc)
    k.sphere(0.16 * s, loc + Vector((0, 0, 0.62 * s)), mat, segments=20)
    body = [(0.0, 0.0), (0.3 * s, 0.0), (0.3 * s, 0.08 * s), (0.26 * s, 0.3 * s),
            (0.18 * s, 0.42 * s), (0.08 * s, 0.47 * s), (0.0, 0.47 * s)]
    k.lathe(body, mat, segments=32, location=loc, smooth_angle=60,
            name="figure")


def main():
    scene = k.reset_scene()
    m = k.palette()
    red = k.weathered("red_plastic", (0.45, 0.03, 0.02), metallic=0.0,
                      roughness=0.35, rust=0.0, wear=0.2, grime=0.3,
                      worn_color=(0.6, 0.15, 0.1))
    # base: rounded slab with a rubber collar
    k.box((1.5, 1.3, 0.32), (0, 0.05, 0.16), m["steel"], bevel=0.12)
    k.box((1.56, 1.36, 0.1), (0, 0.05, 0.08), m["rubber"], bevel=0.05)
    k.cylinder(0.42, 0.1, (-0.1, 0.12, 0.34), m["rubber"], vertices=40,
               bevel=0.03)
    k.torus(0.38, 0.06, (-0.1, 0.12, 0.38), m["frame"], major_seg=40)
    # stick
    k.tube_between((-0.1, 0.12, 0.36), (-0.02, 0.2, 1.05), 0.075, m["steel"],
                   vertices=16)
    k.tube_between((-0.08, 0.14, 0.5), (-0.03, 0.19, 0.95), 0.09, m["rubber"],
                   vertices=16)
    k.sphere(0.2, (-0.02, 0.2, 1.12), red, segments=24)
    # buttons and an LED
    for x, y, mat in ((0.42, 0.4, red), (0.52, 0.12, m["yellow"])):
        k.cylinder(0.08, 0.06, (x, y, 0.34), mat, vertices=20, bevel=0.015)
        k.torus(0.085, 0.015, (x, y, 0.32), m["frame"], major_seg=20)
    k.box((0.12, 0.06, 0.03), (-0.45, -0.45, 0.33),
          k.emissive("led", (0.3, 1.0, 0.2), 6.0), bevel=0.01)
    for i in range(4):
        k.sphere(0.03, (-0.65 + i * 0.43, -0.52, 0.31), m["rivet"])
    # red team mate badge on the front-right corner
    k.cylinder(0.33, 0.06, (0.5, -0.42, 0.35), m["frame"], vertices=32,
               bevel=0.015)
    figure((0.5, -0.42, 0.38), red, s=0.62)
    k.setup_lights(scene, key=4.6, fill=0.7)
    # Icons only: no ground, so no shadow catcher in the render.
    catcher = k.add_shadow_catcher()
    catcher.hide_render = True
    k.render_entity(scene, "command_tool", entity_path=None,
                    icon_paths=[(k.icon_path("command-tool-shortcut-56"), 56),
                                (k.icon_path("command-tool-shortcut-24"), 24)],
                    size_px=128, scale=0.5, shift=(0, -0.35), catcher=catcher,
                    icon_mipmaps=1)


main()
