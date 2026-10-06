"""Draws the Control app icon (three mixer sliders) and writes every iOS and
Android size.

Run from the repo root:  python3 scripts/generate_icon.py   (needs Pillow)
"""
import json
from pathlib import Path

from PIL import Image, ImageDraw

SIZE = 1024
SS = 4  # supersampling for smooth edges
ICONSET = Path("ios/Runner/Assets.xcassets/AppIcon.appiconset")
ANDROID_RES = Path("android/app/src/main/res")
TOP, BOTTOM = (16, 36, 44), (8, 14, 18)

# Android densities: legacy icon is 48dp, adaptive layers are 108dp.
DENSITIES = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}


def _sliders(d: ImageDraw.ImageDraw, s: int, scale: float = 1.0) -> None:
    """The three sliders, scaled about the centre by [scale]."""
    teal = (46, 196, 182, 255)
    track = (40, 70, 76, 255)

    def at(v: float) -> float:
        return (0.5 + (v - 0.5) * scale) * s

    xs = [0.30, 0.50, 0.70]
    knobs = [0.62, 0.36, 0.52]
    y0, y1 = at(0.22), at(0.78)
    w = 0.045 * s * scale
    r = 0.085 * s * scale
    for x, k in zip(xs, knobs):
        cx = at(x)
        d.rounded_rectangle([cx - w / 2, y0, cx + w / 2, y1], radius=w / 2, fill=track)
        ky = y0 + (y1 - y0) * k
        d.rounded_rectangle([cx - w / 2, ky, cx + w / 2, y1], radius=w / 2, fill=teal)
        d.ellipse([cx - r, ky - r, cx + r, ky + r], fill=(236, 248, 246, 255))


def draw() -> Image.Image:
    """The full-bleed square icon (iOS rounds the corners itself)."""
    s = SIZE * SS
    img = Image.new("RGBA", (s, s))
    px = img.load()
    for y in range(s):
        t = y / (s - 1)
        row = tuple(round(TOP[i] + (BOTTOM[i] - TOP[i]) * t) for i in range(3)) + (255,)
        for x in range(s):
            px[x, y] = row
    _sliders(ImageDraw.Draw(img), s)
    return img.resize((SIZE, SIZE), Image.LANCZOS).convert("RGB")


def draw_foreground() -> Image.Image:
    """Android adaptive-icon foreground: the sliders on transparent, kept
    inside the 66dp safe zone of the 108dp layer."""
    s = SIZE * SS
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    _sliders(ImageDraw.Draw(img), s, scale=0.62)
    return img.resize((SIZE, SIZE), Image.LANCZOS)


def write_android(icon: Image.Image) -> None:
    if not ANDROID_RES.exists():
        return
    foreground = draw_foreground()
    # Legacy icon (Android 7 and older launchers): a rounded square.
    mask = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, SIZE - 1, SIZE - 1], radius=round(SIZE * 0.22), fill=255
    )
    legacy = icon.convert("RGBA")
    legacy.putalpha(mask)
    for name, factor in DENSITIES.items():
        folder = ANDROID_RES / f"mipmap-{name}"
        folder.mkdir(parents=True, exist_ok=True)
        px = round(48 * factor)
        legacy.resize((px, px), Image.LANCZOS).save(folder / "ic_launcher.png")
        px = round(108 * factor)
        foreground.resize((px, px), Image.LANCZOS).save(
            folder / "ic_launcher_foreground.png"
        )
    (ANDROID_RES / "drawable").mkdir(parents=True, exist_ok=True)
    (ANDROID_RES / "drawable" / "ic_launcher_background.xml").write_text(
        """<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android">
    <gradient
        android:angle="270"
        android:startColor="#%02X%02X%02X"
        android:endColor="#%02X%02X%02X" />
</shape>
"""
        % (TOP + BOTTOM)
    )
    adaptive = ANDROID_RES / "mipmap-anydpi-v26"
    adaptive.mkdir(parents=True, exist_ok=True)
    (adaptive / "ic_launcher.xml").write_text(
        """<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@drawable/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
    <monochrome android:drawable="@mipmap/ic_launcher_foreground" />
</adaptive-icon>
"""
    )
    print("Wrote Android icons")


def main() -> None:
    icon = draw()
    contents = json.loads((ICONSET / "Contents.json").read_text())
    for entry in contents["images"]:
        name = entry.get("filename")
        if not name:
            continue
        points = float(entry["size"].split("x")[0])
        scale = int(entry["scale"].rstrip("x"))
        px = round(points * scale)
        icon.resize((px, px), Image.LANCZOS).save(ICONSET / name)
    print("Wrote", len(contents["images"]), "iOS icons")
    write_android(icon)


if __name__ == "__main__":
    main()
