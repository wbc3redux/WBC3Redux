"""WBC3 Redux icon (PACKAGING.md "Name"): a bronze Roman numeral III on dark stone with a red ink REDUX stamp across
its foot, our own drawing (nothing from the original game's art). Writes:

  artwork/icon/wbc3redux.ico        Windows icon, 16..256 px (exe, installer, uninstaller, shortcuts)
  artwork/icon/wbc3redux-256.png    window and taskbar icon (project.godot application/config/icon)
  .local/packaging/icon-preview.png  every size side by side, for review (not shipped)

  python packaging/make_icon.py

Drawn on a 64-unit grid at 16x, then scaled down per size with Lanczos. Lettering: DejaVu Serif Condensed Bold
(Bitstream Vera / DejaVu licence, which allows this use), read from C:\\Windows\\Fonts or --font. The outputs are kept
in the project, so a build never needs the font.
"""
import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

PROJECT = Path(__file__).resolve().parents[1]
OUT = PROJECT / 'artwork' / 'icon'
SIZES = [16, 20, 24, 32, 40, 48, 64, 96, 128, 256]
S = 16                       # pixels per grid unit while drawing (64 units -> 1024 px)
STONE = (33, 27, 24, 255)
FRAME = (90, 70, 54, 255)
BRONZE = (201, 143, 69, 255)
BRONZE_LIGHT = (227, 180, 106, 255)
INK = (192, 40, 28, 255)
INK_TEXT = (210, 46, 32, 255)


def box(x, y, w, h):
    return [x * S, y * S, (x + w) * S - 1, (y + h) * S - 1]


def draw(font_path, small=False):
    """The icon at 1024 px. `small` (16..32 px): thicker frame and stamp border, no lettering (unreadable there)."""
    im = Image.new('RGBA', (64 * S, 64 * S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle(box(2, 2, 60, 60), radius=10 * S, fill=STONE)
    if not small:
        d.rounded_rectangle(box(5, 5, 54, 54), radius=7 * S, outline=FRAME, width=int(1.5 * S))
    # The numeral III: three bars with top and bottom serifs, a lighter stripe on each bar.
    for x in (13, 28.5, 44):
        d.rectangle(box(x, 9, 7, 30), fill=BRONZE)
        d.rectangle(box(x + 1, 11, 2, 26), fill=BRONZE_LIGHT)
    for y in (7, 37):
        d.rounded_rectangle(box(10, y, 44, 4), radius=1 * S, fill=BRONZE)
    # The stamp on its own layer, rotated 8 degrees anticlockwise about its centre, as on the main menu.
    stamp = Image.new('RGBA', im.size, (0, 0, 0, 0))
    sd = ImageDraw.Draw(stamp)
    sd.rounded_rectangle(box(7, 39, 50, 16), radius=2 * S, fill=(33, 27, 24, 153))
    sd.rounded_rectangle(box(7, 39, 50, 16), radius=2 * S, outline=INK, width=int((3.6 if small else 2.4) * S))
    if small:
        sd.rectangle(box(13, 45, 38, 4), fill=INK_TEXT)          # the word as a bar: reads as "a stamp" at 16 px
    else:
        font = ImageFont.truetype(str(font_path), int(12.5 * S))
        text, spacing = 'REDUX', 0.9 * S
        widths = [font.getlength(ch) for ch in text]
        total = sum(widths) + spacing * (len(text) - 1)
        x = 32 * S - total / 2
        for ch, w in zip(text, widths):
            sd.text((x, 47 * S), ch, font=font, fill=INK_TEXT, anchor='lm')
            x += w + spacing
    stamp = stamp.rotate(8, resample=Image.BICUBIC, center=(32 * S, 47 * S))
    im.alpha_composite(stamp)
    return im


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--font', type=Path, default=Path(r'C:\Windows\Fonts\DejaVuSerifCondensed-Bold.ttf'))
    args = parser.parse_args()
    if not args.font.is_file():
        raise SystemExit(f'Font not found: {args.font} (DejaVu Serif Condensed Bold; pass --font)')
    OUT.mkdir(parents=True, exist_ok=True)
    big, small = draw(args.font), draw(args.font, small=True)
    images = [(small if size <= 32 else big).resize((size, size), Image.LANCZOS) for size in SIZES]
    largest = images[-1]
    largest.save(OUT / 'wbc3redux.ico', format='ICO', sizes=[(s, s) for s in SIZES], append_images=images[:-1])
    largest.save(OUT / 'wbc3redux-256.png')
    preview = Image.new('RGBA', (sum(SIZES) + 12 * len(SIZES), 256 + 24), (60, 60, 60, 255))
    x = 12
    for size, image in zip(SIZES, images):
        preview.alpha_composite(image, (x, 12 + 256 - size))
        x += size + 12
    (PROJECT / '.local' / 'packaging').mkdir(parents=True, exist_ok=True)
    preview.save(PROJECT / '.local' / 'packaging' / 'icon-preview.png')
    print(f'Wrote {OUT / "wbc3redux.ico"} ({", ".join(map(str, SIZES))} px) and the 256 px PNG')


if __name__ == '__main__':
    main()
