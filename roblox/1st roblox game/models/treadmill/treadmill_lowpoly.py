"""
Low-poly treadmill for Roblox, generated in Blender.

How to use:
  1. Open Blender (3.0 or newer), go to the Scripting tab.
  2. Click "Open", pick this file (or paste it into a new text block).
  3. Press "Run Script" (Alt+P).

Result:
  - A "Treadmill" empty with 7 mesh parts under it, one per colour
    (frame, belt, rails, console, screen, grips, accents).
  - treadmill.fbx exported next to your saved .blend file
    (or to your Desktop / home folder if the .blend isn't saved yet).

Scale: 1 Blender unit = 1 Roblox stud. A Roblox character is about
5 studs tall, so the treadmill is ~7 studs long and ~4.5 studs tall.
"""

import bpy
import bmesh
import math
import os
from mathutils import Matrix, Vector

SEGMENTS = 8          # sides on every cylinder; lower = more low-poly
EXPORT_FBX = True


# ---------------------------------------------------------------- materials

def make_material(name, rgb, emission=0.0):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.diffuse_color = (*rgb, 1.0)  # colour in Solid viewport mode
    if bpy.app.version < (5, 0, 0):
        mat.use_nodes = True             # always on from Blender 5.0
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = (*rgb, 1.0)
        bsdf.inputs["Roughness"].default_value = 0.6
        if emission > 0:
            # input was renamed in Blender 4.0
            key = "Emission Color" if "Emission Color" in bsdf.inputs else "Emission"
            bsdf.inputs[key].default_value = (*rgb, 1.0)
            if "Emission Strength" in bsdf.inputs:
                bsdf.inputs["Emission Strength"].default_value = emission
    return mat


PARTS = {
    # part name: (colour, emission)
    "Frame":   ((0.55, 0.57, 0.60), 0.0),   # light grey metal
    "Belt":    ((0.03, 0.03, 0.03), 0.0),   # black rubber
    "Rails":   ((0.18, 0.19, 0.21), 0.0),   # dark grey plastic
    "Console": ((0.10, 0.11, 0.13), 0.0),   # dark console body
    "Screen":  ((0.10, 0.65, 1.00), 2.0),   # glowing blue display
    "Grips":   ((0.06, 0.06, 0.06), 0.0),   # foam handle grips
    "Accent":  ((0.90, 0.12, 0.10), 0.0),   # red safety key / buttons
}

bms = {name: bmesh.new() for name in PARTS}


# ---------------------------------------------------------------- shape helpers

def box(part, center, size, rot=None):
    """Axis-aligned box (optionally rotated about its centre)."""
    m = Matrix.Translation(Vector(center))
    if rot is not None:
        m = m @ rot
    m = m @ Matrix.Diagonal((*size, 1.0))
    bmesh.ops.create_cube(bms[part], size=1.0, matrix=m)


def cyl(part, p1, p2, radius, segments=SEGMENTS):
    """Cylinder running from point p1 to point p2."""
    p1, p2 = Vector(p1), Vector(p2)
    d = p2 - p1
    rot = d.to_track_quat("Z", "Y").to_matrix().to_4x4()
    m = Matrix.Translation((p1 + p2) / 2) @ rot
    bmesh.ops.create_cone(
        bms[part], cap_ends=True, cap_tris=False, segments=segments,
        radius1=radius, radius2=radius, depth=d.length, matrix=m,
    )


def prism_x(part, profile_yz, x0, x1):
    """Extrude a (y, z) outline along X from x0 to x1."""
    bm = bms[part]
    left = [bm.verts.new((x0, y, z)) for y, z in profile_yz]
    right = [bm.verts.new((x1, y, z)) for y, z in profile_yz]
    bm.faces.new(left)
    bm.faces.new(list(reversed(right)))
    n = len(profile_yz)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((left[i], left[j], right[j], right[i]))


# ---------------------------------------------------------------- model
# +Y is the front (console end), the runner faces +Y. Z is up.

# Base frame + feet
box("Frame", (0, -0.1, 0.35), (3.0, 6.8, 0.4))
for sx in (-1, 1):
    for y in (-3.1, 3.0):
        box("Rails", (sx * 1.25, y, 0.075), (0.4, 0.4, 0.15))

# Running belt and the two side step rails
box("Belt", (0, -0.35, 0.60), (2.2, 6.1, 0.10))
for sx in (-1, 1):
    box("Rails", (sx * 1.30, -0.35, 0.62), (0.40, 6.1, 0.14))

# Rear roller cap and front transport wheels
cyl("Rails", (-1.5, -3.45, 0.40), (1.5, -3.45, 0.40), 0.22)
for sx in (-1, 1):
    cyl("Rails", (sx * 1.40, 3.55, 0.18), (sx * 1.58, 3.55, 0.18), 0.16)

# Motor hood: sloped wedge at the front of the deck
prism_x("Frame",
        [(2.65, 0.30), (3.60, 0.30), (3.60, 1.20), (3.15, 1.20), (2.65, 0.80)],
        -1.5, 1.5)

# Uprights (lean slightly back toward the runner)
UP_BOT_Y, UP_TOP_Y, UP_BOT_Z, UP_TOP_Z = 3.30, 3.00, 1.10, 4.00

def upright_y(z):
    t = (z - UP_BOT_Z) / (UP_TOP_Z - UP_BOT_Z)
    return UP_BOT_Y + (UP_TOP_Y - UP_BOT_Y) * t

for sx in (-1, 1):
    cyl("Frame", (sx * 1.35, UP_BOT_Y, UP_BOT_Z), (sx * 1.35, UP_TOP_Y, UP_TOP_Z), 0.13)

# Console, tilted 30 degrees toward the runner
tilt = Matrix.Rotation(math.radians(30), 4, "X")
c_center = Vector((0, 2.95, 4.15))
box("Console", c_center, (3.2, 0.9, 0.45), tilt)

def on_console(local):
    """Convert a point in console-local space to world space."""
    return c_center + (tilt @ Vector(local).to_4d()).to_3d()

box("Screen", on_console((0, 0.05, 0.245)), (1.4, 0.5, 0.06), tilt)
for bx in (-1.2, -0.9, 0.9, 1.2):
    for by in (-0.15, 0.15):
        box("Accent", on_console((bx, by, 0.245)), (0.18, 0.14, 0.06), tilt)

# Safety key sticking out of the console's front edge
cyl("Accent", on_console((0, -0.45, 0)), on_console((0, -0.62, 0)), 0.09)

# Side handlebars with foam grips
H_Z = 3.30
for sx in (-1, 1):
    x = sx * 1.35
    start = (x, upright_y(H_Z), H_Z)
    cyl("Frame", start, (x, 1.60, H_Z), 0.09)
    cyl("Frame", (x, 1.60, H_Z), (x, 1.48, H_Z - 0.25), 0.09)   # bent end
    cyl("Grips", (x, 2.70, H_Z), (x, 1.75, H_Z), 0.12)

# Front crossbar with centre grip (heart-rate bar)
X_Z = 3.00
cyl("Frame", (-1.35, upright_y(X_Z), X_Z), (1.35, upright_y(X_Z), X_Z), 0.09)
cyl("Grips", (-0.7, upright_y(X_Z), X_Z), (0.7, upright_y(X_Z), X_Z), 0.12)


# ---------------------------------------------------------------- build objects

if bpy.context.object and bpy.context.object.mode != "OBJECT":
    bpy.ops.object.mode_set(mode="OBJECT")

# Remove a treadmill from a previous run so re-running doesn't stack copies
for ob in [o for o in bpy.data.objects if o.name.startswith("Treadmill")]:
    bpy.data.objects.remove(ob, do_unlink=True)

collection = bpy.context.scene.collection
root = bpy.data.objects.new("Treadmill", None)
root.empty_display_type = "PLAIN_AXES"
collection.objects.link(root)

total_tris = 0
for name, (rgb, emission) in PARTS.items():
    bm = bms[name]
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new("Treadmill_" + name)
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(make_material("Treadmill_" + name, rgb, emission))
    for poly in mesh.polygons:
        poly.use_smooth = False          # flat shading = low-poly look
        total_tris += len(poly.vertices) - 2
    obj = bpy.data.objects.new("Treadmill_" + name, mesh)
    collection.objects.link(obj)
    obj.parent = root

print(f"Treadmill built: {len(PARTS)} parts, ~{total_tris} triangles")


# ---------------------------------------------------------------- export

if EXPORT_FBX:
    if bpy.data.filepath:
        out_dir = os.path.dirname(bpy.data.filepath)
    else:
        desktop = os.path.join(os.path.expanduser("~"), "Desktop")
        out_dir = desktop if os.path.isdir(desktop) else os.path.expanduser("~")
    out_path = os.path.join(out_dir, "treadmill.fbx")

    bpy.ops.object.select_all(action="DESELECT")
    root.select_set(True)
    for child in root.children:
        child.select_set(True)

    bpy.ops.export_scene.fbx(
        filepath=out_path,
        use_selection=True,
        object_types={"EMPTY", "MESH"},
        mesh_smooth_type="FACE",
        apply_scale_options="FBX_SCALE_ALL",
        add_leaf_bones=False,
        bake_anim=False,
    )
    print("Exported:", out_path)
