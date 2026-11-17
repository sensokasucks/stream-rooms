#!/usr/bin/env python3
"""Makes the Route 22 Cruise's filler billboards (textures/ad_*.png): made-up roadside ads shown
when the Billboard pictures set is empty and "Filler ads" is ticked (r22_billboards.gd). Every
business and slogan here is invented. Run it again only to change an ad; the results are committed.

    python3 rooms/route22/textures/make_ads.py
"""
import os
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
W, H = 1024, 448
BOLD = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
SERIF = "/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf"


def font(path, size):
    return ImageFont.truetype(path, size)


def centred(d, y, text, f, fill, x=W // 2):
    w = d.textlength(text, font=f)
    d.text((x - w / 2, y), text, font=f, fill=fill)


def sun_stripes(d, cx, cy, r, cols):
    for i, c in enumerate(cols):
        rr = r - i * r // len(cols)
        d.pieslice([cx - rr, cy - rr, cx + rr, cy + rr], 180, 360, fill=c)


def mesa(d, x0, base, w, h, col):
    d.polygon([(x0, base), (x0 + w * 0.15, base - h), (x0 + w * 0.85, base - h), (x0 + w, base)], fill=col)


# [file, background, painter]
def ad_rock_shop(d):
    d.rectangle([0, 0, W, H], fill=(40, 70, 110))
    for i in range(7):
        x = 80 + i * 130
        d.polygon([(x, 330), (x + 40, 250), (x + 80, 330)], fill=[(180, 90, 200), (90, 200, 220), (240, 200, 80)][i % 3])
    centred(d, 40, "ROCK SHOP", font(BOLD, 120), (250, 230, 120))
    centred(d, 175, "GEODES · FOSSILS · METEORITES", font(BOLD, 42), (240, 240, 240))
    centred(d, 360, "NEXT RIGHT", font(BOLD, 56), (250, 120, 80))


def ad_jerky(d):
    d.rectangle([0, 0, W, H], fill=(150, 40, 30))
    d.rectangle([20, 20, W - 20, H - 20], outline=(250, 220, 160), width=10)
    centred(d, 50, "HOT", font(SERIF, 70), (250, 220, 160))
    centred(d, 120, "JERKY", font(SERIF, 170), (255, 245, 220))
    centred(d, 320, "3 MILES · TURN AT THE WINDMILL", font(BOLD, 40), (250, 220, 160))


def ad_diner(d):
    d.rectangle([0, 0, W, H], fill=(235, 225, 200))
    sun_stripes(d, 830, 300, 170, [(240, 120, 60), (240, 170, 70), (240, 210, 110)])
    centred(d, 40, "ROADRUNNER", font(BOLD, 86), (200, 50, 50), x=420)
    centred(d, 140, "DINER", font(BOLD, 150), (40, 90, 120), x=420)
    centred(d, 330, "PIE · COFFEE · OPEN LATE", font(BOLD, 40), (60, 60, 60), x=420)


def ad_motel(d):
    d.rectangle([0, 0, W, H], fill=(20, 40, 60))
    mesa(d, 560, 448, 420, 160, (140, 60, 40))
    mesa(d, 700, 448, 300, 230, (170, 80, 50))
    centred(d, 40, "MESA MOTEL", font(BOLD, 110), (120, 230, 220), x=480)
    centred(d, 180, "POOL · COLOR TV · COOL ROOMS", font(BOLD, 40), (250, 250, 250), x=480)
    centred(d, 290, "VACANCY", font(BOLD, 80), (255, 90, 120), x=420)


def ad_arch(d):
    d.rectangle([0, 0, W, H], fill=(90, 160, 210))
    d.ellipse([560, 120, 1000, 600], fill=(190, 80, 40))
    d.ellipse([650, 230, 910, 600], fill=(90, 160, 210))
    d.rectangle([0, 400, W, H], fill=(200, 120, 70))
    centred(d, 50, "SEE THE", font(BOLD, 60), (255, 255, 255), x=310)
    centred(d, 125, "STONE ARCH", font(BOLD, 76), (255, 240, 200), x=300)
    centred(d, 260, "12 MI · SCENIC LOOP", font(BOLD, 44), (40, 40, 60), x=310)


def ad_candy(d):
    d.rectangle([0, 0, W, H], fill=(250, 200, 220))
    for i in range(5):
        x = 70 + i * 200
        d.rounded_rectangle([x, 250, x + 60, 400], 25, fill=(60, 150, 80))
        d.rounded_rectangle([x - 40, 300, x, 330], 12, fill=(60, 150, 80))
        d.rounded_rectangle([x + 60, 280, x + 100, 310], 12, fill=(60, 150, 80))
    centred(d, 40, "CACTUS CANDY", font(BOLD, 110), (200, 30, 90))
    centred(d, 170, "PRICKLY PEAR TAFFY · FREE TASTES", font(BOLD, 38), (80, 40, 60))


def ad_services(d):
    d.rectangle([0, 0, W, H], fill=(20, 110, 70))
    d.rectangle([16, 16, W - 16, H - 16], outline=(240, 240, 240), width=8)
    centred(d, 60, "GAS · FOOD · LODGING", font(BOLD, 70), (255, 255, 255))
    centred(d, 210, "NEXT SERVICES 42 MI", font(BOLD, 72), (255, 255, 255))
    centred(d, 330, "FILL UP NOW", font(BOLD, 48), (250, 220, 90))


def ad_canyon(d):
    d.rectangle([0, 0, W, H], fill=(250, 150, 60))
    sun_stripes(d, 512, 448, 380, [(240, 90, 50), (245, 120, 55), (250, 150, 60)])
    mesa(d, -20, 448, 360, 120, (90, 30, 30))
    mesa(d, 700, 448, 360, 150, (90, 30, 30))
    centred(d, 40, "HIDDEN CANYON", font(BOLD, 100), (255, 250, 230))
    centred(d, 160, "JEEP TOURS AT SUNSET", font(BOLD, 52), (60, 20, 20))


ADS = [("ad_rock_shop", ad_rock_shop), ("ad_jerky", ad_jerky), ("ad_diner", ad_diner), ("ad_motel", ad_motel),
       ("ad_arch", ad_arch), ("ad_candy", ad_candy), ("ad_services", ad_services), ("ad_canyon", ad_canyon)]

for name, paint in ADS:
    im = Image.new("RGB", (W, H))
    paint(ImageDraw.Draw(im))
    im.save(os.path.join(HERE, name + ".png"), optimize=True)
    print("wrote", name)
