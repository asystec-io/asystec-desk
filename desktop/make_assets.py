"""Prepare Windows assets from the supplied final Asystec Desk brand package."""
from pathlib import Path
import shutil

from PIL import Image

ROOT = Path(__file__).resolve().parent
BRAND = ROOT / "branding"
OUTPUT = ROOT / "assets"
OUTPUT.mkdir(exist_ok=True)

# Preserve the supplied ICO's hand-simplified 16/32/48 px frames.
sources = {
    "icon.ico": "icono_app/asystec-desk.ico",
    "tray-icon.ico": "icono_app/asystec-desk.ico",
    "icon.png": "icono_app/asystec-desk_icono_512.png",
    "icon.svg": "icono_app/asystec-desk_icono_1024_maestro.svg",
    "logo.png": "logo_horizontal/asystec-desk_logo-horizontal_principal_2048.png",
    "logo_light.png": "logo_horizontal/asystec-desk_logo-horizontal_principal_2048.png",
    "logo_dark.png": "logo_horizontal/asystec-desk_logo-horizontal_negativo_2048.png",
}
for name, relative in sources.items():
    shutil.copy2(BRAND / relative, OUTPUT / name)

# Fit the unmodified negative lockup into Inno Setup's 164:314 sidebar ratio.
sidebar = Image.new("RGBA", (492, 942), "#0F1F45")
with Image.open(BRAND / "logo_vertical/asystec-desk_logo-vertical_negativo_2048.png") as source:
    logo = source.convert("RGBA")
    logo.thumbnail((412, 460), Image.Resampling.LANCZOS)
    sidebar.alpha_composite(logo, ((sidebar.width - logo.width) // 2, 180))
sidebar.convert("RGB").save(OUTPUT / "wizard.png")
print(OUTPUT)
