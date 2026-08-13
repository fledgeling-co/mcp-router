# Hero artefact — source and provenance

`hero-manifold.png` is the source render behind `docs/assets/hero-manifold.{webp,jpg}`.

## How it was made

Generated with `media-gen-pro` → **GPT Image 2**, with `design/icon/icon-512.png`
passed as a reference image so the object matches the mark. Two candidates were
generated; this is the one that won. The other put the object flatter to camera,
so the amber branch read as a sticker on the surface rather than as light coming
from inside the hub.

Prompt:

> A single machined object photographed on a near-black surface: three thick
> frosted-glass channels curve in from the left and converge into one upright
> rounded pillar of the same glass, and from the right side of that pillar a
> single short bar glows warm amber from within while two other stubs beside it
> stay dark and unlit. Shot at a three-quarter angle from slightly above, with
> one hard raking key light from the upper left grazing across the glass so its
> edges catch a cool lilac highlight and the shadowed undersides fall away into
> black. The glass is thick and slightly cloudy like cast resin rather than
> clear, with visible internal depth, fine surface micro-texture and a soft
> contact shadow beneath it. Deep charcoal-violet background, no props, no text,
> generous empty space around the object.

Context passed alongside it constrained the palette to the icon's own tokens and
named the register: a product photograph of a physical instrument, not a glossy
CG icon, with exactly one warm element in frame.

## How the shipped assets were derived

```bash
python3 -c "
from PIL import Image
Image.open('hero-manifold.png').convert('RGB') \
     .crop((18, 150, 1268, 1100)).resize((1100, 836), Image.LANCZOS) \
     .save('hero-crop.png')"

cwebp -q 86 -sharp_yuv hero-crop.png -o ../../docs/assets/hero-manifold.webp
magick hero-crop.png -strip -quality 84 ../../docs/assets/hero-manifold.jpg
```

The crop trims the dead ground at the bottom of the frame and keeps the negative
space the composition already had around the object.

## Why it is framed rather than floated

The first attempt masked the image with a radial fade so the photographed ground
would dissolve into the page. That cannot work here: the object fills the frame,
so any fade reaching the edges eats the object with it. It ships in a hairline
frame instead, with the warm bloom drawn behind it in CSS so the lit branch still
emits past the edge.
