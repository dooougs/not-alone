"""Shared layout for the wooden Habitat and the Iron Habitat.

Both are a round drum on a plinth of blocks, under a low domed roof with
radial beams and a hex-paned skylight, with front stairs to a door, a dish
and beacon mast, a chimney, a roof vent, lamp posts strung with cable, a side
airlock and a barrel. style="wood" builds it from timber planks banded with
iron; style="iron" builds it from riveted iron plate (the layout first made
for PR #12's Iron Habitat).

Dimensions are in tiles before the final scale_model(); the 4x4 footprint
leaves the sprite frame spanning screen y -2.3..1.7 tiles around the centre.
"""

import math
import random

import bpy
from mathutils import Vector

import factorio_kit as k

DRUM_RADIUS = 1.22
DRUM_HEIGHT = 1.06
PLINTH_HEIGHT = 0.24
EAVE_RADIUS = 1.38
ROOF_TOP_RADIUS = 0.64
ROOF_BASE_Z = PLINTH_HEIGHT + DRUM_HEIGHT
ROOF_PROFILE = [(EAVE_RADIUS, 0.07), (1.31, 0.16), (1.16, 0.27), (0.96, 0.36),
                (ROOF_TOP_RADIUS + 0.06, 0.44)]
ROOF_TOP_Z = ROOF_BASE_Z + ROOF_PROFILE[-1][1]
ENTRANCE_ANGLE = -108
MODEL_SCALE = 1.05


def roof_z(radius):
    pts = ROOF_PROFILE
    if radius >= pts[0][0]:
        return ROOF_BASE_Z + pts[0][1]
    for (r0, z0), (r1, z1) in zip(pts, pts[1:]):
        if r1 <= radius <= r0:
            t = (r0 - radius) / (r0 - r1)
            return ROOF_BASE_Z + z0 + (z1 - z0) * t
    return ROOF_TOP_Z


def materials(style):
    m = k.palette()
    if style == "wood":
        m["wall"] = k.wood("planks", (0.2, 0.105, 0.05))
        m["wall_alt"] = k.wood("planks_dark", (0.18, 0.085, 0.035))
        m["roof"] = k.wood("roof_boards", (0.21, 0.11, 0.052), wear=0.45)
        m["post"] = k.wood("timber", (0.16, 0.08, 0.035))
        m["band"] = m["frame"]
        m["door"] = k.wood("door", (0.2, 0.1, 0.045))
    else:
        m["wall"] = k.weathered("iron_plate", (0.25, 0.225, 0.2), metallic=0.75,
                                roughness=0.5, rust=0.5, scale=4.0)
        m["wall_alt"] = k.weathered("iron_plate_dark", (0.22, 0.21, 0.2),
                                    metallic=0.75, roughness=0.5, rust=0.35)
        m["roof"] = k.weathered("roof_plate", (0.22, 0.2, 0.18), metallic=0.6,
                                roughness=0.62, rust=0.55, scale=3.5)
        m["post"] = m["steel_dark"]
        m["band"] = m["frame"]
        m["door"] = m["steel"]
    return m


# ------------------------------------------------------------------ pieces

def build_plinth(m):
    count = 26
    for i in range(count):
        angle = 360 * i / count + 5
        if not k.is_clear(angle, [(ENTRANCE_ANGLE, 15)]):
            continue
        h = PLINTH_HEIGHT + (0.07 if i % 3 == 0 else 0)
        depth = 0.34 if i % 2 else 0.26
        k.box((depth, 0.28, h), k.polar(DRUM_RADIUS + 0.12, angle, h / 2),
              m["concrete"], rotation=k.facing(angle), bevel=0.03)
        if i % 3 == 2:
            k.box((0.2, 0.22, 0.14), k.polar(DRUM_RADIUS + 0.33, angle + 4, 0.07),
                  m["concrete"], rotation=k.facing(angle + 10), bevel=0.025)
        if i % 5 == 1:
            k.box((0.02, 0.26, 0.07), k.polar(DRUM_RADIUS + 0.12 + depth / 2,
                                              angle, h * 0.55),
                  m["hazard"], rotation=k.facing(angle), bevel=0)
    k.cylinder(DRUM_RADIUS + 0.05, PLINTH_HEIGHT * 0.9,
               (0, 0, PLINTH_HEIGHT * 0.45), m["concrete"], vertices=64)


def build_drum(m, style):
    z0 = PLINTH_HEIGHT
    k.cylinder(DRUM_RADIUS - 0.03, DRUM_HEIGHT, (0, 0, z0 + DRUM_HEIGHT / 2),
               m["wall_alt"], vertices=64)
    if style == "wood":
        # Horizontal clapboards, each its own bent plank, with staggered
        # butt joints, small gaps and a little warp.
        rng = random.Random(11)
        rows = 11
        pitch = DRUM_HEIGHT / rows
        for row in range(rows):
            a = rng.uniform(0, 40)
            end = a + 360
            while a < end - 1:
                length = min(rng.uniform(38, 70), end - a)
                if end - a - length < 15:
                    length = end - a
                mat = m["wall"] if rng.random() > 0.22 else m["wall_alt"]
                k.arc_board(DRUM_RADIUS - 0.01, 0.035, z0 + row * pitch + 0.006,
                            pitch - 0.014, a + 0.35, a + length - 0.35, mat,
                            steps=max(3, int(length / 8)), rng=rng, warp=0.006)
                a += length
        bands = (0.1, DRUM_HEIGHT * 0.52, DRUM_HEIGHT - 0.08)
    else:
        panels = 20
        pa = 360 / panels
        width = 2 * math.pi * DRUM_RADIUS / panels * 0.95
        for i in range(panels):
            angle = pa * (i + 0.5)
            for zc, hh in ((0.25, 0.44), (0.72, 0.42)):
                k.box((0.04, width, hh), k.polar(DRUM_RADIUS, angle, z0 + zc),
                      m["wall"], rotation=k.facing(angle), bevel=0.012)
            for zc in (0.08, 0.25, 0.42, 0.56, 0.72, 0.88):
                k.sphere(0.02, k.polar(DRUM_RADIUS + 0.025, pa * i, z0 + zc),
                         m["rivet"])
        bands = (0.03, 0.475, DRUM_HEIGHT - 0.03)
    for zc in bands:
        k.cylinder(DRUM_RADIUS + 0.04, 0.06, (0, 0, z0 + zc), m["band"],
                   vertices=64)
        k.ring_of_rivets(DRUM_RADIUS + 0.07, z0 + zc, 40, m["rivet"], size=0.016)
    # posts between sections
    for angle in (-140, -72, -30, 40, 115, 170):
        k.box((0.13, 0.13, DRUM_HEIGHT + 0.05),
              k.polar(DRUM_RADIUS + 0.045, angle, z0 + DRUM_HEIGHT / 2),
              m["post"], rotation=k.facing(angle), bevel=0.02)


def build_roof(m, style):
    rings = [(EAVE_RADIUS, ROOF_BASE_Z - 0.03)] + [
        (r, ROOF_BASE_Z + z) for r, z in ROOF_PROFILE]
    if style == "wood":
        # dark underlay that shows through the gaps between boards
        k.lathe(rings, m["black"], segments=96, name="roof_underlay")
        build_roof_boards(m)
        rng = random.Random(5)
        # eave fascia: short curved boards
        a = 0.0
        while a < 359:
            length = min(rng.uniform(30, 50), 360 - a)
            k.arc_board(EAVE_RADIUS - 0.02, 0.035, ROOF_BASE_Z - 0.03, 0.11,
                        a + 0.3, a + length - 0.3, m["post"],
                        steps=max(3, int(length / 8)), rng=rng, warp=0.004)
            a += length
    else:
        k.lathe(rings, m["roof"], segments=96, name="roof")
        k.cylinder(EAVE_RADIUS + 0.015, 0.11, (0, 0, ROOF_BASE_Z + 0.025),
                   m["band"], vertices=96)
        k.torus(1.15, 0.014, (0, 0, roof_z(1.15) + 0.004), m["frame"],
                major_seg=96, minor_seg=6)
    k.ring_of_rivets(EAVE_RADIUS + 0.03, ROOF_BASE_Z + 0.025, 44, m["rivet"],
                     size=0.016)
    beams = 8
    radii = [EAVE_RADIUS + 0.03, 1.31, 1.16, 0.96, ROOF_TOP_RADIUS + 0.08]
    for i in range(beams):
        angle = 360 * i / beams + 22.5
        pts = [Vector(k.polar(r, angle, roof_z(min(r, EAVE_RADIUS)) + 0.03))
               for r in radii]
        for a, b in zip(pts, pts[1:]):
            k.beam_between(a, b, 0.14, 0.05, m["frame"])
        for p in pts[1:-1]:
            k.sphere(0.022, p + Vector((0, 0, 0.03)), m["rivet"])
    # thin radial plate laps between beams (iron only; wood has real boards)
    angles = [45.0 * j for j in range(8)] if style == "iron" else []
    for angle in angles:
        pts = [Vector(k.polar(r, angle, roof_z(min(r, EAVE_RADIUS)) + 0.004))
               for r in radii[1:]]
        for a, b in zip(pts, pts[1:]):
            k.tube_between(a, b, 0.011, m["frame"], vertices=6)


def build_roof_boards(m):
    """Radial roof boards between the beams, tapered towards the skylight.

    Every board is a separate plank following the dome profile, with gaps,
    random thickness and lift, and some split by a butt joint part way up.
    """
    rng = random.Random(7)
    thickness = 0.03
    r_out, r_in = EAVE_RADIUS + 0.01, ROOF_TOP_RADIUS + 0.02
    per_sector = 8
    for sector in range(8):
        a_start = 45 * sector + 22.5 + 3.2   # clear of the beam
        span = 45 - 6.4
        for b in range(per_sector):
            a0 = a_start + span * b / per_sector + 0.35
            a1 = a_start + span * (b + 1) / per_sector - 0.35
            mat = m["roof"] if rng.random() > 0.2 else m["wall_alt"]
            # optional butt joint
            cuts = [r_out]
            if rng.random() < 0.55:
                cuts.append(rng.uniform(0.95, 1.2))
            cuts.append(r_in)
            for ra, rb in zip(cuts, cuts[1:]):
                lift = rng.uniform(0.0, 0.008)
                t = thickness * rng.uniform(0.8, 1.2)
                tilt = rng.uniform(-0.004, 0.004)
                steps = 7
                secs = []
                for i in range(steps + 1):
                    f = i / steps
                    r = ra + (rb - ra) * f
                    if i == 0 and ra != r_out:
                        r = ra - 0.006
                    if i == steps and rb != r_in:
                        r = rb + 0.006
                    z = roof_z(min(r, EAVE_RADIUS)) + lift
                    za, zb = z + tilt, z - tilt
                    secs.append([k.polar(r, a0, za + t), k.polar(r, a1, zb + t),
                                 k.polar(r, a1, zb), k.polar(r, a0, za)])
                k.board(secs, mat, bevel=0.004, name="roof_board")


def build_skylight(m):
    z = ROOF_TOP_Z
    k.torus(ROOF_TOP_RADIUS + 0.03, 0.045, (0, 0, z + 0.03), m["frame"])
    k.ring_of_rivets(ROOF_TOP_RADIUS + 0.03, z + 0.075, 24, m["rivet"], 0.013)
    k.cylinder(ROOF_TOP_RADIUS + 0.02, 0.3, (0, 0, z - 0.15), m["interior"],
               vertices=48)
    k.cylinder(ROOF_TOP_RADIUS - 0.02, 0.02, (0, 0, z - 0.06),
               k.emissive("floor_glow", (1.0, 0.5, 0.15), 0.25,
                          base=(0.1, 0.07, 0.04)), vertices=48)
    for (x, y, sz) in ((0.18, 0.12, 0.14), (-0.2, 0.05, 0.11),
                       (0.02, -0.22, 0.12), (-0.05, 0.26, 0.1)):
        k.box((sz, sz, sz), (x, y, z - 0.05 + sz / 2), m["steel_dark"],
              bevel=0.01)
    for ang in (40, 160, 280):
        k.sphere(0.035, k.polar(ROOF_TOP_RADIUS * 0.62, ang, z - 0.02),
                 m["lamp"], segments=10)
    k.cylinder(ROOF_TOP_RADIUS, 0.01, (0, 0, z + 0.04),
               k.glass("skylight", (0.75, 0.8, 0.75), roughness=0.1),
               vertices=48)
    hex_r = ROOF_TOP_RADIUS * 0.45
    corners = [k.polar(hex_r, 60 * i + 30, z + 0.05) for i in range(6)]
    for i in range(6):
        k.tube_between(corners[i], corners[(i + 1) % 6], 0.02, m["frame"], 6)
        k.tube_between(corners[i],
                       k.polar(ROOF_TOP_RADIUS, 60 * i + 30, z + 0.05),
                       0.02, m["frame"], 6)


def build_entrance(m, style):
    angle = ENTRANCE_ANGLE
    door_r = DRUM_RADIUS + 0.06
    z0 = PLINTH_HEIGHT
    k.box((0.09, 0.52, 0.74), k.polar(door_r, angle, z0 + 0.37), m["frame"],
          rotation=k.facing(angle), bevel=0.02)
    if style == "wood":
        side = Vector(k.polar(1, angle + 90, 0))
        for j in range(4):
            k.box((0.05, 0.092, 0.64 - 0.01 * (j % 2)),
                  Vector(k.polar(door_r + 0.045, angle, z0 + 0.33))
                  + side * (-0.15 + 0.1 * j), m["door"],
                  rotation=k.facing(angle), bevel=0.008)
        for zz in (0.12, 0.5):
            k.box((0.03, 0.38, 0.06), k.polar(door_r + 0.08, angle, z0 + zz),
                  m["post"], rotation=k.facing(angle), bevel=0.008)
    else:
        k.box((0.05, 0.4, 0.64), k.polar(door_r + 0.045, angle, z0 + 0.33),
              m["door"], rotation=k.facing(angle), bevel=0.015)
    k.box((0.03, 0.26, 0.12), k.polar(door_r + 0.075, angle, z0 + 0.5),
          m["window"], rotation=k.facing(angle), bevel=0.005)
    k.box((0.06, 0.16, 0.05), k.polar(door_r + 0.08, angle, z0 + 0.79),
          m["lamp"], rotation=k.facing(angle), bevel=0.01)
    # landing and stairs
    steps = 3
    if style == "wood":
        # plank decking on the landing and two boards per tread, on a frame
        side = Vector(k.polar(1, angle + 90, 0))
        k.box((0.42, 0.66, 0.04), k.polar(DRUM_RADIUS + 0.3, angle, z0 - 0.03),
              m["frame"], rotation=k.facing(angle), bevel=0.008)
        for j in range(4):
            k.box((0.095, 0.66, 0.03),
                  k.polar(DRUM_RADIUS + 0.14 + 0.105 * j, angle, z0 + 0.005),
                  m["post"], rotation=k.facing(angle + (j - 1.5) * 0.6),
                  bevel=0.006)
        for s in range(steps):
            r = DRUM_RADIUS + 0.5 + s * 0.12
            zz = z0 * (1 - (s + 1) / (steps + 1))
            k.box((0.12, 0.6, zz + 0.01), k.polar(r, angle, (zz + 0.01) / 2),
                  m["frame"], rotation=k.facing(angle), bevel=0.008)
            for j in range(2):
                k.box((0.058, 0.62, 0.03), k.polar(r - 0.03 + 0.06 * j, angle,
                                                   zz + 0.025),
                      m["post"], rotation=k.facing(angle + (j - 0.5) * 1.2),
                      bevel=0.006)
    else:
        k.box((0.42, 0.66, 0.06), k.polar(DRUM_RADIUS + 0.3, angle, z0 - 0.01),
              m["steel_dark"], rotation=k.facing(angle), bevel=0.01)
    for s in range(steps):
        r = DRUM_RADIUS + 0.5 + s * 0.12
        zz = z0 * (1 - (s + 1) / (steps + 1))
        if style != "wood":
            k.box((0.13, 0.62, zz + 0.04), k.polar(r, angle, (zz + 0.04) / 2),
                  m["steel_dark"], rotation=k.facing(angle), bevel=0.01)
        k.box((0.035, 0.6, 0.015), k.polar(r + 0.07, angle, zz + 0.045),
              m["yellow"], rotation=k.facing(angle), bevel=0)
    a = math.radians(angle)
    side = Vector((-math.sin(a), math.cos(a), 0))
    for sgn in (-1, 1):
        off = side * 0.32 * sgn
        top = Vector(k.polar(DRUM_RADIUS + 0.48, angle, z0)) + off
        bottom = Vector(k.polar(DRUM_RADIUS + 0.86, angle, 0.02)) + off
        k.tube_between(top, bottom, 0.025, m["frame"], 6)
        rt, rb = top + Vector((0, 0, 0.32)), bottom + Vector((0, 0, 0.3))
        k.tube_between(rt, rb, 0.02, m["yellow"], 8)
        for t in (0.0, 0.5, 1.0):
            p = top.lerp(bottom, t)
            k.tube_between(p, p + Vector((0, 0, 0.31)), 0.016, m["yellow"], 6)
        k.tube_between(rt, Vector(k.polar(DRUM_RADIUS + 0.08, angle, z0 + 0.32))
                       + off * 1.05, 0.02, m["yellow"], 8)


def build_windows(m):
    for angle in (-45, 155):
        r = DRUM_RADIUS + 0.04
        z = PLINTH_HEIGHT + 0.56
        k.box((0.08, 0.62, 0.38), k.polar(r, angle, z), m["frame"],
              rotation=k.facing(angle), bevel=0.02)
        k.box((0.04, 0.5, 0.27), k.polar(r + 0.025, angle, z), m["window"],
              rotation=k.facing(angle), bevel=0.005)
        k.box((0.05, 0.035, 0.27), k.polar(r + 0.045, angle, z), m["frame"],
              rotation=k.facing(angle), bevel=0)
        k.box((0.05, 0.5, 0.03), k.polar(r + 0.045, angle, z), m["frame"],
              rotation=k.facing(angle), bevel=0)
    for angle in (-132, -80):
        k.box((0.05, 0.07, 0.12), k.polar(DRUM_RADIUS + 0.08, angle,
                                          PLINTH_HEIGHT + 0.72), m["lamp"],
              rotation=k.facing(angle), bevel=0.01)


def build_roof_details(m):
    # dish antenna
    base = Vector(k.polar(0.8, 120, roof_z(0.8) + 0.02))
    k.box((0.22, 0.22, 0.08), base, m["frame"], bevel=0.015)
    k.tube_between(base, base + Vector((0, 0, 0.26)), 0.03, m["steel_dark"], 8)
    dish_c = base + Vector((0.05, -0.05, 0.38))
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.26, location=dish_c,
                                         segments=24, ring_count=12)
    dish = bpy.context.active_object
    dish.scale = (1, 1, 0.32)
    dish.rotation_euler = (math.radians(-50), 0, math.radians(-30))
    k.shade_smooth(dish, 80)
    k.assign(dish, m["steel"])
    k.tube_between(dish_c, dish_c + Vector((0.14, -0.16, 0.14)), 0.012,
                   m["frame"], 6)
    # mast with beacon
    mast = Vector(k.polar(0.64, 88, roof_z(0.64) + 0.03))
    k.box((0.16, 0.16, 0.1), mast, m["frame"], bevel=0.015)
    k.tube_between(mast, mast + Vector((0, 0, 0.5)), 0.026, m["steel_dark"], 8)
    k.sphere(0.05, mast + Vector((0, 0, 0.54)), m["lamp"], segments=12)
    # chimney
    chim = Vector(k.polar(0.98, 48, roof_z(0.98)))
    k.cylinder(0.1, 0.4, chim + Vector((0, 0, 0.19)), m["steel_dark"], 16)
    k.cylinder(0.125, 0.05, chim + Vector((0, 0, 0.4)), m["frame"], 16)
    k.cylinder(0.075, 0.02, chim + Vector((0, 0, 0.425)), m["black"], 16)
    # roof vent
    vent = Vector(k.polar(0.92, -18, roof_z(0.92) + 0.02))
    k.box((0.36, 0.36, 0.06), vent, m["frame"], rotation=k.facing(-15),
          bevel=0.015)
    k.cylinder(0.12, 0.2, vent + Vector((0, 0, 0.12)), m["steel"], 20)
    for j in range(4):
        k.cylinder(0.135, 0.015, vent + Vector((0, 0, 0.05 + 0.045 * j)),
                   m["frame"], 20)
    k.cylinder(0.14, 0.04, vent + Vector((0, 0, 0.24)), m["steel_dark"], 20)


def lamp_post(loc, m, height=0.85):
    loc = Vector(loc)
    k.box((0.28, 0.28, 0.34), loc + Vector((0, 0, 0.17)), m["concrete"],
          bevel=0.03)
    k.box((0.29, 0.06, 0.07), loc + Vector((0, -0.12, 0.27)), m["hazard"],
          bevel=0)
    k.box((0.12, 0.12, height), loc + Vector((0, 0, 0.34 + height / 2)),
          m["post"], bevel=0.015)
    k.box((0.16, 0.16, 0.06), loc + Vector((0, 0, 0.34 + height)), m["frame"],
          bevel=0.01)
    k.sphere(0.05, loc + Vector((0, -0.07, 0.34 + height - 0.08)), m["lamp"])
    return loc + Vector((0, 0, 0.34 + height - 0.14))


def build_posts_and_cables(m):
    left = lamp_post(k.polar(EAVE_RADIUS + 0.22, 192, 0), m)
    right_a = lamp_post(k.polar(EAVE_RADIUS + 0.18, 52, 0), m, height=0.95)
    right_b = lamp_post(k.polar(EAVE_RADIUS + 0.26, 14, 0), m, height=0.8)
    k.sagging_cable(left, k.polar(EAVE_RADIUS, 150, ROOF_BASE_Z + 0.1), 0.12,
                    m["brass"])
    k.sagging_cable(right_a, k.polar(EAVE_RADIUS, 85, ROOF_BASE_Z + 0.1), 0.1,
                    m["brass"])
    k.sagging_cable(right_a, right_b, 0.15, m["brass"])


def build_airlock(m):
    angle = -12
    r = DRUM_RADIUS + 0.33
    z0 = PLINTH_HEIGHT
    k.box((0.58, 0.62, 0.78), k.polar(r, angle, z0 + 0.2), m["steel_dark"],
          rotation=k.facing(angle), bevel=0.04)
    k.box((0.62, 0.66, 0.08), k.polar(r, angle, z0 + 0.62), m["frame"],
          rotation=k.facing(angle), bevel=0.02)
    k.box((0.05, 0.38, 0.4), k.polar(r + 0.28, angle, z0 + 0.18),
          m["interior"], rotation=k.facing(angle), bevel=0.01)
    k.box((0.06, 0.42, 0.05), k.polar(r + 0.3, angle, z0 + 0.46), m["lamp"],
          rotation=k.facing(angle), bevel=0.01)
    k.box((0.2, 0.58, 0.05), k.polar(r + 0.38, angle, 0.04), m["hazard"],
          rotation=k.facing(angle), bevel=0.01)
    for j in (-1, 1):
        k.box((0.6, 0.05, 0.7), Vector(k.polar(r, angle, z0 + 0.2))
              + Vector(k.polar(0.33 * j, angle + 90, 0)), m["frame"],
              rotation=k.facing(angle), bevel=0.01)


def build_props(m):
    k.barrel(k.polar(DRUM_RADIUS + 0.3, -42, 0), 0.13, 0.36, m["blue"],
             m["frame"])
    k.box((0.08, 0.2, 0.26), k.polar(DRUM_RADIUS + 0.08, -60,
                                     PLINTH_HEIGHT + 0.36),
          m["frame"], rotation=k.facing(-60), bevel=0.015)
    k.tube_between(k.polar(DRUM_RADIUS + 0.1, -25, PLINTH_HEIGHT + 0.05),
                   k.polar(DRUM_RADIUS + 0.1, -25, PLINTH_HEIGHT + 0.85), 0.03,
                   m["steel_dark"], 10)
    k.box((0.3, 0.32, 0.52), k.polar(DRUM_RADIUS + 0.28, 205, 0.26),
          m["concrete"], rotation=k.facing(205), bevel=0.03)
    k.box((0.31, 0.33, 0.07), k.polar(DRUM_RADIUS + 0.28, 205, 0.17),
          m["hazard"], rotation=k.facing(205), bevel=0)


def build(style):
    scene = k.reset_scene()
    m = materials(style)
    build_plinth(m)
    build_drum(m, style)
    build_roof(m, style)
    build_skylight(m)
    build_entrance(m, style)
    build_windows(m)
    build_roof_details(m)
    build_posts_and_cables(m)
    build_airlock(m)
    build_props(m)
    k.scale_model(MODEL_SCALE)
    k.setup_lights(scene)
    return scene
