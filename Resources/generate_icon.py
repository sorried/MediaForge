"""Generate the app's raster icon without external dependencies."""
from pathlib import Path
import math
import json
import struct
import zlib

SIZE = 1024

def chunk(kind, content):
    return struct.pack(">I", len(content)) + kind + content + struct.pack(">I", zlib.crc32(kind + content) & 0xffffffff)

def inside_triangle(x, y):
    return 390 <= x <= 700 and abs(y - 512) <= (700 - x) * 0.60

rows = bytearray()
for y in range(SIZE):
    rows.append(0)
    for x in range(SIZE):
        edge = max(abs(x - 511.5) - 350, abs(y - 511.5) - 350, 0)
        corner = math.hypot(max(abs(x - 511.5) - 350, 0), max(abs(y - 511.5) - 350, 0))
        if corner > 142:
            rgba = (0, 0, 0, 0)
        else:
            t = y / SIZE
            rgba = (int(35 + 14 * t), int(74 + 32 * t), int(135 + 45 * t), 255)
            if 240 <= x <= 784 and 275 <= y <= 749:
                rgba = (17, 32, 58, 255)
                if y < 320 or y > 704:
                    if (x - 250) % 88 < 48:
                        rgba = (138, 189, 242, 255)
            if inside_triangle(x, y):
                rgba = (246, 166, 75, 255)
        rows.extend(rgba)
png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(bytes(rows), 9)) + chunk(b"IEND", b"")
root = Path(__file__).resolve().parent
(root / "AppIcon.png").write_bytes(png)
catalog = root / "Assets.xcassets"
icons = catalog / "AppIcon.appiconset"
icons.mkdir(parents=True, exist_ok=True)
(catalog / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}) + "\n")
images = []
for points in [16, 32, 128, 256, 512]:
    for scale in [1, 2]:
        size = points * scale
        raster = bytearray()
        for y in range(size):
            raster.append(0)
            source_y = min(SIZE - 1, int((y + 0.5) * SIZE / size))
            for x in range(size):
                source_x = min(SIZE - 1, int((x + 0.5) * SIZE / size))
                offset = source_y * (SIZE * 4 + 1) + 1 + source_x * 4
                raster.extend(rows[offset:offset + 4])
        icon_png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(bytes(raster), 9)) + chunk(b"IEND", b"")
        name = f"icon_{points}x{points}@{scale}x.png"
        (icons / name).write_bytes(icon_png)
        images.append({"filename": name, "idiom": "mac", "scale": f"{scale}x", "size": f"{points}x{points}"})
(icons / "Contents.json").write_text(json.dumps({"images": images, "info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
