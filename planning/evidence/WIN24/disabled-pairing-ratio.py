"""Compute the WIN24 pairing: TextFillColorDisabled on ControlFillColorDisabled.

Both tokens are alpha over the ground, so each must be composited before any ratio is taken.
Values read 2026-08-30 from
microsoft/microsoft-ui-xaml @ winui3/main, controls/dev/CommonStyles/Common_themeresources_any.xaml
"""


def srgb_lin(c):
    c = c / 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def lum(rgb):
    r, g, b = (srgb_lin(x) for x in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def ratio(a, b):
    la, lb = lum(a), lum(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def over(fg_rgb, alpha, bg_rgb):
    """Composite fg at alpha over bg."""
    return tuple(bg + (fg - bg) * alpha for fg, bg in zip(fg_rgb, bg_rgb))


def hexa(s):
    """#AARRGGBB -> (rgb, alpha)."""
    s = s.lstrip("#")
    a = int(s[0:2], 16) / 255.0
    return (int(s[2:4], 16), int(s[4:6], 16), int(s[6:8], 16)), a


CASES = [
    # appearance, ground, control fill token, text token
    ("dark",  (0x20, 0x20, 0x20), "#0BFFFFFF", "#5DFFFFFF"),
    ("light", (0xF3, 0xF3, 0xF3), "#4DF9F9F9", "#5C000000"),
]

print("appearance | fill composited | text composited | ratio")
for name, ground, fill_hex, text_hex in CASES:
    f_rgb, f_a = hexa(fill_hex)
    t_rgb, t_a = hexa(text_hex)
    fill = over(f_rgb, f_a, ground)              # control fill over the base ground
    text = over(t_rgb, t_a, fill)                # disabled label over that fill
    r = ratio(text, fill)
    print("%-9s | %-15s | %-15s | %.2f:1" % (
        name,
        "#%02X%02X%02X" % tuple(round(c) for c in fill),
        "#%02X%02X%02X" % tuple(round(c) for c in text),
        r))

# Control: the macOS twin section 3 already publishes at 2.94 dark / 2.62 light. Recomputed here
# so the method is shown to reproduce a number nobody is arguing about BEFORE it is trusted on a
# new one. Values read from DESIGN.md: `--t4` #6E6E76 / #9A9AA2 (line 162), `--f3` #FFF @5% dark
# and #000 @3% light (line 127) - alpha, so it composites over the ground exactly as the Windows
# tokens do - and `--ground` #1C1C1E dark / #FFF light.
#
# A first attempt at this control GUESSED the macOS hexes and produced 2.75 dark against a
# published 2.94. That mismatch is the whole reason the control is here: it caught the guess
# before the Windows figures were trusted, rather than after they were written into the design.
print()
print("control - macOS --t4 on --f3, section 3 publishes 2.94 dark / 2.62 light:")
for name, ground, t4, f3_rgb, f3_a in (
        ("dark",  (0x1C, 0x1C, 0x1E), (0x6E, 0x6E, 0x76), (255, 255, 255), 0.05),
        ("light", (0xFF, 0xFF, 0xFF), (0x9A, 0x9A, 0xA2), (0, 0, 0),       0.03)):
    f3 = over(f3_rgb, f3_a, ground)
    print("  %-5s %.2f:1  (fill %s)" % (
        name, ratio(t4, f3), "#%02X%02X%02X" % tuple(round(c) for c in f3)))
