# Shared kit for the UI's 3D-rendered pictures (premium icons: glossy cartoon plastic, a thick dark outline,
# a transparent background), rendered headless with Cycles:
#   blender -b -P tools/blender/<icon>.py -- <out.png> [size]
# Each icon script imports this, builds its objects with the helpers and calls render(out).
import bpy, math, sys
from mathutils import Vector

INK = (0.035, 0.04, 0.07)

def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)

def args():
    a = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    out = a[0] if a else 'icon.png'
    size = int(a[1]) if len(a) > 1 else 512
    return out, size

def srgb(c):
    return tuple((x / 255) ** 2.2 for x in c)

_mats = {}
def mat(color, rough=0.32, coat=0.6, emit=0.0):
    key = (tuple(color), rough, coat, emit)
    if key in _mats:
        return _mats[key]
    m = bpy.data.materials.new('m%d' % len(_mats))
    m.use_nodes = True
    b = m.node_tree.nodes['Principled BSDF']
    b.inputs['Base Color'].default_value = (*srgb(color), 1)
    b.inputs['Roughness'].default_value = rough
    b.inputs['Coat Weight'].default_value = coat
    b.inputs['Coat Roughness'].default_value = 0.08
    if emit:
        b.inputs['Emission Color'].default_value = (*srgb(color), 1)
        b.inputs['Emission Strength'].default_value = emit
    _mats[key] = m
    return m

_ink = None
def ink_mat():
    # the outline: an inverted hull, dark where its back faces show, see-through where its front faces would
    global _ink
    if _ink:
        return _ink
    m = bpy.data.materials.new('ink'); m.use_nodes = True
    nt = m.node_tree; nt.nodes.clear()
    out = nt.nodes.new('ShaderNodeOutputMaterial')
    geo = nt.nodes.new('ShaderNodeNewGeometry')
    em = nt.nodes.new('ShaderNodeEmission'); em.inputs['Color'].default_value = (*INK, 1)
    tr = nt.nodes.new('ShaderNodeBsdfTransparent')
    mix = nt.nodes.new('ShaderNodeMixShader')
    # only camera rays see it (else the hull shadows the object it wraps)
    lp = nt.nodes.new('ShaderNodeLightPath')
    notcam = nt.nodes.new('ShaderNodeMath'); notcam.operation = 'SUBTRACT'; notcam.inputs[0].default_value = 1
    nt.links.new(lp.outputs['Is Camera Ray'], notcam.inputs[1])
    either = nt.nodes.new('ShaderNodeMath'); either.operation = 'MAXIMUM'
    nt.links.new(geo.outputs['Backfacing'], either.inputs[0])
    nt.links.new(notcam.outputs[0], either.inputs[1])
    nt.links.new(either.outputs[0], mix.inputs['Fac'])
    nt.links.new(em.outputs[0], mix.inputs[1])
    nt.links.new(tr.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], out.inputs['Surface'])
    _ink = m
    return m

def finish(ob, material, outline=0.045, smooth=True, subsurf=0):
    ob.data.materials.clear()
    ob.data.materials.append(material)
    if subsurf:
        s = ob.modifiers.new('sub', 'SUBSURF'); s.levels = subsurf; s.render_levels = subsurf
    if smooth:
        for p in ob.data.polygons:
            p.use_smooth = True
    if outline:
        ob.data.materials.append(ink_mat())
        so = ob.modifiers.new('ink', 'SOLIDIFY')
        so.thickness = outline; so.offset = 1; so.use_flip_normals = True
        so.material_offset = 1; so.use_rim = False
    return ob

def sphere(loc, scale, material, outline=0.07, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=48, ring_count=24, radius=1, location=loc, rotation=rot)
    ob = bpy.context.object; ob.scale = scale
    return finish(ob, material, outline)

def rounded_box(loc, size, material, outline=0.045, rot=(0, 0, 0), bevel=0.3):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    ob = bpy.context.object; ob.scale = size
    bpy.ops.object.transform_apply(scale=True)
    bv = ob.modifiers.new('bev', 'BEVEL'); bv.width = bevel * min(size); bv.segments = 6; bv.limit_method = 'NONE'
    return finish(ob, material, outline)

def torus(loc, major, minor, material, outline=0.04, rot=(0, 0, 0), scale=(1, 1, 1)):
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor, major_segments=64, minor_segments=20, location=loc, rotation=rot)
    ob = bpy.context.object; ob.scale = scale
    return finish(ob, material, outline)

def prism(points, depth, loc, material, outline=0.035, rot=(0, 0, 0), bevel=0.03):
    # a flat 2D shape (points in x/z) extruded `depth` along y, softly bevelled
    me = bpy.data.meshes.new('prism')
    n = len(points)
    v = [(x, -depth / 2, z) for x, z in points] + [(x, depth / 2, z) for x, z in points]
    f = [tuple(range(n))[::-1], tuple(range(n, 2 * n))]
    for i in range(n):
        j = (i + 1) % n
        f.append((i, j, n + j, n + i))
    me.from_pydata(v, [], f); me.update()
    import bmesh
    bm = bmesh.new(); bm.from_mesh(me)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)  # outward, so the outline hull grows outward
    bmesh.ops.triangulate(bm, faces=[x for x in bm.faces if len(x.verts) > 4])  # (a concave cap: a bolt, a star)
    bm.to_mesh(me); bm.free()
    ob = bpy.data.objects.new('prism', me); bpy.context.scene.collection.objects.link(ob)
    ob.location = loc; ob.rotation_euler = rot
    if bevel:
        bv = ob.modifiers.new('bev', 'BEVEL'); bv.width = bevel; bv.segments = 4; bv.limit_method = 'NONE'
    return finish(ob, material, outline, smooth=False)

def light(kind, loc, energy, size=4, color=(1, 1, 1), target=(0, 0, 0)):
    d = bpy.data.lights.new(kind, kind); d.energy = energy; d.color = color
    if kind == 'AREA':
        d.size = size
    ob = bpy.data.objects.new(kind, d); bpy.context.scene.collection.objects.link(ob)
    ob.location = loc
    dirv = Vector(target) - Vector(loc)
    ob.rotation_euler = dirv.to_track_quat('-Z', 'Y').to_euler()
    return ob

def render(out, size=512, cam_loc=(0, -9, 1.2), target=(0, 0, 0.6), ortho=4.2, samples=96):
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    sc.cycles.device = 'CPU'; sc.cycles.samples = samples; sc.cycles.use_denoising = True
    sc.render.film_transparent = True
    sc.render.resolution_x = sc.render.resolution_y = size
    sc.render.image_settings.file_format = 'PNG'; sc.render.image_settings.color_mode = 'RGBA'
    sc.view_settings.view_transform = 'Standard'; sc.view_settings.look = 'None'
    sc.view_settings.exposure = 0.0
    w = bpy.data.worlds.new('w'); sc.world = w; w.use_nodes = True
    w.node_tree.nodes['Background'].inputs['Color'].default_value = (0.55, 0.6, 0.75, 1)
    w.node_tree.nodes['Background'].inputs['Strength'].default_value = 0.55
    cd = bpy.data.cameras.new('cam'); cd.type = 'ORTHO'; cd.ortho_scale = ortho
    cam = bpy.data.objects.new('cam', cd); sc.collection.objects.link(cam); sc.camera = cam
    cam.location = cam_loc
    cam.rotation_euler = (Vector(target) - Vector(cam_loc)).to_track_quat('-Z', 'Y').to_euler()
    light('AREA', (-4, -6, 7), 900, 6, target=target)
    light('AREA', (5, -3, 3), 300, 4, (0.85, 0.92, 1), target=target)
    light('AREA', (2, 6, 5), 600, 5, target=target)  # rim
    sc.render.filepath = out
    bpy.ops.render.render(write_still=True)
