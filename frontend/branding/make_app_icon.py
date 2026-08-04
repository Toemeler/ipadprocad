#!/usr/bin/env python3
"""Renders the iOS app icon set from the source artwork.

The iOS project is NOT in version control — CI scaffolds it with
`flutter create` on every build (see .github/workflows/m1-core-build.yml), which
also writes Flutter's default blue icon. So the icon set lives here, outside the
generated tree, and the workflow copies it over the scaffolded one.

Run after changing the artwork or the layout below:

    python3 frontend/branding/make_app_icon.py

Needs Pillow (`pip install Pillow`); nothing in CI runs it, the PNGs it writes
are committed.
"""
import json
import pathlib

from PIL import Image

HERE = pathlib.Path(__file__).parent
SRC = HERE / 'app_icon_source.png'
OUT = HERE / 'AppIcon.appiconset'

# Cream white. iOS icons cannot be transparent — an alpha channel is rejected
# for the marketing size and renders black on device — so the background is
# composited in here rather than left to the platform.
CREAM = (250, 246, 236)

# The artwork's SOLID bounds inside the 1024 source, i.e. without the soft
# shadow it casts. Centring and scaling on these keeps the glyph optically
# centred; using the alpha bounds instead would let the shadow push it up.
SOLID = (279, 244, 746, 800)

# Height of that solid artwork as a fraction of the icon. 0.65 leaves the
# dashed cube clear of iOS's rounded-rectangle mask at every size.
HEIGHT_FRACTION = 0.65

# name -> pixel size. Exactly the set Flutter's iOS template ships, so the
# scaffolded Contents.json is replaced like for like.
SIZES = {
    'Icon-App-20x20@1x': 20,
    'Icon-App-20x20@2x': 40,
    'Icon-App-20x20@3x': 60,
    'Icon-App-29x29@1x': 29,
    'Icon-App-29x29@2x': 58,
    'Icon-App-29x29@3x': 87,
    'Icon-App-40x40@1x': 40,
    'Icon-App-40x40@2x': 80,
    'Icon-App-40x40@3x': 120,
    'Icon-App-60x60@2x': 120,
    'Icon-App-60x60@3x': 180,
    'Icon-App-76x76@1x': 76,
    'Icon-App-76x76@2x': 152,
    'Icon-App-83.5x83.5@2x': 167,
    'Icon-App-1024x1024@1x': 1024,
}

CONTENTS = {
    'images': [
        {'size': s, 'idiom': i, 'filename': f'{f}.png', 'scale': sc}
        for s, i, f, sc in [
            ('20x20', 'iphone', 'Icon-App-20x20@2x', '2x'),
            ('20x20', 'iphone', 'Icon-App-20x20@3x', '3x'),
            ('29x29', 'iphone', 'Icon-App-29x29@1x', '1x'),
            ('29x29', 'iphone', 'Icon-App-29x29@2x', '2x'),
            ('29x29', 'iphone', 'Icon-App-29x29@3x', '3x'),
            ('40x40', 'iphone', 'Icon-App-40x40@2x', '2x'),
            ('40x40', 'iphone', 'Icon-App-40x40@3x', '3x'),
            ('60x60', 'iphone', 'Icon-App-60x60@2x', '2x'),
            ('60x60', 'iphone', 'Icon-App-60x60@3x', '3x'),
            ('20x20', 'ipad', 'Icon-App-20x20@1x', '1x'),
            ('20x20', 'ipad', 'Icon-App-20x20@2x', '2x'),
            ('29x29', 'ipad', 'Icon-App-29x29@1x', '1x'),
            ('29x29', 'ipad', 'Icon-App-29x29@2x', '2x'),
            ('40x40', 'ipad', 'Icon-App-40x40@1x', '1x'),
            ('40x40', 'ipad', 'Icon-App-40x40@2x', '2x'),
            ('76x76', 'ipad', 'Icon-App-76x76@1x', '1x'),
            ('76x76', 'ipad', 'Icon-App-76x76@2x', '2x'),
            ('83.5x83.5', 'ipad', 'Icon-App-83.5x83.5@2x', '2x'),
            ('1024x1024', 'ios-marketing', 'Icon-App-1024x1024@1x', '1x'),
        ]
    ],
    'info': {'version': 1, 'author': 'xcode'},
}


def master(size: int) -> Image.Image:
    """The icon at [size], composited on cream, no alpha channel."""
    src = Image.open(SRC).convert('RGBA')
    cx, cy = (SOLID[0] + SOLID[2]) / 2, (SOLID[1] + SOLID[3]) / 2
    scale = (HEIGHT_FRACTION * size) / (SOLID[3] - SOLID[1])
    w = round(src.width * scale)
    art = src.resize((w, round(src.height * scale)), Image.LANCZOS)
    out = Image.new('RGBA', (size, size), CREAM + (255,))
    out.alpha_composite(art, (round(size / 2 - cx * scale),
                              round(size / 2 - cy * scale)))
    return out.convert('RGB')


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    # Render once at full resolution and downsample: compositing directly at
    # 20 px would alias the dashed edges into mush.
    big = master(1024)
    for name, px in SIZES.items():
        img = big if px == 1024 else big.resize((px, px), Image.LANCZOS)
        img.save(OUT / f'{name}.png', format='PNG', optimize=True)
    (OUT / 'Contents.json').write_text(json.dumps(CONTENTS, indent=2) + '\n')
    print(f'wrote {len(SIZES)} icons + Contents.json to {OUT}')


if __name__ == '__main__':
    main()
