"""Builds the Outpost model and renders its sprite and icon.

A squat military bunker: a riveted steel dome on a short plated drum and an
octagonal concrete pad, with a front door and steps, a roof fan hatch, a
radio mast, a red unit banner, green ammo crates, sandbags, and fuel tanks
and a generator on the east side.

Run with Blender:   blender -b -P image-builder/blender/outpost.py
or with the bpy module:   python image-builder/blender/outpost.py

Writes graphics/entity/outpost.png (256x256, scale 0.5, shift {0, -0.3}) and
graphics/icons/outpost.png (64x64).
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

import factorio_kit as k  # noqa: E402

PAD_R = 1.5
PAD_H = 0.12
DRUM_R = 1.2
DRUM_H = 0.72
DOME_BASE = PAD_H + DRUM_H
DOME_H = 0.68
DOOR_ANGLE = -90
BANNER_ANGLE = -38
MODEL_SCALE = 0.9


def dome_point(r_frac, angle, lift=0.0):
    """Point on the dome at a fraction of its radius (1 = eave)."""
    phi = math.acos(min(1.0, r_frac))
    r = DRUM_R * 1.02 * r_frac
    z = DOME_BASE + DOME_H * math.sin(phi)
    return Vector(k.polar(r + lift * r_frac, angle, z + lift * math.sin(phi)))


def banner_image(path):
    """Red unit banner with a skull over crossed rifles."""
    from PIL import Image, ImageDraw
    w, h = 128, 256
    img = Image.new("RGB", (w, h), (92, 18, 14))
    d = ImageDraw.Draw(img)
    d.rectangle((0, 0, w - 1, 10), fill=(40, 30, 22))
    d.rectangle((6, 14, w - 7, h - 8), outline=(150, 120, 70), width=3)
    bone = (205, 195, 170)
    cx, cy = w // 2, 110
    for sgn in (-1, 1):
        d.line((cx - 40 * sgn, cy + 52, cx + 40 * sgn, cy - 40), fill=bone,
               width=9)
        d.line((cx - 44 * sgn, cy + 56, cx - 30 * sgn, cy + 40),
               fill=(110, 80, 40), width=13)
    d.ellipse((cx - 26, cy - 34, cx + 26, cy + 16), fill=bone)
    d.rectangle((cx - 15, cy + 8, cx + 15, cy + 26), fill=bone)
    for ex in (-11, 11):
        d.ellipse((cx + ex - 8, cy - 14, cx + ex + 8, cy + 2), fill=(30, 8, 6))
    d.polygon(((cx, cy + 3), (cx - 4, cy + 10), (cx + 4, cy + 10)),
              fill=(30, 8, 6))
    for tx in range(-12, 13, 6):
        d.line((cx + tx, cy + 15, cx + tx, cy + 26), fill=(60, 30, 20), width=2)
    # tattered bottom
    for x in range(0, w, 16):
        d.polygon(((x, h), (x + 8, h - 14), (x + 16, h)), fill=(0, 0, 0))
    img.save(path)


def build_pad(m):
    k.cylinder(PAD_R, PAD_H, (0, 0, PAD_H / 2), m["concrete"], vertices=8,
               rotation=(0, 0, math.radians(22.5)), smooth=False, bevel=0.03)
    k.cylinder(PAD_R + 0.03, 0.05, (0, 0, PAD_H - 0.02), m["frame"],
               vertices=8, rotation=(0, 0, math.radians(22.5)), smooth=False)
    for i in range(8):
        a = 45 * i
        k.sphere(0.022, k.polar((PAD_R + 0.03) * math.cos(math.radians(22.5)),
                                a, PAD_H + 0.005), m["rivet"])
    # hazard edge in front of the door
    k.box((0.18, 0.9, 0.02), k.polar(PAD_R - 0.12, DOOR_ANGLE, PAD_H + 0.005),
          m["hazard"], rotation=k.facing(DOOR_ANGLE), bevel=0)


def build_drum(m):
    k.cylinder(DRUM_R, DRUM_H, (0, 0, PAD_H + DRUM_H / 2), m["steel_dark"],
               vertices=64)
    panels = 18
    w = 2 * math.pi * DRUM_R / panels * 0.95
    for i in range(panels):
        a = 360 * (i + 0.5) / panels
        if not k.is_clear(a, [(DOOR_ANGLE, 14)]):
            continue
        k.box((0.04, w, DRUM_H - 0.06), k.polar(DRUM_R + 0.01, a,
                                                PAD_H + DRUM_H / 2),
              m["hull"], rotation=k.facing(a), bevel=0.012)
        for zc in (0.08, DRUM_H / 2, DRUM_H - 0.08):
            k.sphere(0.018, k.polar(DRUM_R + 0.035, 360 * i / panels,
                                    PAD_H + zc), m["rivet"])
    for zc in (0.03, DRUM_H - 0.02):
        k.cylinder(DRUM_R + 0.04, 0.05, (0, 0, PAD_H + zc), m["brass"],
                   vertices=64)
    # firing slits
    for a in (-140, -40, 20, 160, 200):
        k.box((0.06, 0.34, 0.07), k.polar(DRUM_R + 0.03, a,
                                          PAD_H + DRUM_H * 0.62),
              m["black"], rotation=k.facing(a), bevel=0.005)
        k.box((0.08, 0.42, 0.03), k.polar(DRUM_R + 0.05, a,
                                          PAD_H + DRUM_H * 0.62 + 0.06),
              m["frame"], rotation=k.facing(a), bevel=0.005)


def build_dome(m):
    prof = []
    for i in range(17):
        phi = math.radians(90 * i / 16)
        prof.append((DRUM_R * 1.02 * math.cos(phi),
                     DOME_BASE + DOME_H * math.sin(phi)))
    prof[-1] = (0.0, prof[-1][1])
    k.lathe(prof[:-3] + [(0.36, prof[-3][1])], m["hull"], segments=96,
            name="dome")
    # meridian straps
    for i in range(12):
        a = 360 * i / 12 + 15
        pts = [dome_point(f, a, 0.012) for f in (1.0, 0.92, 0.8, 0.65, 0.5,
                                                 0.38)]
        for p0, p1 in zip(pts, pts[1:]):
            k.beam_between(p0, p1, 0.09, 0.03, m["frame"], bevel=0.008)
        for p in pts[1:-1]:
            k.sphere(0.018, p + Vector((0, 0, 0.02)), m["rivet"])
    # latitude seams
    for f in (0.9, 0.7):
        p = dome_point(f, 0)
        k.torus(p.xy.length, 0.013, (0, 0, p.z), m["frame"], major_seg=96,
                minor_seg=6)
    k.torus(DRUM_R * 1.03, 0.04, (0, 0, DOME_BASE + 0.01), m["brass"],
            major_seg=96)
    # top hatch with a fan
    top = DOME_BASE + DOME_H * math.sin(math.acos(0.3))
    k.cylinder(0.4, 0.1, (0, 0, top + 0.02), m["frame"], vertices=40, bevel=0.01)
    k.cylinder(0.32, 0.04, (0, 0, top + 0.08), m["black"], vertices=40)
    for j in range(6):
        b = k.box((0.27, 0.07, 0.012), (0, 0, top + 0.09), m["steel"],
                  rotation=(math.radians(18), 0, math.radians(60 * j)),
                  bevel=0.003)
        b.location = Vector(k.polar(0.14, 60 * j, top + 0.09))
    k.cylinder(0.06, 0.06, (0, 0, top + 0.1), m["steel_dark"], vertices=16)
    k.torus(0.34, 0.025, (0, 0, top + 0.1), m["steel_dark"])
    for j in range(8):
        k.beam_between(Vector(k.polar(0.06, 22.5 + 45 * j, top + 0.13)),
                       Vector(k.polar(0.34, 22.5 + 45 * j, top + 0.13)), 0.02,
                       0.015, m["frame"], bevel=0)
    # roof vent box
    v = dome_point(0.72, 130, 0.02)
    k.box((0.3, 0.24, 0.16), v + Vector((0, 0, 0.06)), m["steel_dark"],
          rotation=k.facing(130), bevel=0.015)
    for j in range(4):
        k.box((0.02, 0.22, 0.12), v + Vector(k.polar(-0.09 + 0.06 * j, 130,
                                                    0.07)),
              m["frame"], rotation=k.facing(130), bevel=0)


def build_door(m):
    a = DOOR_ANGLE
    z0 = PAD_H
    # protruding vestibule
    k.box((0.5, 0.74, 0.78), k.polar(DRUM_R + 0.05, a, z0 + 0.39),
          m["hull"], rotation=k.facing(a), bevel=0.03)
    k.box((0.56, 0.8, 0.07), k.polar(DRUM_R + 0.07, a, z0 + 0.8), m["frame"],
          rotation=k.facing(a), bevel=0.02)
    k.box((0.04, 0.46, 0.62), k.polar(DRUM_R + 0.3, a, z0 + 0.32), m["steel"],
          rotation=k.facing(a), bevel=0.012)
    k.box((0.02, 0.02, 0.58), k.polar(DRUM_R + 0.325, a, z0 + 0.32),
          m["frame"], rotation=k.facing(a), bevel=0)
    k.box((0.03, 0.16, 0.08), k.polar(DRUM_R + 0.33, a, z0 + 0.5),
          m["window"], rotation=k.facing(a), bevel=0.004)
    k.box((0.05, 0.2, 0.05), k.polar(DRUM_R + 0.31, a, z0 + 0.72), m["lamp"],
          rotation=k.facing(a), bevel=0.01)
    side = Vector(k.polar(1, a + 90, 0))
    for sgn in (-1, 1):
        k.box((0.5, 0.06, 0.8), Vector(k.polar(DRUM_R + 0.05, a, z0 + 0.4))
              + side * 0.38 * sgn, m["brass"], rotation=k.facing(a),
              bevel=0.01)
    # steps down off the pad
    for s in range(2):
        r = DRUM_R + 0.4 + s * 0.13
        h = PAD_H * (1 - s / 2)
        k.box((0.13, 0.52, h), k.polar(r, a, h / 2), m["steel_dark"],
              rotation=k.facing(a), bevel=0.008)
        k.box((0.03, 0.5, 0.012), k.polar(r + 0.05, a, h), m["yellow"],
              rotation=k.facing(a), bevel=0)
    for sgn in (-1, 1):
        p0 = Vector(k.polar(DRUM_R + 0.32, a, PAD_H)) + side * 0.28 * sgn
        p1 = Vector(k.polar(DRUM_R + 0.6, a, 0.02)) + side * 0.28 * sgn
        k.tube_between(p0, p0 + Vector((0, 0, 0.3)), 0.016, m["yellow"], 6)
        k.tube_between(p1, p1 + Vector((0, 0, 0.3)), 0.016, m["yellow"], 6)
        k.tube_between(p0 + Vector((0, 0, 0.3)), p1 + Vector((0, 0, 0.3)),
                       0.018, m["yellow"], 6)


def build_banner(m, banner_mat):
    a = BANNER_ANGLE
    r = DRUM_R + 0.06
    # pole bracket
    k.box((0.06, 0.6, 0.05), k.polar(r + 0.02, a, PAD_H + 0.9), m["frame"],
          rotation=k.facing(a), bevel=0.01)
    bpy.ops.mesh.primitive_plane_add(size=1, location=k.polar(r + 0.04, a,
                                                              PAD_H + 0.56))
    flag = bpy.context.active_object
    flag.scale = (0.5, 0.7, 1)
    flag.rotation_euler = (0, math.radians(90), math.radians(a))
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    # gentle cloth folds
    mod = flag.modifiers.new("sub", "SUBSURF")
    mod.subdivision_type = "SIMPLE"
    mod.levels = 4
    mod.render_levels = 4
    wave = flag.modifiers.new("wave", "WAVE")
    wave.use_x = True
    wave.use_y = False
    wave.height = 0.012
    wave.width = 0.18
    wave.narrowness = 1.0
    k.assign(flag, banner_mat)
    # rotate UVs so the picture stands upright on the wall
    uv = flag.data.uv_layers.active.data
    for loop in flag.data.loops:
        co = flag.data.vertices[loop.vertex_index].co
        uv[loop.index].uv = (0.5 + (Vector(co).dot(Vector(k.polar(1, a + 90,
                                                                0))) / 0.5),
                             (co.z + 0.35) / 0.7)


def build_mast(m):
    base = Vector(k.polar(1.05, 125, PAD_H))
    k.box((0.34, 0.34, 0.18), base + Vector((0, 0, 0.09)), m["concrete"],
          bevel=0.02)
    h = 1.95
    for dx, dy in ((-0.07, -0.07), (0.07, -0.07), (0.07, 0.07), (-0.07, 0.07)):
        k.tube_between(base + Vector((dx * 1.4, dy * 1.4, 0.18)),
                       base + Vector((dx * 0.5, dy * 0.5, 0.18 + h)), 0.022,
                       m["steel_dark"], 8)
    for j in range(6):
        z = 0.3 + j * 0.3
        f = 1.4 - 0.9 * (z / h)
        k.box((0.14 * f + 0.03, 0.14 * f + 0.03, 0.02),
              base + Vector((0, 0, 0.18 + z)), m["frame"], bevel=0)
    top = base + Vector((0, 0, 0.18 + h))
    k.tube_between(top, top + Vector((0, 0, 0.3)), 0.012, m["steel"], 6)
    k.sphere(0.03, top + Vector((0, 0, 0.31)),
             k.emissive("beacon_red", (1.0, 0.08, 0.04), 8.0), segments=10)
    for zz, rr in ((0.6, 0.24), (1.15, 0.2)):
        k.tube_between(base + Vector((0, 0, 0.18 + zz)),
                       base + Vector((rr, -rr * 0.4, 0.18 + zz + 0.02)),
                       0.012, m["frame"], 6)
        k.box((0.05, 0.05, 0.22), base + Vector((rr, -rr * 0.4, 0.18 + zz
                                                 + 0.08)),
              m["steel"], bevel=0.008)
    # cable down into the dome
    k.sagging_cable(base + Vector((0.05, -0.05, 0.9)),
                    dome_point(0.85, 120, 0.02), 0.1, m["rubber"], radius=0.014)


def build_east_side(m):
    # fuel tanks lying on cradles
    for j, a in enumerate((8, 34)):
        c = Vector(k.polar(DRUM_R + 0.2, a, PAD_H + 0.2))
        tank = k.cylinder(0.17, 0.62, c, m["green"] if j else m["steel"],
                          vertices=24, rotation=(math.radians(90), 0,
                                                 math.radians(a)), bevel=0.02)
        for s in (-0.22, 0.22):
            off = Vector(k.polar(s, a + 90, 0))
            k.box((0.36, 0.06, 0.08), c + off + Vector((0, 0, -0.16)),
                  m["frame"], rotation=k.facing(a), bevel=0.01)
            k.torus(0.172, 0.014, c + off, m["frame"],
                    rotation=(math.radians(90), 0, math.radians(a)))
        k.cylinder(0.05, 0.05, c + Vector(k.polar(0.31, a + 90, 0.0)),
                   m["brass"], vertices=12,
                   rotation=(math.radians(90), 0, math.radians(a)))
    # generator box
    g = Vector(k.polar(DRUM_R + 0.17, -12, PAD_H))
    k.box((0.42, 0.46, 0.44), g + Vector((0, 0, 0.22)), m["steel_dark"],
          rotation=k.facing(-12), bevel=0.025)
    k.box((0.44, 0.48, 0.05), g + Vector((0, 0, 0.45)), m["frame"],
          rotation=k.facing(-12), bevel=0.01)
    for j in range(5):
        k.box((0.02, 0.36, 0.03), g + Vector(k.polar(0.22, -12,
                                                     0.1 + j * 0.06)),
              m["frame"], rotation=k.facing(-12), bevel=0)
    k.cylinder(0.04, 0.3, g + Vector((0.08, 0.1, 0.6)), m["steel_dark"], 10)
    k.cylinder(0.05, 0.03, g + Vector((0.08, 0.1, 0.75)), m["black"], 10)
    k.box((0.03, 0.06, 0.04), g + Vector(k.polar(0.23, -12, 0.36)) +
          Vector(k.polar(0.12, 78, 0)),
          k.emissive("led_green", (0.2, 1.0, 0.2), 6.0), rotation=k.facing(-12),
          bevel=0)


def build_crates_and_sandbags(m):
    crates = [((-1.05, -0.95), (0.34, 0.24, 0.2), 30),
              ((-1.22, -0.62), (0.3, 0.22, 0.2), 70),
              ((-1.08, -0.92), (0.3, 0.2, 0.17), 40, 0.2),
              ((-1.35, 0.35), (0.3, 0.22, 0.18), 95),
              ((0.6, 1.05), (0.32, 0.22, 0.2), 10)]
    for c in crates:
        z = (c[3] if len(c) > 3 else 0.0) + PAD_H
        k.crate((c[0][0], c[0][1], z), c[1], m["green"], m["frame"],
                rotation=c[2])
    for f, a, rot in ((0.62, 62, 62), (0.66, 44, 44)):
        p = dome_point(f, a)
        k.crate((p.x, p.y, p.z - 0.05), (0.3, 0.22, 0.2), m["green"],
                m["frame"], rotation=rot)
    # an ammo can on top
    k.box((0.12, 0.07, 0.08), (-1.1, -0.9, PAD_H + 0.41 + 0.04), m["green"],
          rotation=(0, 0, math.radians(20)), bevel=0.01)
    # sandbag wall on the west
    sand = k.weathered("sandbag", (0.2, 0.17, 0.11), metallic=0.0,
                       roughness=0.9, rust=0.0, wear=0.2, grime=0.8,
                       worn_color=(0.34, 0.3, 0.21))
    for row in range(2):
        for j in range(6):
            a = 160 + j * 13 + row * 6.5
            if row == 1 and j == 5:
                continue
            loc = Vector(k.polar(PAD_R + 0.02, a, PAD_H * 0.4 + 0.07 + row * 0.11))
            bpy.ops.mesh.primitive_uv_sphere_add(radius=0.1, location=loc,
                                                 segments=12, ring_count=8)
            bag = bpy.context.active_object
            bag.scale = (0.85, 1.7, 0.6)
            bag.rotation_euler = (0, 0, math.radians(a))
            k.shade_smooth(bag, 80)
            k.assign(bag, sand)


def main():
    scene = k.reset_scene()
    m = k.palette()
    m["hull"] = k.weathered("hull", (0.3, 0.29, 0.27), metallic=0.65,
                              roughness=0.55, rust=0.25, scale=4.0)
    banner_png = os.path.join(k.HERE, "textures", "outpost_banner.png")
    os.makedirs(os.path.dirname(banner_png), exist_ok=True)
    banner_image(banner_png)
    banner_mat = k.image_decal("banner", banner_png, roughness=0.85)
    build_pad(m)
    build_drum(m)
    build_dome(m)
    build_door(m)
    build_banner(m, banner_mat)
    build_mast(m)
    build_east_side(m)
    build_crates_and_sandbags(m)
    k.scale_model(MODEL_SCALE)
    k.setup_lights(scene)
    k.render_entity(scene, "outpost", entity_path=k.entity_path("outpost"),
                    icon_paths=[(k.icon_path("outpost"), 64)])


main()
