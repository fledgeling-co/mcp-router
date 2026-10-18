"""Generate the three logo PNGs the MSIX manifest references.

WHY THESE ARE GENERATED AND NOT DRAWN. MakeAppx refuses to pack a manifest whose referenced assets
are absent, so without them there is no package and DEF-073 stays open on a technicality. These are
placeholders and this file says so rather than letting three anonymous PNGs read as artwork
somebody approved: `design/marketing-src/` holds the real marks, and swapping them in is a design
decision that belongs to whoever owns that directory.

Written with no dependencies - a hand-assembled PNG of one solid colour - because adding Pillow to
this repository to produce three placeholder squares would be a dependency nobody wants and a
tool-availability failure on the next machine.
"""
import binascii
import io
import pathlib
import struct
import sys
import zlib

# The brand ink, taken from the marketing source rather than invented here, so a placeholder that
# does ship for a while at least ships in the product's own colour.
INK = (0x1B, 0x1D, 0x24)

SIZES = {
    "StoreLogo.png": 50,
    "Square150x150Logo.png": 150,
    "Square44x44Logo.png": 44,
}


def chunk(kind: bytes, payload: bytes) -> bytes:
    return (struct.pack(">I", len(payload)) + kind + payload
            + struct.pack(">I", binascii.crc32(kind + payload) & 0xFFFFFFFF))


def png(size: int) -> bytes:
    header = struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0)  # 8-bit truecolour
    row = bytes([0]) + bytes(INK) * size                          # filter 0, then the pixels
    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", header)
            + chunk(b"IDAT", zlib.compress(row * size, 9))
            + chunk(b"IEND", b""))


def main() -> int:
    out = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "app/windows/packaging/Assets")
    out.mkdir(parents=True, exist_ok=True)
    for name, size in sorted(SIZES.items()):
        path = out / name
        io.open(path, "wb").write(png(size))
        print("wrote %s (%dx%d)" % (path, size, size))
    print("These are PLACEHOLDERS. design/marketing-src/ holds the real marks; substituting them")
    print("is a design decision and is not this script's to make.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
