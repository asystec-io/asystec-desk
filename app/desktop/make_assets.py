"""Generate the provisional AD typography mark from scratch (requires Pillow)."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

OUTPUT = Path(__file__).resolve().parent / "assets"
OUTPUT.mkdir(exist_ok=True)
FONT = Path("C:/Windows/Fonts/seguisb.ttf")


def font(size):
    return ImageFont.truetype(str(FONT), size)


icon = Image.new("RGBA", (512, 512), (0, 0, 0, 0))
draw = ImageDraw.Draw(icon)
draw.rounded_rectangle((8, 8, 504, 504), radius=116, fill="#087F8C")
draw.text((256, 244), "AD", font=font(226), anchor="mm", fill="white")
draw.rounded_rectangle((126, 386, 386, 410), radius=12, fill="#9AE6D8")
icon.save(OUTPUT / "icon.png")
for name in ("icon.ico", "tray-icon.ico"):
    icon.save(OUTPUT / name, sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
for name, color in (("logo.png", "#152F3A"), ("logo_light.png", "#152F3A"), ("logo_dark.png", "#F0FAFC")):
    logo = Image.new("RGBA", (1000, 200), (0, 0, 0, 0))
    logo.alpha_composite(icon.resize((180, 180), Image.Resampling.LANCZOS), (0, 10))
    ImageDraw.Draw(logo).text((215, 90), "Asystec Desk", font=font(116), anchor="lm", fill=color)
    logo.save(OUTPUT / name)
print(OUTPUT)
