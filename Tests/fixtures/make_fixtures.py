# Builds small test scenes for collect.py. Run with Blender:
#   Blender --background --factory-startup --python make_fixtures.py -- <work dir> <spotlight dir> <tag>
# <work dir>/project/scene.blend uses:
#   - an image at an absolute path outside the project (<work dir>/outside/abs_tex.png)
#   - an image whose saved path is gone; the file now lives in <spotlight dir> (found by Spotlight)
#   - a UDIM image (2 tiles), an image sequence (3 frames), a linked library, a missing image
import bpy, os, sys

work, spot, tag = sys.argv[sys.argv.index("--") + 1:][:3]
project = os.path.join(work, "project")


def png(path, size=4):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img = bpy.data.images.new(os.path.basename(path), size, size)
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)


png(os.path.join(work, "outside", "abs_tex.png"))
png(os.path.join(spot, "moved_%s.png" % tag))
png(os.path.join(spot, "older", "copy", "moved_%s.png" % tag))  # decoy, farther from the project
for tile in (1001, 1002):
    png(os.path.join(project, "udim", "udim_tex.%d.png" % tile))
for frame in (1, 2, 3):
    png(os.path.join(project, "seq", "frame_%04d.png" % frame))

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.mesh.primitive_cube_add()
bpy.context.object.name = "LibCube"
os.makedirs(os.path.join(project, "lib"), exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(project, "lib", "lib.blend"))

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(project, "scene.blend"))


def keep(img):
    img.use_fake_user = True
    return img


keep(bpy.data.images.load(os.path.join(work, "outside", "abs_tex.png"))).filepath = os.path.join(work, "outside", "abs_tex.png")
moved = keep(bpy.data.images.new("moved", 4, 4))
moved.source = "FILE"
moved.filepath = "//old_place/moved_%s.png" % tag
udim = keep(bpy.data.images.load(os.path.join(project, "udim", "udim_tex.1001.png")))
udim.source = "TILED"
udim.filepath = "//udim/udim_tex.<UDIM>.png"
seq = keep(bpy.data.images.load(os.path.join(project, "seq", "frame_0001.png")))
seq.source = "SEQUENCE"
seq.filepath = "//seq/frame_0001.png"
gone = keep(bpy.data.images.new("gone", 4, 4))
gone.source = "FILE"
gone.filepath = "//nowhere/gone_%s.png" % tag

with bpy.data.libraries.load(os.path.join(project, "lib", "lib.blend"), link=True, relative=True) as (src, dst):
    dst.objects = ["LibCube"]
for ob in dst.objects:
    bpy.context.scene.collection.objects.link(ob)

bpy.ops.wm.save_as_mainfile(filepath=os.path.join(project, "scene.blend"), relative_remap=False)
print("FIXTURE", [(i.name, i.source, i.filepath) for i in bpy.data.images], [l.filepath for l in bpy.data.libraries])
