# Renders the part lists of tools/seed_sheet.luau (Roblox Blocks, Wedges, Balls, Cylinders, ellipsoids) on a grass
# floor from the front, the zones left to right.
import bpy, json, math, sys
from mathutils import Matrix, Vector
args = sys.argv[sys.argv.index('--') + 1:]
items = json.load(open(args[0]))
out = args[1]
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene

def lin(c):
    return tuple(x ** 2.2 for x in c)

mats = {}
def mat(c):
    k = tuple(round(x, 3) for x in c)
    if k not in mats:
        m = bpy.data.materials.new(str(k)); m.use_nodes = True
        b = m.node_tree.nodes['Principled BSDF']
        b.inputs['Base Color'].default_value = (*lin(c), 1); b.inputs['Roughness'].default_value = 0.55
        mats[k] = m
    return mats[k]

def mesh_box():
    v = [(x, y, z) for x in (-.5, .5) for y in (-.5, .5) for z in (-.5, .5)]
    f = [(0,1,3,2),(4,6,7,5),(0,4,5,1),(2,3,7,6),(0,2,6,4),(1,5,7,3)]
    return v, f
def mesh_wedge():
    # roblox space: slope faces -Z/up, high edge at +Z. verts in roblox coords (x,y,z)
    v = [(-.5,-.5,-.5),(.5,-.5,-.5),(.5,-.5,.5),(-.5,-.5,.5),(-.5,.5,.5),(.5,.5,.5)]
    f = [(0,1,2,3),(0,4,5,1),(3,2,5,4),(0,3,4),(1,5,2)]
    return v, f
def mesh_cwedge():
    v = [(-.5,-.5,-.5),(.5,-.5,-.5),(.5,-.5,.5),(-.5,-.5,.5),(.5,.5,-.5)]
    f = [(0,1,2,3),(0,4,1),(1,4,2),(2,4,3),(3,4,0)]
    return v, f

R2B = Matrix(((1,0,0,0),(0,0,-1,0),(0,1,0,0),(0,0,0,1)))  # roblox (x,y,z) -> blender (x,-z,y)

def add(p, offset):
    s = p['shape']; sx, sy, sz = p['size']
    c = p['cf']
    rb = Matrix(((c[3],c[4],c[5],c[0]),(c[6],c[7],c[8],c[1]),(c[9],c[10],c[11],c[2]),(0,0,0,1)))
    if s in ('Ball', 'Egg', 'Cylinder'):
        if s == 'Ball':
            d = min(sx, sy, sz); sc = (d, d, d)
        else:
            sc = (sx, sy, sz)
        if s == 'Cylinder':
            d = min(sy, sz)
            bpy.ops.mesh.primitive_cylinder_add(vertices=24, radius=0.5, depth=1)
            ob = bpy.context.object
            local = Matrix.Rotation(math.pi/2, 4, 'Y') # blender cyl along Z -> along X
            sc = (sx, d, d)
        else:
            bpy.ops.mesh.primitive_uv_sphere_add(segments=24, ring_count=12, radius=0.5)
            ob = bpy.context.object; local = Matrix.Identity(4)
            bpy.ops.object.shade_smooth()
        ob.data.transform(local)
        S = Matrix.Diagonal((*sc, 1))
        ob.matrix_world = Matrix.Translation(offset) @ R2B @ rb @ S
    else:
        v, f = {'WedgePart': mesh_wedge, 'CornerWedgePart': mesh_cwedge}.get(s, mesh_box)()
        me = bpy.data.meshes.new('p'); me.from_pydata(v, [], f); me.update()
        ob = bpy.data.objects.new('p', me); scene.collection.objects.link(ob)
        S = Matrix.Diagonal((sx, sy, sz, 1))
        ob.matrix_world = Matrix.Translation(offset) @ R2B @ rb @ S
    ob.data.materials.append(mat(p['color']))

# normalise each design to ~2 high and lay out on a grid: columns = zones, rows = designs
GAP = 3.2
for it in items:
    ys = []
    for p in it['parts']:
        ys.append(p['cf'][1] + max(p['size']) / 2)
    off = Vector(((4 - it['col']) * GAP, (it['row'] - 1) * GAP * 1.1, 0))
    for p in it['parts']:
        add(p, off)

# fit: scale by bounds is fine (exported designs are ~1-2 studs); ground + light + camera
bpy.ops.mesh.primitive_plane_add(size=80, location=(0, 0, 0))
g = bpy.context.object; g.data.materials.append(mat((0.42, 0.75, 0.32)))
w = bpy.data.worlds.new('w'); scene.world = w; w.use_nodes = True
w.node_tree.nodes['Background'].inputs['Color'].default_value = (0.55, 0.75, 1.0, 1); w.node_tree.nodes['Background'].inputs['Strength'].default_value = 0.9
sun = bpy.data.lights.new('sun', 'SUN'); sun.energy = 3.2; sun.angle = 0.2
so = bpy.data.objects.new('sun', sun); scene.collection.objects.link(so); so.rotation_euler = (math.radians(50), 0, math.radians(-35))
cam = bpy.data.cameras.new('cam'); cam.type = 'ORTHO'; cam.ortho_scale = float(args[2]) if len(args) > 2 else 24
co = bpy.data.objects.new('cam', cam); scene.collection.objects.link(co); scene.camera = co
co.location = (0, 30, 17); co.rotation_euler = (math.radians(62), 0, math.radians(180))
co.location.y += 1.7; so.rotation_euler = (math.radians(50), 0, math.radians(145))
scene.render.engine = 'CYCLES'; scene.cycles.samples = 48; scene.cycles.device = 'CPU'
scene.render.resolution_x = 3200; scene.render.resolution_y = 1200
scene.view_settings.view_transform = 'Standard'
scene.render.filepath = out
bpy.ops.render.render(write_still=True)
