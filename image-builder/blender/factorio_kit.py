"""Shared Blender toolkit for the Not Alone entity sprites and icons.

Every model script in this folder imports this module. It sets up a scene
that renders like Factorio's own art:

* Projection. An orthographic camera looks north, pitched PITCH (41.4)
  degrees from straight down. Ground depth is foreshortened to cos(PITCH) =
  0.75 and one tile of height reads as sin(PITCH) = 0.66 tiles, measured from
  the vanilla assembler, furnace and chest sprites in image-builder/assets
  (a 3x3 assembler's roof is 3 tiles wide and ~2.25 deep). 1 Blender unit = 1 tile, and the sprite frame maps
  exactly onto the prototype's width/height/scale/shift, so footprints line
  up in game.
* Lighting. A warm key sun from the upper left (north-west) casts shadows to
  the lower right, with a cool sky fill. A shadow catcher bakes the ground
  shadow and contact darkening into the sprite's alpha.
* Materials. Weathered metal with grime in crevices (ambient occlusion),
  bright worn edges (bevel normal vs. true normal), noise breakup and rust
  patches; painted metal that wears through to steel; timber planks with
  per-plank tint variation. The palette is muted and desaturated, with AgX
  tone mapping to keep highlights soft.

Run any model with Blender:     blender -b -P image-builder/blender/<model>.py
or with the bpy module:         python image-builder/blender/<model>.py
Set FA_SAMPLES to trade quality for speed (default 128).
"""

import math
import os
import sys

import bpy
import bmesh
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
GRAPHICS = os.path.join(ROOT, "graphics")

SAMPLES = int(os.environ.get("FA_SAMPLES", "128"))
SUPERSAMPLE = int(os.environ.get("FA_SUPERSAMPLE", "4"))  # render at 4x, then downscale
PITCH = math.radians(float(os.environ.get("FA_PITCH", "41.4")))

# Direction the key light comes *from*: upper left, a little behind.
SUN_FROM = Vector((-1.0, 0.35, 1.05)).normalized()


# ---------------------------------------------------------------- scene setup

def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = SAMPLES
    scene.cycles.use_adaptive_sampling = True
    scene.cycles.use_denoising = True
    scene.cycles.max_bounces = 6
    scene.cycles.transparent_max_bounces = 24
    scene.render.film_transparent = True
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.image_settings.color_depth = "8"
    try:
        scene.view_settings.view_transform = "AgX"
        scene.view_settings.look = "AgX - Medium High Contrast"
    except TypeError:
        scene.view_settings.view_transform = "Filmic"
        scene.view_settings.look = "Medium High Contrast"
    scene.view_settings.exposure = -0.25
    return scene


# ------------------------------------------------------------------ materials

def _nodes(mat):
    mat.use_nodes = True
    return mat.node_tree.nodes, mat.node_tree.links


def _mix(nodes, links, a, b, fac):
    """Colour mix node. a/b/fac are sockets or constants."""
    node = nodes.new("ShaderNodeMix")
    node.data_type = "RGBA"
    for key, value in (("A", a), ("B", b)):
        if isinstance(value, tuple):
            node.inputs[key].default_value = (*value[:3], 1.0)
        else:
            links.new(value, node.inputs[key])
    if isinstance(fac, (int, float)):
        node.inputs["Factor"].default_value = fac
    else:
        links.new(fac, node.inputs["Factor"])
    return node.outputs["Result"]


def _math(nodes, links, op, a, b=None, clamp=False):
    node = nodes.new("ShaderNodeMath")
    node.operation = op
    node.use_clamp = clamp
    for i, value in enumerate((a, b)):
        if value is None:
            continue
        if isinstance(value, (int, float)):
            node.inputs[i].default_value = value
        else:
            links.new(value, node.inputs[i])
    return node.outputs[0]


def _noise(nodes, links, scale, detail=6.0, roughness=0.6, w_offset=0.0):
    coord = nodes.new("ShaderNodeTexCoord")
    tex = nodes.new("ShaderNodeTexNoise")
    tex.noise_dimensions = "4D"
    tex.inputs["Scale"].default_value = scale
    tex.inputs["Detail"].default_value = detail
    tex.inputs["Roughness"].default_value = roughness
    tex.inputs["W"].default_value = w_offset
    links.new(coord.outputs["Generated" if False else "Object"],
              tex.inputs["Vector"])
    return tex.outputs["Fac"]


def _ramp(nodes, links, fac, lo, hi):
    node = nodes.new("ShaderNodeMapRange")
    node.clamp = True
    links.new(fac, node.inputs["Value"])
    node.inputs["From Min"].default_value = lo
    node.inputs["From Max"].default_value = hi
    return node.outputs["Result"]


def _edge_mask(nodes, links, radius=0.012):
    """~1 on convex edges, 0 on flat faces (Cycles bevel normal trick)."""
    bevel = nodes.new("ShaderNodeBevel")
    bevel.samples = 6
    bevel.inputs["Radius"].default_value = radius
    geo = nodes.new("ShaderNodeNewGeometry")
    dot = nodes.new("ShaderNodeVectorMath")
    dot.operation = "DOT_PRODUCT"
    links.new(bevel.outputs["Normal"], dot.inputs[0])
    links.new(geo.outputs["Normal"], dot.inputs[1])
    return _ramp(nodes, links, _math(nodes, links, "SUBTRACT", 1.0,
                                     dot.outputs["Value"]), 0.004, 0.06)


def _ao_mask(nodes, links, distance=0.15):
    """~1 in crevices and corners, 0 in the open."""
    ao = nodes.new("ShaderNodeAmbientOcclusion")
    ao.samples = 8
    ao.inputs["Distance"].default_value = distance
    return _math(nodes, links, "SUBTRACT", 1.0, ao.outputs["AO"])


def weathered(name, color, metallic=0.7, roughness=0.5, grime=0.6, wear=0.5,
              rust=0.25, scale=5.0, worn_color=None, rust_color=None,
              variation=0.12, grime_color=(0.035, 0.03, 0.025)):
    """General purpose weathered surface (metal or paint).

    worn_color is what shows through on worn edges: bright steel for bare
    metal, darker steel for paint.
    """
    mat = bpy.data.materials.new(name)
    nodes, links = _nodes(mat)
    bsdf = nodes["Principled BSDF"]
    base = color
    worn = worn_color or tuple(min(1.0, c * 1.7 + 0.08) for c in color)
    rust_c = rust_color or (0.27, 0.12, 0.05)

    # Per-object and large scale tint variation so panels don't look cloned.
    info = nodes.new("ShaderNodeObjectInfo")
    big = _noise(nodes, links, scale * 0.35, detail=3.0)
    var = _math(nodes, links, "ADD", info.outputs["Random"], big)
    var = _ramp(nodes, links, var, 0.4, 1.6)
    col = _mix(nodes, links, tuple(c * (1 - variation) for c in base),
               tuple(min(1, c * (1 + variation)) for c in base), var)

    # Fine mottling.
    fine = _noise(nodes, links, scale * 6.0, detail=8.0, w_offset=3.0)
    col = _mix(nodes, links, col, tuple(c * 0.6 for c in base),
               _ramp(nodes, links, fine, 0.42, 0.72))
    speck = _noise(nodes, links, scale * 40.0, detail=2.0, w_offset=9.0)
    col = _mix(nodes, links, col, tuple(min(1, c * 1.3) for c in base),
               _math(nodes, links, "MULTIPLY",
                     _ramp(nodes, links, speck, 0.55, 0.75), 0.5))

    # Rust patches.
    rust_amt = None
    if rust > 0:
        rn = _noise(nodes, links, scale * 1.6, detail=10.0, roughness=0.7,
                    w_offset=7.0)
        rust_amt = _math(nodes, links, "MULTIPLY",
                         _ramp(nodes, links, rn, 0.56, 0.72), rust)
        col = _mix(nodes, links, col, rust_c, rust_amt)

    # Worn bright edges, broken up by noise.
    edge = None
    if wear > 0:
        en = _noise(nodes, links, scale * 4.0, detail=4.0, w_offset=11.0)
        edge = _math(nodes, links, "MULTIPLY", _edge_mask(nodes, links),
                     _ramp(nodes, links, en, 0.3, 0.6))
        edge = _math(nodes, links, "MULTIPLY", edge, wear, clamp=True)
        col = _mix(nodes, links, col, worn, edge)

    # Grime in crevices.
    if grime > 0:
        gm = _math(nodes, links, "MULTIPLY", _ao_mask(nodes, links), grime * 1.6,
                   clamp=True)
        col = _mix(nodes, links, col, grime_color, gm)

    links.new(col, bsdf.inputs["Base Color"])

    rough = nodes.new("ShaderNodeMapRange")
    rough.inputs["To Min"].default_value = roughness
    rough.inputs["To Max"].default_value = min(1.0, roughness + 0.35)
    links.new(rust_amt if rust_amt is not None else fine, rough.inputs["Value"])
    if rust_amt is None:
        rough.inputs["To Max"].default_value = roughness + 0.12
    links.new(rough.outputs["Result"], bsdf.inputs["Roughness"])

    if edge is not None and metallic < 0.5:
        # Paint: worn edges reveal metal.
        metal = nodes.new("ShaderNodeMapRange")
        links.new(edge, metal.inputs["Value"])
        metal.inputs["To Min"].default_value = metallic
        metal.inputs["To Max"].default_value = 0.85
        links.new(metal.outputs["Result"], bsdf.inputs["Metallic"])
    elif rust_amt is not None:
        metal = nodes.new("ShaderNodeMapRange")
        links.new(rust_amt, metal.inputs["Value"])
        metal.inputs["To Min"].default_value = metallic
        metal.inputs["To Max"].default_value = 0.05
        links.new(metal.outputs["Result"], bsdf.inputs["Metallic"])
    else:
        bsdf.inputs["Metallic"].default_value = metallic
    return mat


def wood(name, color=(0.30, 0.15, 0.065), grime=0.6, wear=0.35):
    """Weathered timber: grain along the plank's local Z, per-plank tint."""
    mat = bpy.data.materials.new(name)
    nodes, links = _nodes(mat)
    bsdf = nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 0.78
    info = nodes.new("ShaderNodeObjectInfo")
    coord = nodes.new("ShaderNodeTexCoord")
    mapping = nodes.new("ShaderNodeMapping")
    mapping.inputs["Scale"].default_value = (7.0, 7.0, 1.2)
    links.new(coord.outputs["Object"], mapping.inputs["Vector"])
    wave = nodes.new("ShaderNodeTexWave")
    wave.wave_type = "RINGS"
    wave.inputs["Scale"].default_value = 1.0
    wave.inputs["Distortion"].default_value = 6.0
    wave.inputs["Detail"].default_value = 3.0
    links.new(mapping.outputs["Vector"], wave.inputs["Vector"])
    dark = tuple(c * 0.55 for c in color)
    light = tuple(min(1, c * 1.25) for c in color)
    col = _mix(nodes, links, dark, color,
               _ramp(nodes, links, wave.outputs["Fac"], 0.1, 0.9))
    # per-plank tint
    tint = _mix(nodes, links, (0.78, 0.74, 0.7), (1.15, 1.08, 1.0),
                info.outputs["Random"])
    mult = nodes.new("ShaderNodeMix")
    mult.data_type = "RGBA"
    mult.blend_type = "MULTIPLY"
    mult.inputs["Factor"].default_value = 1.0
    links.new(col, mult.inputs["A"])
    links.new(tint, mult.inputs["B"])
    col = mult.outputs["Result"]
    fine = _noise(nodes, links, 30.0, detail=6.0, w_offset=5.0)
    col = _mix(nodes, links, col, tuple(c * 0.6 for c in color),
               _ramp(nodes, links, fine, 0.5, 0.75))
    if wear:
        col = _mix(nodes, links, col, light,
                   _math(nodes, links, "MULTIPLY", _edge_mask(nodes, links),
                         wear, clamp=True))
    if grime:
        col = _mix(nodes, links, col, (0.03, 0.02, 0.012),
                   _math(nodes, links, "MULTIPLY", _ao_mask(nodes, links),
                         grime * 1.6, clamp=True))
    links.new(col, bsdf.inputs["Base Color"])
    return mat


def emissive(name, color, strength, base=None):
    mat = bpy.data.materials.new(name)
    nodes, _ = _nodes(mat)
    bsdf = nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*(base or color), 1.0)
    bsdf.inputs["Emission Color"].default_value = (*color, 1.0)
    bsdf.inputs["Emission Strength"].default_value = strength
    bsdf.inputs["Roughness"].default_value = 0.4
    return mat


def glass(name, tint=(0.6, 0.75, 0.7), roughness=0.05, alpha=0.45):
    """Grimy window glass: dark reflective surface you can half see through."""
    mat = bpy.data.materials.new(name)
    nodes, links = _nodes(mat)
    bsdf = nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*[c * 0.08 for c in tint], 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Specular IOR Level"].default_value = 0.9
    dirt = _noise(nodes, links, 18.0, detail=6.0)
    a = _ramp(nodes, links, dirt, 0.3, 0.75)
    am = nodes.new("ShaderNodeMapRange")
    links.new(a, am.inputs["Value"])
    am.inputs["To Min"].default_value = alpha
    am.inputs["To Max"].default_value = min(1.0, alpha + 0.35)
    links.new(am.outputs["Result"], bsdf.inputs["Alpha"])
    return mat


def hazard(name="hazard", scale=7.0, yellow=(0.62, 0.42, 0.04)):
    """Worn black/yellow hazard stripes."""
    mat = bpy.data.materials.new(name)
    nodes, links = _nodes(mat)
    bsdf = nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 0.6
    coord = nodes.new("ShaderNodeTexCoord")
    wave = nodes.new("ShaderNodeTexWave")
    wave.wave_type = "BANDS"
    wave.bands_direction = "DIAGONAL"
    wave.inputs["Scale"].default_value = scale
    links.new(coord.outputs["Object"], wave.inputs["Vector"])
    ramp = nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.interpolation = "CONSTANT"
    ramp.color_ramp.elements[0].color = (0.03, 0.03, 0.03, 1)
    ramp.color_ramp.elements[1].position = 0.5
    ramp.color_ramp.elements[1].color = (*yellow, 1)
    links.new(wave.outputs["Fac"], ramp.inputs["Fac"])
    col = ramp.outputs["Color"]
    col = _mix(nodes, links, col, (0.28, 0.27, 0.25),
               _math(nodes, links, "MULTIPLY", _edge_mask(nodes, links), 0.7,
                     clamp=True))
    col = _mix(nodes, links, col, (0.03, 0.03, 0.025),
               _math(nodes, links, "MULTIPLY", _ao_mask(nodes, links), 0.9,
                     clamp=True))
    links.new(col, bsdf.inputs["Base Color"])
    return mat


def image_decal(name, image_path, base=(0.3, 0.3, 0.3), roughness=0.6,
                emission=0.0):
    """Material from a picture, mapped by UV (used for banners and signs)."""
    mat = bpy.data.materials.new(name)
    nodes, links = _nodes(mat)
    bsdf = nodes["Principled BSDF"]
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(image_path)
    tex.interpolation = "Cubic"
    links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = roughness
    if emission:
        links.new(tex.outputs["Color"], bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = emission
    return mat


def palette():
    """The shared Factorio-style material set."""
    return {
        # Bare steel, grimy and a little rusty: the backbone of everything.
        "steel": weathered("steel", (0.23, 0.21, 0.18), metallic=0.75,
                           roughness=0.5, rust=0.3),
        "steel_dark": weathered("steel_dark", (0.16, 0.15, 0.135),
                                metallic=0.75, roughness=0.5, rust=0.15),
        "iron": weathered("iron", (0.25, 0.22, 0.19), metallic=0.7,
                          roughness=0.55, rust=0.45),
        "frame": weathered("frame", (0.11, 0.105, 0.1), metallic=0.8,
                           roughness=0.45, rust=0.1, wear=0.7),
        "rivet": weathered("rivet", (0.42, 0.4, 0.37), metallic=0.9,
                           roughness=0.35, rust=0.0, grime=0.2, wear=0.0),
        "concrete": weathered("concrete", (0.17, 0.165, 0.155), metallic=0.0,
                              roughness=0.85, rust=0.0, wear=0.35,
                              worn_color=(0.27, 0.26, 0.24)),
        "brass": weathered("brass", (0.3, 0.21, 0.09), metallic=0.85,
                           roughness=0.4, rust=0.0, wear=0.4),
        "copper": weathered("copper", (0.45, 0.22, 0.12), metallic=0.85,
                            roughness=0.4, rust=0.15,
                            rust_color=(0.16, 0.25, 0.2)),
        "rubber": weathered("rubber", (0.05, 0.05, 0.05), metallic=0.0,
                            roughness=0.75, rust=0.0, wear=0.15),
        # Paints wear through to dark steel.
        "yellow": weathered("paint_yellow", (0.6, 0.4, 0.05), metallic=0.1,
                            roughness=0.5, rust=0.15,
                            worn_color=(0.2, 0.19, 0.18), wear=0.8),
        "red": weathered("paint_red", (0.38, 0.06, 0.04), metallic=0.1,
                         roughness=0.55, rust=0.1,
                         worn_color=(0.2, 0.19, 0.18), wear=0.7),
        "green": weathered("paint_green", (0.14, 0.17, 0.08), metallic=0.1,
                           roughness=0.6, rust=0.15,
                           worn_color=(0.2, 0.19, 0.18), wear=0.7),
        "blue": weathered("paint_blue", (0.06, 0.12, 0.25), metallic=0.15,
                          roughness=0.5, rust=0.15,
                          worn_color=(0.2, 0.19, 0.18), wear=0.7),
        "hazard": hazard(),
        "lamp": emissive("lamp", (1.0, 0.5, 0.12), 6.0),
        "lamp_soft": emissive("lamp_soft", (1.0, 0.55, 0.18), 3.0,
                              base=(0.5, 0.35, 0.2)),
        "window": emissive("window", (1.0, 0.45, 0.12), 0.7,
                           base=(0.25, 0.16, 0.08)),
        "interior": emissive("interior", (1.0, 0.5, 0.15), 0.35,
                             base=(0.12, 0.08, 0.05)),
        "glass": glass("glass", (0.55, 0.62, 0.62), roughness=0.08),
        "black": emissive("black", (0, 0, 0), 0.0, base=(0.015, 0.015, 0.015)),
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
    bpy.ops.mesh.primitive_cube_add(size=1, location=location,
                                    rotation=rotation)
    obj = bpy.context.active_object
    obj.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel:
        mod = obj.modifiers.new("bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 2
        mod.limit_method = "ANGLE"
        shade_smooth(obj, 50)
    return assign(obj, mat)


def cylinder(radius, depth, location, mat, vertices=48, rotation=(0, 0, 0),
             smooth=True, bevel=0.0):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius,
                                        depth=depth, location=location,
                                        rotation=rotation)
    obj = bpy.context.active_object
    if bevel:
        mod = obj.modifiers.new("bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 2
        mod.limit_method = "ANGLE"
    if smooth:
        shade_smooth(obj)
    return assign(obj, mat)


def sphere(radius, location, mat, segments=12):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=radius, location=location,
                                         segments=segments,
                                         ring_count=max(4, segments // 2))
    obj = bpy.context.active_object
    shade_smooth(obj, 80)
    return assign(obj, mat)


def torus(major, minor, location, mat, rotation=(0, 0, 0), major_seg=48,
          minor_seg=10):
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor,
                                     location=location, rotation=rotation,
                                     major_segments=major_seg,
                                     minor_segments=minor_seg)
    obj = bpy.context.active_object
    shade_smooth(obj, 80)
    return assign(obj, mat)


def board(sections, mat, bevel=0.005, name="board"):
    """A single plank lofted through a list of cross-sections.

    Each section is four world-space corners (outer-left, outer-right,
    inner-right, inner-left). The plank's local Z axis runs from the first
    section to the last, which is the direction wood() lays its grain, so
    every board gets grain along its length and its own random tint.
    """
    secs = [[Vector(c) for c in sec] for sec in sections]
    start = sum(secs[0], Vector()) / 4
    end = sum(secs[-1], Vector()) / 4
    zax = (end - start).normalized()
    across = (secs[0][1] - secs[0][0])
    xax = (across - zax * across.dot(zax)).normalized()
    yax = zax.cross(xax)
    centre = sum((sum(sec, Vector()) / 4 for sec in secs), Vector()) / len(secs)
    frame = Matrix((xax, yax, zax)).transposed().to_4x4()
    frame.translation = centre
    inv = frame.inverted()
    bm = bmesh.new()
    rings = [[bm.verts.new(inv @ c) for c in sec] for sec in secs]
    for a, b in zip(rings, rings[1:]):
        for i in range(4):
            j = (i + 1) % 4
            bm.faces.new((a[i], a[j], b[j], b[i]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    obj.matrix_world = frame
    bpy.context.collection.objects.link(obj)
    if bevel:
        mod = obj.modifiers.new("bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 1
        mod.limit_method = "ANGLE"
    shade_smooth(obj, 30)
    return assign(obj, mat)


def arc_board(radius, thickness, z0, height, a0, a1, mat, steps=6, rng=None,
              warp=0.0):
    """A horizontal plank bent around a drum, from angle a0 to a1 (degrees).

    rng adds a little bow, cup and thickness variation so boards don't line
    up perfectly.
    """
    secs = []
    t = thickness
    dz0 = dz1 = dr = 0.0
    if rng is not None:
        dz0, dz1 = rng.uniform(-warp, warp), rng.uniform(-warp, warp)
        dr = rng.uniform(-0.004, 0.006)
        t = thickness * rng.uniform(0.8, 1.15)
    for i in range(steps + 1):
        f = i / steps
        a = a0 + (a1 - a0) * f
        bow = dr * math.sin(math.pi * f)
        zb = z0 + dz0 * (1 - f) + dz1 * f
        ro, ri = radius + t + bow, radius + bow
        secs.append([polar(ro, a, zb + height), polar(ro, a, zb),
                     polar(ri, a, zb), polar(ri, a, zb + height)])
    return board(secs, mat)


def lathe(profile, mat, segments=64, location=(0, 0, 0), smooth_angle=35,
          cap_top=True, cap_bottom=True, name="lathe"):
    """Surface of revolution from a list of (radius, z) points, bottom up."""
    bm = bmesh.new()
    rings = []
    for r, z in profile:
        rings.append([bm.verts.new((r * math.cos(2 * math.pi * i / segments),
                                    r * math.sin(2 * math.pi * i / segments),
                                    z)) for i in range(segments)])
    for a, b in zip(rings, rings[1:]):
        for i in range(segments):
            j = (i + 1) % segments
            bm.faces.new((a[i], a[j], b[j], b[i]))
    if cap_bottom and profile[0][0] > 1e-4:
        bm.faces.new(list(reversed(rings[0])))
    if cap_top and profile[-1][0] > 1e-4:
        bm.faces.new(rings[-1])
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    obj.location = location
    bpy.context.collection.objects.link(obj)
    shade_smooth(obj, smooth_angle)
    return assign(obj, mat)


def polar(radius, angle_deg, z):
    a = math.radians(angle_deg)
    return (radius * math.cos(a), radius * math.sin(a), z)


def facing(angle_deg):
    """Rotation that turns an object's +X axis outwards at angle_deg."""
    return (0, 0, math.radians(angle_deg))


def tube_between(p0, p1, radius, mat, vertices=10):
    p0, p1 = Vector(p0), Vector(p1)
    direction = p1 - p0
    obj = cylinder(radius, direction.length, (p0 + p1) / 2, mat,
                   vertices=vertices)
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = direction.to_track_quat("Z", "Y")
    return obj


def pipe_path(points, radius, mat, joints=True, joint_mat=None):
    """A pipe run through points, with flanged joints at the bends."""
    pts = [Vector(p) for p in points]
    for a, b in zip(pts, pts[1:]):
        tube_between(a, b, radius, mat, vertices=14)
    if joints:
        for p in pts:
            sphere(radius * 1.0, p, mat, segments=14)
        for a, b in zip(pts, pts[1:]):
            d = (b - a)
            if d.length > radius * 6:
                for t in (radius * 2.5 / d.length, 1 - radius * 2.5 / d.length):
                    c = a.lerp(b, t)
                    f = cylinder(radius * 1.35, radius * 0.7, c,
                                 joint_mat or mat, vertices=14)
                    f.rotation_mode = "QUATERNION"
                    f.rotation_quaternion = d.to_track_quat("Z", "Y")


def beam_between(p0, p1, width, height, mat, bevel=0.012):
    """Box running from p0 to p1, kept level across its width."""
    p0, p1 = Vector(p0), Vector(p1)
    x = (p1 - p0).normalized()
    y = Vector((0, 0, 1)).cross(x).normalized()
    z = x.cross(y)
    obj = box(((p1 - p0).length + 0.04, width, height), (0, 0, 0), mat,
              bevel=bevel)
    rot = Matrix((x, y, z)).transposed().to_4x4()
    obj.matrix_world = Matrix.Translation((p0 + p1) / 2) @ rot
    return obj


def sagging_cable(p0, p1, sag, mat, steps=12, radius=0.016):
    p0, p1 = Vector(p0), Vector(p1)
    points = []
    for i in range(steps + 1):
        t = i / steps
        p = p0.lerp(p1, t)
        p.z -= sag * 4 * t * (1 - t)
        points.append(p)
    for a, b in zip(points, points[1:]):
        tube_between(a, b, radius, mat, vertices=6)


def ring_of_rivets(radius, z, count, mat, size=0.02, skip=None):
    for i in range(count):
        ang = 360 * i / count
        if skip and not skip(ang):
            continue
        sphere(size, polar(radius, ang, z), mat, segments=8)


def rivet_row(p0, p1, count, mat, size=0.018):
    p0, p1 = Vector(p0), Vector(p1)
    for i in range(count):
        t = (i + 0.5) / count
        sphere(size, p0.lerp(p1, t), mat, segments=8)


def is_clear(angle, gaps):
    for centre, half_width in gaps:
        diff = (angle - centre + 180) % 360 - 180
        if abs(diff) < half_width:
            return False
    return True


def crate(location, size, mat, band_mat, rotation=0.0):
    """Ammo/supply crate with banding."""
    sx, sy, sz = size
    loc = Vector(location) + Vector((0, 0, sz / 2))
    rot = (0, 0, math.radians(rotation))
    box((sx, sy, sz), loc, mat, rotation=rot, bevel=0.015)
    for k in (-0.3, 0.3):
        off = Matrix.Rotation(math.radians(rotation), 3, "Z") @ Vector((sx * k, 0, 0))
        box((0.025, sy + 0.012, sz + 0.012), loc + off, band_mat, rotation=rot,
            bevel=0.004)


def barrel(location, radius, height, mat, band_mat):
    loc = Vector(location)
    cylinder(radius, height, loc + Vector((0, 0, height / 2)), mat,
             vertices=24, bevel=0.01)
    for zc in (0.2, 0.8):
        cylinder(radius * 1.04, 0.02, loc + Vector((0, 0, height * zc)),
                 band_mat, vertices=24)
    cylinder(radius * 0.25, 0.02, loc + Vector((radius * 0.4, 0, height + 0.005)),
             band_mat, vertices=10)


# --------------------------------------------------------- camera & lights

def look_rotation(direction):
    return Vector(direction).to_track_quat("-Z", "Y").to_euler()


def setup_camera(scene, tiles_w, tiles_h, shift):
    """Camera matching a Factorio sprite of tiles_w x tiles_h tiles (after
    scale) drawn with the given shift (tiles, +y is down on screen)."""
    cam_data = bpy.data.cameras.new("camera")
    cam_data.type = "ORTHO"
    cam_data.sensor_fit = "HORIZONTAL"
    cam_data.ortho_scale = tiles_w
    cam_data.clip_start = 0.1
    cam_data.clip_end = 100
    cam = bpy.data.objects.new("camera", cam_data)
    scene.collection.objects.link(cam)
    pitch = PITCH
    # Point on the ground under the frame centre: shift.y tiles up the screen
    # is shift.y / cos(pitch) tiles north on the foreshortened ground.
    target = Vector((shift[0], -shift[1] / math.cos(pitch), 0.0))
    view = Vector((0, math.sin(pitch), -math.cos(pitch)))
    cam.location = target - view * 30
    cam.rotation_euler = look_rotation(view)
    scene.camera = cam
    return cam


def setup_lights(scene, key=4.2, fill=0.55):
    sun = bpy.data.lights.new("key", "SUN")
    sun.energy = key
    sun.color = (1.0, 0.93, 0.82)
    sun.angle = math.radians(6)
    sun_obj = bpy.data.objects.new("key", sun)
    sun_obj.rotation_euler = look_rotation(-SUN_FROM)
    scene.collection.objects.link(sun_obj)

    # Weak bounce from the lower right so the shaded side keeps some form.
    rim = bpy.data.lights.new("bounce", "SUN")
    rim.energy = key * 0.12
    rim.color = (0.75, 0.8, 0.9)
    rim_obj = bpy.data.objects.new("bounce", rim)
    rim_obj.rotation_euler = look_rotation(-Vector((0.8, -0.9, 0.35)))
    scene.collection.objects.link(rim_obj)

    world = bpy.data.worlds.new("world")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0.42, 0.45, 0.5, 1)
    bg.inputs["Strength"].default_value = fill
    scene.world = world


def add_shadow_catcher(size=12):
    bpy.ops.mesh.primitive_plane_add(size=size, location=(0, 0, 0))
    plane = bpy.context.active_object
    plane.name = "shadow_catcher"
    plane.is_shadow_catcher = True
    mat = bpy.data.materials.new("catcher")
    mat.use_nodes = True
    mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (
        0.5, 0.5, 0.5, 1)
    assign(plane, mat)
    return plane


def scale_model(factor, origin=(0, 0, 0)):
    """Scale everything built so far (except camera/lights) about origin."""
    if factor == 1:
        return
    o = Vector(origin)
    for obj in list(bpy.data.objects):
        if obj.type != "MESH" or obj.name == "shadow_catcher":
            continue
        obj.matrix_world = (Matrix.Translation(o)
                            @ Matrix.Scale(factor, 4)
                            @ Matrix.Translation(-o)
                            @ obj.matrix_world)


# ------------------------------------------------------------------- output

def _render(scene, path, width_px, height_px):
    scene.render.resolution_x = width_px
    scene.render.resolution_y = height_px
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def _unstretch(path, out_w, out_h):
    """Undo the camera pitch: stretch the raw render back to square tiles."""
    from PIL import Image
    raw = Image.open(path)
    if raw.mode not in ("RGBA",):
        raw = raw.convert("RGBA")
    if raw.size == (out_w, out_h):
        return raw
    return _resize(raw, (out_w, out_h))


def _resize(img, size):
    """Downscale with premultiplied alpha.

    Resizing straight alpha lets the black of fully transparent pixels bleed
    into edges, which gives a dark, jagged fringe in game. Premultiplying
    first keeps edges clean, the way vanilla sprites are filtered.
    """
    from PIL import Image
    return img.convert("RGBa").resize(size, Image.LANCZOS).convert("RGBA")


def _icon_crop(img, margin=0.02):
    from PIL import Image
    alpha = img.getchannel("A").point(lambda a: 255 if a > 24 else 0)
    left, top, right, bottom = alpha.getbbox()
    side = max(right - left, bottom - top) * (1 + 2 * margin)
    cx, cy = (left + right) / 2, (top + bottom) / 2
    box_ = (int(cx - side / 2), int(cy - side / 2),
            int(cx + side / 2), int(cy + side / 2))
    canvas = Image.new("RGBA", (int(side) + 2, int(side) + 2), (0, 0, 0, 0))
    canvas.alpha_composite(img, (-box_[0], -box_[1]))
    return canvas


def _icon_from(img, size, mipmaps=1):
    """Square icon cropped to the model.

    With mipmaps > 1 the file holds the vanilla mipmap strip: size, size/2,
    size/4 ... side by side from the top-left with no padding (a 64 px icon
    with 4 levels is 120x64, like base/graphics/icons). Factorio infers the
    level count from the file, and each level is filtered from the full
    render rather than from the level above, so small icons stay crisp.
    """
    from PIL import Image
    crop = _icon_crop(img)
    levels = [_resize(crop, (size >> i, size >> i)) for i in range(mipmaps)]
    if mipmaps == 1:
        return levels[0]
    width = sum(l.width for l in levels)
    strip = Image.new("RGBA", (width, size), (0, 0, 0, 0))
    x = 0
    for l in levels:
        strip.paste(l, (x, 0))
        x += l.width
    return strip


def render_entity(scene, name, entity_path=None, icon_paths=(), size_px=256,
                  scale=0.5, shift=(0.0, -0.3), keep_blend=True,
                  catcher=None, icon_only=False, icon_mipmaps=4):
    """Render the sprite (shadow baked in) and any icons.

    size_px/scale/shift are the values in the prototype's sprite definition,
    so the output lines up with the entity's footprint in game.
    icon_paths is a list of (path, size) tuples; each is written with
    icon_mipmaps levels (vanilla item icons use 64 px with 4).
    """
    tiles = size_px * scale / 32.0
    setup_camera(scene, tiles, tiles, shift)
    if catcher is None:
        catcher = add_shadow_catcher()
    if keep_blend:
        bpy.ops.wm.save_as_mainfile(filepath=os.path.join(HERE, name + ".blend"),
                                    compress=True)
    if "--no-render" in sys.argv:
        return
    tmp = os.path.join(HERE, "_raw_" + name + ".png")
    w = size_px * SUPERSAMPLE
    h = w
    # Pass 1: the model alone (also the source of the icons).
    catcher.hide_render = True
    _render(scene, tmp, w, h)
    model = _unstretch(tmp, w, w)
    for path, size in icon_paths:
        _icon_from(model, size, icon_mipmaps).save(path, optimize=True)
        print("wrote", path)
    catcher.hide_render = False
    if entity_path and not icon_only:
        # Pass 2: with the ground shadow. Shadow that would be cut off by the
        # frame edge is faded out so it never ends in a hard line.
        _render(scene, tmp, w, h)
        full = _unstretch(tmp, w, w)
        img = _fade_shadow_edges(full, model, int(w * 0.05))
        _resize(img, (size_px, size_px)).save(entity_path, optimize=True)
        print("wrote", entity_path)
    if os.path.exists(tmp):
        os.remove(tmp)


def _fade_shadow_edges(full, model, border):
    import numpy as np
    from PIL import Image
    f = np.asarray(full).astype(np.float32) / 255.0
    m = np.asarray(model).astype(np.float32) / 255.0
    hh, ww = f.shape[:2]
    ys = np.minimum(np.arange(hh), hh - 1 - np.arange(hh)) / border
    xs = np.minimum(np.arange(ww), ww - 1 - np.arange(ww)) / border
    fade = np.clip(np.minimum(ys[:, None], xs[None, :]), 0, 1)
    fade = fade * fade * (3 - 2 * fade)
    shadow_a = f[..., 3] * fade
    a = np.maximum(m[..., 3], shadow_a)
    # Where the model is see-through (glass, antialiased edges) keep the
    # composited colour from the full pass; pure shadow is black.
    out = np.zeros_like(f)
    out[..., :3] = np.where(m[..., 3:4] > 0.0, f[..., :3], 0.0)
    out[..., 3] = a
    return Image.fromarray((np.clip(out, 0, 1) * 255 + 0.5).astype(np.uint8),
                           "RGBA")


def entity_path(name):
    return os.path.join(GRAPHICS, "entity", name + ".png")


def icon_path(name):
    return os.path.join(GRAPHICS, "icons", name + ".png")
