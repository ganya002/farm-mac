# Writes the preview image Blender saved inside a .blend as a PNG. Runs with Blender's own Python
# (it bundles `zstandard`, needed for compressed .blend files), without starting Blender:
#   <Blender.app>/Contents/Resources/<ver>/python/bin/python3 -I thumbnail.py <file.blend> <out.png>
# Exit 1 when the file has no preview. QuickLook would do this, but Blender's QuickLook extension
# is often not registered on a Mac.
import struct, sys, zlib

ZSTD_MAGIC = b"\x28\xb5\x2f\xfd"
LIMIT = 64 << 20  # the preview is one of the first blocks; never read further than this


def head(path):
    with open(path, "rb") as f:
        start = f.read(4)
        f.seek(0)
        if start == ZSTD_MAGIC:
            import zstandard
            return zstandard.ZstdDecompressor().stream_reader(f).read(LIMIT)
        return f.read(LIMIT)


def preview(data):
    if not data.startswith(b"BLENDER"):
        return None
    if data[7:9].isdigit():  # Blender 5: "BLENDER17-01v0502", 64-bit block headers
        size, little = int(data[7:9]), data[12:13] == b"v"
        layout, header = ("<" if little else ">") + "4siQqq", 32
        offset = size
        def block(at):
            code, _sdna, _old, length, _count = struct.unpack_from(layout, data, at)
            return code, length
    else:  # "BLENDER-v402": pointer size, endianness
        pointer = 8 if data[7:8] == b"-" else 4
        little = data[8:9] == b"v"
        layout = ("<" if little else ">") + "4si"
        header, offset = 16 + pointer, 12
        def block(at):
            code, length = struct.unpack_from(layout, data, at)
            return code, length
    order = "<" if little else ">"
    while offset + header <= len(data):
        code, length = block(offset)
        body = offset + header
        if code == b"TEST":
            width, height = struct.unpack_from(order + "ii", data, body)
            pixels = data[body + 8: body + 8 + width * height * 4]
            return (width, height, pixels) if width > 0 and height > 0 and len(pixels) == width * height * 4 else None
        if code in (b"ENDB", b"DNA1") or length < 0:
            return None
        offset = body + length
    return None


def png(width, height, rgba):
    rows = b"".join(b"\x00" + rgba[y * width * 4:(y + 1) * width * 4] for y in reversed(range(height)))  # stored bottom-up
    def chunk(kind, body):
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(rows, 6)) + chunk(b"IEND", b""))


if __name__ == "__main__":
    found = preview(head(sys.argv[1]))
    if not found:
        sys.exit(1)
    with open(sys.argv[2], "wb") as out:
        out.write(png(*found))
