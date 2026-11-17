# Collects every external file a .blend needs into a staging folder, then saves a copy of the
# .blend there with relative paths. The student's own file is never written.
#
#   Blender --background --factory-startup --disable-autoexec scene.blend --python collect.py -- <staging>
#
# Prints "FARM_PROGRESS <n> <m>" while it works and one "FARM_COLLECT <json>" line at the end.
# The datablock walk matches COMMON_PY in the farm site's blender.ts, plus UDIM tiles.
import bpy, json, os, re, shutil, subprocess, sys

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
STAGING = os.path.abspath(ARGS[0]) if ARGS else None
SOURCE = bpy.data.filepath
SOURCE_DIR = os.path.dirname(SOURCE)
HOME = os.path.expanduser("~")
SKIP_DIRS = (os.path.join(HOME, ".Trash") + os.sep, os.path.join(HOME, "Library") + os.sep)
TILE_TOKENS = {"<UDIM>": r"\d{4}", "<UVTILE>": r"u\d+_v\d+"}


def external_files():
    for img in bpy.data.images:
        if img.packed_file or img.source in {"GENERATED", "VIEWER"} or img.type in {"RENDER_RESULT", "COMPOSITING"}:
            continue
        yield "image", img
    for lib in bpy.data.libraries:
        if not getattr(lib, "packed_file", None):
            yield "library", lib
    for snd in bpy.data.sounds:
        if not snd.packed_file:
            yield "sound", snd
    for font in bpy.data.fonts:
        if not font.packed_file and font.filepath != "<builtin>":
            yield "font", font
    for clip in bpy.data.movieclips:
        yield "video", clip
    for vol in getattr(bpy.data, "volumes", []):
        if not vol.packed_file:
            yield "volume", vol
    for cache in bpy.data.cache_files:
        yield "cache", cache


def tile_pattern(name):
    """Regex for a UDIM name like wood.<UDIM>.png, or None."""
    for token in TILE_TOKENS:
        if token in name:
            parts = re.split("(" + "|".join(map(re.escape, TILE_TOKENS)) + ")", name)
            return re.compile("^" + "".join(TILE_TOKENS.get(p, re.escape(p)) for p in parts) + "$", re.I)
    return None


def sequence_pattern(name):
    """Regex for every frame of an image sequence, from one frame's name (shot_0001.png)."""
    match = re.match(r"^(.*?)(\d+)(\.[^.]+)?$", name)
    if not match:
        return None
    head, digits, ext = match.group(1), match.group(2), match.group(3) or ""
    return re.compile("^" + re.escape(head) + r"\d{%d,}" % len(digits) + re.escape(ext) + "$", re.I)


def is_sequence(kind, block):
    if kind in {"image", "video"} and getattr(block, "source", "") == "SEQUENCE":
        return True
    return kind == "volume" and getattr(block, "is_sequence", False)


def members(directory, name, kind, block):
    """Files on disk this datablock uses, given its folder and file name."""
    pattern = tile_pattern(name) or (sequence_pattern(name) if is_sequence(kind, block) else None)
    if pattern is None:
        path = os.path.join(directory, name)
        return [path] if os.path.isfile(path) else []
    try:
        return sorted(os.path.join(directory, n) for n in os.listdir(directory) if pattern.match(n))
    except OSError:
        return []


def search_name(name):
    """A file name Spotlight can look for: UDIM tokens become the first tile."""
    return name.replace("<UDIM>", "1001").replace("<UVTILE>", "u1_v1")


def distance(a, b):
    """How many folder steps separate two folders."""
    pa, pb = a.rstrip(os.sep).split(os.sep), b.rstrip(os.sep).split(os.sep)
    common = len(os.path.commonprefix([pa, pb]))
    return len(pa) + len(pb) - 2 * common


def spotlight(name):
    """Best match for a missing file: closest to the .blend's folder, then newest."""
    try:
        out = subprocess.run(["mdfind", "-name", name], capture_output=True, text=True, timeout=20).stdout
    except (OSError, subprocess.TimeoutExpired):
        return None
    hits = []
    for path in out.splitlines():
        if os.path.basename(path).lower() != name.lower() or not os.path.isfile(path):
            continue
        if path.startswith(SKIP_DIRS) or (STAGING and path.startswith(STAGING + os.sep)):
            continue
        hits.append(path)
    if not hits:
        return None
    return min(hits, key=lambda p: (distance(os.path.dirname(p), SOURCE_DIR), -os.path.getmtime(p)))


def progress(n, m):
    print("FARM_PROGRESS %d %d" % (n, m), flush=True)


def main():
    if not STAGING:
        raise SystemExit("usage: ... --python collect.py -- <staging folder>")
    os.makedirs(STAGING, exist_ok=True)
    blocks = [(kind, block) for kind, block in external_files() if block.filepath and block.library is None]
    # shortcut: datablocks that come from a linked library keep their paths; the library file itself
    # is copied but its own nested dependencies are not collected. Upgrade if a class uses nested links.
    items = []
    progress(0, len(blocks))
    for n, (kind, block) in enumerate(blocks, 1):
        original = block.filepath
        full = os.path.normpath(bpy.path.abspath(original))
        directory, name = os.path.split(full)
        item = {"type": kind, "block": block.name, "name": name, "original": original}
        files = members(directory, name, kind, block)
        if files:
            item["status"] = "collected"
        else:
            hit = spotlight(search_name(name))
            if hit:
                directory = os.path.dirname(hit)
                files = members(directory, name, kind, block) or [hit]
                item["status"] = "found"
                item["source"] = hit
            else:
                item["status"] = "missing"
        if files:
            target = os.path.join(STAGING, "textures", str(n))
            os.makedirs(target, exist_ok=True)
            for path in files:
                shutil.copy2(path, target)
            # Single files keep their own name (Spotlight's hit may differ in case); patterns keep the token.
            staged = name if len(files) > 1 or tile_pattern(name) else os.path.basename(files[0])
            block.filepath = "//textures/%d/%s" % (n, staged)
            item["staged"] = "textures/%d/%s" % (n, staged)
            item["files"] = len(files)
            item["bytes"] = sum(os.path.getsize(p) for p in files)
        items.append(item)
        progress(n, len(blocks))

    blend = os.path.basename(SOURCE) or "scene.blend"
    if blend.lower().endswith((".blend1", ".blend2")):
        blend = blend.rsplit(".", 1)[0] + ".blend"
    # copy=True keeps the open file pointing at the student's .blend; relative_remap=False leaves our
    # "//textures/..." paths exactly as set (they are relative to the staged copy).
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(STAGING, blend), copy=True, relative_remap=False, check_existing=False)
    report = {"blend": blend, "source": SOURCE, "items": items}
    print("FARM_COLLECT " + json.dumps(report), flush=True)


main()
