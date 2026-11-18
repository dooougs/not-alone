"""Builds the Iron Habitat model and renders its sprites.

The model follows the wooden Habitat (graphics/entity/habitat.png): a round
drum on a plinth of blocks, a low roof with radial beams and a hex-paned
skylight, front stairs to a door, a dish and beacon mast, a chimney, roof
vent, lamp posts strung with cable, a side airlock and a barrel. Wood is
replaced with riveted iron plate.

Run with Blender:   blender -b -P image-builder/blender/iron_habitat.py
or with the bpy module:   python image-builder/blender/iron_habitat.py

Writes:
  image-builder/blender/iron_habitat.blend
  graphics/entity/iron-habitat.png   (256x256, drawn at scale 0.5)
  graphics/icons/iron-habitat.png    (64x64)
"""

import math
import os
import sys

import bpy
import bmesh
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
BLEND_PATH = os.path.join(HERE, "iron_habitat.blend")
ENTITY_PATH = os.path.join(ROOT, "graphics", "entity", "iron-habitat.png")
ICON_PATH = os.path.join(ROOT, "graphics", "icons", "iron-habitat.png")
RAW_PATH = os.path.join(HERE, "render_raw.png")

# Supersampled render size, downscaled to the sprite sizes afterwards.
RENDER_SIZE = 1024
SAMPLES = int(os.environ.get("IRON_HABITAT_SAMPLES", "96"))

DRUM_RADIUS = 1.22
DRUM_HEIGHT = 1.1
PLINTH_HEIGHT = 0.24
EAVE_RADIUS = 1.36
ROOF_TOP_RADIUS = 0.6
ROOF_BASE_Z = PLINTH_HEIGHT + DRUM_HEIGHT
# Dome profile of the roof as (radius, height above ROOF_BASE_Z), eave first.
ROOF_PROFILE = [(EAVE_RADIUS, 0.08), (1.3, 0.2), (1.15, 0.35), (0.95, 0.47),
                (ROOF_TOP_RADIUS + 0.06, 0.6)]
ROOF_TOP_Z = ROOF_BASE_Z + ROOF_PROFILE[-1][1]


def roof_z(radius):
    """Height of the roof surface at a given radius."""
    pts = ROOF_PROFILE
    if radius >= pts[0][0]:
        return ROOF_BASE_Z + pts[0][1]
    for (r0, z0), (r1, z1) in zip(pts, pts[1:]):
        if r1 <= radius <= r0:
            t = (r0 - radius) / (r0 - r1)
            return ROOF_BASE_Z + z0 + (z1 - z0) * t
    return ROOF_TOP_Z


# ---------------------------------------------------------------- scene setup

def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = SAMPLES
    scene.cycles.use_denoising = True
    scene.render.film_transparent = True
    scene.render.resolution_x = RENDER_SIZE
    scene.render.resolution_y = RENDER_SIZE
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    return scene


def material(name, color, metallic=0.0, roughness=0.5, emission=None,
             strength=0.0, noise=0.0, rust=0.0, alpha=1.0):
    """Principled material with optional grime noise and rust mixed in."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    bsdf = nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    if alpha < 1.0:
        bsdf.inputs["Alpha"].default_value = alpha
    if emission:
        bsdf.inputs["Emission Color"].default_value = (*emission, 1.0)
        bsdf.inputs["Emission Strength"].default_value = strength
    if noise > 0 or rust > 0:
        coord = nodes.new("ShaderNodeTexCoord")
        tex = nodes.new("ShaderNodeTexNoise")
        tex.inputs["Scale"].default_value = 5.0
        tex.inputs["Detail"].default_value = 8.0
        links.new(coord.outputs["Object"], tex.inputs["Vector"])
        ramp = nodes.new("ShaderNodeValToRGB")
        ramp.color_ramp.elements[0].position = 0.35
        ramp.color_ramp.elements[1].position = 0.75
        links.new(tex.outputs["Fac"], ramp.inputs["Fac"])
        rust_color = nodes.new("ShaderNodeRGB")
        rust_color.outputs[0].default_value = (0.32, 0.14, 0.06, 1.0)
        base = nodes.new("ShaderNodeRGB")
        base.outputs[0].default_value = (*color, 1.0)
        dark = nodes.new("ShaderNodeMix")
        dark.data_type = "RGBA"
        dark.inputs["Factor"].default_value = noise
        links.new(base.outputs[0], dark.inputs["A"])
        dark.inputs["B"].default_value = (color[0] * 0.55, color[1] * 0.55,
                                          color[2] * 0.55, 1.0)
        mix_fac = nodes.new("ShaderNodeMath")
        mix_fac.operation = "MULTIPLY"
        mix_fac.inputs[1].default_value = rust
        links.new(ramp.outputs["Color"], mix_fac.inputs[0])
        rusty = nodes.new("ShaderNodeMix")
        rusty.data_type = "RGBA"
        links.new(mix_fac.outputs[0], rusty.inputs["Factor"])
        links.new(dark.outputs["Result"], rusty.inputs["A"])
        links.new(rust_color.outputs[0], rusty.inputs["B"])
        links.new(rusty.outputs["Result"], bsdf.inputs["Base Color"])
        # Rusty patches are rough and not metallic.
        rough = nodes.new("ShaderNodeMapRange")
        links.new(mix_fac.outputs[0], rough.inputs["Value"])
        rough.inputs["To Min"].default_value = roughness
        rough.inputs["To Max"].default_value = 0.9
        links.new(rough.outputs["Result"], bsdf.inputs["Roughness"])
        metal = nodes.new("ShaderNodeMapRange")
        links.new(mix_fac.outputs[0], metal.inputs["Value"])
        metal.inputs["To Min"].default_value = metallic
        metal.inputs["To Max"].default_value = 0.1
        links.new(metal.outputs["Result"], bsdf.inputs["Metallic"])
    return mat


def hazard_material():
    mat = bpy.data.materials.new("hazard")
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    bsdf = nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 0.6
    coord = nodes.new("ShaderNodeTexCoord")
    wave = nodes.new("ShaderNodeTexWave")
    wave.wave_type = "BANDS"
    wave.bands_direction = "DIAGONAL"
    wave.inputs["Scale"].default_value = 6.0
    links.new(coord.outputs["Object"], wave.inputs["Vector"])
    ramp = nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.interpolation = "CONSTANT"
    ramp.color_ramp.elements[0].color = (0.02, 0.02, 0.02, 1)
    ramp.color_ramp.elements[1].position = 0.5
    ramp.color_ramp.elements[1].color = (0.85, 0.55, 0.05, 1)
    links.new(wave.outputs["Fac"], ramp.inputs["Fac"])
    links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    return mat


def make_materials():
    return {
        "plate": material("iron_plate", (0.33, 0.32, 0.31), metallic=0.75,
                          roughness=0.55, noise=0.55, rust=0.6),
        "plate_dark": material("iron_dark", (0.19, 0.2, 0.21), metallic=0.85,
                               roughness=0.5, noise=0.3, rust=0.25),
        "strap": material("iron_strap", (0.14, 0.14, 0.15), metallic=0.9,
                          roughness=0.38, noise=0.2, rust=0.15),
        "rivet": material("rivet", (0.55, 0.55, 0.56), metallic=1.0,
                          roughness=0.3),
        "stone": material("plinth", (0.17, 0.17, 0.18), metallic=0.3,
                          roughness=0.75, noise=0.4),
        "yellow": material("rail_paint", (0.85, 0.6, 0.08), metallic=0.2,
                           roughness=0.45),
        "lamp": material("lamp", (1.0, 0.6, 0.15), emission=(1.0, 0.55, 0.1),
                         strength=12.0),
        "glow": material("interior_glow", (0.03, 0.025, 0.02),
                         emission=(1.0, 0.5, 0.12), strength=0.5),
        "window": material("window_glow", (0.9, 0.6, 0.25),
                           emission=(1.0, 0.6, 0.2), strength=2.5),
        "glow_dim": material("interior", (0.35, 0.22, 0.12),
                             emission=(1.0, 0.5, 0.15), strength=0.6),
        "glass": material("glass", (0.08, 0.1, 0.1), metallic=0.0,
                          roughness=0.04, alpha=0.6),
        "door": material("door", (0.32, 0.3, 0.28), metallic=0.8,
                         roughness=0.5, noise=0.3),
        "barrel": material("barrel", (0.12, 0.25, 0.5), metallic=0.6,
                           roughness=0.4),
        "cable": material("cable", (0.85, 0.55, 0.1), metallic=0.1,
                          roughness=0.5),
        "hazard": hazard_material(),
    }


# ------------------------------------------------------------- mesh helpers

def assign(obj, mat):
    obj.data.materials.clear()
    obj.data.materials.append(mat)
    return obj


def shade_smooth(obj, angle=40):
    for poly in obj.data.polygons:
        poly.use_smooth = True
    try:
        obj.data.set_sharp_from_angle(angle=math.radians(angle))
    except AttributeError:
        pass


def box(size, location, mat, rotation=(0, 0, 0), bevel=0.02):
    bpy.ops.mesh.primitive_cube_add(size=1, location=location, rotation=rotation)
    obj = bpy.context.active_object
    obj.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel:
        mod = obj.modifiers.new("bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 2
    return assign(obj, mat)


def cylinder(radius, depth, location, mat, vertices=48, rotation=(0, 0, 0),
             smooth=True):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius,
                                        depth=depth, location=location,
                                        rotation=rotation)
    obj = bpy.context.active_object
    if smooth:
        shade_smooth(obj)
    return assign(obj, mat)


def sphere(radius, location, mat, segments=10):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=radius, location=location,
                                         segments=segments,
                                         ring_count=segments // 2)
    obj = bpy.context.active_object
    shade_smooth(obj)
    return assign(obj, mat)


def polar(radius, angle_deg, z):
    a = math.radians(angle_deg)
    return (radius * math.cos(a), radius * math.sin(a), z)


def facing(angle_deg):
    """Rotation that turns an object's +X axis outwards at angle_deg."""
    return (0, 0, math.radians(angle_deg))


def tube_between(p0, p1, radius, mat, vertices=8):
    p0, p1 = Vector(p0), Vector(p1)
    direction = p1 - p0
    obj = cylinder(radius, direction.length, (p0 + p1) / 2, mat,
                   vertices=vertices)
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = direction.to_track_quat("Z", "Y")
    return obj


def beam_between(p0, p1, width, height, mat, bevel=0.012):
    """Box running from p0 to p1, kept level across its width."""
    p0, p1 = Vector(p0), Vector(p1)
    x = (p1 - p0).normalized()
    y = Vector((0, 0, 1)).cross(x).normalized()
    z = x.cross(y)
    obj = box(((p1 - p0).length + 0.04, width, height), (p0 + p1) / 2, mat,
              bevel=bevel)
    from mathutils import Matrix
    rot = Matrix((x, y, z)).transposed().to_4x4()
    obj.matrix_world = Matrix.Translation((p0 + p1) / 2) @ rot
    return obj


def sagging_cable(p0, p1, sag, mat, steps=10):
    p0, p1 = Vector(p0), Vector(p1)
    points = []
    for i in range(steps + 1):
        t = i / steps
        p = p0.lerp(p1, t)
        p.z -= sag * 4 * t * (1 - t)
        points.append(p)
    for a, b in zip(points, points[1:]):
        tube_between(a, b, 0.018, mat, vertices=6)


def ring_of_rivets(radius, z, count, mat, size=0.022):
    for i in range(count):
        sphere(size, polar(radius, 360 * i / count, z), mat, segments=8)


def is_clear(angle, gaps):
    for centre, half_width in gaps:
        diff = (angle - centre + 180) % 360 - 180
        if abs(diff) < half_width:
            return False
    return True


# ------------------------------------------------------------ the building

def build_plinth(m):
    """Chunky blocks ringing the base, like the stone footing of the original."""
    count = 26
    for i in range(count):
        angle = 360 * i / count + 5
        if not is_clear(angle, [(-112, 16)]):
            continue
        h = PLINTH_HEIGHT + (0.07 if i % 3 == 0 else 0)
        depth = 0.34 if i % 2 else 0.26
        box((depth, 0.28, h), polar(DRUM_RADIUS + 0.12, angle, h / 2),
            m["stone"], rotation=facing(angle), bevel=0.03)
        if i % 3 == 2:
            box((0.2, 0.22, 0.14), polar(DRUM_RADIUS + 0.34, angle + 4, 0.07),
                m["stone"], rotation=facing(angle + 10), bevel=0.025)
        if i % 4 == 1:
            box((0.02, 0.3, 0.07), polar(DRUM_RADIUS + 0.34, angle, h * 0.55),
                m["hazard"], rotation=facing(angle), bevel=0)
    cylinder(DRUM_RADIUS + 0.05, PLINTH_HEIGHT * 0.9,
             (0, 0, PLINTH_HEIGHT * 0.45), m["stone"], vertices=64)


def build_drum(m):
    """Iron-plated walls: vertical panels, straps and rivet seams."""
    z0 = PLINTH_HEIGHT
    cylinder(DRUM_RADIUS - 0.03, DRUM_HEIGHT, (0, 0, z0 + DRUM_HEIGHT / 2),
             m["plate_dark"], vertices=64)
    panels = 20
    panel_angle = 360 / panels
    width = 2 * math.pi * DRUM_RADIUS / panels * 0.94
    for i in range(panels):
        angle = panel_angle * (i + 0.5)
        for row, (zc, hh) in enumerate([(0.24, 0.42), (0.69, 0.4)]):
            box((0.04, width, hh), polar(DRUM_RADIUS, angle, z0 + zc),
                m["plate"], rotation=facing(angle), bevel=0.012)
        # vertical seam rivets
        seam = panel_angle * i
        for zc in (0.08, 0.24, 0.4, 0.55, 0.7, 0.86):
            sphere(0.02, polar(DRUM_RADIUS + 0.025, seam, z0 + zc), m["rivet"])
    for zc in (0.03, 0.465, DRUM_HEIGHT - 0.03):
        band = cylinder(DRUM_RADIUS + 0.035, 0.06, (0, 0, z0 + zc), m["strap"],
                        vertices=64)
        ring_of_rivets(DRUM_RADIUS + 0.065, z0 + zc, 40, m["rivet"], size=0.017)
    # pilasters between sections, echoing the timber posts of the original
    for angle in (-140, -70, -30, 40, 115, 170):
        box((0.12, 0.12, DRUM_HEIGHT + 0.05),
            polar(DRUM_RADIUS + 0.04, angle, z0 + DRUM_HEIGHT / 2),
            m["strap"], rotation=facing(angle), bevel=0.02)


def build_roof(m):
    """Domed lid with radial beams and an overhanging eave."""
    bm = bmesh.new()
    rings = [(EAVE_RADIUS, ROOF_BASE_Z - 0.03)] + [
        (r, ROOF_BASE_Z + z) for r, z in ROOF_PROFILE]
    segs = 72
    verts = []
    for r, z in rings:
        ring = [bm.verts.new((r * math.cos(2 * math.pi * i / segs),
                              r * math.sin(2 * math.pi * i / segs), z))
                for i in range(segs)]
        verts.append(ring)
    for a, b in zip(verts, verts[1:]):
        for i in range(segs):
            j = (i + 1) % segs
            bm.faces.new((a[i], a[j], b[j], b[i]))
    bm.faces.new(list(reversed(verts[0])))
    mesh = bpy.data.meshes.new("roof")
    bm.to_mesh(mesh)
    bm.free()
    roof = bpy.data.objects.new("roof", mesh)
    bpy.context.collection.objects.link(roof)
    shade_smooth(roof, angle=35)
    assign(roof, m["plate"])

    # eave strap
    cylinder(EAVE_RADIUS + 0.015, 0.11, (0, 0, ROOF_BASE_Z + 0.025),
             m["strap"], vertices=72)
    ring_of_rivets(EAVE_RADIUS + 0.025, ROOF_BASE_Z + 0.025, 44, m["rivet"],
                   size=0.017)
    # a lap seam strap part way up
    bpy.ops.mesh.primitive_torus_add(major_radius=1.15, minor_radius=0.022,
                                     location=(0, 0, roof_z(1.15) + 0.005))
    seam = bpy.context.active_object
    shade_smooth(seam)
    assign(seam, m["strap"])
    # radial beams following the dome
    beams = 8
    radii = [EAVE_RADIUS + 0.03, 1.3, 1.15, 0.95, ROOF_TOP_RADIUS + 0.08]
    for i in range(beams):
        angle = 360 * i / beams + 22.5
        pts = [Vector(polar(r, angle, roof_z(min(r, EAVE_RADIUS)) + 0.03))
               for r in radii]
        for a, b in zip(pts, pts[1:]):
            beam_between(a, b, 0.14, 0.05, m["strap"])
        for p in pts[1:-1]:
            sphere(0.022, p + Vector((0, 0, 0.03)), m["rivet"])
    # thin radial plate seams between the beams
    for i in range(beams):
        angle = 360 * i / beams
        pts = [Vector(polar(r, angle, roof_z(min(r, EAVE_RADIUS)) + 0.004))
               for r in radii[1:]]
        for a, b in zip(pts, pts[1:]):
            tube_between(a, b, 0.012, m["strap"], vertices=6)


def build_skylight(m):
    """Round skylight with a hex frame and warm light showing through."""
    z = ROOF_TOP_Z
    bpy.ops.mesh.primitive_torus_add(major_radius=ROOF_TOP_RADIUS + 0.03,
                                     minor_radius=0.04, location=(0, 0, z + 0.03))
    rim = bpy.context.active_object
    shade_smooth(rim)
    assign(rim, m["plate_dark"])
    ring_of_rivets(ROOF_TOP_RADIUS + 0.03, z + 0.07, 24, m["rivet"], 0.014)
    # interior well so the opening reads as a lit room below
    cylinder(ROOF_TOP_RADIUS + 0.02, 0.3, (0, 0, z - 0.15), m["glow_dim"],
             vertices=48)
    # glowing interior below the glass
    cylinder(ROOF_TOP_RADIUS - 0.02, 0.02, (0, 0, z - 0.02), m["glow"],
             vertices=48)
    cylinder(ROOF_TOP_RADIUS, 0.01, (0, 0, z + 0.03), m["glass"],
             vertices=48)
    # a few crates glimpsed through the glass
    for (x, y, sz) in ((0.18, 0.12, 0.14), (-0.2, 0.05, 0.11), (0.02, -0.22, 0.12)):
        box((sz, sz, sz), (x, y, z - 0.01 + sz / 2), m["door"], bevel=0.01)
    # hexagon frame and spokes
    hex_r = ROOF_TOP_RADIUS * 0.45
    corners = [polar(hex_r, 60 * i + 30, z + 0.045) for i in range(6)]
    for i in range(6):
        tube_between(corners[i], corners[(i + 1) % 6], 0.018, m["strap"], 6)
        tube_between(corners[i], polar(ROOF_TOP_RADIUS, 60 * i + 30, z + 0.045),
                     0.018, m["strap"], 6)


def build_entrance(m):
    """Door, steps and railings at the front-left like the wooden Habitat."""
    angle = -112
    door_r = DRUM_RADIUS + 0.06
    z0 = PLINTH_HEIGHT
    box((0.08, 0.5, 0.72), polar(door_r, angle, z0 + 0.36), m["strap"],
        rotation=facing(angle), bevel=0.02)
    box((0.05, 0.4, 0.64), polar(door_r + 0.04, angle, z0 + 0.33), m["door"],
        rotation=facing(angle), bevel=0.015)
    box((0.03, 0.28, 0.12), polar(door_r + 0.07, angle, z0 + 0.48), m["glass"],
        rotation=facing(angle), bevel=0.005)
    box((0.06, 0.14, 0.05), polar(door_r + 0.07, angle, z0 + 0.76), m["lamp"],
        rotation=facing(angle), bevel=0.01)
    # landing and stairs
    box((0.5, 0.62, 0.06), polar(DRUM_RADIUS + 0.35, angle, z0 - 0.01),
        m["plate_dark"], rotation=facing(angle), bevel=0.01)
    steps = 3
    for s in range(steps):
        r = DRUM_RADIUS + 0.66 + s * 0.17
        zz = z0 * (1 - (s + 1) / (steps + 1))
        box((0.19, 0.6, zz + 0.04), polar(r, angle, (zz + 0.04) / 2),
            m["plate_dark"], rotation=facing(angle), bevel=0.01)
        box((0.04, 0.58, 0.015), polar(r + 0.08, angle, zz + 0.045),
            m["yellow"], rotation=facing(angle), bevel=0)
    # side stringers and yellow handrails
    a = math.radians(angle)
    side = Vector((-math.sin(a), math.cos(a), 0))
    for sgn in (-1, 1):
        offset = side * 0.3 * sgn
        top = Vector(polar(DRUM_RADIUS + 0.55, angle, z0)) + offset
        bottom = Vector(polar(DRUM_RADIUS + 1.18, angle, 0.02)) + offset
        tube_between(top, bottom, 0.025, m["strap"], 6)
        rail_top = top + Vector((0, 0, 0.32))
        rail_bottom = bottom + Vector((0, 0, 0.3))
        tube_between(rail_top, rail_bottom, 0.02, m["yellow"], 8)
        for t in (0.0, 0.5, 1.0):
            p = top.lerp(bottom, t)
            tube_between(p, p + Vector((0, 0, 0.31)), 0.015, m["yellow"], 6)
        tube_between(rail_top, Vector(polar(DRUM_RADIUS + 0.08, angle, z0 + 0.32))
                     + offset * 1.05, 0.02, m["yellow"], 8)


def build_windows(m):
    for angle in (-45, 155):
        r = DRUM_RADIUS + 0.04
        z = PLINTH_HEIGHT + 0.55
        box((0.07, 0.62, 0.36), polar(r, angle, z), m["strap"],
            rotation=facing(angle), bevel=0.02)
        box((0.04, 0.52, 0.27), polar(r + 0.02, angle, z), m["window"],
            rotation=facing(angle), bevel=0.005)
        box((0.05, 0.035, 0.27), polar(r + 0.04, angle, z), m["strap"],
            rotation=facing(angle), bevel=0)
    for angle in (-130, -75):
        box((0.04, 0.06, 0.12), polar(DRUM_RADIUS + 0.08, angle,
                                       PLINTH_HEIGHT + 0.7), m["lamp"],
            rotation=facing(angle), bevel=0.01)


def build_roof_details(m):
    # dish antenna on a stand
    base = Vector(polar(0.78, 118, roof_z(0.78) + 0.02))
    box((0.22, 0.22, 0.08), base, m["strap"], bevel=0.015)
    tube_between(base, base + Vector((0, 0, 0.3)), 0.03, m["plate_dark"], 8)
    bpy.ops.mesh.primitive_cone_add(vertices=24, radius1=0.24, radius2=0.05,
                                    depth=0.09,
                                    location=base + Vector((0.05, -0.05, 0.42)),
                                    rotation=(math.radians(-55), 0,
                                              math.radians(-25)))
    dish = bpy.context.active_object
    shade_smooth(dish)
    assign(dish, m["rivet"])
    tube_between(base + Vector((0.05, -0.05, 0.42)),
                 base + Vector((0.22, -0.2, 0.55)), 0.012, m["strap"], 6)
    # tall mast with beacon
    mast = Vector(polar(0.66, 90, roof_z(0.66) + 0.03))
    box((0.16, 0.16, 0.1), mast, m["strap"], bevel=0.015)
    tube_between(mast, mast + Vector((0, 0, 0.75)), 0.025, m["plate_dark"], 8)
    sphere(0.055, mast + Vector((0, 0, 0.8)), m["lamp"], segments=12)
    tube_between(mast + Vector((-0.2, 0.05, 0)),
                 mast + Vector((-0.2, 0.05, 0.95)), 0.022, m["strap"], 8)
    # chimney
    chim = Vector(polar(0.98, 48, roof_z(0.98)))
    cylinder(0.1, 0.42, chim + Vector((0, 0, 0.2)), m["plate_dark"], vertices=16)
    cylinder(0.125, 0.05, chim + Vector((0, 0, 0.42)), m["strap"], vertices=16)
    cylinder(0.075, 0.02, chim + Vector((0, 0, 0.445)), m["stone"], vertices=16)
    # roof vent unit
    vent = Vector(polar(0.92, -18, roof_z(0.92) + 0.02))
    box((0.36, 0.36, 0.06), vent, m["strap"], rotation=facing(-15), bevel=0.015)
    cylinder(0.12, 0.2, vent + Vector((0, 0, 0.12)), m["rivet"], vertices=20)
    for k in range(4):
        cylinder(0.135, 0.015, vent + Vector((0, 0, 0.05 + 0.045 * k)),
                 m["strap"], vertices=20)
    cylinder(0.14, 0.04, vent + Vector((0, 0, 0.24)), m["plate_dark"],
             vertices=20)


def lamp_post(location, m, height=0.95):
    loc = Vector(location)
    box((0.3, 0.3, 0.38), loc + Vector((0, 0, 0.19)), m["stone"], bevel=0.03)
    box((0.31, 0.06, 0.08), loc + Vector((0, -0.13, 0.3)), m["hazard"], bevel=0)
    box((0.12, 0.12, height), loc + Vector((0, 0, 0.38 + height / 2)),
        m["plate_dark"], bevel=0.015)
    box((0.16, 0.16, 0.06), loc + Vector((0, 0, 0.38 + height)), m["strap"],
        bevel=0.01)
    sphere(0.055, loc + Vector((0, -0.07, 0.38 + height - 0.08)), m["lamp"])
    return loc + Vector((0, 0, 0.38 + height - 0.15))


def build_posts_and_cables(m):
    left = lamp_post(polar(EAVE_RADIUS + 0.25, 195, 0), m)
    right_a = lamp_post(polar(EAVE_RADIUS + 0.2, 52, 0), m, height=1.05)
    right_b = lamp_post(polar(EAVE_RADIUS + 0.3, 12, 0), m, height=0.9)
    sagging_cable(left, polar(EAVE_RADIUS, 150, ROOF_BASE_Z + 0.1), 0.12,
                  m["cable"])
    sagging_cable(right_a, polar(EAVE_RADIUS, 85, ROOF_BASE_Z + 0.1), 0.1,
                  m["cable"])
    sagging_cable(right_a, right_b, 0.15, m["cable"])


def build_airlock(m):
    """Boxy side module with a lit doorway and hazard sill."""
    angle = -12
    r = DRUM_RADIUS + 0.35
    z0 = PLINTH_HEIGHT
    box((0.6, 0.62, 0.78), polar(r, angle, z0 + 0.2), m["plate_dark"],
        rotation=facing(angle), bevel=0.04)
    box((0.62, 0.66, 0.08), polar(r, angle, z0 + 0.62), m["strap"],
        rotation=facing(angle), bevel=0.02)
    box((0.05, 0.4, 0.4), polar(r + 0.29, angle, z0 + 0.2), m["glow"],
        rotation=facing(angle), bevel=0.01)
    box((0.06, 0.44, 0.05), polar(r + 0.31, angle, z0 + 0.48), m["lamp"],
        rotation=facing(angle), bevel=0.01)
    box((0.22, 0.6, 0.05), polar(r + 0.4, angle, 0.06), m["hazard"],
        rotation=facing(angle), bevel=0.01)
    for k in (-1, 1):
        box((0.62, 0.05, 0.7), Vector(polar(r, angle, z0 + 0.2))
            + Vector(polar(0.33 * k, angle + 90, 0)), m["strap"],
            rotation=facing(angle), bevel=0.01)


def build_props(m):
    barrel = Vector(polar(DRUM_RADIUS + 0.32, -40, 0))
    cylinder(0.13, 0.36, barrel + Vector((0, 0, 0.18)), m["barrel"], vertices=20)
    for zc in (0.08, 0.28):
        cylinder(0.135, 0.02, barrel + Vector((0, 0, zc)), m["strap"],
                 vertices=20)
    cylinder(0.04, 0.02, barrel + Vector((0.05, 0, 0.37)), m["strap"], 10)
    # pipes and junction boxes on the wall
    box((0.08, 0.2, 0.26), polar(DRUM_RADIUS + 0.07, -60, PLINTH_HEIGHT + 0.35),
        m["strap"], rotation=facing(-60), bevel=0.015)
    tube_between(polar(DRUM_RADIUS + 0.09, -25, PLINTH_HEIGHT + 0.05),
                 polar(DRUM_RADIUS + 0.09, -25, PLINTH_HEIGHT + 0.85), 0.03,
                 m["plate_dark"], 10)
    box((0.3, 0.32, 0.55), polar(DRUM_RADIUS + 0.3, 205, 0.28), m["stone"],
        rotation=facing(205), bevel=0.03)
    box((0.31, 0.33, 0.07), polar(DRUM_RADIUS + 0.3, 205, 0.18), m["hazard"],
        rotation=facing(205), bevel=0)


# --------------------------------------------------------- camera & lights

def setup_camera_and_lights(scene):
    cam_data = bpy.data.cameras.new("camera")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 4.6
    cam = bpy.data.objects.new("camera", cam_data)
    scene.collection.objects.link(cam)
    elevation = math.radians(40)
    azimuth = math.radians(-90)  # looking from the south (screen bottom)
    distance = 20
    target = Vector((0, -0.3, 0.95))
    cam.location = target + Vector((math.cos(azimuth) * math.cos(elevation),
                                    math.sin(azimuth) * math.cos(elevation),
                                    math.sin(elevation))) * distance
    cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam

    # Factorio sprites are lit from the upper left.
    sun = bpy.data.lights.new("sun", "SUN")
    sun.energy = 5.5
    sun.color = (1.0, 0.94, 0.86)
    sun.angle = math.radians(8)
    sun_obj = bpy.data.objects.new("sun", sun)
    sun_obj.rotation_euler = (math.radians(45), math.radians(-35), math.radians(-30))
    scene.collection.objects.link(sun_obj)

    fill = bpy.data.lights.new("fill", "SUN")
    fill.energy = 0.8
    fill_obj = bpy.data.objects.new("fill", fill)
    fill_obj.rotation_euler = (math.radians(60), math.radians(40), math.radians(150))
    scene.collection.objects.link(fill_obj)

    world = bpy.data.worlds.new("world")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.5, 0.52, 0.56, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.35
    scene.world = world


# ------------------------------------------------------------------- output

def write_sprites():
    try:
        from PIL import Image
    except ImportError:
        Image = None
    if Image is None:
        # Fall back to Blender's own scaler.
        img = bpy.data.images.load(RAW_PATH)
        img.scale(256, 256)
        img.save(filepath=ENTITY_PATH)
        img.scale(64, 64)
        img.save(filepath=ICON_PATH)
        return
    raw = Image.open(RAW_PATH).convert("RGBA")
    raw.resize((256, 256), Image.LANCZOS).save(ENTITY_PATH)
    bbox = raw.getbbox()
    # Icon: crop tight to the building, keep it square, then shrink.
    left, top, right, bottom = bbox
    side = max(right - left, bottom - top)
    cx, cy = (left + right) / 2, (top + bottom) / 2
    crop = raw.crop((int(cx - side / 2), int(cy - side / 2),
                     int(cx + side / 2), int(cy + side / 2)))
    crop.resize((64, 64), Image.LANCZOS).save(ICON_PATH)


def main():
    scene = reset_scene()
    m = make_materials()
    build_plinth(m)
    build_drum(m)
    build_roof(m)
    build_skylight(m)
    build_entrance(m)
    build_windows(m)
    build_roof_details(m)
    build_posts_and_cables(m)
    build_airlock(m)
    build_props(m)
    setup_camera_and_lights(scene)
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH, compress=True)
    if "--no-render" in sys.argv:
        return
    scene.render.filepath = RAW_PATH
    bpy.ops.render.render(write_still=True)
    write_sprites()
    os.remove(RAW_PATH)


main()
