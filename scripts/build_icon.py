#!/usr/bin/env python3

from pathlib import Path
from PIL import Image, ImageDraw
import subprocess


root = Path(__file__).resolve().parent.parent
iconset = root / ".build" / "AppIcon.iconset"
output = root / "Packaging" / "AppIcon.icns"
iconset.mkdir(parents=True, exist_ok=True)


def render(size: int) -> Image.Image:
    scale = size / 1024
    image = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    margin = int(92 * scale)
    radius = int(220 * scale)
    draw.rounded_rectangle(
        (margin, margin, size - margin, size - margin),
        radius=radius,
        fill=(31, 190, 108, 255),
    )
    draw.rounded_rectangle(
        (margin, margin, size - margin, size - margin),
        radius=radius,
        outline=(255, 255, 255, 42),
        width=max(1, int(12 * scale)),
    )
    bolt = [
        (560, 205),
        (326, 543),
        (482, 543),
        (410, 819),
        (700, 443),
        (531, 443),
    ]
    draw.polygon([(int(x * scale), int(y * scale)) for x, y in bolt], fill="white")
    return image


for points in (16, 32, 128, 256, 512):
    render(points).save(iconset / f"icon_{points}x{points}.png")
    render(points * 2).save(iconset / f"icon_{points}x{points}@2x.png")

subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(output)], check=True)
