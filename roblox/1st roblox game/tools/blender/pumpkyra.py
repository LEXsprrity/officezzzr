# Pumpkyra, modelled in Blender from code: a ribbed jack-o'-lantern blossom (hollow, carved face, glowing
# inside), a crown of curled violet flame petals, a twisted thorny vine, five-lobed pumpkin leaves, curling
# tendrils with pumpkin buds, a lumpy mound with roots. Every part has its own painted texture (UV mapped).
# blender -b -P pumpkyra.py -- <out dir>
import bpy, bmesh, math, os, sys
import numpy as np
from mathutils import Vector

OUT = sys.argv[sys.argv.index('--') + 1]
os.makedirs(OUT, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
TAU = math.tau


def srgb(c):
    return np.array(c, dtype=np.float32) / 255.0


def lin(c):
    return tuple(float((x / 255.0) ** 2.2) for x in c)


def ramp(t, stops):
    t = np.clip(t, 0, 1)
    out = np.zeros(t.shape + (3,), dtype=np.float32)
    xs = [s[0] for s in stops]
    for ch in range(3):
        out[..., ch] = np.interp(t, xs, [s[1][ch] / 255.0 for s in stops])
    return out


def mix(a, b, t):
    t = np.clip(t, 0, 1)[..., None]
    return a * (1 - t) + b * t


def image(name, size, fn):
    w, h = size
    U, V = np.meshgrid((np.arange(w) + 0.5) / w, (np.arange(h) + 0.5) / h)
    rgb = np.clip(fn(U, V), 0, 1)
    rgba = np.concatenate([rgb, np.ones(rgb.shape[:2] + (1,), dtype=np.float32)], axis=2)
    img = bpy.data.images.new(name, w, h)
    img.pixels.foreach_set(rgba.astype(np.float32).ravel())
    img.filepath_raw = os.path.join(OUT, name + '.png')
    img.file_format = 'PNG'
    img.save()
    return img


def material(name, img=None, color=None, emit=0.0, rough=0.55, emit_color=None):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes['Principled BSDF']
    if img is not None:
        t = nt.nodes.new('ShaderNodeTexImage')
        t.image = img
        nt.links.new(t.outputs['Color'], b.inputs['Base Color'])
        if emit > 0:
            nt.links.new(t.outputs['Color'], b.inputs['Emission Color'])
    if color is not None:
        b.inputs['Base Color'].default_value = (*lin(color), 1)
    if emit_color is not None:
        b.inputs['Emission Color'].default_value = (*lin(emit_color), 1)
    b.inputs['Emission Strength'].default_value = emit
    b.inputs['Roughness'].default_value = rough
    return m


def make(name, verts, faces, fuv, mat, recalc=True):
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in verts], [], faces)
    uv = me.uv_layers.new(name='UVMap')
    for poly, uvl in zip(me.polygons, fuv):
        for li, q in zip(poly.loop_indices, uvl):
            uv.data[li].uv = q
    if recalc:
        bm = bmesh.new()
        bm.from_mesh(me)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(me)
        bm.free()
    me.shade_smooth()
    ob = bpy.data.objects.new(name, me)
    scene.collection.objects.link(ob)
    if mat:
        me.materials.append(mat)
    return ob


def tube(name, path, radius, n=20, rfn=None, mat=None, fixed=False, cap=True, uv_v=(0, 1)):
    rings = len(path)
    if fixed:
        Ns = [Vector((1, 0, 0))] * rings
        Bs = [Vector((0, 1, 0))] * rings
    else:
        T = [(path[min(i + 1, rings - 1)] - path[max(i - 1, 0)]).normalized() for i in range(rings)]
        n0 = T[0].orthogonal().normalized()
        Ns = [n0]
        for i in range(1, rings):
            v = Ns[-1] - T[i] * Ns[-1].dot(T[i])
            Ns.append((v if v.length > 1e-6 else T[i].orthogonal()).normalized())
        Bs = [T[i].cross(Ns[i]) for i in range(rings)]
    verts = []
    for i in range(rings):
        s = i / (rings - 1)
        for j in range(n):
            a = TAU * j / n
            r = radius[i] * (rfn(s, a) if rfn else 1)
            verts.append(path[i] + (Ns[i] * math.cos(a) + Bs[i] * math.sin(a)) * r)
    faces, fuv = [], []
    v0, v1 = uv_v
    for i in range(rings - 1):
        for j in range(n):
            j2 = (j + 1) % n
            faces.append((i * n + j, i * n + j2, (i + 1) * n + j2, (i + 1) * n + j))
            a, b = j / n, (j + 1) / n
            c, d = v0 + (v1 - v0) * i / (rings - 1), v0 + (v1 - v0) * (i + 1) / (rings - 1)
            fuv.append([(a, c), (b, c), (b, d), (a, d)])
    if cap:
        for end, i in ((0, 0), (1, rings - 1)):
            c = len(verts)
            verts.append(path[i])
            vv = v0 if end == 0 else v1
            for j in range(n):
                j2 = (j + 1) % n
                faces.append((c, i * n + j2, i * n + j) if end == 0 else (c, i * n + j, i * n + j2))
                fuv.append([(0.5, vv)] * 3)
    return make(name, verts, faces, fuv, mat)


def apply_mods(ob):
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg))
    ob.modifiers.clear()
    ob.data = me


def solidify(ob, t, offset=0.0):
    m = ob.modifiers.new('S', 'SOLIDIFY')
    m.thickness = t
    m.offset = offset
    apply_mods(ob)


def prism(name, poly, y0, y1):
    n = len(poly)
    verts = [Vector((x, y0, z)) for x, z in poly] + [Vector((x, y1, z)) for x, z in poly]
    faces = [tuple(range(n)), tuple(range(2 * n - 1, n - 1, -1))]
    for i in range(n):
        j = (i + 1) % n
        faces.append((i, j, n + j, n + i))
    return make(name, verts, faces, [[(0, 0)] * len(f) for f in faces], None)


def join(name, obs):
    bpy.ops.object.select_all(action='DESELECT')
    for o in obs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = obs[0]
    bpy.ops.object.join()
    obs[0].name = name
    obs[0].data.name = name
    return obs[0]


# ------------------------------------------------------------------------------------------------
# Textures
# ------------------------------------------------------------------------------------------------
def pumpkin_tex(U, V):
    rib = np.abs(np.cos(4 * TAU * U)) ** 0.45  # 1 on a lobe, 0 in a groove
    base = mix(srgb((150, 45, 5)), srgb((255, 138, 25)), rib)
    base = mix(base, srgb((255, 190, 80)), (rib ** 6) * 0.35)  # a sheen down each lobe
    streak = 0.06 * np.sin(TAU * (37 * U + 2 * V)) * rib
    base = base * (0.72 + 0.28 * np.clip(V * 1.6, 0, 1))[..., None] + streak[..., None]
    base = mix(base, srgb((105, 105, 30)), np.clip((V - 0.9) / 0.1, 0, 1) * 0.8)
    return mix(base, srgb((255, 205, 95)), (V < 0.02).astype(np.float32))  # (the carved walls' flesh)


def petal_tex(U, V):
    c = ramp(V, [(0, (45, 8, 90)), (0.4, (120, 30, 215)), (0.75, (205, 50, 225)), (1, (255, 150, 245))])
    edge = np.abs(U - 0.5) * 2
    c = mix(c, srgb((255, 160, 255)), edge ** 4 * 0.6)
    vein = np.exp(-((U - 0.5) / 0.04) ** 2) * (1 - V) * 0.5
    return mix(c, srgb((255, 120, 40)), vein)


def vine_tex(U, V):
    s = 0.5 + 0.5 * np.sin(TAU * (3 * U + 9 * V))
    c = mix(srgb((32, 48, 28)), srgb((85, 35, 110)), np.clip((s - 0.6) / 0.3, 0, 1))
    bark = 0.05 * np.sin(TAU * (8 * U + 1.5 * np.sin(TAU * 4 * V)))
    c = c + bark[..., None]
    return mix(c, srgb((20, 18, 25)), (V > 0.985).astype(np.float32) * 0.5)


def leaf_tex(U, V):
    x, y = U * 2.6, (V - 0.5) * 2.6  # leaf-local, the stem notch near (0.55, 0)
    dx, dy = x - 0.55, y
    d = np.hypot(dx, dy)
    a = np.arctan2(dy, dx)
    c = mix(srgb((125, 185, 60)), srgb((40, 85, 35)), np.clip(d / 1.9, 0, 1))
    c = mix(c, srgb((70, 35, 95)), np.clip((d - 1.3) / 0.8, 0, 1) * 0.7)
    vein = np.zeros_like(U)
    for va in (0, 1.25, -1.25, 2.5, -2.5):
        da = np.angle(np.exp(1j * (a - va)))
        vein = np.maximum(vein, np.exp(-(da * d / 0.035) ** 2) * (d > 0.05))
        for side in (-1, 1):  # side veins
            for k in (0.45, 0.85, 1.25):
                px, py = 0.55 + np.cos(va) * k, np.sin(va) * k
                sa = va + side * 0.75
                ex, ey = x - px, y - py
                along = ex * np.cos(sa) + ey * np.sin(sa)
                across = -ex * np.sin(sa) + ey * np.cos(sa)
                vein = np.maximum(vein, np.exp(-(across / 0.018) ** 2) * (along > 0) * (along < 0.4 - k * 0.12) * 0.7)
    return mix(c, srgb((180, 255, 90)), vein)


def soil_tex(U, V):
    n = 0.5 + 0.25 * np.sin(TAU * (7 * U + 3 * V)) + 0.25 * np.sin(TAU * (13 * V - 5 * U + 0.3))
    c = mix(srgb((40, 26, 36)), srgb((75, 48, 60)), n)
    crack = np.abs(np.sin(TAU * (3 * U + 0.5 * np.sin(TAU * 2 * V) + 0.2 * np.sin(TAU * 7 * U))))
    glow = np.clip(1 - crack / 0.035, 0, 1) * (np.sin(TAU * 4 * V) > -0.2)
    return mix(c, srgb((185, 90, 255)), glow)


T_PUMPKIN = image('Pumpkyra_Pumpkin', (1024, 512), pumpkin_tex)
T_PETAL = image('Pumpkyra_Petals', (256, 512), petal_tex)
T_VINE = image('Pumpkyra_Vine', (512, 512), vine_tex)
T_LEAF = image('Pumpkyra_Leaf', (1024, 1024), leaf_tex)
T_SOIL = image('Pumpkyra_Mound', (512, 512), soil_tex)

M_PUMPKIN = material('Pumpkin', T_PUMPKIN, rough=0.4)
M_PETAL = material('Petals', T_PETAL, emit=0.45, rough=0.3)
M_VINE = material('Vine', T_VINE, rough=0.7)
M_LEAF = material('Leaves', T_LEAF, emit=0.15, rough=0.5)
M_SOIL = material('Mound', T_SOIL, rough=0.9)
M_GLOW = material('Glow', color=(255, 190, 60), emit=18, emit_color=(255, 175, 50))

# ------------------------------------------------------------------------------------------------
# The jack-o'-lantern blossom
# ------------------------------------------------------------------------------------------------
HEAD_Z, W, H = 7.15, 3.0, 2.3


def pumpkin(name, center, w, h, n=72, rings=34):
    path, radius = [], []
    for i in range(rings):
        phi = 0.07 + (math.pi - 0.14) * i / (rings - 1)
        z = -math.cos(phi) * h / 2 * (1 - 0.3 * math.exp(-(math.sin(phi) / 0.38) ** 2))
        path.append(center + Vector((0, 0, z)))
        radius.append(math.sin(phi) * w / 2)
    rib = lambda s, a: 0.8 + 0.2 * abs(math.cos(4 * a)) ** 0.4
    return tube(name, path, radius, n=n, rfn=rib, mat=M_PUMPKIN, fixed=True, uv_v=(0.03, 1))


head = pumpkin('Pumpkin', Vector((0, 0, HEAD_Z)), W, H)
solidify(head, 0.12, -1)

eye = lambda cx, s: [(cx - 0.33, 0.12), (cx + 0.33, 0.12), (cx + s * 0.12, 0.62)]
cutters = [prism('cut', eye(-0.6, -1), -3, 0), prism('cut', eye(0.6, 1), -3, 0),
           prism('cut', [(-0.15, -0.12), (0.15, -0.12), (0, 0.15)], -3, 0)]
mouth = []
xs = [-1.05 + i * 0.105 for i in range(21)]
zc = lambda x: -0.5 + 0.22 * (x / 1.05) ** 2
top = []
for x in xs:
    top.append((x, zc(x) + (0.0 if abs(x) > 1.0 else 0.16)))
mouth = [(-1.05, zc(-1.05))]
for x in xs[1:-1]:
    zt = zc(x) + 0.17
    if -0.5 < x < -0.28 or 0.28 < x < 0.5:  # two fangs hanging down
        zt = zc(x) + 0.0
    mouth.append((x, zt))
mouth.append((1.05, zc(1.05)))
for x in reversed(xs[1:-1]):
    zb = zc(x) - 0.2
    if -0.12 < x < 0.12:  # one tooth pointing up
        zb = zc(x) - 0.04
    mouth.append((x, zb))
cutters.append(prism('cut', mouth, -3, 0))
for c in cutters:
    c.location.z = HEAD_Z
    bpy.context.view_layer.update()
cut = join('Cutter', cutters)
m = head.modifiers.new('B', 'BOOLEAN')
m.operation = 'DIFFERENCE'
m.solver = 'EXACT'
m.object = cut
apply_mods(head)
bpy.data.objects.remove(cut)

bpy.ops.mesh.primitive_uv_sphere_add(segments=32, ring_count=16, radius=1, location=(0, 0, HEAD_Z))
glow = bpy.context.object
glow.name = 'PumpkinGlow'
glow.scale = (W / 2 * 0.78, W / 2 * 0.78, H / 2 * 0.72)
bpy.ops.object.transform_apply(scale=True)
glow.data.materials.append(M_GLOW)

# the crown: seven curled flame petals around the top, a curly stem
TOP = Vector((0, 0, HEAD_Z + H * 0.36))
petals = []
for k in range(7):
    a = TAU * k / 7 + 0.2
    out = Vector((math.cos(a), math.sin(a), 0))
    side = Vector((-math.sin(a), math.cos(a), 0))
    big = 1.0 if k % 2 == 0 else 0.78
    N, verts, faces, fuv = 26, [], [], []
    for i in range(N):
        u = i / (N - 1)
        c = TOP + out * (0.5 + big * (1.4 * u - 0.95 * u ** 3)) + Vector((0, 0, big * 1.9 * u)) + side * 0.18 * math.sin(TAU * u) * big
        w = 0.5 * big * math.sin(math.pi * u) ** 0.75 * (1 - 0.35 * u) + 0.02 * (1 - u)
        cup = out * 0.12 * (1 - u)
        for e in (-1, 0, 1):
            verts.append(c + side * w * e + (cup if e == 0 else Vector()))
    for i in range(N - 1):
        for e in range(2):
            p = i * 3 + e
            faces.append((p, p + 1, p + 4, p + 3))
            fuv.append([(e / 2, i / (N - 1)), ((e + 1) / 2, i / (N - 1)), ((e + 1) / 2, (i + 1) / (N - 1)), (e / 2, (i + 1) / (N - 1))])
    ob = make('Petal', verts, faces, fuv, M_PETAL, recalc=False)
    solidify(ob, 0.06)
    petals.append(ob)
join('Petals', petals)

stem_path = [TOP + Vector((0.25 * math.sin(2.2 * t) * t, 0.05 * t, 0.9 * t + 0.25 * t * t)) for t in np.linspace(0, 1, 16)]
curl = [stem_path[-1] + Vector((0.18 * math.sin(3.5 * t) + 0.25 * t, 0, 0.18 * (1 - math.cos(3.5 * t)) * (1 - 0.5 * t))) for t in np.linspace(0, 1, 14)]
stem = tube('Stem', stem_path + curl[1:], [0.2 * (1 - 0.6 * i / 29) for i in range(29)], n=14, mat=M_VINE)

# ------------------------------------------------------------------------------------------------
# The vine, thorns, tendrils with buds, leaves, the mound and roots
# ------------------------------------------------------------------------------------------------
vine_pts, vine_r = [], []
for t in np.linspace(0, 1, 44):
    vine_pts.append(Vector((0.45 * math.sin(3.4 * t + 0.3) * (1 - 0.55 * t), 0.35 * math.sin(2.6 * t + 1.2) * (1 - 0.55 * t), 0.2 + t * (HEAD_Z - H * 0.42 - 0.2))))
    vine_r.append(0.33 * (1 - 0.48 * t) + 0.22 * math.exp(-t * 14))
vine_at = lambda t: vine_pts[int(round(t * 43))]
greens = [tube('Vine', vine_pts, vine_r, n=22, rfn=lambda s, a: 1 + 0.1 * math.cos(5 * a + 16 * s), mat=M_VINE)]

for k in range(8):
    t = 0.14 + 0.09 * k
    a = k * 2.4
    d = Vector((math.cos(a), math.sin(a), 0.35)).normalized()
    base = vine_at(t) + Vector((d.x, d.y, 0)) * vine_r[int(round(t * 43))] * 0.8
    pts = [base + d * 0.42 * s + Vector((0, 0, 0.12 * s * s)) for s in np.linspace(0, 1, 6)]
    greens.append(tube('Thorn', pts, [0.09 * (1 - s) + 0.004 for s in np.linspace(0, 1, 6)], n=8, mat=M_VINE, uv_v=(0.99, 1)))

buds = []
for side, t, a in ((1, 0.55, 0.35), (-1, 0.7, 3.6)):
    start = vine_at(t)
    out = Vector((math.cos(a), math.sin(a), 0))
    sd = Vector((-math.sin(a), math.cos(a), 0))
    pts = [start + out * 1.45 * s + Vector((0, 0, 0.55 * math.sin(1.15 * math.pi * s))) + sd * 0.25 * math.sin(TAU * s) for s in np.linspace(0, 1, 26)]
    greens.append(tube('Tendril', pts, [0.09 * (1 - 0.55 * s) for s in np.linspace(0, 1, 26)], n=10, mat=M_VINE))
    end = pts[-1]
    spiral = [end + out * (0.05 + 0.22 * s) + Vector((0, 0, 0)) + (sd * math.sin(5 * s) + Vector((0, 0, math.cos(5 * s) - 1))) * 0.2 * (1 - 0.6 * s) for s in np.linspace(0, 1, 22)]
    greens.append(tube('Curl', spiral, [0.045 * (1 - 0.7 * s) for s in np.linspace(0, 1, 22)], n=8, mat=M_VINE))
    hang = [end + Vector((0, 0, -0.32 * s)) for s in np.linspace(0, 1, 5)]
    greens.append(tube('BudStem', hang, [0.04] * 5, n=8, mat=M_VINE))
    buds.append(pumpkin('Bud', end + Vector((0, 0, -0.55)), 0.62, 0.5, n=40, rings=18))
join('Buds', buds)

leaves = []
for k, a in enumerate((0.5, 2.6, 4.5, 1.6, 3.9)):
    t = 0.08 + 0.07 * k if k < 3 else 0.38 + 0.12 * (k - 3)
    small = 1.0 if k < 3 else 0.55
    origin = vine_at(t)
    out = Vector((math.cos(a), math.sin(a), 0))
    sd = Vector((-math.sin(a), math.cos(a), 0))
    R0 = 1.18 * small
    rings, segs = 7, 72
    verts, faces, fuv = [], [], []
    center_local = (1.25 * small, 0.0)

    def place(x, y):
        z = -0.16 * (x - 0.5) ** 2 + 0.1 * y * y + 0.35 * x * 0.3
        return origin + out * (x + 0.15) + sd * y + Vector((0, 0, z + 0.15))

    verts.append(place(*center_local))
    uvs = [(1.25 / 2.6, 0.5)]
    for r in range(1, rings + 1):
        f = r / rings
        for j in range(segs):
            th = TAU * j / segs
            R = R0 * (0.6 + 0.4 * abs(math.cos(2.5 * th)) ** 0.7) * (1 + 0.035 * math.sin(28 * th))
            x = center_local[0] + math.cos(th) * R * f
            y = math.sin(th) * R * f
            verts.append(place(x, y))
            uvs.append((x / small / 2.6, y / small / 2.6 + 0.5))
    for j in range(segs):
        j2 = (j + 1) % segs
        faces.append((0, 1 + j, 1 + j2))
    for r in range(1, rings):
        for j in range(segs):
            j2 = (j + 1) % segs
            a0, a1 = 1 + (r - 1) * segs, 1 + r * segs
            faces.append((a0 + j, a1 + j, a1 + j2, a0 + j2))
    fuv = [[uvs[i] for i in f] for f in faces]
    ob = make('Leaf', verts, faces, fuv, M_LEAF, recalc=False)
    solidify(ob, 0.05)
    leaves.append(ob)
    pet = [origin + (out * 0.75 * small * s) + Vector((0, 0, 0.18 * math.sin(math.pi * s) + 0.15 * s)) for s in np.linspace(0, 1, 8)]
    greens.append(tube('Petiole', pet, [0.09] * 8, n=10, mat=M_VINE))
join('Leaves', leaves)
join('Vine', greens)

mound_path, mound_r = [], []
for i in range(14):
    s = i / 13
    mound_path.append(Vector((0, 0, 0.8 * s ** 0.85)))
    mound_r.append(2.0 * (1 - s ** 1.5) + 0.3)
mound = tube('Mound', mound_path, mound_r, n=48, rfn=lambda s, a: 1 + 0.07 * math.sin(5 * a + 1) + 0.04 * math.sin(11 * a), mat=M_SOIL, fixed=True)
roots = []
for k in range(5):
    a = TAU * k / 5 + 0.4
    d = Vector((math.cos(a), math.sin(a), 0))
    pts = [Vector((0, 0, 0.45)) + d * (0.3 + 1.9 * s) + Vector((0, 0, -0.5 * s ** 0.7 + 0.08 * math.sin(math.pi * s))) for s in np.linspace(0, 1, 14)]
    roots.append(tube('Root', pts, [0.16 * (1 - 0.8 * s) for s in np.linspace(0, 1, 14)], n=10, mat=M_VINE))
join('Mound', [mound] + roots)

# ------------------------------------------------------------------------------------------------
# Render (a Halloween night) and export
# ------------------------------------------------------------------------------------------------
parts = [o for o in scene.objects if o.type == 'MESH']
scene.render.engine = 'CYCLES'
scene.cycles.samples = int(os.environ.get("SAMPLES", "96"))
scene.cycles.use_denoising = True
scene.render.resolution_x, scene.render.resolution_y = 900, 1200
scene.view_settings.view_transform = 'AgX'
scene.view_settings.look = 'AgX - Punchy'

world = bpy.data.worlds.new('Night')
scene.world = world
world.use_nodes = True
world.node_tree.nodes['Background'].inputs['Color'].default_value = (0.012, 0.006, 0.03, 1)

bpy.ops.mesh.primitive_circle_add(vertices=64, radius=14, fill_type='NGON', location=(0, 0, -0.02))
ground = bpy.context.object
ground.data.materials.append(material('Ground', color=(45, 32, 55), rough=0.95))


def light(kind, loc, energy, color, size=1.0, target=(0, 0, 4.5)):
    data = bpy.data.lights.new(kind + 'L', kind)
    data.energy = energy
    data.color = lin(color)
    if kind == 'AREA':
        data.size = size
    elif kind == 'POINT':
        data.shadow_soft_size = size
    ob = bpy.data.objects.new(kind, data)
    scene.collection.objects.link(ob)
    ob.location = loc
    if kind != 'POINT':
        ob.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
    return ob


light('AREA', (-7, -9, 9), 1400, (210, 190, 255), 6)
light('AREA', (6, 7, 8), 900, (150, 255, 120), 4)
light('AREA', (7, -4, 2), 500, (255, 140, 60), 3)
light('POINT', (0, 0, HEAD_Z), 260, (255, 150, 40), 0.3)
light('POINT', (0, -1.2, 0.6), 120, (180, 80, 255), 0.5)

scene.use_nodes = True
nt = scene.node_tree
rl, comp = nt.nodes['Render Layers'], nt.nodes['Composite']
glare = nt.nodes.new('CompositorNodeGlare')
glare.glare_type = 'FOG_GLOW'
glare.quality = 'HIGH'
glare.threshold = 0.9
glare.size = 8
nt.links.new(rl.outputs['Image'], glare.inputs['Image'])
nt.links.new(glare.outputs['Image'], comp.inputs['Image'])

cam_data = bpy.data.cameras.new('Cam')
cam_data.lens = 50
cam = bpy.data.objects.new('Cam', cam_data)
scene.collection.objects.link(cam)
scene.camera = cam
for name, yaw, dist, h in (('front', -0.35, 19, 6.5), ('side', 0.9, 19, 8.5), ('close', -0.15, 9.5, 8.2)):
    target = Vector((0, 0, 4.9 if name != 'close' else 7.2))
    cam.location = target + Vector((math.sin(yaw) * dist, -math.cos(yaw) * dist, h - target.z))
    cam.rotation_euler = (target - cam.location).to_track_quat('-Z', 'Y').to_euler()
    scene.render.filepath = os.path.join(OUT, f'Pumpkyra_{name}.png')
    bpy.ops.render.render(write_still=True)

bpy.ops.object.select_all(action='DESELECT')
for o in parts:
    o.select_set(True)
bpy.ops.export_scene.fbx(filepath=os.path.join(OUT, 'Pumpkyra.fbx'), use_selection=True, object_types={'MESH'},
                         path_mode='COPY', embed_textures=True, apply_scale_options='FBX_SCALE_ALL',
                         axis_forward='-Z', axis_up='Y', mesh_smooth_type='FACE')
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, 'Pumpkyra.blend'))
for o in parts:
    print(o.name, len(o.data.polygons), 'faces')
