"""Builds the Cloner model and renders its sprite and icon.

A 3x3 machine: a chamfered steel base with a hazard-striped plinth, and in
the middle a glass vat of glowing green growth medium holding a figure, under
a domed cap fed by pipes. Around it sit a column of tanks with radiation
plaques, control cabinets with green readouts, and coolant runs.

Run with Blender:   blender -b -P image-builder/blender/cloner.py
or with the bpy module:   python image-builder/blender/cloner.py

Writes graphics/entity/cloner.png (256x256, scale 0.5, shift {0, -0.3}) and
graphics/icons/cloner.png (64x64).
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

import factorio_kit as k  # noqa: E402

HALF = 1.38          # half width of the base, inside a 3x3 footprint
BASE_H = 0.36
DECK_Z = BASE_H + 0.08
VAT_R = 0.46
VAT_H = 1.05
VAT_C = Vector((0.0, 0.12, 0.0))


def trefoil_image(path):
    """Yellow radiation plaque."""
    from PIL import Image, ImageDraw
    s = 128
    img = Image.new("RGB", (s, s), (150, 110, 15))
    d = ImageDraw.Draw(img)
    d.rectangle((0, 0, s - 1, s - 1), outline=(40, 32, 20), width=8)
    c = s // 2
    for a in (90, 210, 330):
        d.pieslice((c - 44, c - 44, c + 44, c + 44), a - 30, a + 30,
                   fill=(25, 20, 12))
    d.ellipse((c - 15, c - 15, c + 15, c + 15), fill=(150, 110, 15))
    d.ellipse((c - 10, c - 10, c + 10, c + 10), fill=(25, 20, 12))
    img.save(path)


def screen_image(path):
    """Green CRT readout lines."""
    from PIL import Image, ImageDraw
    w, h = 128, 96
    img = Image.new("RGB", (w, h), (4, 20, 6))
    d = ImageDraw.Draw(img)
    for i, ln in enumerate((90, 60, 100, 40, 75)):
        d.rectangle((10, 10 + i * 16, 10 + ln, 18 + i * 16), fill=(60, 200, 50))
    d.line([(10 + x * 6, 80 - int(10 * math.sin(x * 0.9))) for x in range(18)],
           fill=(120, 255, 90), width=3)
    img.save(path)


def build_base(m):
    # chamfered octagon-ish slab: a box with big vertical bevels
    k.box((HALF * 2, HALF * 2, BASE_H), (0, 0, BASE_H / 2), m["steel_dark"],
          bevel=0.12)
    k.box((HALF * 2 - 0.1, HALF * 2 - 0.1, 0.08), (0, 0, BASE_H + 0.04),
          m["steel_dark"], bevel=0.05)
    # deck plate seams
    for t in (-0.7, 0.0, 0.7):
        k.box((HALF * 2 - 0.2, 0.012, 0.01), (0, t, DECK_Z), m["frame"], bevel=0)
        k.box((0.012, HALF * 2 - 0.2, 0.01), (t, 0, DECK_Z), m["frame"], bevel=0)
    # side skirt panels
    for j in range(4):
        xx = -HALF + 0.42 + j * (2 * HALF - 0.84) / 3
        k.box((0.5, 0.04, BASE_H - 0.1), (xx, -HALF - 0.01, BASE_H / 2),
              m["steel"], bevel=0.012)
        k.box((0.04, 0.5, BASE_H - 0.1), (HALF + 0.01, xx, BASE_H / 2),
              m["steel"], bevel=0.012)
        k.box((0.04, 0.5, BASE_H - 0.1), (-HALF - 0.01, xx, BASE_H / 2),
              m["steel"], bevel=0.012)
    # hazard band on the front lip
    k.box((HALF * 1.4, 0.03, 0.09), (0, -HALF - 0.005, BASE_H * 0.55),
          m["hazard"], bevel=0)
    # rivet rows and corner feet
    for sx in (-1, 1):
        for sy in (-1, 1):
            k.box((0.36, 0.36, BASE_H + 0.06),
                  (sx * (HALF - 0.16), sy * (HALF - 0.16), (BASE_H + 0.06) / 2),
                  m["frame"], bevel=0.04)
            k.sphere(0.03, (sx * (HALF - 0.16), sy * (HALF - 0.16),
                            BASE_H + 0.07), m["rivet"])
    k.rivet_row((-HALF + 0.4, -HALF + 0.01, BASE_H - 0.06),
                (HALF - 0.4, -HALF + 0.01, BASE_H - 0.06), 10, m["rivet"])
    # front vent grille with green status light
    k.box((0.7, 0.04, 0.14), (0, -HALF + 0.0, BASE_H * 0.55), m["frame"],
          bevel=0.01)
    for j in range(6):
        k.box((0.08, 0.05, 0.03), (-0.25 + j * 0.1, -HALF - 0.01,
                                   BASE_H * 0.55), m["green_glow"], bevel=0)


def build_vat(m):
    c = VAT_C
    z0 = DECK_Z
    # plinth under the vat
    k.cylinder(VAT_R + 0.2, 0.14, c + Vector((0, 0, z0 + 0.07)), m["frame"],
               vertices=8, rotation=(0, 0, math.radians(22.5)), smooth=False,
               bevel=0.02)
    k.cylinder(VAT_R + 0.1, 0.12, c + Vector((0, 0, z0 + 0.2)), m["steel"],
               vertices=40, bevel=0.015)
    k.torus(VAT_R + 0.1, 0.02, c + Vector((0, 0, z0 + 0.26)), m["frame"])
    vz = z0 + 0.26
    # fluid, figure and glass
    k.cylinder(VAT_R - 0.03, VAT_H - 0.1, c + Vector((0, 0, vz + (VAT_H - 0.1) / 2)),
               m["fluid"], vertices=40)
    fig = m["figure"]
    fz = vz - 0.02
    c = c + Vector((0, -0.2, 0))
    k.sphere(0.075, c + Vector((0, -0.05, fz + 0.66)), fig)
    torso = k.cylinder(0.08, 0.3, c + Vector((0, -0.05, fz + 0.45)), fig, 12)
    torso.scale = (1.3, 0.8, 1)
    for sx in (-1, 1):
        k.tube_between(c + Vector((sx * 0.05, -0.05, fz + 0.32)),
                       c + Vector((sx * 0.06, -0.05, fz + 0.02)), 0.032, fig, 8)
        k.tube_between(c + Vector((sx * 0.11, -0.05, fz + 0.57)),
                       c + Vector((sx * 0.17, -0.05, fz + 0.3)), 0.025, fig, 8)
    c = VAT_C
    k.cylinder(VAT_R, VAT_H, c + Vector((0, 0, vz + VAT_H / 2)), m["vat_glass"],
               vertices=48)
    # cage bars
    for j in range(6):
        a = 60 * j + 30
        k.tube_between(c + Vector(k.polar(VAT_R + 0.02, a, vz)),
                       c + Vector(k.polar(VAT_R + 0.02, a, vz + VAT_H)), 0.022,
                       m["frame"], 8)
    for zz in (0.32, 0.66):
        k.torus(VAT_R + 0.02, 0.014, c + Vector((0, 0, vz + zz)), m["frame"])
    # domed cap
    top = vz + VAT_H
    k.cylinder(VAT_R + 0.04, 0.07, c + Vector((0, 0, top + 0.035)), m["steel"],
               vertices=40, bevel=0.015)
    k.ring_of_rivets(VAT_R + 0.04, top + 0.035, 16, m["rivet"])
    cap = [(VAT_R, top + 0.07)] + [
        (VAT_R * math.cos(math.radians(t)),
         top + 0.07 + 0.12 * math.sin(math.radians(t))) for t in range(10, 91, 10)]
    cap[-1] = (0.0, cap[-1][1])
    k.lathe(cap, m["steel_dark"], segments=40, location=(c.x, c.y, 0),
            name="cap")
    k.cylinder(0.08, 0.12, c + Vector((0, 0, top + 0.24)), m["frame"], 16)
    k.sphere(0.05, c + Vector((0, 0, top + 0.31)), m["green_glow"])
    return top


def build_left_tanks(m, trefoil):
    # tall column of two tanks and a pipe on the back-left
    x, y = -0.95, 0.55
    k.cylinder(0.3, 1.15, (x, y, DECK_Z + 0.575), m["steel"], vertices=32,
               bevel=0.03)
    for zz in (0.15, 0.6, 1.05):
        k.torus(0.305, 0.022, (x, y, DECK_Z + zz), m["frame"])
    k.cylinder(0.18, 0.08, (x, y, DECK_Z + 1.19), m["frame"], 24)
    k.cylinder(0.06, 0.25, (x, y, DECK_Z + 1.3), m["steel_dark"], 12)
    # plaque on the tank's front
    bpy.ops.mesh.primitive_plane_add(size=0.24, location=(x + 0.02, y - 0.31,
                                                          DECK_Z + 0.75),
                                     rotation=(math.radians(90), 0,
                                               math.radians(5)))
    k.assign(bpy.context.active_object, trefoil)
    # a short drum tank in front of it
    x2, y2 = -0.98, -0.45
    k.box((0.5, 0.56, 0.5), (x2, y2, DECK_Z + 0.25), m["steel_dark"],
          bevel=0.04)
    k.box((0.52, 0.58, 0.05), (x2, y2, DECK_Z + 0.5), m["frame"], bevel=0.015)
    bpy.ops.mesh.primitive_plane_add(size=0.22, location=(x2 - 0.05, y2 - 0.285,
                                                          DECK_Z + 0.27),
                                     rotation=(math.radians(90), 0, 0))
    k.assign(bpy.context.active_object, trefoil)
    k.barrel((x2 + 0.05, y2 + 0.02, DECK_Z + 0.53), 0.12, 0.25, m["green"],
             m["frame"])


def build_right_cabinets(m, screen):
    x = 0.98
    for y, h in ((0.55, 0.95), (-0.1, 0.72)):
        k.box((0.56, 0.58, h), (x - 0.02, y, DECK_Z + h / 2), m["steel"], bevel=0.03)
        k.box((0.58, 0.6, 0.05), (x, y, DECK_Z + h), m["frame"], bevel=0.015)
        # louvre/readout on the front face
        bpy.ops.mesh.primitive_plane_add(size=1, location=(x, y - 0.292,
                                                           DECK_Z + h * 0.62),
                                         rotation=(math.radians(90), 0, 0))
        p = bpy.context.active_object
        p.scale = (0.34, 0.24, 1)
        k.assign(p, screen)
        k.box((0.4, 0.02, 0.3), (x, y - 0.285, DECK_Z + h * 0.62), m["frame"],
              bevel=0.005)
        for j in range(3):
            k.box((0.05, 0.03, 0.035), (x - 0.1 + j * 0.1, y - 0.295,
                                        DECK_Z + h * 0.25),
                  m["green_glow"] if j != 1 else m["lamp"], bevel=0)
    # a hazard step at the front-right
    k.box((0.5, 0.3, 0.12), (0.98, -0.95, DECK_Z + 0.06), m["hazard"],
          bevel=0.01)


def build_pipes(m):
    c = VAT_C
    top = DECK_Z + 0.26 + VAT_H
    # pipes from the tank column into the vat cap
    k.pipe_path([(-0.95, 0.55, DECK_Z + 1.0), (-0.95, 0.55, top + 0.26),
                 (c.x - 0.15, c.y, top + 0.26), (c.x - 0.15, c.y, top + 0.15)],
                0.05, m["steel_dark"], joint_mat=m["frame"])
    k.pipe_path([(0.98, 0.55, DECK_Z + 0.95), (0.98, 0.55, top + 0.11),
                 (c.x + 0.25, c.y, top + 0.11)], 0.045, m["copper"],
                joint_mat=m["frame"])
    # green coolant tube along the deck
    k.pipe_path([(-0.7, -0.45, DECK_Z + 0.35), (-0.35, -0.45, DECK_Z + 0.35),
                 (c.x - 0.3, c.y - 0.25, DECK_Z + 0.25)], 0.035, m["green"],
                joint_mat=m["frame"])
    k.pipe_path([(0.72, -0.1, DECK_Z + 0.4), (0.4, -0.1, DECK_Z + 0.4),
                 (c.x + 0.32, c.y - 0.2, DECK_Z + 0.22)], 0.035, m["steel_dark"],
                joint_mat=m["frame"])
    # back wall of conduits
    for j, xx in enumerate((-0.45, -0.25, 0.25, 0.45)):
        k.tube_between((xx, 1.05, DECK_Z), (xx, 1.05, DECK_Z + 0.85 - 0.1 * j),
                       0.04, m["steel_dark"] if j % 2 else m["frame"], 12)
    k.box((1.2, 0.18, 0.12), (0, 1.05, DECK_Z + 0.5), m["steel"], bevel=0.02)
    # front control lectern
    k.box((0.42, 0.2, 0.22), (0.05, -0.85, DECK_Z + 0.11), m["steel_dark"],
          bevel=0.02)
    p = k.box((0.36, 0.2, 0.03), (0.05, -0.85, DECK_Z + 0.24), m["frame"],
              rotation=(math.radians(-25), 0, 0), bevel=0.005)
    for j in range(4):
        k.box((0.05, 0.04, 0.02), (-0.08 + j * 0.09, -0.86, DECK_Z + 0.26),
              m["green_glow"] if j % 2 == 0 else m["red_glow"], bevel=0)


def build_clutter(m, screen):
    c = VAT_C
    # pillars flanking the vat front, with hazard caps
    for sx in (-1, 1):
        p = (c.x + sx * 0.5, c.y - 0.45, DECK_Z)
        k.box((0.16, 0.16, 0.62), (p[0], p[1], DECK_Z + 0.31), m["steel"],
              bevel=0.02)
        k.box((0.18, 0.18, 0.06), (p[0], p[1], DECK_Z + 0.63), m["hazard"],
              bevel=0.01)
        k.box((0.05, 0.02, 0.1), (p[0], p[1] - 0.085, DECK_Z + 0.45),
              m["green_glow"], bevel=0)
    # front-left monitor console
    x, y = -0.85, -0.98
    k.box((0.5, 0.3, 0.36), (x, y, DECK_Z + 0.18), m["steel"], bevel=0.025)
    k.box((0.52, 0.32, 0.04), (x, y, DECK_Z + 0.37), m["frame"], bevel=0.01)
    bpy.ops.mesh.primitive_plane_add(size=1, location=(x, y - 0.152,
                                                       DECK_Z + 0.2),
                                     rotation=(math.radians(90), 0, 0))
    pl = bpy.context.active_object
    pl.scale = (0.34, 0.2, 1)
    k.assign(pl, screen)
    # back-right fan unit
    x, y = 0.98, 1.05
    k.box((0.5, 0.5, 0.3), (x, y, DECK_Z + 0.15), m["steel_dark"], bevel=0.03)
    k.cylinder(0.19, 0.04, (x, y, DECK_Z + 0.31), m["black"], 24)
    k.torus(0.19, 0.022, (x, y, DECK_Z + 0.32), m["frame"])
    for j in range(5):
        k.box((0.17, 0.05, 0.01), (x, y, DECK_Z + 0.33), m["steel"],
              rotation=(math.radians(20), 0, math.radians(72 * j)), bevel=0)
    # back-left valve stack
    k.pipe_path([(-0.6, 1.0, DECK_Z), (-0.6, 1.0, DECK_Z + 0.6),
                 (-0.95, 0.85, DECK_Z + 0.6)], 0.04, m["green"],
                joint_mat=m["frame"])
    k.cylinder(0.08, 0.03, (-0.6, 1.0, DECK_Z + 0.68), m["red"], 12)
    # cables across the deck
    k.sagging_cable((0.73, -0.35, DECK_Z + 0.3), (c.x + 0.3, c.y - 0.15,
                                                  DECK_Z + 0.3), 0.15,
                    m["rubber"], radius=0.018)
    k.sagging_cable((-0.6, -0.85, DECK_Z + 0.3), (c.x - 0.35, c.y - 0.2,
                                                  DECK_Z + 0.25), 0.12,
                    m["rubber"], radius=0.018)


def main():
    scene = k.reset_scene()
    m = k.palette()
    m["fluid"] = k.emissive("growth_medium", (0.35, 1.0, 0.12), 1.4,
                            base=(0.2, 0.6, 0.1))
    m["fluid"].node_tree.nodes["Principled BSDF"].inputs["Alpha"].default_value = 0.14
    m["figure"] = k.emissive("figure", (0.4, 1.0, 0.3), 0.6,
                             base=(0.05, 0.12, 0.04))
    m["vat_glass"] = k.glass("vat_glass", (0.6, 0.9, 0.6), roughness=0.05,
                             alpha=0.15)
    m["green_glow"] = k.emissive("green_glow", (0.3, 1.0, 0.15), 6.0)
    m["red_glow"] = k.emissive("red_glow", (1.0, 0.15, 0.05), 5.0)
    tex = os.path.join(k.HERE, "textures")
    os.makedirs(tex, exist_ok=True)
    trefoil_image(os.path.join(tex, "radiation_plaque.png"))
    screen_image(os.path.join(tex, "readout.png"))
    trefoil = k.image_decal("plaque", os.path.join(tex, "radiation_plaque.png"),
                            roughness=0.6)
    screen = k.image_decal("readout", os.path.join(tex, "readout.png"),
                           roughness=0.2, emission=2.5)
    build_base(m)
    build_vat(m)
    build_left_tanks(m, trefoil)
    build_right_cabinets(m, screen)
    build_pipes(m)
    build_clutter(m, screen)
    k.setup_lights(scene)
    # green glow spilling from the vat onto the deck
    glow = bpy.data.lights.new("vat_glow", "POINT")
    glow.energy = 25
    glow.color = (0.4, 1.0, 0.25)
    glow.shadow_soft_size = 0.3
    obj = bpy.data.objects.new("vat_glow", glow)
    obj.location = VAT_C + Vector((0, -0.6, DECK_Z + 0.6))
    scene.collection.objects.link(obj)
    k.render_entity(scene, "cloner", entity_path=k.entity_path("cloner"),
                    icon_paths=[(k.icon_path("cloner"), 64)])


main()
