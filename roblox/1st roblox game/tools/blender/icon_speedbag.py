# The Free Gift's Speed bag: a glossy blue sack tied with a rope, a white lightning bolt on it, sneakers
# spilling out of its top.   blender -b -P tools/blender/icon_speedbag.py -- <out.png> [size]
import bpy, math, os, sys
sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import icon_kit as K

K.reset()
out, size = K.args()

BLUE = K.mat((40, 130, 245))
BLUE_DARK = K.mat((20, 70, 190))
BLUE_LIGHT = K.mat((90, 185, 255))
WHITE = K.mat((245, 248, 255))
CYAN = K.mat((60, 225, 255))
ROPE = K.mat((15, 45, 140), rough=0.5, coat=0.2)
SOLE = K.mat((240, 240, 245), rough=0.45)

# the sack
K.sphere((0, 0, 0.95), (1.35, 1.05, 1.12), BLUE, 0.09)
K.sphere((-0.35, -0.55, 1.35), (0.55, 0.35, 0.38), BLUE_LIGHT, 0)  # a soft highlight lobe on its upper left
# the gathered cloth over the tie, the tie and its two tassels
K.sphere((0, 0, 2.28), (0.88, 0.72, 0.26), BLUE, 0.07)
K.torus((0, 0, 2.0), 0.66, 0.17, ROPE, 0.06, scale=(1, 0.85, 1))
for side in (-1, 1):
    K.sphere((0.28 * side, -0.62, 1.55), (0.06, 0.06, 0.36), ROPE, 0.03, rot=(0, 0.35 * side, 0))
    K.sphere((0.4 * side, -0.66, 1.18), (0.13, 0.13, 0.13), ROPE, 0.035)

# the white lightning bolt on its front
bolt = [(0.12, 0.62), (-0.42, -0.06), (-0.04, -0.06), (-0.2, -0.66), (0.42, 0.1), (0.04, 0.1), (0.2, 0.62)]
K.prism(bolt, 0.18, (0, -1.0, 0.9), WHITE, 0.04, rot=(math.radians(-8), 0, math.radians(-6)))

# golden lightning bolts bursting out of its top, and a few sparkles around them
GOLD = K.mat((255, 205, 40), rough=0.25, coat=0.8)
BOLT = [(0.12, 0.62), (-0.42, -0.06), (-0.04, -0.06), (-0.2, -0.66), (0.42, 0.1), (0.04, 0.1), (0.2, 0.62)]
for x, y, z, tilt, k in ((-0.8, 0.35, 2.7, 32, 0.8), (0.8, 0.35, 2.7, -32, 0.8), (0.0, -0.1, 3.0, 0, 1.1)):
    b = K.prism(BOLT, 0.22, (x, y, z), GOLD, 0.07, rot=(0, math.radians(tilt), 0))
    b.scale = (k, k, k)
STAR = []
for i in range(8):
    r = 0.5 if i % 2 == 0 else 0.14
    a = math.pi / 2 + i * math.pi / 4
    STAR.append((r * math.cos(a), r * math.sin(a)))
for x, z, k in ((-1.3, 2.7, 0.75), (1.35, 2.35, 0.6), (1.15, 3.35, 0.5), (-1.05, 3.4, 0.45)):
    st = K.prism(STAR, 0.08, (x, -0.6, z), WHITE, 0.05, bevel=0.02)
    st.scale = (k, k, k)

K.render(out, size, cam_loc=(0, -9, 3.0), target=(0, 0, 1.7), ortho=4.6)
