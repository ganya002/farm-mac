# Opens a staged .blend and prints, per external datablock, its path and whether it resolves.
#   Blender --background --factory-startup staging/scene.blend --python verify_staged.py
import bpy, json, os

out = []
for coll, kind in ((bpy.data.images, "image"), (bpy.data.libraries, "library")):
    for block in coll:
        if not block.filepath or getattr(block, "library", None):
            continue
        full = bpy.path.abspath(block.filepath)
        if "<UDIM>" in full:
            exists = all(os.path.isfile(full.replace("<UDIM>", str(t.number))) for t in block.tiles)
        else:
            exists = os.path.isfile(full)
        out.append({"type": kind, "name": block.name, "path": block.filepath, "exists": exists})
print("FARM_VERIFY " + json.dumps(out))
