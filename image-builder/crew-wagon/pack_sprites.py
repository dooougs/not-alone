"""Pack the Crew wagon renders into Factorio rolling stock sheets.

    python3 pack_sprites.py <renders dir> <mod graphics dir>

Each layer (color, mask, shadow) is cropped to the union of its frames'
opaque area, then laid out 4 columns by 8 rows per file, 4 files for the 128
directions, the same layout as vanilla's cargo wagon. Renders put the wagon's
ground centre at the middle of a 512px frame at 64px per tile, so the crop
offset gives each layer's shift. The shifts and frame sizes are printed as Lua
for data.lua.
"""

import os
import sys

from PIL import Image

DIRECTIONS = 128
FRAME_PX = 512
COLUMNS = 4
ROWS_PER_FILE = 8
PAD = 2


def union_bbox(frames):
	box = None
	for im in frames:
		b = im.getchannel("A").point(lambda a: 255 if a > 2 else 0).getbbox()
		if not b:
			continue
		box = b if box is None else (min(box[0], b[0]), min(box[1], b[1]), max(box[2], b[2]), max(box[3], b[3]))
	return (max(0, box[0] - PAD), max(0, box[1] - PAD), min(FRAME_PX, box[2] + PAD), min(FRAME_PX, box[3] + PAD))


def prepare(layer, im):
	if layer == "shadow":
		# vanilla shadows are pure black with the darkness in alpha
		alpha = im.getchannel("A").point(lambda a: 0 if a < 16 else a)
		im = Image.new("RGBA", im.size, (0, 0, 0, 0))
		im.putalpha(alpha)
	elif layer == "mask":
		# a soft, desaturated overlay like the vanilla masks
		alpha = im.getchannel("A").point(lambda a: a * 0.8)
		gray = im.convert("L")
		im = Image.merge("RGBA", (gray, gray, gray, alpha))
	return im


def pack(src, dst, layer, name):
	frames = [prepare(layer, Image.open(os.path.join(src, layer, f"{i:03d}.png")).convert("RGBA"))
		for i in range(DIRECTIONS)]
	x0, y0, x1, y1 = union_bbox(frames)
	w, h = x1 - x0, y1 - y0
	per_file = COLUMNS * ROWS_PER_FILE
	for n in range(DIRECTIONS // per_file):
		sheet = Image.new("RGBA", (w * COLUMNS, h * ROWS_PER_FILE), (0, 0, 0, 0))
		for k in range(per_file):
			r, c = divmod(k, COLUMNS)
			sheet.paste(frames[n * per_file + k].crop((x0, y0, x1, y1)), (c * w, r * h))
		sheet.save(os.path.join(dst, f"{name}-{n + 1}.png"), optimize=True)
	# shift in tiles at scale 0.5 (64px per tile in the file)
	cx = (x0 + x1) / 2 - FRAME_PX / 2
	cy = (y0 + y1) / 2 - FRAME_PX / 2
	return w, h, cx / 64, cy / 64


def main():
	src, dst = sys.argv[1], sys.argv[2]
	os.makedirs(dst, exist_ok=True)
	for layer, name in (("color", "crew-wagon"), ("mask", "crew-wagon-mask"), ("shadow", "crew-wagon-shadow")):
		w, h, sx, sy = pack(src, dst, layer, name)
		print(f'{layer} = {{width = {w}, height = {h}, shift = {{{sx:.4f}, {sy:.4f}}}}},')

	icon = Image.open(os.path.join(src, "icon", "icon.png")).convert("RGBA")
	bbox = icon.getchannel("A").getbbox()
	icon = icon.crop(bbox)
	side = max(icon.size)
	square = Image.new("RGBA", (side, side), (0, 0, 0, 0))
	square.paste(icon, ((side - icon.width) // 2, (side - icon.height) // 2))
	mips = square.resize((64, 64), Image.LANCZOS)
	icons_dir = os.path.join(os.path.dirname(dst.rstrip("/")), "..", "icons")
	mips.save(os.path.join(icons_dir, "crew-wagon.png"), optimize=True)


if __name__ == "__main__":
	main()
