from PIL import Image, ImageDraw, ImageFilter, ImageChops, ImageFont

w, h = 1920, 1080
img = Image.new('RGB', (w, h))
draw = ImageDraw.Draw(img)

# Gradient from deep indigo (top-left) to teal (bottom-right)
for y in range(h):
    for x in range(w):
        t = (x + y) / (w + h)
        r = int(10 + (34 - 10) * t)
        g = int(15 + (211 - 15) * t)
        b = int(40 + (238 - 40) * t)
        draw.point((x, y), (r, g, b))

# Central glow overlay
glow = Image.new('L', (w, h), 0)
gd = ImageDraw.Draw(glow)
cx, cy = w // 2, h // 2
max_r = 500
for i in range(max_r, 0, -1):
    alpha = int(60 * (1 - i / max_r))
    gd.ellipse([cx - i, cy - i, cx + i, cy + i], fill=alpha)

glow = glow.filter(ImageFilter.GaussianBlur(40))
img = ImageChops.screen(img, Image.merge('RGB', (glow, glow, glow)))

# Text: "Rigel" in center
try:
    font_large = ImageFont.truetype("C:/Windows/Fonts/segoeuil.ttf", 96)
    font_small = ImageFont.truetype("C:/Windows/Fonts/segoeuil.ttf", 36)
except:
    font_large = ImageFont.load_default()
    font_small = ImageFont.load_default()

draw.text((cx, cy - 60), "Rigel", fill=(255, 255, 255, 180), font=font_large, anchor="mm")
draw.text((cx, cy + 50), "1 «Orion»", fill=(200, 230, 255, 140), font=font_small, anchor="mm")

import os
out = os.path.join(os.path.dirname(__file__) or '.', 'backgrounds', 'rigel.png')
os.makedirs(os.path.dirname(out), exist_ok=True)
img.save(out)
print(f"saved: {out}")