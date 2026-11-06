#!/usr/bin/env python3
"""Apply the BetterOQB SVG app icons to generated Flutter Android/iOS runners.

Run AFTER flutter create --platforms=android,ios .; platform folders are not
tracked in this repository. Requires Pillow and CairoSVG (and native libcairo).
"""

from __future__ import annotations

import argparse
import io
import json
import re
from pathlib import Path
from xml.etree import ElementTree as ET

import cairosvg
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
SVG = "{http://www.w3.org/2000/svg}"
PALETTE = {
    "#D0BCFF": "#514166",  # Back card
    "#8065B3": "#D0BCFF",  # Back card outline
    "#FBF8FF": "#302B38",  # Front card
    "#6750A4": "#EADDFF",  # Question / outlines / completion badge
    "#FFFFFF": "#1D1B20",  # Checkmark inside the badge
}


def artwork(*, monochrome: bool = False, background: str | None = None,
            dark: bool = False, scale: float = 1.0) -> bytes:
    path = ROOT / "assets/icon" / (
        "betteroqb-icon-monochrome.svg" if monochrome else "betteroqb-icon.svg"
    )
    root = ET.fromstring(path.read_bytes())
    # The source has a rounded-square preview background. Platform masks must
    # determine the rounded corners, so omit it and use full-bleed backgrounds.
    if not monochrome:
        for child in list(root):
            if child.tag == SVG + "rect" and child.get("width") == "128" and child.get("height") == "128":
                root.remove(child)
                break
    for el in root.iter():
        for attr in ("fill", "stroke"):
            paint = el.get(attr)
            if paint == "currentColor":
                el.set(attr, "#FFFFFF")
            elif dark and paint in PALETTE:
                el.set(attr, PALETTE[paint])
    if scale != 1.0:
        group = ET.Element(SVG + "g", {
            "transform": f"translate(64 64) scale({scale}) translate(-64 -64)"
        })
        for child in list(root):
            if child.tag not in (SVG + "title", SVG + "desc"):
                root.remove(child)
                group.append(child)
        root.append(group)
    if background is not None:
        root.insert(0, ET.Element(SVG + "rect", {
            "width": "128", "height": "128", "fill": background
        }))
    return ET.tostring(root, encoding="utf-8", xml_declaration=True)


def raster(svg: bytes, size: int, *, opaque: bool = False) -> Image.Image:
    png = cairosvg.svg2png(bytestring=svg, output_width=size, output_height=size)
    with Image.open(io.BytesIO(png)) as im:
        image = im.convert("RGBA")
    return image.convert("RGB") if opaque else image


def save_png(img: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path, format="PNG", optimize=True)


def generate_android() -> None:
    res = ROOT / "android/app/src/main/res"
    manifest = ROOT / "android/app/src/main/AndroidManifest.xml"
    if not manifest.is_file():
        raise SystemExit("Missing Android runner; run flutter create --platforms=android . first")

    # The same asset name is used by Flutter's default manifest. Older devices
    # use legacy launcher mipmaps; Android 8+ uses the adaptive icon XML.
    legacy_svg = artwork(background="#EADDFF")
    densities = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
    for density, size in densities.items():
        image = raster(legacy_svg, size).convert("RGBA")
        dest = res / f"mipmap-{density}"
        save_png(image, dest / "ic_launcher.png")
        mask = Image.new("L", (size, size), 0)
        ImageDraw.Draw(mask).ellipse((0, 0, size - 1, size - 1), fill=255)
        rounded = image.copy()
        rounded.putalpha(mask)
        save_png(rounded, dest / "ic_launcher_round.png")

    # Android adaptive layers have a 108dp canvas and a centered 66dp safe zone.
    # Scaling the source mark to 80% keeps it within that safe zone.
    foreground = raster(artwork(scale=0.80), 432)
    monochrome = raster(artwork(monochrome=True, scale=0.80), 432)
    drawables = res / "drawable-nodpi"
    save_png(foreground, drawables / "better_oqb_icon_foreground.png")
    save_png(monochrome, drawables / "better_oqb_icon_monochrome.png")
    colors = res / "values/better_oqb_icon_colors.xml"
    colors.parent.mkdir(parents=True, exist_ok=True)
    colors.write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<resources><color name="better_oqb_icon_bg">#EADDFF</color></resources>\n',
        encoding="utf-8",
    )
    adaptive = (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@color/better_oqb_icon_bg" />\n'
        '    <foreground android:drawable="@drawable/better_oqb_icon_foreground" />\n'
        '    <monochrome android:drawable="@drawable/better_oqb_icon_monochrome" />\n'
        '</adaptive-icon>\n'
    )
    adaptive_dir = res / "mipmap-anydpi-v26"
    adaptive_dir.mkdir(parents=True, exist_ok=True)
    for name in ("ic_launcher.xml", "ic_launcher_round.xml"):
        (adaptive_dir / name).write_text(adaptive, encoding="utf-8")

    manifest_text = manifest.read_text(encoding="utf-8")
    if "android:roundIcon=" not in manifest_text:
        manifest_text, count = re.subn(
            r"<application\b", '<application android:roundIcon="@mipmap/ic_launcher_round"',
            manifest_text, count=1,
        )
        if count != 1:
            raise SystemExit("Could not locate <application> in AndroidManifest.xml")
        manifest.write_text(manifest_text, encoding="utf-8")
    print("Applied Android legacy, adaptive and monochrome themed icons")


def generate_ios() -> None:
    icon_set = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    if not icon_set.is_dir():
        raise SystemExit("Missing iOS runner; run flutter create --platforms=ios . first")
    # A single universal 1024px icon supports iPhone/iPad; iOS 18+ can choose
    # the Dark and Tinted variants. They must be registered in Contents.json.
    variants = [
        ("AppIcon-Light.png", artwork(background="#EADDFF"), None),
        ("AppIcon-Dark.png", artwork(background="#1D1B20", dark=True), "dark"),
        ("AppIcon-Tinted.png", artwork(monochrome=True, background="#171717"), "tinted"),
    ]
    entries = []
    for filename, source, appearance in variants:
        save_png(raster(source, 1024, opaque=True), icon_set / filename)
        entry = {"filename": filename, "idiom": "universal", "platform": "ios", "size": "1024x1024"}
        if appearance is not None:
            entry["appearances"] = [{"appearance": "luminosity", "value": appearance}]
        entries.append(entry)
    (icon_set / "Contents.json").write_text(
        json.dumps({"images": entries, "info": {"author": "xcode", "version": 1}}, indent=2) + "\n",
        encoding="utf-8",
    )
    # Old Flutter template assets are now unreferenced. Avoid packaging the
    # stock Flutter logo along with the new app icon assets.
    for old in icon_set.glob("Icon-App-*.png"):
        old.unlink()
    print("Applied iOS light, dark and tinted app icons")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--platform", choices=("android", "ios", "all"), default="all")
    args = parser.parse_args()
    if args.platform in ("android", "all"):
        generate_android()
    if args.platform in ("ios", "all"):
        generate_ios()


if __name__ == "__main__":
    main()
