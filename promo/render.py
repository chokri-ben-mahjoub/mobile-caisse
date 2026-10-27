"""Renders the 9:16 promo (1080x1920 @30fps) and muxes it with audio.wav -> caisse_pos_promo.mp4"""
import json, math, os, subprocess, sys
from functools import lru_cache
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
TL = json.load(open(os.path.join(HERE, "timeline.json")))
CS, CE, TOTAL = TL["starts"], TL["ends"], TL["total"]
W, H, FPS = 1080, 1920, 30
FD = "C:/Windows/Fonts/"

NAVY = (9, 16, 56)
BLUE = (37, 99, 235)
INDIGO = (91, 52, 214)
CYAN = (34, 211, 238)
GREEN = (34, 197, 94)
AMBER = (251, 191, 36)
RED = (239, 68, 68)
PINK = (236, 72, 153)
WHITE = (255, 255, 255)
INK = (15, 23, 42)
MUTED = (100, 116, 139)
SOFT = (241, 245, 249)


# ---------------------------------------------------------------- helpers
def clamp(x, a=0.0, b=1.0):
    return max(a, min(b, x))


def prog(t, t0, d):
    return clamp((t - t0) / d)


def e_out(p):
    return 1 - (1 - p) ** 3


def e_back(p):
    c1 = 1.70158
    c3 = c1 + 1
    return 1 + c3 * (p - 1) ** 3 + c1 * (p - 1) ** 2


def e_io(p):
    return p * p * (3 - 2 * p)


@lru_cache(None)
def font(name, size):
    return ImageFont.truetype(FD + name, size)


BLK, BOLD, REG = "seguibl.ttf", "segoeuib.ttf", "segoeui.ttf"
SS = 2  # supersampling for sprites


def put(layer, spr, cx, cy, scale=1.0, alpha=1.0, anchor="c"):
    """alpha-composite sprite centred at (cx, cy) onto an RGBA layer (clipped)."""
    if alpha <= 0.003 or scale <= 0.01:
        return
    if scale != 1.0:
        spr = spr.resize((max(1, int(spr.width * scale)), max(1, int(spr.height * scale))), Image.BILINEAR)
    if alpha < 1:
        a = spr.getchannel("A").point(lambda v: int(v * alpha))
        spr = spr.copy()
        spr.putalpha(a)
    if anchor == "c":
        x, y = int(cx - spr.width / 2), int(cy - spr.height / 2)
    else:  # top-left
        x, y = int(cx), int(cy)
    x0, y0 = max(0, x), max(0, y)
    x1, y1 = min(layer.width, x + spr.width), min(layer.height, y + spr.height)
    if x1 <= x0 or y1 <= y0:
        return
    layer.alpha_composite(spr, dest=(x0, y0), source=(x0 - x, y0 - y))
    return


def _sprite(w, h):
    return Image.new("RGBA", (w * SS, h * SS), (0, 0, 0, 0))


def _down(img):
    return img.resize((img.width // SS, img.height // SS), Image.LANCZOS)


@lru_cache(None)
def rrect(w, h, r, fill, outline=None, ow=0, shadow=0):
    pad = shadow * 2 if shadow else 0
    im = _sprite(w + pad * 2, h + pad * 2)
    if shadow:
        sh = Image.new("RGBA", im.size, (0, 0, 0, 0))
        ImageDraw.Draw(sh).rounded_rectangle(
            [pad * SS, (pad + shadow * 0.6) * SS, (pad + w) * SS, (pad + h + shadow * 0.6) * SS], r * SS, fill=(0, 0, 20, 120))
        im.alpha_composite(sh.filter(ImageFilter.GaussianBlur(shadow * SS * 0.7)))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle([pad * SS, pad * SS, (pad + w) * SS - 1, (pad + h) * SS - 1], r * SS, fill=fill,
                        outline=outline, width=ow * SS)
    return _down(im)


@lru_cache(None)
def grad_rrect(w, h, r, c1, c2, vertical=False):
    g = Image.new("RGBA", (w, h))
    px = np.zeros((h, w, 4), np.uint8)
    n = h if vertical else w
    for i in range(n):
        f = i / max(1, n - 1)
        col = [int(c1[k] + (c2[k] - c1[k]) * f) for k in range(3)] + [255]
        if vertical:
            px[i, :, :] = col
        else:
            px[:, i, :] = col
    g = Image.fromarray(px, "RGBA")
    mask = _sprite(w, h)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, w * SS - 1, h * SS - 1], r * SS, fill=(255, 255, 255, 255))
    mask = _down(mask).getchannel("A")
    g.putalpha(mask)
    return g


@lru_cache(None)
def txt(text, name, size, fill, stroke=0, stroke_fill=None):
    f = font(name, size)
    l, t, r, b = f.getbbox(text, stroke_width=stroke)
    im = Image.new("RGBA", (r - l + 8 + stroke * 2, b - t + 8 + stroke * 2), (0, 0, 0, 0))
    ImageDraw.Draw(im).text((4 - l + stroke, 4 - t + stroke), text, font=f, fill=fill + (255,), stroke_width=stroke,
                            stroke_fill=(stroke_fill or fill) + (255,))
    return im


def text(layer, s, cx, cy, size, fill=WHITE, name=BLK, scale=1.0, alpha=1.0):
    put(layer, txt(s, name, size, fill), cx, cy, scale, alpha)


def pop(layer, spr, cx, cy, t, t0, d=0.45, rise=0, alpha_to=1.0):
    p = prog(t, t0, d)
    if p <= 0:
        return
    put(layer, spr, cx, cy + (1 - e_out(p)) * rise, max(0.01, e_back(p)), clamp(p * 3) * alpha_to)


@lru_cache(None)
def glow(size, color):
    im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(im).ellipse([size * 0.2, size * 0.2, size * 0.8, size * 0.8], fill=color + (255,))
    return im.filter(ImageFilter.GaussianBlur(size * 0.14))


@lru_cache(None)
def bg_base():
    y = np.linspace(0, 1, H)[:, None]
    top, mid, bot = np.array(NAVY), np.array((26, 46, 150)), np.array((76, 36, 170))
    f1 = np.clip(y * 2, 0, 1)
    f2 = np.clip(y * 2 - 1, 0, 1)
    col = np.where(y < 0.5, top + (mid - top) * f1, mid + (bot - mid) * f2)
    arr = np.repeat(col[:, None, :], W, axis=1).astype(np.uint8)
    return Image.fromarray(arr, "RGB")


def background(t):
    im = bg_base().copy().convert("RGBA")
    for i, (c, sz, ph, rx, ry) in enumerate([(CYAN, 1100, 0.0, 330, 380), (PINK, 1000, 2.1, 380, 300), (BLUE, 1300, 4.0, 250, 450)]):
        a = t * 0.45 + ph
        cx, cy = W / 2 + math.cos(a) * rx, 420 + 560 * (i % 2) + math.sin(a * 0.8) * ry
        g = glow(sz, c)
        g2 = g.copy()
        g2.putalpha(g.getchannel("A").point(lambda v: int(v * 0.42)))
        put(im, g2, cx, cy)
    # slow floating dots
    d = ImageDraw.Draw(im)
    rng = np.random.default_rng(3)
    for i in range(28):
        x = rng.uniform(0, W)
        sp = rng.uniform(25, 70)
        y = (rng.uniform(0, H) - t * sp) % H
        r = rng.uniform(2, 6)
        d.ellipse([x - r, y - r, x + r, y + r], fill=(255, 255, 255, int(rng.uniform(25, 70))))
    return im.convert("RGB")


# ------------------------------------------------------------------ icons
@lru_cache(None)
def icon(kind, size, color):
    s = size * SS
    im = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    c = color + (255,)
    lw = max(3, s // 12)
    u = s / 100
    if kind == "check":
        d.line([(22 * u, 54 * u), (42 * u, 74 * u), (80 * u, 30 * u)], fill=c, width=int(lw * 1.4), joint="curve")
    elif kind == "monitor":
        d.rounded_rectangle([10 * u, 15 * u, 90 * u, 65 * u], 6 * u, outline=c, width=lw)
        d.line([(50 * u, 65 * u), (50 * u, 82 * u)], fill=c, width=lw)
        d.line([(30 * u, 85 * u), (70 * u, 85 * u)], fill=c, width=lw)
    elif kind == "tablet":
        d.rounded_rectangle([20 * u, 8 * u, 80 * u, 92 * u], 9 * u, outline=c, width=lw)
        d.ellipse([44 * u, 78 * u, 56 * u, 90 * u], outline=c, width=max(2, lw // 2))
        d.ellipse([38 * u, 34 * u, 62 * u, 58 * u], outline=c, width=lw)
    elif kind == "wifi":
        for i, r in enumerate((42, 28, 14)):
            d.arc([50 * u - r * u, 78 * u - r * u, 50 * u + r * u, 78 * u + r * u], 225, 315, fill=c, width=lw)
        d.ellipse([44 * u, 72 * u, 56 * u, 84 * u], fill=c)
    elif kind == "print":
        d.rounded_rectangle([14 * u, 34 * u, 86 * u, 70 * u], 8 * u, outline=c, width=lw)
        d.rectangle([30 * u, 12 * u, 70 * u, 36 * u], outline=c, width=lw)
        d.rectangle([30 * u, 56 * u, 70 * u, 88 * u], fill=color + (255,))
    elif kind == "box":
        d.polygon([(50 * u, 10 * u), (88 * u, 28 * u), (88 * u, 72 * u), (50 * u, 90 * u), (12 * u, 72 * u), (12 * u, 28 * u)],
                  outline=c, width=lw)
        d.line([(12 * u, 28 * u), (50 * u, 46 * u), (88 * u, 28 * u)], fill=c, width=lw)
        d.line([(50 * u, 46 * u), (50 * u, 90 * u)], fill=c, width=lw)
    elif kind == "chart":
        for i, hh in enumerate((35, 55, 42, 78)):
            x = (14 + i * 21) * u
            d.rounded_rectangle([x, (88 - hh) * u, x + 14 * u, 88 * u], 3 * u, fill=c)
    elif kind == "return":
        d.arc([16 * u, 20 * u, 84 * u, 88 * u], 200, 520, fill=c, width=lw)
        d.polygon([(8 * u, 28 * u), (34 * u, 24 * u), (22 * u, 48 * u)], fill=c)
    elif kind == "lock":
        d.rounded_rectangle([20 * u, 44 * u, 80 * u, 90 * u], 9 * u, fill=c)
        d.arc([30 * u, 12 * u, 70 * u, 72 * u], 180, 360, fill=c, width=lw)
        d.line([(30 * u, 42 * u), (30 * u, 30 * u)], fill=c, width=lw)
        d.line([(70 * u, 42 * u), (70 * u, 30 * u)], fill=c, width=lw)
    elif kind == "user":
        d.ellipse([32 * u, 10 * u, 68 * u, 46 * u], fill=c)
        d.pieslice([14 * u, 54 * u, 86 * u, 126 * u], 180, 360, fill=c)
    elif kind == "cross":
        d.line([(24 * u, 24 * u), (76 * u, 76 * u)], fill=c, width=int(lw * 1.5))
        d.line([(76 * u, 24 * u), (24 * u, 76 * u)], fill=c, width=int(lw * 1.5))
    elif kind == "slash":
        d.line([(10 * u, 90 * u), (90 * u, 10 * u)], fill=c, width=int(lw * 1.5))
    return _down(im)


def badge(kind, size, fg, bg, slash=False):
    """rounded colour tile with an icon."""
    t = rrect(size, size, size // 4, bg).copy()
    ic = icon(kind, int(size * 0.62), fg)
    t.alpha_composite(ic, ((size - ic.width) // 2, (size - ic.height) // 2))
    if slash:
        sl = icon("slash", int(size * 0.78), RED)
        t.alpha_composite(sl, ((size - sl.width) // 2, (size - sl.height) // 2))
    return t


@lru_cache(None)
def logo(size):
    im = Image.open(os.path.join(HERE, "..", "assets", "icon", "icon.png")).convert("RGBA").resize((size * SS, size * SS), Image.LANCZOS)
    m = Image.new("L", im.size, 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, im.width - 1, im.height - 1], int(size * 0.23) * SS, fill=255)
    im.putalpha(m)
    sh = rrect(size, size, int(size * 0.23), (0, 0, 0, 0), shadow=36)
    out = Image.new("RGBA", (size + 144, size + 144), (0, 0, 0, 0))
    out.alpha_composite(sh, (0, 0))
    out.alpha_composite(_down(im), (72, 72))
    return out


# --------------------------------------------------------- phone UI mockup
PW, PH = 620, 1280
SW, SH = 568, 1228

ITEMS = [("Eau min\u00e9rale 1.5L", 0.8), ("Baguette", 0.25), ("Jus d'orange", 2.2), ("Chocolat noir", 1.5)]


def money(v):
    return f"{v:.3f} DT"


@lru_cache(None)
def phone_body():
    body = rrect(PW, PH, 84, (10, 14, 32, 255), outline=(70, 80, 120, 255), ow=4, shadow=40)
    return body


@lru_cache(None)
def screen_mask():
    m = _sprite(SW, SH)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, SW * SS - 1, SH * SS - 1], 62 * SS, fill=(255, 255, 255, 255))
    return _down(m).getchannel("A")


@lru_cache(None)
def barcode_img():
    rng = np.random.default_rng(11)
    im = Image.new("RGBA", (300, 110), (255, 255, 255, 255))
    d = ImageDraw.Draw(im)
    x = 8
    while x < 292:
        w = int(rng.choice([2, 3, 5, 6]))
        d.rectangle([x, 8, x + w - 1, 102], fill=(15, 23, 42, 255))
        x += w + int(rng.choice([3, 4, 6]))
    return im


def screen_cart(t):
    """t = seconds since the scanning started. Shows the scan + list screen."""
    s = Image.new("RGBA", (SW, SH), (241, 245, 249, 255))
    put(s, grad_rrect(SW, 190, 0, (37, 99, 235), (91, 52, 214)), 0, 0, anchor="tl")
    text(s, "Caisse", 40 + txt("Caisse", BLK, 44, WHITE).width / 2, 100, 44, WHITE)
    put(s, rrect(150, 46, 23, (255, 255, 255, 60)), SW - 110, 100)
    text(s, "En ligne  \u2022  Hors-ligne OK", 0, 0, 1, WHITE, alpha=0)  # keep cache warm-free
    text(s, "Hors-ligne OK", SW - 110, 100, 21, WHITE, BOLD)
    # viewfinder
    put(s, rrect(504, 270, 34, (15, 23, 42, 255), shadow=14), SW / 2, 285)
    bc = barcode_img()
    shake = math.sin(t * 9) * 3
    put(s, bc, SW / 2 + shake, 285, 1.2)
    corner = (255, 255, 255, 255)
    for (cx, cy, sx, sy) in [(70, 170, 1, 1), (SW - 70, 170, -1, 1), (70, 400, 1, -1), (SW - 70, 400, -1, -1)]:
        d = ImageDraw.Draw(s)
        d.line([(cx, cy + sy * 46), (cx, cy), (cx + sx * 46, cy)], fill=corner, width=7, joint="curve")
    # laser
    ly = 205 + (math.sin(t * 7) * 0.5 + 0.5) * 160
    s.alpha_composite(rrect(420, 8, 4, (239, 68, 68, 255)), (int(SW / 2 - 210), int(ly)))
    # beep flash on every new item
    flash = 0
    for i in range(len(ITEMS)):
        dt = t - (0.15 + i * 0.4)
        if 0 <= dt < 0.18:
            flash = max(flash, 1 - dt / 0.18)
    if flash > 0:
        ov = Image.new("RGBA", (504, 270), (255, 255, 255, int(140 * flash)))
        put(s, ov, SW / 2, 285)
    # list
    total = 0.0
    shown = 0
    for i, (n, p) in enumerate(ITEMS):
        t0 = 0.15 + i * 0.4
        pr = prog(t, t0, 0.35)
        if pr <= 0:
            continue
        total += p
        shown += 1
        y = 470 + i * 104
        card = rrect(504, 92, 24, (255, 255, 255, 255), shadow=10)
        put(s, card, SW / 2 + (1 - e_out(pr)) * 120, y + 46, 1, clamp(pr * 2.5))
        ox = (1 - e_out(pr)) * 120
        text(s, n, 56 + ox + txt(n, BOLD, 30, INK).width / 2 - 4, y + 34, 30, INK, BOLD, alpha=clamp(pr * 2.5))
        text(s, "1 \u00d7 " + money(p), 56 + ox + txt("1 \u00d7 " + money(p), REG, 22, MUTED).width / 2 - 4, y + 66, 22, MUTED, REG, alpha=clamp(pr * 2.5))
        text(s, money(p), SW - 56 - txt(money(p), BLK, 28, BLUE).width / 2 + ox, y + 46, 28, BLUE, BLK, alpha=clamp(pr * 2.5))
    # total banner
    put(s, grad_rrect(504, 170, 36, (37, 99, 235), (91, 52, 214)), SW / 2, SH - 130)
    text(s, "TOTAL", 40 + 30 + 8, SH - 190, 22, (200, 215, 255), BOLD)
    tv = txt(money(total), BLK, 56, WHITE)
    put(s, tv, 54 + tv.width / 2, SH - 140)
    put(s, rrect(170, 62, 31, (255, 255, 255, 255)), SW - 140, SH - 130)
    text(s, "Encaisser", SW - 140, SH - 132, 25, BLUE, BLK)
    return s


@lru_cache(None)
def ticket_img():
    w, h = 330, 470
    im = Image.new("RGBA", (w, h), (255, 255, 255, 255))
    d = ImageDraw.Draw(im)
    d.text((w / 2, 34), "MA BOUTIQUE", font=font(BOLD, 26), fill=INK, anchor="mm")
    d.text((w / 2, 64), "Ticket n\u00b0 128", font=font(REG, 19), fill=MUTED, anchor="mm")
    y = 100
    for n, p in ITEMS:
        d.text((24, y), n[:16], font=font(REG, 20), fill=INK)
        d.text((w - 24, y), f"{p:.3f}", font=font(REG, 20), fill=INK, anchor="ra")
        y += 34
    d.line([(24, y + 6), (w - 24, y + 6)], fill=(180, 190, 205), width=2)
    d.text((24, y + 22), "TOTAL", font=font(BLK, 26), fill=INK)
    d.text((w - 24, y + 22), "4.750 DT", font=font(BLK, 26), fill=INK, anchor="ra")
    d.text((w / 2, h - 56), "Merci de votre visite !", font=font(REG, 19), fill=MUTED, anchor="mm")
    for x in range(0, w, 22):  # torn edge
        d.polygon([(x, h), (x + 11, h - 12), (x + 22, h)], fill=(0, 0, 0, 0))
    return im


def screen_pay(t, paid_t):
    """t = seconds since the payment screen opened, paid_t = time of the green confirmation."""
    s = Image.new("RGBA", (SW, SH), (241, 245, 249, 255))
    put(s, grad_rrect(SW, 190, 0, (37, 99, 235), (91, 52, 214)), 0, 0, anchor="tl")
    text(s, "Paiement", 40 + txt("Paiement", BLK, 44, WHITE).width / 2, 100, 44, WHITE)
    put(s, grad_rrect(504, 230, 40, (37, 99, 235), (91, 52, 214)), SW / 2, 330)
    text(s, "\u00c0 PAYER", SW / 2, 250, 24, (200, 215, 255), BOLD)
    tv = txt("4.750 DT", BLK, 96, WHITE)
    put(s, tv, SW / 2, 340)
    for i, (lab, col, active) in enumerate([("Esp\u00e8ces", GREEN, True), ("QR code", BLUE, False)]):
        x = 150 + i * 268
        sel = active
        put(s, rrect(244, 150, 30, (255, 255, 255, 255), outline=(col + (255,)) if sel else (210, 218, 230, 255), ow=4 if sel else 2, shadow=10), x, 560)
        ic = badge("print" if False else ("user" if False else "chart"), 1, WHITE, col) if False else None
        put(s, rrect(64, 64, 20, col + (40,)), x, 530)
        put(s, icon("check" if active else "box", 40, col), x, 530)
        text(s, lab, x, 600, 28, INK, BLK)
    # received / change
    put(s, rrect(504, 150, 30, (255, 255, 255, 255), shadow=10), SW / 2, 760)
    text(s, "Re\u00e7u", 120, 725, 22, MUTED, BOLD)
    text(s, "5.000 DT", 140, 775, 40, INK, BLK)
    text(s, "\u00e0 rendre", SW - 120, 725, 22, MUTED, BOLD)
    text(s, "0.250 DT", SW - 150, 775, 40, GREEN, BLK)
    # confirm button / paid state
    pp = prog(t, paid_t, 0.5)
    if pp <= 0:
        put(s, grad_rrect(504, 100, 50, (34, 197, 94), (22, 163, 74)), SW / 2, 960)
        text(s, "Valider l'encaissement", SW / 2, 960, 32, WHITE, BLK)
    else:
        circ = rrect(220, 220, 110, GREEN + (255,), shadow=20)
        put(s, circ, SW / 2, 980, max(0.01, e_back(pp)))
        put(s, icon("check", 130, WHITE), SW / 2, 980, max(0.01, e_back(pp)))
        text(s, "Pay\u00e9 !", SW / 2, 1140, 54, GREEN, BLK, alpha=clamp(pp * 2))
    return s


def phone(layer, cx, cy, scale, screen, alpha=1.0, tilt_shift=0):
    p = Image.new("RGBA", (PW + 160, PH + 160), (0, 0, 0, 0))
    p.alpha_composite(phone_body(), (0, 0)) if phone_body().width == p.width else p.alpha_composite(phone_body(), (80 - 80, 80 - 80))
    sc = screen.copy()
    sc.putalpha(Image.fromarray((np.array(screen_mask()) * (np.array(sc.getchannel("A")) / 255)).astype(np.uint8)))
    ox = (p.width - SW) // 2
    oy = (p.height - SH) // 2
    p.alpha_composite(sc, (ox, oy))
    # notch
    nw = rrect(150, 34, 17, (10, 14, 32, 255))
    p.alpha_composite(nw, ((p.width - 150) // 2, oy + 16))
    put(layer, p, cx, cy, scale, alpha)


# ---------------------------------------------------------------- confetti
def confetti(layer, t, t0, cx, cy, n=70):
    if t < t0:
        return
    rng = np.random.default_rng(5)
    d = ImageDraw.Draw(layer)
    cols = [CYAN, AMBER, PINK, GREEN, WHITE, BLUE]
    dt = t - t0
    for i in range(n):
        ang = rng.uniform(-math.pi, 0)
        sp = rng.uniform(500, 1300)
        vx, vy = math.cos(ang) * sp, math.sin(ang) * sp
        x = cx + vx * dt
        y = cy + vy * dt + 1500 * dt * dt
        r = rng.uniform(7, 15)
        a = clamp(1 - dt / 1.8)
        col = cols[i % len(cols)] + (int(255 * a),)
        rot = rng.uniform(0, 6) + dt * rng.uniform(-9, 9)
        w, h = r, r * 0.5
        pts = [(x + math.cos(rot) * w - math.sin(rot) * h, y + math.sin(rot) * w + math.cos(rot) * h),
               (x - math.cos(rot) * w - math.sin(rot) * h, y - math.sin(rot) * w + math.cos(rot) * h),
               (x - math.cos(rot) * w + math.sin(rot) * h, y - math.sin(rot) * w - math.cos(rot) * h),
               (x + math.cos(rot) * w + math.sin(rot) * h, y + math.sin(rot) * w - math.cos(rot) * h)]
        d.polygon(pts, fill=col)


# ----------------------------------------------------------------- scenes
S1_START = 0.0
S2_START = TL["S2"]
S3_START = CS[4] - 0.3
S4_START = CS[7] - 0.3
S5_START = TL["S5"]
SCENES = [(S1_START, S2_START), (S2_START, S3_START), (S3_START, S4_START), (S4_START, S5_START), (S5_START, TOTAL)]


def scene1(L, t):
    # t since scene start
    pl = e_back(prog(t, 0.1, 0.7))
    put(L, logo(330), W / 2, 760 + math.sin(t * 2.2) * 10, max(0.01, pl), clamp(prog(t, 0.1, 0.3)))
    # halo ring
    rp = prog(t, 0.2, 1.2)
    if rp > 0:
        r = 220 + 360 * e_out(rp)
        d = ImageDraw.Draw(L)
        d.ellipse([W / 2 - r, 760 - r, W / 2 + r, 760 + r], outline=(255, 255, 255, int(120 * (1 - rp))), width=6)
    text(L, "VOTRE CAISSE", W / 2, 1110, 112, WHITE, BLK, scale=max(0.01, e_back(prog(t, CS[0] - 0.0 - 0.0, 0.5))) if t >= CS[0] else 0.01,
         alpha=prog(t, CS[0], 0.25))
    dp = prog(t, CS[0] + 1.25, 0.5)
    text(L, "dans votre poche.", W / 2, 1250, 98, CYAN, BLK, scale=max(0.01, e_back(dp)), alpha=clamp(dp * 3))
    # underline sweep
    up = e_out(prog(t, CS[0] + 1.6, 0.6))
    if up > 0:
        L.alpha_composite(rrect(int(560 * up) + 4, 10, 5, CYAN + (255,)), (int(W / 2 - 280), 1330))


def scene2(L, t):
    ts = t + S2_START  # absolute time
    # phone slides in
    pin = e_out(prog(t, 0.0, 0.7))
    cy = 1040 + (1 - pin) * 900
    scan_t = ts - (CS[1] - 0.0)
    # which screen?
    pay_open = CS[2] + 0.35
    if ts < pay_open:
        scr = screen_cart(max(0, ts - CS[1] + 0.15))
    else:
        sw = prog(ts, pay_open, 0.35)
        pay = screen_pay(ts - pay_open, CS[3] - pay_open + 0.15)
        scr = pay
        if sw < 1:  # quick cross-fade from list screen
            old = screen_cart(3)
            scr = Image.blend(old, pay, e_io(sw))
    ph_scale = 0.95 + 0.012 * math.sin(ts * 1.5)
    phone(L, W / 2, cy, ph_scale, scr)
    # captions
    caps = [(CS[1] - 0.12, "SCANNEZ", WHITE), (CS[2] - 0.1, "ENCAISSEZ", CYAN), (CS[3] - 0.1, "C'EST TERMIN\u00c9 !", GREEN)]
    cur = None
    for c in caps:
        if ts >= c[0]:
            cur = c
    if cur is None:
        text(L, "En 3 secondes", W / 2, 330, 80, WHITE, BLK, scale=max(0.01, e_back(prog(t, 0.3, 0.5))))
    else:
        p = prog(ts, cur[0], 0.35)
        col = cur[2]
        text(L, cur[1], W / 2, 300, 124, col, BLK, scale=max(0.01, 0.6 + 0.4 * e_back(p)), alpha=clamp(p * 3))
    # ticket slides out of the phone after payment
    tp = prog(ts, CS[3] + 0.55, 0.8)
    if tp > 0:
        put(L, rrect(10, 10, 5, (0, 0, 0, 0)), 0, 0)
        tk = ticket_img()
        put(L, tk, W / 2 + 330, 1380 - 150 * e_out(tp) + 40, 0.72, clamp(tp * 3))
    confetti(L, ts, CS[3] + 0.1, W / 2, 1000)


def scene3(L, t):
    ts = t + S3_START
    text(L, "ZERO CONTRAINTE", W / 2, 330, 84, WHITE, BLK, scale=max(0.01, e_back(prog(t, 0.15, 0.5))), alpha=prog(t, 0.15, 0.2))
    rows = [
        (CS[4], "monitor", "Pas d'ordinateur", "Votre t\u00e9l\u00e9phone suffit", True, RED),
        (CS[5], "tablet", "Pas d'\u00e9cran tactile", "Un simple smartphone Android", True, AMBER),
        (CS[6], "wifi", "Marche sans internet", "100 % hors-ligne, donn\u00e9es sur le t\u00e9l\u00e9phone", False, GREEN),
    ]
    for i, (t0, ic, title, sub, slash, col) in enumerate(rows):
        y = 640 + i * 360
        p = prog(ts, t0 - 0.25, 0.5)
        if p <= 0:
            continue
        side = -1 if i % 2 == 0 else 1
        x = W / 2 + side * (1 - e_out(p)) * 700
        card = rrect(940, 300, 56, (255, 255, 255, 255), shadow=26)
        put(L, card, x, y, 1.0, clamp(p * 2.5))
        sp = prog(ts, t0, 0.35)
        bd = badge(ic, 180, col, col + (35,) if False else (col[0], col[1], col[2], 38), slash=False)
        put(L, bd, x - 330, y, 1.0, clamp(p * 2.5))
        if slash and sp > 0:
            sl = icon("slash", 190, RED if col != RED else RED)
            put(L, sl, x - 330, y, max(0.01, sp), 1.0)
            # bold red bar growing
        if not slash:
            put(L, rrect(70, 70, 35, GREEN + (255,)), x - 330 + 62, y + 62, max(0.01, e_back(sp)), 1.0)
            put(L, icon("check", 46, WHITE), x - 330 + 62, y + 62, max(0.01, e_back(sp)), 1.0)
        tt = txt(title, BLK, 56, INK)
        put(L, tt, x - 200 + tt.width / 2, y - 32, 1.0, clamp(p * 2.5))
        st = txt(sub, BOLD, 30, MUTED)
        put(L, st, x - 200 + st.width / 2, y + 40, 1.0, clamp(p * 2.5))


FEATS = [
    ("print", "Ticket Bluetooth", "imprimante 58 mm", CYAN),
    ("box", "Stock + alertes", "jamais en rupture", AMBER),
    ("chart", "B\u00e9n\u00e9fice live", "chaque vente", GREEN),
    ("return", "Retours", "remboursement facile", PINK),
    ("lock", "Cl\u00f4ture de caisse", "rapport Z en 1 clic", BLUE),
    ("user", "\u00c9quipe & r\u00f4les", "acc\u00e8s par vendeur", INDIGO),
]


def scene4(L, t):
    ts = t + S4_START
    text(L, "TOUT EST INCLUS", W / 2, 320, 88, WHITE, BLK, scale=max(0.01, e_back(prog(t, 0.15, 0.5))), alpha=prog(t, 0.15, 0.2))
    span = CE[7] - CS[7] - 1.2
    for i, (ic, a, b, col) in enumerate(FEATS):
        t0 = CS[7] + 0.15 + i * span / 6
        p = prog(ts, t0, 0.45)
        if p <= 0:
            continue
        col_i, row_i = i % 2, i // 2
        x = 290 + col_i * 500
        y = 560 + row_i * 275
        card = rrect(470, 245, 46, (255, 255, 255, 255), shadow=22)
        put(L, card, x, y, max(0.01, e_back(p)), clamp(p * 3))
        sc = max(0.01, e_back(p))
        put(L, badge(ic, 96, col, (col[0], col[1], col[2], 45)) if False else badge(ic, 96, col, (col[0], col[1], col[2], 45)), x - 150 * sc + 0, y - 55 * sc, sc, clamp(p * 3))
        ta = txt(a, BLK, 38 if len(a) < 16 else 33, INK)
        put(L, ta, x, y + 25 * sc, sc, clamp(p * 3))
        tb = txt(b, BOLD, 25, MUTED)
        put(L, tb, x, y + 78 * sc, sc, clamp(p * 3))
    # profit mini chart
    cp = prog(ts, CE[7] - 1.6, 0.5)
    if cp > 0:
        card = rrect(970, 330, 56, (255, 255, 255, 255), shadow=26)
        put(L, card, W / 2, 1480, max(0.01, e_back(cp)), clamp(cp * 3))
        text(L, "B\u00e9n\u00e9fice du jour", 270, 1385, 36, INK, BLK, alpha=cp)
        big = txt("+ 218.400 DT", BLK, 64, GREEN)
        put(L, big, 270 + 0 + (big.width - 400) / 2 + 80 if False else 90 + big.width / 2 + 0, 1470, 1, cp)
        vals = [0.35, 0.55, 0.42, 0.7, 0.6, 0.85, 1.0]
        for i, v in enumerate(vals):
            gp = e_out(prog(ts, CE[7] - 1.4 + i * 0.07, 0.6))
            h = int(180 * v * gp) + 6
            x = 560 + i * 58
            L.alpha_composite(rrect(40, h, 12, (GREEN if i == 6 else (180, 205, 255)) + (255,)), (x, 1580 - h))


def scene5(L, t):
    ts = t + S5_START
    lp = e_back(prog(t, 0.05, 0.7))
    put(L, logo(300), W / 2, 700 + math.sin(t * 2) * 8, max(0.01, lp), clamp(prog(t, 0.05, 0.3)))
    text(L, "CAISSE POS", W / 2, 990, 136, WHITE, BLK, scale=max(0.01, e_back(prog(t, 0.25, 0.5))), alpha=prog(t, 0.25, 0.2))
    a = prog(ts, CS[9], 0.5)
    text(L, "Vendez plus vite.", W / 2, 1150, 92, CYAN, BLK, scale=max(0.01, e_back(a)), alpha=clamp(a * 3))
    b = prog(ts, CS[9] + 1.15, 0.5)
    text(L, "G\u00e9rez plus simple.", W / 2, 1260, 92, WHITE, BLK, scale=max(0.01, e_back(b)), alpha=clamp(b * 3))
    c = prog(ts, CS[9] + 2.0, 0.5)
    if c > 0:
        pulse = 1 + 0.035 * math.sin((ts - CS[9]) * 6)
        put(L, grad_rrect(700, 130, 65, (34, 211, 238), (37, 99, 235)), W / 2, 1450, max(0.01, e_back(c)) * pulse, clamp(c * 3))
        text(L, "Demandez votre d\u00e9mo", W / 2, 1448, 50, WHITE, BLK, scale=max(0.01, e_back(c)) * pulse, alpha=clamp(c * 3))
        text(L, "Disponible sur Android", W / 2, 1565, 34, (190, 205, 245), BOLD, alpha=c)
    confetti(L, ts, S5_START + 0.05, W / 2, 900, n=50)


FUNCS = [scene1, scene2, scene3, scene4, scene5]


def frame(t):
    base = background(t)
    for (a, b), fn in zip(SCENES, FUNCS):
        if not (a - 0.02 <= t < b + 0.0):
            continue
        L = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        lt = t - a
        fn(L, lt)
        fin = e_out(prog(lt, 0, 0.25)) if a > 0 else 1
        fout = 1 - prog(t, b - 0.2, 0.2) if b < TOTAL else 1
        k = fin * fout
        if k < 1:
            A = L.getchannel("A").point(lambda v: int(v * k))
            L.putalpha(A)
        yoff = int((1 - fin) * 60)
        base.paste(L, (0, yoff), L)
        # flash punch on scene entry
        if a > 0 and lt < 0.14:
            fl = Image.new("RGB", (W, H), (255, 255, 255))
            base = Image.blend(base, fl, 0.28 * (1 - lt / 0.14))
        break
    return base


def main():
    args = sys.argv[1:]
    if args and args[0] == "preview":
        times = [float(x) for x in args[1:]]
        out = os.path.join(HERE, "preview")
        os.makedirs(out, exist_ok=True)
        for x in times:
            frame(x).save(os.path.join(out, f"f_{x:05.2f}.png"))
        return
    import imageio_ffmpeg
    ff = imageio_ffmpeg.get_ffmpeg_exe()
    outp = os.path.join(HERE, "caisse_pos_promo.mp4")
    cmd = [ff, "-y", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}", "-r", str(FPS), "-i", "-",
           "-i", os.path.join(HERE, "audio.wav"), "-c:v", "libx264", "-preset", "medium", "-crf", "18",
           "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart", "-shortest", outp]
    p = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    n = int(TOTAL * FPS)
    for i in range(n):
        p.stdin.write(frame(i / FPS).tobytes())
        if i % 60 == 0:
            print(i, "/", n, flush=True)
    p.stdin.close()
    p.wait()
    print("done", outp)


if __name__ == "__main__":
    main()
