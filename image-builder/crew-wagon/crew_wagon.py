"""Blender model and sprite renderer for the not-alone Crew wagon.

Run with Blender's Python (`pip install bpy` works headless):

    python3 crew_wagon.py --mode color --out renders/color --frames 0-127
    python3 crew_wagon.py --mode mask --out renders/mask --frames 0-127
    python3 crew_wagon.py --mode shadow --out renders/shadow --frames 0-127
    python3 crew_wagon.py --mode icon --out renders/icon

Then `pack_sprites.py` crops the frames and lays them out as sheets in the
vanilla rolling stock format (128 directions over half a turn,
back_equals_front, 4 columns by 8 rows per file).

Units are tiles. The wagon's long axis is +Y (north) at frame 0 and each
frame turns it clockwise by 180/128 degrees, matching vanilla.
"""

import argparse
import math
import sys

import bpy
import bmesh
from mathutils import Matrix, Vector

DIRECTIONS = 128
PX_PER_TILE = 64
FRAME_PX = 512
CAMERA_TILT = math.radians(45)   # camera pitch away from straight down
GROUND_STRETCH = 1.12            # keeps track length close to vanilla on screen

BODY_LEN = 5.5
BODY_HALF_W = 0.95
BODY_Z0 = 0.8
BODY_Z1 = 1.72
ROOF_Z = 1.95
BAYS = 5


def parse_args():
	argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
	p = argparse.ArgumentParser()
	p.add_argument("--mode", choices=["color", "mask", "shadow", "icon", "preview"], default="color")
	p.add_argument("--out", default="renders")
	p.add_argument("--frames", default="0-127")
	p.add_argument("--samples", type=int, default=48)
	p.add_argument("--blend", default="")
	return p.parse_args(argv)


def frame_list(spec):
	frames = []
	for part in spec.split(","):
		if "-" in part:
			a, b = part.split("-")
			frames.extend(range(int(a), int(b) + 1))
		else:
			frames.append(int(part))
	return frames


# ---------------------------------------------------------------- materials

def node_material(name, base, metallic=0.6, rough=0.5, emission=None, strength=0.0,
		grime=0.45, bump=0.25, scale=7.0, ribs=0.0):
	"""Grimy painted metal: noise drives dirt and roughness, optional ribbing."""
	mat = bpy.data.materials.new(name)
	mat.use_nodes = True
	nt = mat.node_tree
	nodes, links = nt.nodes, nt.links
	bsdf = nodes["Principled BSDF"]
	bsdf.inputs["Metallic"].default_value = metallic

	coord = nodes.new("ShaderNodeTexCoord")
	noise = nodes.new("ShaderNodeTexNoise")
	noise.inputs["Scale"].default_value = scale
	noise.inputs["Distortion"].default_value = 0.6
	noise.inputs["Detail"].default_value = 10
	noise.inputs["Roughness"].default_value = 0.65
	links.new(coord.outputs["Object"], noise.inputs["Vector"])
	fine = nodes.new("ShaderNodeTexNoise")
	fine.inputs["Scale"].default_value = scale * 9
	fine.inputs["Detail"].default_value = 6
	links.new(coord.outputs["Object"], fine.inputs["Vector"])

	ramp = nodes.new("ShaderNodeValToRGB")
	ramp.color_ramp.elements[0].position = 0.3
	ramp.color_ramp.elements[1].position = 0.7
	links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
	dark = (base[0] * (1 - grime) * 0.95, base[1] * (1 - grime) * 0.85, base[2] * (1 - grime) * 0.75, 1)
	mix = nodes.new("ShaderNodeMix")
	mix.data_type = "RGBA"
	mix.inputs[6].default_value = dark
	mix.inputs[7].default_value = tuple(base[:3]) + (1,)
	links.new(ramp.outputs["Color"], mix.inputs["Factor"])
	speck = nodes.new("ShaderNodeMix")
	speck.data_type = "RGBA"
	speck.blend_type = "MULTIPLY"
	speck.inputs["Factor"].default_value = 1.0
	links.new(mix.outputs[2], speck.inputs[6])
	grit = nodes.new("ShaderNodeValToRGB")
	grit.color_ramp.elements[0].position = 0.25
	grit.color_ramp.elements[0].color = (0.45, 0.42, 0.38, 1)
	grit.color_ramp.elements[1].position = 0.75
	grit.color_ramp.elements[1].color = (1.25, 1.22, 1.18, 1)
	links.new(fine.outputs["Fac"], grit.inputs["Fac"])
	links.new(grit.outputs["Color"], speck.inputs[7])
	geo = nodes.new("ShaderNodeNewGeometry")
	edge = nodes.new("ShaderNodeValToRGB")
	edge.color_ramp.elements[0].position = 0.55
	edge.color_ramp.elements[1].position = 0.7
	edge.color_ramp.elements[1].color = (0.6, 0.6, 0.6, 1)
	links.new(geo.outputs["Pointiness"], edge.inputs["Fac"])
	wear = nodes.new("ShaderNodeMix")
	wear.data_type = "RGBA"
	wear.blend_type = "SCREEN"
	links.new(edge.outputs["Color"], wear.inputs["Factor"])
	links.new(speck.outputs[2], wear.inputs[6])
	wear.inputs[7].default_value = (0.5, 0.47, 0.42, 1)
	color = wear.outputs[2]

	def multiply(color, factor_socket=None, value=None):
		mul = nodes.new("ShaderNodeMix")
		mul.data_type = "RGBA"
		mul.blend_type = "MULTIPLY"
		mul.inputs["Factor"].default_value = 1.0
		links.new(color, mul.inputs[6])
		if factor_socket is not None:
			links.new(factor_socket, mul.inputs[7])
		return mul.outputs[2]

	# vanilla sprites are heavily weathered: soot packed into crevices...
	ao = nodes.new("ShaderNodeAmbientOcclusion")
	ao.inputs["Distance"].default_value = 0.18
	ao.samples = 8
	ao_ramp = nodes.new("ShaderNodeValToRGB")
	ao_ramp.color_ramp.elements[0].position = 0.25
	ao_ramp.color_ramp.elements[0].color = (0.08, 0.07, 0.06, 1)
	ao_ramp.color_ramp.elements[1].position = 0.9
	links.new(ao.outputs["AO"], ao_ramp.inputs["Fac"])
	color = multiply(color, ao_ramp.outputs["Color"])

	# ...dirt running down the sides in streaks...
	stretch = nodes.new("ShaderNodeMapping")
	stretch.inputs["Scale"].default_value = (14, 14, 1.2)
	links.new(coord.outputs["Object"], stretch.inputs["Vector"])
	streak = nodes.new("ShaderNodeTexNoise")
	streak.inputs["Scale"].default_value = 3.0
	streak.inputs["Detail"].default_value = 4
	links.new(stretch.outputs["Vector"], streak.inputs["Vector"])
	streak_ramp = nodes.new("ShaderNodeValToRGB")
	streak_ramp.color_ramp.elements[0].position = 0.4
	streak_ramp.color_ramp.elements[0].color = (0.45, 0.42, 0.38, 1)
	streak_ramp.color_ramp.elements[1].position = 0.65
	links.new(streak.outputs["Fac"], streak_ramp.inputs["Fac"])
	color = multiply(color, streak_ramp.outputs["Color"])

	# ...grime thickest low down, near the track...
	sep = nodes.new("ShaderNodeSeparateXYZ")
	links.new(coord.outputs["Object"], sep.inputs["Vector"])
	low = nodes.new("ShaderNodeValToRGB")
	low.color_ramp.elements[0].position = 0.35
	low.color_ramp.elements[0].color = (0.35, 0.27, 0.2, 1)
	low.color_ramp.elements[1].position = 0.6
	low_map = nodes.new("ShaderNodeMapRange")
	low_map.inputs["From Min"].default_value = 0.4
	low_map.inputs["From Max"].default_value = 2.0
	links.new(sep.outputs["Z"], low_map.inputs["Value"])
	links.new(low_map.outputs["Result"], low.inputs["Fac"])
	color = multiply(color, low.outputs["Color"])

	# ...and pixel-scale grit so surfaces never read as flat colour
	grain = nodes.new("ShaderNodeTexNoise")
	grain.inputs["Scale"].default_value = 28
	grain.inputs["Detail"].default_value = 2
	links.new(coord.outputs["Object"], grain.inputs["Vector"])
	grain_ramp = nodes.new("ShaderNodeValToRGB")
	grain_ramp.color_ramp.elements[0].position = 0.3
	grain_ramp.color_ramp.elements[0].color = (0.55, 0.55, 0.55, 1)
	grain_ramp.color_ramp.elements[1].position = 0.7
	grain_ramp.color_ramp.elements[1].color = (1.3, 1.3, 1.3, 1)
	links.new(grain.outputs["Fac"], grain_ramp.inputs["Fac"])
	color = multiply(color, grain_ramp.outputs["Color"])
	links.new(color, bsdf.inputs["Base Color"])

	rmap = nodes.new("ShaderNodeMapRange")
	rmap.inputs["To Min"].default_value = rough - 0.15
	rmap.inputs["To Max"].default_value = rough + 0.2
	links.new(noise.outputs["Fac"], rmap.inputs["Value"])
	links.new(rmap.outputs["Result"], bsdf.inputs["Roughness"])

	height = fine.outputs["Fac"]
	if ribs > 0:
		wave = nodes.new("ShaderNodeTexWave")
		wave.wave_type = "BANDS"
		wave.bands_direction = "X"
		wave.wave_profile = "TRI"
		wave.inputs["Scale"].default_value = ribs
		links.new(coord.outputs["Object"], wave.inputs["Vector"])
		add = nodes.new("ShaderNodeMath")
		add.operation = "ADD"
		links.new(wave.outputs["Fac"], add.inputs[0])
		links.new(fine.outputs["Fac"], add.inputs[1])
		height = add.outputs[0]
	if bump > 0:
		b = nodes.new("ShaderNodeBump")
		b.inputs["Strength"].default_value = bump
		b.inputs["Distance"].default_value = 0.02
		links.new(height, b.inputs["Height"])
		links.new(b.outputs["Normal"], bsdf.inputs["Normal"])

	if emission:
		bsdf.inputs["Emission Color"].default_value = emission
		bsdf.inputs["Emission Strength"].default_value = strength
	return mat


def make_materials():
	m = {}
	m["body"] = node_material("body", (0.15, 0.14, 0.13), metallic=0.75, rough=0.42, ribs=9, bump=0.6, grime=0.6)
	m["panel"] = node_material("panel", (0.2, 0.19, 0.175), metallic=0.7, rough=0.45, grime=0.55, ribs=11, bump=0.5)
	m["rib"] = node_material("rib", (0.25, 0.24, 0.22), metallic=0.8, rough=0.4, grime=0.45)
	m["chassis"] = node_material("chassis", (0.15, 0.085, 0.045), metallic=0.5, rough=0.65, grime=0.55)
	m["dark"] = node_material("dark", (0.05, 0.048, 0.045), metallic=0.5, rough=0.55, grime=0.2, bump=0.1)
	m["stripe"] = node_material("stripe", (0.11, 0.105, 0.1), metallic=0.3, rough=0.6, grime=0.35, ribs=11, bump=0.45)
	m["glass"] = node_material("glass", (0.04, 0.04, 0.045), metallic=0.0, rough=0.12,
		emission=(0.75, 0.4, 0.15, 1), strength=0.28, grime=0.3, bump=0)
	m["lamp"] = node_material("lamp", (1, 0.9, 0.7), metallic=0, rough=0.3,
		emission=(1.0, 0.85, 0.55, 1), strength=14.0, grime=0, bump=0)
	return m


# ---------------------------------------------------------------- geometry

def link(obj, parent):
	bpy.context.collection.objects.link(obj)
	obj.parent = parent
	return obj


def box(name, size, loc, mat, parent, bevel=0.02):
	mesh = bpy.data.meshes.new(name)
	bm = bmesh.new()
	bmesh.ops.create_cube(bm, size=1.0)
	bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
	bmesh.ops.translate(bm, vec=Vector(loc), verts=bm.verts)
	bm.to_mesh(mesh)
	bm.free()
	obj = link(bpy.data.objects.new(name, mesh), parent)
	obj.data.materials.append(mat)
	if bevel:
		mod = obj.modifiers.new("bevel", "BEVEL")
		mod.width = bevel
		mod.segments = 2
		mod.limit_method = "ANGLE"
	return obj


def cylinder(name, radius, depth, loc, rot, mat, parent, verts=16):
	mesh = bpy.data.meshes.new(name)
	bm = bmesh.new()
	bmesh.ops.create_cone(bm, cap_ends=True, segments=verts, radius1=radius, radius2=radius, depth=depth)
	bm.to_mesh(mesh)
	bm.free()
	obj = link(bpy.data.objects.new(name, mesh), parent)
	obj.location = loc
	obj.rotation_euler = rot
	obj.data.materials.append(mat)
	for f in obj.data.polygons:
		f.use_smooth = True
	return obj


def profile_prism(name, profile, y0, y1, mat, parent, bevel=0.025):
	"""Extrude a closed XZ profile along Y."""
	mesh = bpy.data.meshes.new(name)
	bm = bmesh.new()
	front = [bm.verts.new((x, y0, z)) for x, z in profile]
	back = [bm.verts.new((x, y1, z)) for x, z in profile]
	n = len(profile)
	bm.faces.new(list(reversed(front)))
	bm.faces.new(back)
	for i in range(n):
		j = (i + 1) % n
		bm.faces.new((front[i], front[j], back[j], back[i]))
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	bm.to_mesh(mesh)
	bm.free()
	obj = link(bpy.data.objects.new(name, mesh), parent)
	obj.data.materials.append(mat)
	if bevel:
		mod = obj.modifiers.new("bevel", "BEVEL")
		mod.width = bevel
		mod.segments = 2
		mod.limit_method = "ANGLE"
	return obj


def body_profile(grow=0.0):
	w = BODY_HALF_W + grow
	c = 0.34  # roof chamfer
	t = 0.05  # walls lean in slightly
	return [
		(-(w - t), BODY_Z0 - grow), (w - t, BODY_Z0 - grow),
		(w, BODY_Z1 - 0.25 + grow * 0.3), (w - 0.06, BODY_Z1 + grow * 0.3),
		(w - c, ROOF_Z + grow), (-(w - c), ROOF_Z + grow),
		(-(w - 0.06), BODY_Z1 + grow * 0.3), (-w, BODY_Z1 - 0.25 + grow * 0.3),
	]


def build_wagon(m):
	root = bpy.data.objects.new("crew_wagon", None)
	bpy.context.collection.objects.link(root)
	half = BODY_LEN / 2

	# chassis: rust brown frame like the vanilla wagons, with end beams
	# the engine draws bogies at +-2 tiles, so the frame stays clear of them
	box("frame", (1.3, 2.4, 0.22), (0, 0, 0.7), m["chassis"], root)
	for s in (-1, 1):
		box(f"sill{s}", (0.12, BODY_LEN - 0.3, 0.14), (s * 0.7, 0, 0.74), m["chassis"], root)
		box(f"endbeam{s}", (1.7, 0.22, 0.26), (0, s * (half + 0.3), 0.62), m["chassis"], root)
		# buffers and coupler
		for x in (-0.55, 0.55):
			cylinder(f"buf{s}{x}", 0.07, 0.3, (x, s * (half + 0.55), 0.62), (math.pi / 2, 0, 0), m["dark"], root)
			cylinder(f"bufhead{s}{x}", 0.13, 0.05, (x, s * (half + 0.7), 0.62), (math.pi / 2, 0, 0), m["rib"], root)
		box(f"coupler{s}", (0.18, 0.4, 0.14), (0, s * (half + 0.55), 0.6), m["dark"], root)
		# end platform with hand rails, so the crew has somewhere to stand
		box(f"platform{s}", (1.55, 0.42, 0.06), (0, s * (half + 0.22), 0.77), m["panel"], root, bevel=0.01)
		for x in (-0.72, 0.72):
			cylinder(f"post{s}{x}", 0.025, 0.5, (x, s * (half + 0.4), 1.03), (0, 0, 0), m["rib"], root, verts=8)
			cylinder(f"rail{s}{x}", 0.022, 0.42, (x, s * (half + 0.22), 1.27), (math.pi / 2, 0, 0), m["rib"], root, verts=8)
		cylinder(f"rearrail{s}", 0.022, 1.44, (0, s * (half + 0.4), 1.27), (0, math.pi / 2, 0), m["rib"], root, verts=8)
		# steps down from the platform
		for x in (-0.68, 0.68):
			box(f"step{s}{x}", (0.3, 0.2, 0.04), (x * 1.05, s * (half + 0.22), 0.55), m["dark"], root, bevel=0.005)

	# undercarriage tanks between the bogies
	for y in (-0.7, 0.7):
		cylinder(f"tank{y}", 0.17, 0.9, (0, y, 0.55), (math.pi / 2, 0, 0), m["dark"], root)

	# body shell
	profile_prism("body", body_profile(), -half, half, m["body"], root)
	wall_z = BODY_Z1 - 0.25

	# end walls with a door and a small window
	for s in (-1, 1):
		y = s * (half + 0.07)  # proud of the end rib
		box(f"doorframe{s}", (0.7, 0.03, 1.0), (0, y, BODY_Z0 + 0.52), m["dark"], root, bevel=0.01)
		box(f"door{s}", (0.58, 0.05, 0.92), (0, y, BODY_Z0 + 0.5), m["stripe"], root, bevel=0.012)
		box(f"doorwin{s}", (0.36, 0.06, 0.26), (0, y, BODY_Z0 + 0.78), m["glass"], root, bevel=0.005)
		box(f"doorhandle{s}", (0.06, 0.08, 0.12), (0.21, y, BODY_Z0 + 0.45), m["rib"], root, bevel=0)
		for x in (-0.62, 0.62):
			box(f"endpost{s}{x}", (0.12, 0.06, BODY_Z1 - BODY_Z0), (x, y, (BODY_Z0 + BODY_Z1) / 2), m["rib"], root, bevel=0.012)
		# corner lamps, the vanilla wagons' signature
		for x in (-0.5, 0.5):
			box(f"lamp{s}{x}", (0.18, 0.12, 0.09), (x, s * (half + 0.01), ROOF_Z - 0.02), m["lamp"], root, bevel=0.01)

	# ribs split the body into bays, like the vanilla cargo wagon panels
	bay = BODY_LEN / BAYS
	for i in range(BAYS + 1):
		y = -half + i * bay
		profile_prism(f"rib{i}", body_profile(0.04), y - 0.055, y + 0.055, m["rib"], root, bevel=0.015)
		for side in (-1, 1):
			for z in (BODY_Z0 + 0.12, BODY_Z0 + 0.42, wall_z - 0.05, BODY_Z1 - 0.05):
				cylinder(f"rivet{i}{side}{z}", 0.022, 0.03, (side * (BODY_HALF_W + 0.05), y, z),
					(0, math.pi / 2, 0), m["rib"], root, verts=8)

	# per bay: lit passenger windows, a ribbed lower panel and a tintable stripe
	for i in range(BAYS):
		y = -half + (i + 0.5) * bay
		inner = bay - 0.2
		for s in (-1, 1):
			x = s * (BODY_HALF_W + 0.005)
			box(f"winframe{i}{s}", (0.05, inner - 0.08, 0.42), (x, y, wall_z - 0.12), m["dark"], root, bevel=0.012)
			for k in (-1, 1):
				wy = y + k * (inner / 4 - 0.01)
				# glass set back in the frame, shaded by a lintel and split by a sash bar
				box(f"win{i}{s}{k}", (0.06, inner / 2 - 0.12, 0.3),
					(x + s * 0.004, wy, wall_z - 0.12), m["glass"], root, bevel=0.006)
				box(f"lintel{i}{s}{k}", (0.07, inner / 2 - 0.1, 0.06), (x + s * 0.012, wy, wall_z + 0.01), m["dark"], root, bevel=0.006)
				box(f"sash{i}{s}{k}", (0.065, inner / 2 - 0.12, 0.025), (x + s * 0.01, wy, wall_z - 0.1), m["dark"], root, bevel=0)
			box(f"mullion{i}{s}", (0.065, 0.05, 0.36), (x, y, wall_z - 0.12), m["rib"], root, bevel=0.005)
			box(f"sill{i}{s}", (0.08, inner - 0.04, 0.04), (x, y, wall_z - 0.35), m["rib"], root, bevel=0.008)
			box(f"stripe{i}{s}", (0.05, inner, 0.15), (x - s * 0.012, y, wall_z - 0.45), m["stripe"], root, bevel=0.006)
			low_top = wall_z - 0.53
			box(f"lowpanel{i}{s}", (0.04, inner - 0.04, low_top - BODY_Z0), (x - s * 0.02, y, (low_top + BODY_Z0) / 2), m["stripe"], root, bevel=0.008)
			box(f"lowrib{i}{s}", (0.05, inner, 0.04), (x - s * 0.02, y, BODY_Z0 + 0.03), m["rib"], root, bevel=0.008)

		# roof panel per bay with longitudinal ribs, read from above like vanilla
		top = ROOF_Z
		box(f"roofpanel{i}", (1.12, inner, 0.04), (0, y, top + 0.01), m["stripe"], root, bevel=0.015)
		for r in (-0.45, -0.3, 0.3, 0.45):
			box(f"roofrib{i}{r}", (0.05, inner - 0.08, 0.05), (r, y, top + 0.045), m["rib"], root, bevel=0.01)

	# roof: a central tintable walkway with vents between the bays, hatches at the ends
	box("walkway", (0.42, BODY_LEN - 1.0, 0.07), (0, 0, ROOF_Z + 0.06), m["stripe"], root, bevel=0.015)
	for i in range(1, BAYS):
		y = -half + i * bay
		if i % 2:
			cylinder(f"vent{i}", 0.1, 0.16, (0, y, ROOF_Z + 0.16), (0, 0, 0), m["rib"], root, verts=12)
			cylinder(f"ventcap{i}", 0.15, 0.04, (0, y, ROOF_Z + 0.25), (0, 0, 0), m["dark"], root, verts=12)
		else:
			# a boxy fan housing breaks up the row of domes
			box(f"fan{i}", (0.3, 0.3, 0.1), (0, y, ROOF_Z + 0.14), m["rib"], root, bevel=0.015)
			cylinder(f"fanblade{i}", 0.11, 0.02, (0, y, ROOF_Z + 0.2), (0, 0, 0), m["dark"], root, verts=12)
	# pipes and a tool box along the walkway, offset so the bays differ
	cylinder("roofpipe", 0.035, BODY_LEN * 0.45, (0.3, -0.6, ROOF_Z + 0.06), (math.pi / 2, 0, 0), m["chassis"], root, verts=8)
	box("toolbox", (0.22, 0.42, 0.12), (-0.3, 0.9, ROOF_Z + 0.08), m["chassis"], root, bevel=0.015)
	for s in (-1, 1):
		box(f"hatch{s}", (0.5, 0.36, 0.08), (0, s * (half - 0.32), ROOF_Z + 0.06), m["rib"], root, bevel=0.015)
		box(f"hatchwheel{s}", (0.16, 0.16, 0.03), (0, s * (half - 0.32), ROOF_Z + 0.11), m["dark"], root, bevel=0.01)
	return root


# ---------------------------------------------------------------- scene

def setup_scene(args):
	bpy.ops.wm.read_factory_settings(use_empty=True)
	scene = bpy.context.scene
	scene.render.engine = "CYCLES"
	scene.cycles.device = "CPU"
	scene.cycles.samples = args.samples
	scene.cycles.use_denoising = True
	scene.cycles.max_bounces = 4
	scene.render.film_transparent = True
	scene.render.resolution_x = FRAME_PX
	scene.render.resolution_y = FRAME_PX
	scene.render.resolution_percentage = 100
	scene.render.image_settings.file_format = "PNG"
	scene.render.image_settings.color_mode = "RGBA"
	scene.view_settings.view_transform = "Standard"
	scene.view_settings.look = "None"

	world = bpy.data.worlds.new("world")
	world.use_nodes = True
	world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.42, 0.44, 0.48, 1)
	world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.4
	scene.world = world

	# key light from the upper left like vanilla sprites, shadows fall to the right
	sun = bpy.data.lights.new("sun", "SUN")
	sun.energy = 8.0
	sun.angle = math.radians(4)
	sun_obj = bpy.data.objects.new("sun", sun)
	sun_obj.rotation_euler = (math.radians(32), math.radians(-22), math.radians(-35))
	scene.collection.objects.link(sun_obj)
	fill = bpy.data.lights.new("fill", "SUN")
	fill.energy = 0.6
	fill.use_shadow = False
	fill_obj = bpy.data.objects.new("fill", fill)
	fill_obj.rotation_euler = (math.radians(55), math.radians(30), math.radians(150))
	scene.collection.objects.link(fill_obj)
	return scene


def setup_camera(scene, size_px=FRAME_PX, px_per_tile=PX_PER_TILE, tilt=CAMERA_TILT):
	cam = bpy.data.cameras.new("cam")
	cam.type = "ORTHO"
	cam.ortho_scale = size_px / px_per_tile
	obj = bpy.data.objects.new("cam", cam)
	scene.collection.objects.link(obj)
	dist = 30
	obj.location = (0, -dist * math.sin(tilt), dist * math.cos(tilt))
	obj.rotation_euler = (tilt, 0, 0)
	scene.camera = obj
	return obj


def ground_stretch_parent(root):
	"""Stretch world Y so the ground reads close to vanilla's proportions."""
	stretch = bpy.data.objects.new("stretch", None)
	bpy.context.collection.objects.link(stretch)
	stretch.scale = (1, GROUND_STRETCH, 1)
	turn = bpy.data.objects.new("turn", None)
	bpy.context.collection.objects.link(turn)
	turn.parent = stretch
	root.parent = turn
	return turn


def holdout_material():
	mat = bpy.data.materials.new("holdout")
	mat.use_nodes = True
	nt = mat.node_tree
	for n in list(nt.nodes):
		nt.nodes.remove(n)
	out = nt.nodes.new("ShaderNodeOutputMaterial")
	hold = nt.nodes.new("ShaderNodeHoldout")
	nt.links.new(hold.outputs[0], out.inputs["Surface"])
	return mat


def apply_mode(mode, m, root, scene):
	parts = [o for o in bpy.data.objects if o.type == "MESH"]
	if mode == "mask":
		# only the tintable paint shows, flat and unlit so the tint is even at
		# every angle; everything else cuts it out
		hold = holdout_material()
		paint = bpy.data.materials.new("paint")
		paint.use_nodes = True
		nt = paint.node_tree
		for n in list(nt.nodes):
			nt.nodes.remove(n)
		out = nt.nodes.new("ShaderNodeOutputMaterial")
		emit = nt.nodes.new("ShaderNodeEmission")
		emit.inputs["Color"].default_value = (0.6, 0.6, 0.6, 1)
		nt.links.new(emit.outputs[0], out.inputs["Surface"])
		for o in parts:
			if o.data.materials:
				o.data.materials[0] = paint if o.data.materials[0] == m["stripe"] else hold
	elif mode == "shadow":
		plane = bpy.data.meshes.new("ground")
		bm = bmesh.new()
		bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=12)
		bm.to_mesh(plane)
		bm.free()
		ground = bpy.data.objects.new("ground", plane)
		scene.collection.objects.link(ground)
		ground.is_shadow_catcher = True
		for o in parts:
			o.visible_camera = False
		scene.world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.0
		scene.objects["fill"].hide_render = True


def render_frames(args):
	scene = setup_scene(args)
	m = make_materials()
	root = build_wagon(m)
	turn = ground_stretch_parent(root)
	apply_mode(args.mode, m, root, scene)

	if args.mode == "icon":
		# a close three-quarter perspective so the icon is chunky like vanilla's
		cam = setup_camera(scene, size_px=256, px_per_tile=256 / 7.0, tilt=math.radians(55))
		cam.data.type = "PERSP"
		cam.data.lens = 50
		cam.location = (0, -11 * math.sin(math.radians(55)), 11 * math.cos(math.radians(55)) + 1.0)
		# show the paint in the wagon's default blue, as the game would
		for node in m["stripe"].node_tree.nodes:
			if node.bl_idname == "ShaderNodeMix" and node.blend_type == "MIX":
				node.inputs[6].default_value = (0.05, 0.07, 0.09, 1)
				node.inputs[7].default_value = (0.1, 0.15, 0.2, 1)
		scene.render.resolution_x = 256
		scene.render.resolution_y = 256
		turn.rotation_euler = (0, 0, -math.radians(24))
		scene.render.filepath = f"{args.out}/icon.png"
		bpy.ops.render.render(write_still=True)
		return

	setup_camera(scene)
	if args.blend:
		bpy.ops.wm.save_as_mainfile(filepath=args.blend)
	for f in frame_list(args.frames):
		turn.rotation_euler = (0, 0, -math.pi * f / DIRECTIONS)
		scene.render.filepath = f"{args.out}/{f:03d}.png"
		bpy.ops.render.render(write_still=True)


if __name__ == "__main__":
	render_frames(parse_args())
