# Makes six small, colourful scenes for the screenshots in docs/screenshots, each with a rendered
# "<name>.blend.png" next to it: background Blender saves only a placeholder preview inside the
# .blend, so Demo mode shows these instead.
#   Blender --background --factory-startup --python make_demo_scenes.py -- <folder>
import bpy, math, os, random, sys

out = sys.argv[sys.argv.index("--") + 1]
os.makedirs(out, exist_ok=True)

SCENES = {
    "robot arm": ((0.93, 0.55, 0.45), (0.16, 0.18, 0.24), "arm"),
    "desert temple v3": ((0.95, 0.75, 0.45), (0.98, 0.86, 0.70), "temple"),
    "forest_scene": ((0.35, 0.65, 0.40), (0.75, 0.88, 0.95), "forest"),
    "headphones product": ((0.85, 0.30, 0.38), (0.96, 0.92, 0.90), "product"),
    "space station final": ((0.70, 0.75, 0.85), (0.05, 0.06, 0.12), "station"),
    "my room": ((0.90, 0.60, 0.55), (0.98, 0.93, 0.88), "room"),
}


def material(color):
    m = bpy.data.materials.new("m")
    m.diffuse_color = (*color, 1)
    return m


def add(kind, location, scale, color, rotation=(0, 0, 0)):
    getattr(bpy.ops.mesh, "primitive_%s_add" % kind)(location=location, rotation=rotation)
    ob = bpy.context.object
    ob.scale = scale
    ob.data.materials.append(material(color))
    return ob


def shade(color, factor):
    return tuple(min(1, c * factor) for c in color)


for name, (main, sky, kind) in SCENES.items():
    random.seed(name)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    shading = scene.display.shading
    shading.light, shading.color_type = "STUDIO", "MATERIAL"
    shading.show_shadows, shading.show_cavity = True, True
    world = bpy.data.worlds.new("w")
    world.color = sky
    scene.world = world
    add("plane", (0, 0, 0), (12, 12, 1), shade(sky, 0.85))
    if kind == "arm":
        add("cylinder", (0, 0, 0.3), (1.2, 1.2, 0.3), shade(main, 0.6))
        add("cube", (0, 0, 1.5), (0.35, 0.35, 1.2), main, (0.3, 0, 0))
        add("cube", (0, 0.9, 2.9), (0.3, 0.3, 1.0), main, (-0.9, 0, 0))
        add("uv_sphere", (0, 0.35, 2.4), (0.45, 0.45, 0.45), (0.9, 0.9, 0.92))
    elif kind == "temple":
        for i in range(6):
            add("cylinder", (-2.5 + i, 0, 1.5), (0.3, 0.3, 1.5), main)
        add("cube", (0, 0, 3.2), (3.4, 1.2, 0.2), shade(main, 0.9))
        add("cone", (0, 0, 3.9), (3.6, 1.4, 0.5), shade(main, 0.75), (0, 0, math.pi / 4))
    elif kind == "forest":
        for _ in range(14):
            x, y = random.uniform(-5, 5), random.uniform(-3, 4)
            h = random.uniform(1.2, 2.4)
            add("cylinder", (x, y, 0.4), (0.12, 0.12, 0.4), (0.45, 0.3, 0.2))
            add("cone", (x, y, 0.8 + h / 2), (0.7, 0.7, h / 2), shade(main, random.uniform(0.8, 1.2)))
    elif kind == "product":
        add("torus", (0, 0, 1.6), (1.3, 1.3, 1.3), main, (math.pi / 2, 0, 0))
        add("cylinder", (-1.3, 0, 0.9), (0.55, 0.55, 0.35), shade(main, 0.6), (0, math.pi / 2, 0))
        add("cylinder", (1.3, 0, 0.9), (0.55, 0.55, 0.35), shade(main, 0.6), (0, math.pi / 2, 0))
    elif kind == "station":
        add("torus", (0, 0, 2), (2.2, 2.2, 2.2), main, (1.1, 0.2, 0))
        add("cylinder", (0, 0, 2), (0.4, 0.4, 2.5), shade(main, 1.2), (1.1, 0.2, 0))
        add("cube", (3, 0, 2.6), (1.4, 0.05, 0.6), (0.25, 0.35, 0.8), (0.4, 0, 0.3))
        for _ in range(20):
            add("ico_sphere", (random.uniform(-6, 6), random.uniform(3, 8), random.uniform(0, 6)), (0.04,) * 3, (1, 1, 1))
    else:
        add("cube", (0, 2, 2), (4, 0.1, 2), shade(sky, 0.95))
        add("cube", (-1.5, 0.8, 0.45), (1.6, 0.9, 0.3), main)
        add("cube", (-1.5, 1.6, 0.9), (1.6, 0.15, 0.6), shade(main, 0.8))
        add("cylinder", (1.8, 0.5, 0.6), (0.5, 0.5, 0.6), (0.4, 0.55, 0.45))
        add("uv_sphere", (1.8, 0.5, 1.6), (0.6, 0.6, 0.6), (0.35, 0.6, 0.4))
    bpy.ops.object.empty_add(location=(0, 0.6, 1.3))
    target = bpy.context.object
    bpy.ops.object.camera_add(location=(9, -11, 6.5))
    camera = bpy.context.object
    camera.data.lens = 52
    camera.constraints.new("TRACK_TO").target = target
    scene.camera = camera
    path = os.path.join(out, name + ".blend")
    bpy.ops.wm.save_as_mainfile(filepath=path)
    scene.render.resolution_x, scene.render.resolution_y, scene.render.resolution_percentage = 640, 480, 100
    scene.render.filepath = path + ".png"
    bpy.ops.render.render(write_still=True)
