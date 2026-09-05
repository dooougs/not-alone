from pathlib import Path
import struct
import subprocess
import tempfile
from PIL import Image

ROOT = Path(__file__).resolve().parent
HTML = ROOT / "banner.html"
EDGE = Path(r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe")
if not EDGE.exists():
    EDGE = Path(r"C:\Program Files\Microsoft\Edge\Application\msedge.exe")
WIDTH, HEIGHT = 1152, 768
LAYER_NAMES = [
    ("Background", "background"),
    ("Footer", "footer"),
    ("Title", "title"),
    ("Gear", "gear"),
    ("Subtitle", "subtitle"),
    ("Miner", "miner"),
    ("Builder", "builder"),
    ("Carrier", "carrier"),
    ("Soldier", "soldier"),
    ("Miner card", "miner-card"),
    ("Builder card", "builder-card"),
    ("Carrier card", "carrier-card"),
    ("Soldier card", "soldier-card"),
]


def u32(value):
    return struct.pack(">I", value)


def i32(value):
    return struct.pack(">i", value)


def cstring(value):
    return value.encode("utf-8") + b"\0"


def prop(prop_id, data):
    return u32(prop_id) + u32(len(data)) + data


def unmix_transparent_image(light, dark):
    result = Image.new("RGBA", light.size)
    output = result.load()
    light_pixels = light.load()
    dark_pixels = dark.load()
    for y in range(HEIGHT):
        for x in range(WIDTH):
            light_red, light_green, light_blue = light_pixels[x, y]
            dark_red, dark_green, dark_blue = dark_pixels[x, y]
            alpha = max(0, min(255, round(255 - (
                (light_red - dark_red) + (light_green - dark_green) + (light_blue - dark_blue)
            ) / 3)))
            if alpha:
                output[x, y] = tuple(max(0, min(255, round(channel * 255 / alpha))) for channel in (dark_red, dark_green, dark_blue)) + (alpha,)
            else:
                output[x, y] = (0, 0, 0, 0)
    return result


def render_layers(folder):
    source = HTML.read_text(encoding="utf-8")
    base = ROOT.as_uri() + "/"
    rendered = []
    for index, (layer_name, target) in enumerate(LAYER_NAMES):
        if target is None:
            rules = ""
        elif target == "background":
            rules = (
                "body { background: transparent !important; }"
                ".bg { display: block !important; }"
                ".bg:after { display: none !important; }"
                ".footer, [data-drag] { display: none !important; }"
            )
        elif target == "footer":
            rules = (
                "body { background: transparent !important; }"
                ".bg, [data-drag] { display: none !important; }"
            )
        else:
            rules = (
                "body { background: transparent !important; }"
                ".bg { display: none !important; }"
                ".footer { display: none !important; }"
                "[data-drag] { visibility: hidden !important; }"
                f'[data-drag="{target}"] {{ visibility: visible !important; }}'
            )
            if target == "title":
                rules += '[data-drag="title"] .gear { visibility: hidden !important; }'
            elif target == "gear":
                rules += ".title { color: transparent !important; -webkit-text-fill-color: transparent !important; }"
        variant = source.replace("<head>", f'<head><base href="{base}"><style>{rules}</style>', 1)
        variant_path = folder / f"layer-{index:02d}.html"
        light_path = folder / f"layer-{index:02d}-light.png"
        dark_path = folder / f"layer-{index:02d}-dark.png"
        for screenshot_path, color in ((light_path, "255,255,255"), (dark_path, "0,0,0")):
            rendered_variant = variant.replace(
                "</head>", f'<style>body {{ background: rgb({color}) !important; }}</style></head>', 1
            )
            variant_path.write_text(rendered_variant, encoding="utf-8")
            subprocess.run(
                [
                    str(EDGE), "--headless", "--disable-gpu", "--hide-scrollbars",
                    f"--window-size={WIDTH},{HEIGHT}", f"--screenshot={screenshot_path}",
                    variant_path.as_uri(),
                ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            )
        light = Image.open(light_path).convert("RGB")
        image = light.convert("RGBA") if target == "background" else unmix_transparent_image(
            light, Image.open(dark_path).convert("RGB")
        )
        rendered.append((layer_name, image))
    return rendered


def save_layer_copies(layers):
    output_folder = ROOT / "layers"
    output_folder.mkdir(exist_ok=True)
    for layer_name, image in layers:
        filename = layer_name.lower().replace(" ", "-") + ".png"
        image.save(output_folder / filename)


def layer_record(name, image):
    raw = image.tobytes()
    tiles = []
    for top in range(0, HEIGHT, 64):
        for left in range(0, WIDTH, 64):
            tile = bytearray()
            for row in range(top, min(top + 64, HEIGHT)):
                start = (row * WIDTH + left) * 4
                end = (row * WIDTH + min(left + 64, WIDTH)) * 4
                tile.extend(raw[start:end])
            tile_width = min(64, WIDTH - left)
            tile_height = min(64, HEIGHT - top)
            if tile_width != 64 or tile_height != 64:
                padded = bytearray(64 * 64 * 4)
                for row in range(tile_height):
                    padded[row * 64 * 4:row * 64 * 4 + tile_width * 4] = tile[row * tile_width * 4:(row + 1) * tile_width * 4]
                tile = padded
            tiles.append(bytes(tile))

    properties = prop(6, u32(255)) + prop(7, u32(0)) + prop(8, u32(1)) + u32(0)
    record = u32(WIDTH) + u32(HEIGHT) + cstring(name) + properties
    record += u32(0) + u32(0)
    return record, tiles


def write_xcf(path, layers):
    records = []
    tile_sets = []
    for name, image in layers:
        record, tiles = layer_record(name, image)
        records.append(record)
        tile_sets.append(tiles)

    output = bytearray(b"gimp xcf ")
    output += b"011\0" + u32(WIDTH) + u32(HEIGHT) + u32(0)
    output += prop(17, u32(0)) + u32(0) + u32(0)
    output += u32(len(records))
    layer_offsets_start = len(output)
    output += b"\0" * (4 * len(records))
    output += u32(0)
    offsets = []
    for record in records:
        offsets.append(len(output))
        output += record
    output[layer_offsets_start:layer_offsets_start + 4 * len(offsets)] = b"".join(u32(v) for v in offsets)

    pixel_data = bytearray()
    hierarchy_offsets = []
    for tiles in tile_sets:
        tile_offsets = []
        for tile in tiles:
            tile_offsets.append(len(output) + len(pixel_data))
            pixel_data.extend(tile)
        level_offset = len(output) + len(pixel_data)
        pixel_data.extend(u32(WIDTH) + u32(HEIGHT))
        pixel_data.extend(b"".join(u32(offset) for offset in tile_offsets))
        pixel_data.extend(u32(0))
        hierarchy_offsets.append(len(output) + len(pixel_data))
        pixel_data.extend(u32(WIDTH) + u32(HEIGHT) + u32(4) + u32(level_offset) + u32(0))

    for index, record_offset in enumerate(offsets):
        hierarchy_field = record_offset + len(records[index]) - 8
        output[hierarchy_field:hierarchy_field + 4] = u32(hierarchy_offsets[index])
    output += pixel_data
    path.write_bytes(output)


def main():
    output = ROOT / "banner.xcf"
    with tempfile.TemporaryDirectory(prefix="not-alone-xcf-") as temp:
        layers = render_layers(Path(temp))
        save_layer_copies(layers)
        write_xcf(output, layers)
    print(f"Created {output}")


if __name__ == "__main__":
    main()
