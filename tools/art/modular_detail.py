# Executed by modular_build.py (shares its globals): the neutral body, hair, leather/ranger set, mage robe set,
# boots, gloves and head pieces. Everything is faceted (flat shaded) lofts, layered panels and chamfered blocks.
import math
from mathutils import Vector

M_Eye = mk_mat("M_Eye", (0.05, 0.04, 0.04), 0.4)
M_Hair = mk_mat("M_Hair", (0.14, 0.09, 0.06), 0.9)
M_Charcoal = mk_mat("M_Charcoal", (0.17, 0.16, 0.18), 0.9)
M_Moss = mk_mat("M_Moss", (0.20, 0.27, 0.13), 0.95)
M_Gold = mk_mat("M_Gold", (0.62, 0.48, 0.22), 0.45, 0.6)
M_Gem = mk_mat("M_Gem", (0.18, 0.55, 0.62), 0.25)
M_Stitch = mk_mat("M_Stitch", (0.36, 0.29, 0.20), 0.9)

JN = {b.name: b for b in rig.data.bones}
def hp(n):
    return Vector(JN[n].head_local)

def side_of(s):
    return "Left" if s > 0 else "Right"

PI = math.pi
FRONT = -PI / 2          # ring angle that faces -Y (the character's front) for vertical (Z) lofts
BACK = PI / 2

def skirt_w(top=0.96, bot=0.30, mx=0.7, split=0.5):
    """Hip-hung cloth: follows the legs more the lower it hangs, left/right by x."""
    def f(p):
        leg = smooth(top, bot, p.z) * mx
        sl = smooth(-0.12, 0.12, p.x)
        up = leg * (1.0 if p.z > split else 0.55)
        lo = leg - up
        return W(Hips=1 - leg, LeftUpperLeg=up * sl, RightUpperLeg=up * (1 - sl),
                 LeftLowerLeg=lo * sl, RightLowerLeg=lo * (1 - sl))
    return f

def trunk_w(z):
    if z < 1.0: return W(Hips=1)
    if z < 1.1: return W(Hips=0.5, Spine=0.5)
    if z < 1.3: return W(Spine=0.5, Chest=0.5)
    return W(Chest=1)

# ------------------------------------------------------------------ body
def leg_rings(s, infl=0.0):
    knee = Vector(P(s, 0.115, -0.018, 0.52)); ank = Vector(P(s, 0.125, 0.025, 0.105))
    up = (knee - Vector(P(s, 0.105, 0.0, 0.94))).normalized(); lo = (ank - knee).normalized()
    sd = side_of(s); d = infl
    return [
        Ring(P(s, 0.105, 0.0, 0.99), up, 0.085 + d, 0.09 + d, W(Hips=0.5, **{sd + "UpperLeg": 0.5})),
        Ring(P(s, 0.108, -0.005, 0.86), up, 0.082 + d, 0.086 + d, W(**{sd + "UpperLeg": 1})),
        Ring(P(s, 0.110, -0.010, 0.70), up, 0.072 + d, 0.076 + d, W(**{sd + "UpperLeg": 1})),
        Ring(tuple(knee), up, 0.058 + d, 0.062 + d, W(**{sd + "UpperLeg": 0.5, sd + "LowerLeg": 0.5})),
        Ring(P(s, 0.117, -0.005, 0.40), lo, 0.062 + d, 0.068 + d, W(**{sd + "LowerLeg": 1})),   # calf bulge
        Ring(P(s, 0.121, 0.012, 0.26), lo, 0.050 + d, 0.054 + d, W(**{sd + "LowerLeg": 1})),
        Ring(tuple(ank + Vector((0, 0, 0.03))), lo, 0.040 + d, 0.044 + d, W(**{sd + "LowerLeg": 0.5, sd + "Foot": 0.5})),
    ]

def foot_rings(s, infl=0.0, sole=0.0):
    sd = side_of(s); d = infl
    ax = Vector((0, -1, -0.05))
    return [
        Ring(P(s, 0.125, 0.065, 0.07 + sole), ax, 0.046 + d, 0.048 + d + sole, W(**{sd + "Foot": 1})),
        Ring(P(s, 0.125, 0.0, 0.058 + sole * 0.5), ax, 0.048 + d, 0.040 + d + sole, W(**{sd + "Foot": 1})),
        Ring(P(s, 0.128, -0.10, 0.04 + sole * 0.5), ax, 0.050 + d, 0.030 + d + sole,
             W(**{sd + "Foot": 0.5, sd + "Toes": 0.5})),
        Ring(P(s, 0.128, -0.19, 0.032 + sole * 0.5), ax, 0.038 + d, 0.020 + d + sole, W(**{sd + "Toes": 1})),
    ]

def arm_path(s):
    return (Vector(P(s, 0.205, 0.01, 1.465)), Vector(P(s, 0.41, 0.022, 1.26)),
            Vector(P(s, 0.584, -0.009, 1.076)), Vector(P(s, 0.652, -0.021, 1.004)))

def arm_rings(s, infl=0.0, radii=(0.052, 0.047, 0.041, 0.036, 0.030), flare=0.0, start=0):
    sh, el, wr, hd = arm_path(s)
    sd = side_of(s)
    a1 = (el - sh).normalized(); a2 = (wr - el).normalized()
    d = infl
    r = [
        Ring(sh.lerp(el, 0.05), a1, radii[0] + d, radii[0] + d, W(**{sd + "Shoulder": 0.4, sd + "UpperArm": 0.6})),
        Ring(sh.lerp(el, 0.3), a1, (radii[0] + radii[1]) / 2 + d, (radii[0] + radii[1]) / 2 + d, W(**{sd + "UpperArm": 1})),
        Ring(sh.lerp(el, 0.65), a1, radii[1] + d, radii[1] + d, W(**{sd + "UpperArm": 1})),
        Ring(el, (a1 + a2).normalized(), radii[2] + d, radii[2] + d, W(**{sd + "UpperArm": 0.5, sd + "LowerArm": 0.5})),
        Ring(el.lerp(wr, 0.3), a2, radii[3] + 0.006 + d + flare * 0.2, radii[3] + 0.006 + d + flare * 0.2, W(**{sd + "LowerArm": 1})),
        Ring(el.lerp(wr, 0.65), a2, radii[3] + d + flare * 0.5, radii[3] + d + flare * 0.5, W(**{sd + "LowerArm": 1})),
        Ring(wr, a2, radii[4] + d + flare, radii[4] + d + flare, W(**{sd + "LowerArm": 0.5, sd + "Hand": 0.5})),
    ]
    return r[start:]

def hand_frame(s):
    sh, el, wr, hd = arm_path(s)
    ax = (hd - wr).normalized()
    u, w = frame(ax)          # w ~ width direction (front/back), u ~ thickness
    return wr, wr + (hd - wr) * 1.3, ax, u, w

def hand_parts(bm, dl, s, infl=0.0, mat=0, finger_mat=None):
    """Palm + four fingers + thumb as small faceted lofts."""
    sd = side_of(s)
    wr, end, ax, u, w = hand_frame(s)
    d = infl
    Wh = W(**{sd + "Hand": 1})
    palm_end = wr + (end - wr) * 0.62
    loft(bm, dl, [Ring(wr, ax, 0.022 + d, 0.032 + d, Wh), Ring(wr.lerp(palm_end, 0.5), ax, 0.021 + d, 0.040 + d, Wh),
                  Ring(palm_end, ax, 0.018 + d, 0.038 + d, Wh)], n=6, cap1=True, mats=[mat, mat])
    fm = mat if finger_mat is None else finger_mat
    for k, off in enumerate((-0.027, -0.009, 0.009, 0.027)):
        base = palm_end + w * off
        ln = (0.040, 0.046, 0.044, 0.034)[k]
        # fingers curl slightly toward the palm side (-u), faceted as 4-sided prisms
        p0 = base; p1 = base + ax * (ln * 0.55) - u * 0.004; p2 = p1 + ax * (ln * 0.5) - u * 0.012
        rr = 0.0085 + d * 0.5
        loft(bm, dl, [Ring(p0, p1 - p0, rr, rr, Wh), Ring(p1, p2 - p0, rr * 0.92, rr * 0.92, Wh),
                      Ring(p2, p2 - p1, rr * 0.75, rr * 0.75, Wh)], n=4, cap1=True, mats=[fm, fm])
    t0 = wr.lerp(palm_end, 0.25) + w * 0.034 * (1 if s > 0 else 1) - u * 0.006
    t1 = t0 + ax * 0.026 + w * 0.020
    t2 = t1 + ax * 0.028 + w * 0.006
    rr = 0.0105 + d * 0.5
    loft(bm, dl, [Ring(t0, t1 - t0, rr, rr, Wh), Ring(t1, t2 - t0, rr * 0.9, rr * 0.9, Wh), Ring(t2, t2 - t1, rr * 0.7, rr * 0.7, Wh)],
         n=4, cap1=True, mats=[fm, fm])

def skin(bm, dl):
    Z = (0, 0, 1)
    def C(z, y=0.0):
        return (0, y, z)
    rings = [
        Ring(C(0.92), Z, 0.165, 0.105, W(Hips=1)),
        Ring(C(1.00), Z, 0.160, 0.100, W(Hips=0.7, Spine=0.3)),
        Ring(C(1.12), Z, 0.140, 0.095, W(Spine=1)),
        Ring(C(1.28), Z, 0.150, 0.100, W(Spine=0.3, Chest=0.7)),
        Ring(C(1.42), Z, 0.165, 0.105, W(Chest=1)),
        Ring(C(1.51), Z, 0.120, 0.085, W(Chest=1)),
        Ring(C(1.56), Z, 0.050, 0.052, W(Chest=0.5, Neck=0.5)),
        Ring(C(1.63), Z, 0.048, 0.050, W(Neck=0.5, Head=0.5)),
        Ring(C(1.655, -0.012), Z, 0.050, 0.070, W(Head=1)),    # chin underside
        Ring(C(1.675, -0.012), Z, 0.074, 0.090, W(Head=1)),    # jaw
        Ring(C(1.715, -0.006), Z, 0.087, 0.100, W(Head=1)),    # cheek
        Ring(C(1.765, -0.005), Z, 0.089, 0.104, W(Head=1)),    # brow
        Ring(C(1.815, -0.002), Z, 0.082, 0.098, W(Head=1)),    # forehead
        Ring(C(1.855, 0.0), Z, 0.064, 0.080, W(Head=1)),       # crown
        Ring(C(1.878, 0.005), Z, 0.030, 0.042, W(Head=1)),
    ]
    loft(bm, dl, rings, n=10, cap0=True, cap1=True, rot=PI / 10)
    box(bm, dl, (0, -0.108, 1.738), (0.024, 0.036, 0.062), W(Head=1))          # nose
    box(bm, dl, (0, -0.100, 1.700), (0.050, 0.022, 0.014), W(Head=1))          # upper lip
    box(bm, dl, (0, -0.102, 1.668), (0.040, 0.024, 0.030), W(Head=1))          # chin
    box(bm, dl, (0, -0.094, 1.777), (0.150, 0.030, 0.020), W(Head=1))          # brow ridge
    for sx in (1, -1):
        box(bm, dl, (sx * 0.037, -0.103, 1.757), (0.024, 0.012, 0.011), W(Head=1), mat=1)   # eyes
        box(bm, dl, (sx * 0.092, 0.012, 1.738), (0.014, 0.036, 0.050), W(Head=1))           # ears
        box(bm, dl, (sx * 0.075, -0.098, 1.690), (0.026, 0.020, 0.044), W(Head=1))          # cheekbone
    for s in (1, -1):
        loft(bm, dl, leg_rings(s), n=8, cap1=True)
        loft(bm, dl, foot_rings(s), n=6, cap1=True)
        loft(bm, dl, arm_rings(s), n=7)
        hand_parts(bm, dl, s)
build("BODY_Skin", [M_Skin, M_Eye], skin)

def hair(bm, dl):
    Z = (0, 0, 1); H = W(Head=1)
    def back_drop(depth):
        # hair falls lower at the sides and back, stays on the forehead at the front
        return lambda a: (1.0, -depth * max(0.0, math.sin(a)) - 0.4 * depth * abs(math.cos(a)) * (0.5 if math.sin(a) > -0.2 else 0))
    rings = [
        Ring((0, 0.0, 1.805), Z, 0.095, 0.112, H, back_drop(0.115)),
        Ring((0, 0.0, 1.835), Z, 0.096, 0.113, H, back_drop(0.05)),
        Ring((0, 0.0, 1.862), Z, 0.080, 0.097, H),
        Ring((0, 0.004, 1.885), Z, 0.050, 0.064, H),
        Ring((0, 0.006, 1.900), Z, 0.020, 0.028, H),
    ]
    loft(bm, dl, rings, n=12, cap1=True, mats=[0, 0, 0, 0], rot=PI / 12)
    for sx in (1, -1):   # sideburns
        box(bm, dl, (sx * 0.093, -0.050, 1.775), (0.016, 0.030, 0.060), H)
build("BODY_Hair", [M_Hair], hair)

def beard(bm, dl):
    H = W(Head=1); Z = (0, 0, 1)
    def tip(depth):
        return lambda a: (1.0, -depth * max(0.0, 1.0 - abs(a - FRONT) / 1.3))
    rings = [
        Ring((0, -0.005, 1.735), Z, 0.100, 0.114, H),
        Ring((0, -0.010, 1.700), Z, 0.099, 0.112, H),
        Ring((0, -0.014, 1.668), Z, 0.082, 0.100, H, tip(0.05)),
        Ring((0, -0.018, 1.640), Z, 0.050, 0.076, H, tip(0.11)),
    ]
    loft(bm, dl, rings, n=8, arc=(FRONT - 1.35, FRONT + 1.35), solidify=0.006)
build("BODY_Beard", [M_Hair], beard)

# ------------------------------------------------------------------ ranger leather set
def band(bm, dl, z, rx, ry, h, w, mat, rot=0.0, n=12, thick=0.008, weights=None):
    """A raised ring (belt, trim) around the torso."""
    Z = (0, 0, 1)
    loft(bm, dl, [Ring((0, 0, z - h / 2), Z, rx, ry, weights or w), Ring((0, 0, z + h / 2), Z, rx, ry, weights or w)],
         n=n, mats=[mat])

def chamfer_block(bm, dl, c, size, w, mat=0):
    """A block with its vertical edges chamfered (octagonal prism), for pouches and buckles."""
    hx, hy, hz = size[0] / 2, size[1] / 2, size[2] / 2
    k = min(hx, hy) * 0.45
    pts = [(-hx + k, -hy), (hx - k, -hy), (hx, -hy + k), (hx, hy - k), (hx - k, hy), (-hx + k, hy), (-hx, hy - k), (-hx, -hy + k)]
    lo = [bm.verts.new(Vector(c) + Vector((x, y, -hz))) for x, y in pts]
    hi = [bm.verts.new(Vector(c) + Vector((x, y, hz))) for x, y in pts]
    for v in lo + hi:
        for bn, wt in w.items():
            v[dl][BI[bn]] = wt
    for i in range(8):
        f = bm.faces.new((lo[i], lo[(i + 1) % 8], hi[(i + 1) % 8], hi[i])); f.material_index = mat
    f = bm.faces.new(hi); f.material_index = mat
    f = bm.faces.new(lo[::-1]); f.material_index = mat

def jerkin(bm, dl):
    Z = (0, 0, 1)
    sk = skirt_w(0.96, 0.78, 0.5)
    def seam(a):   # panel seams: alternating facets
        return (1.0 + 0.022 * (1 if int(round(a * 12 / PI)) % 2 == 0 else -1), 0.0)
    rings = [
        Ring((0, 0, 0.80), Z, 0.250, 0.176, sk, seam),
        Ring((0, 0, 0.90), Z, 0.240, 0.164, sk, seam),
        Ring((0, 0, 1.00), Z, 0.228, 0.150, W(Hips=0.8, Spine=0.2), seam),
        Ring((0, 0, 1.07), Z, 0.200, 0.140, W(Hips=0.3, Spine=0.7)),
        Ring((0, 0, 1.13), Z, 0.190, 0.138, W(Spine=1)),
        Ring((0, 0, 1.28), Z, 0.208, 0.150, W(Spine=0.3, Chest=0.7), seam),
        Ring((0, 0, 1.42), Z, 0.214, 0.150, W(Chest=1), seam),
        Ring((0, 0, 1.50), Z, 0.165, 0.114, W(Chest=1)),
        Ring((0, 0, 1.545), Z, 0.092, 0.082, W(Chest=0.6, Neck=0.4)),
    ]
    loft(bm, dl, rings, n=12, mats=[0, 0, 1, 1, 0, 0, 0, 0])
    # lacing down the front: stitched strip
    for z in (1.20, 1.26, 1.32, 1.38, 1.44):
        box(bm, dl, (0, -0.158, z), (0.060, 0.012, 0.008), W(Chest=1), mat=2)
    # hanging leather tassets: overlapping tabs around the hips, pointed at the bottom
    for k in range(7):
        a = FRONT + (k - 3) * 0.40
        c = math.cos(a); s_ = math.sin(a)
        def tab(a=a):
            return lambda aa: (1.0, -0.075 * (1.0 - abs(aa - a) / 0.22))
        loft(bm, dl, [Ring((0, 0, 0.93), Z, 0.250, 0.178, W(Hips=1), None),
                      Ring((0, 0, 0.84), Z, 0.268, 0.192, sk, None),
                      Ring((0, 0, 0.745), Z, 0.272, 0.196, sk, tab())],
             n=3, arc=(a - 0.22, a + 0.22), mats=[1, 1], solidify=0.007)
    # belt with buckle and two pouches
    loft(bm, dl, [Ring((0, 0, 1.025), Z, 0.222, 0.152, W(Hips=0.8, Spine=0.2)), Ring((0, 0, 1.085), Z, 0.200, 0.142, W(Hips=0.3, Spine=0.7))],
         n=12, mats=[1])
    chamfer_block(bm, dl, (0, -0.160, 1.055), (0.062, 0.016, 0.062), W(Hips=0.5, Spine=0.5), mat=3)
    chamfer_block(bm, dl, (0.205, -0.065, 0.985), (0.075, 0.095, 0.100), W(Hips=1), mat=1)
    chamfer_block(bm, dl, (-0.205, -0.080, 0.985), (0.070, 0.085, 0.080), W(Hips=1), mat=1)
    box(bm, dl, (0.205, -0.065, 1.030), (0.082, 0.102, 0.016), W(Hips=1), mat=2)      # pouch flap
    # shoulder straps and a diagonal bandolier with a buckle
    for sx in (1, -1):
        loft(bm, dl, [Ring((sx * 0.105, -0.075, 1.51), (0, 0, -1), 0.030, 0.008, W(Chest=1)),
                      Ring((sx * 0.130, -0.115, 1.42), (0, 0, -1), 0.030, 0.008, W(Chest=1))], n=4, mats=[1])
    path = []
    for i in range(6):
        t = i / 5
        z = 1.46 - 0.46 * t
        a = FRONT + 0.95 * (1 - 2 * t)
        r = 0.222 if z > 1.2 else 0.215
        path.append((Vector((math.cos(a) * (r * 1.01), math.sin(a) * (0.162 * 1.01), z))))
    rs = []
    for i, p in enumerate(path):
        ax = path[min(i + 1, 5)] - path[max(i - 1, 0)]
        rs.append(Ring(p, ax, 0.020, 0.010, W(Chest=1) if p.z > 1.2 else W(Spine=0.6, Chest=0.4)))
    loft(bm, dl, rs, n=4, mats=[1] * 5, cap0=True, cap1=True, rot=PI / 4)
    chamfer_block(bm, dl, path[3] + Vector((0, -0.012, 0)), (0.040, 0.012, 0.040), W(Chest=1), mat=3)
    # layered shoulder caps
    for s in (1, -1):
        sd = side_of(s)
        sh = hp(sd + "UpperArm"); a = (hp(sd + "LowerArm") - sh).normalized()
        for k, (off, rad) in enumerate(((0.0, 0.082), (0.045, 0.078), (0.085, 0.074))):
            c = sh + a * off + Vector((0, 0, 0.040 - 0.012 * k))
            loft(bm, dl, [Ring(c - a * 0.012, a, rad, rad * 0.96, W(**{sd + "Shoulder": 0.5, sd + "UpperArm": 0.5})),
                          Ring(c + a * 0.040, a, rad * 0.96, rad * 0.92, W(**{sd + "UpperArm": 1}))],
                 n=8, cap0=(k == 0), mats=[1])
    # collar: a wrapped moss scarf at the neck
    loft(bm, dl, [Ring((0, 0, 1.50), Z, 0.130, 0.100, W(Chest=1)), Ring((0, 0, 1.565), Z, 0.082, 0.075, W(Chest=0.5, Neck=0.5)),
                  Ring((0, 0, 1.625), Z, 0.078, 0.072, W(Neck=0.6, Head=0.4))], n=10, mats=[4, 4])
build("TOR_Leather", [M_LeatherBr, M_LeatherDk, M_Stitch, M_Gold, M_Moss], jerkin)

def gloves(bm, dl):
    for s in (1, -1):
        sd = side_of(s)
        cuff = arm_rings(s, infl=0.010, radii=(0, 0, 0, 0.044, 0.040), flare=0.012, start=4)
        loft(bm, dl, cuff, n=8, mats=[0, 0])
        # bracer straps
        for t in (0.35, 0.65):
            sh, el, wr, hd = arm_path(s)
            c = el.lerp(wr, 0.45 + 0.4 * (t - 0.35)); a = (wr - el).normalized()
            loft(bm, dl, [Ring(c - a * 0.012, a, 0.052, 0.052, W(**{sd + "LowerArm": 1})), Ring(c + a * 0.012, a, 0.052, 0.052, W(**{sd + "LowerArm": 1}))],
                 n=8, mats=[1])
        hand_parts(bm, dl, s, infl=0.010)
        wr, end, ax, u, w = hand_frame(s)
        box(bm, dl, wr.lerp(end, 0.45) + u * 0.020, (0.040, 0.075, 0.012), W(**{sd + "Hand": 1}), mat=1)   # knuckle plate
build("GLV_Leather", [M_LeatherBr, M_LeatherDk], gloves)

def boots_common(bm, dl, s, pointed=False, mats=(0, 1)):
    sd = side_of(s)
    knee = Vector(P(s, 0.115, -0.018, 0.52)); ank = Vector(P(s, 0.125, 0.025, 0.105))
    lo = (ank - knee).normalized()
    LL = W(**{sd + "LowerLeg": 1})
    # shaft with a folded-over cuff
    loft(bm, dl, [Ring(P(s, 0.116, -0.012, 0.455), lo, 0.092, 0.096, LL),     # cuff flare top
                  Ring(P(s, 0.116, -0.010, 0.420), lo, 0.088, 0.092, LL),
                  Ring(P(s, 0.117, -0.006, 0.405), lo, 0.072, 0.076, LL),     # fold
                  Ring(P(s, 0.120, 0.005, 0.32), lo, 0.068, 0.074, LL),
                  Ring(P(s, 0.121, 0.012, 0.22), lo, 0.057, 0.062, W(**{sd + "LowerLeg": 0.7, sd + "Foot": 0.3})),
                  Ring(tuple(ank + Vector((0, 0, 0.03))), lo, 0.056, 0.060, W(**{sd + "LowerLeg": 0.5, sd + "Foot": 0.5}))],
         n=8, mats=[mats[1], mats[1], mats[0], mats[0], mats[0]])
    # straps across the instep
    for z in (0.16, 0.23):
        loft(bm, dl, [Ring(P(s, 0.121, 0.012, z - 0.008), lo, 0.064, 0.068, W(**{sd + "LowerLeg": 0.5, sd + "Foot": 0.5})),
                      Ring(P(s, 0.121, 0.012, z + 0.008), lo, 0.064, 0.068, W(**{sd + "LowerLeg": 0.5, sd + "Foot": 0.5}))],
             n=8, mats=[mats[1]])
    fr = foot_rings(s, infl=0.010, sole=0.010)
    if pointed:
        ax = Vector((0, -1, -0.05))
        fr.append(Ring(P(s, 0.128, -0.255, 0.07), ax, 0.020, 0.014, W(**{sd + "Toes": 1})))
        fr.append(Ring(P(s, 0.128, -0.30, 0.115), ax, 0.010, 0.008, W(**{sd + "Toes": 1})))
    loft(bm, dl, fr, n=8, cap1=True, mats=[mats[0]] * (len(fr) - 1))
    # sole slab and heel block
    if not pointed:
        loft(bm, dl, [Ring(P(s, 0.125, 0.06, 0.012), (0, -1, 0), 0.052, 0.014, W(**{sd + "Foot": 1})),
                      Ring(P(s, 0.128, -0.12, 0.012), (0, -1, 0), 0.058, 0.014, W(**{sd + "Foot": 0.5, sd + "Toes": 0.5})),
                      Ring(P(s, 0.128, -0.20, 0.012), (0, -1, 0), 0.044, 0.012, W(**{sd + "Toes": 1}))], n=6, cap1=True, cap0=True, mats=[mats[1], mats[1]])

def boots(bm, dl):
    for s in (1, -1):
        boots_common(bm, dl, s)
build("BTS_Leather", [M_LeatherBr, M_LeatherDk], boots)

def sorcerer_boots(bm, dl):
    for s in (1, -1):
        boots_common(bm, dl, s, pointed=True, mats=(0, 1))
build("BTS_Sorcerer", [M_Charcoal, M_RobeTrim], sorcerer_boots)

# ------------------------------------------------------------------ mage set
def robe(bm, dl):
    Z = (0, 0, 1)
    sk = skirt_w(0.97, 0.30, 1.0, 0.5)
    def flutes(a):   # vertical folds
        return (1.0 + 0.030 * (1 if int(round(a * 16 / PI)) % 2 == 0 else -1), 0.0)
    def hem(a):      # pointed, uneven hem
        k = int(round(a * 16 / PI))
        return (1.0 + 0.030 * (1 if k % 2 == 0 else -1), 0.055 if k % 2 == 0 else 0.0)
    zs = [(1.555, 0.095, 0.085, W(Chest=0.6, Neck=0.4)), (1.50, 0.205, 0.145, W(Chest=1)), (1.42, 0.222, 0.155, W(Chest=1)),
          (1.30, 0.205, 0.145, W(Chest=0.7, Spine=0.3)), (1.18, 0.185, 0.134, W(Chest=0.3, Spine=0.7)), (1.10, 0.172, 0.126, W(Spine=1)),
          (1.03, 0.186, 0.134, W(Spine=0.4, Hips=0.6)), (0.95, 0.230, 0.172, sk), (0.80, 0.262, 0.215, sk),
          (0.62, 0.290, 0.265, sk), (0.46, 0.318, 0.295, sk), (0.30, 0.338, 0.322, sk), (0.17, 0.352, 0.338, sk), (0.08, 0.364, 0.350, sk)]
    rings = []
    for i, (z, rx, ry, w) in enumerate(zs):
        mod = flutes if 0.2 < z < 1.0 else None
        if z <= 0.08: mod = hem
        rings.append(Ring((0, 0, z), Z, rx, ry, w, mod))
    mats = [1, 0, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0]
    loft(bm, dl, rings, n=16, mats=mats)
    # hem trim band (a second slightly wider skirt strip)
    loft(bm, dl, [Ring((0, 0, 0.22), Z, 0.362, 0.350, sk, flutes), Ring((0, 0, 0.14), Z, 0.372, 0.360, sk, flutes), Ring((0, 0, 0.075), Z, 0.380, 0.368, sk, hem)],
         n=16, mats=[2, 2])
    # tabard panels (front and back) hanging from the shoulders, V-cut hem. They sit a clear 4-5 cm outside the
    # fluted robe (flutes are +-3%) so the two surfaces never coincide (no z-fighting) and the panel reads as a layer.
    def layer(off, ang, wid, mat, nseg, thick):
        def vhem(a_, ang=ang, wid=wid):
            return (1.0, -0.20 * (1.0 - abs(a_ - ang) / wid))
        rs = [(1.46, 0.230, 0.162, W(Chest=1), None), (1.18, 0.206, 0.150, W(Chest=0.5, Spine=0.5), None),
              (0.95, 0.250, 0.186, sk, None), (0.70, 0.292, 0.272, sk, None), (0.46, 0.328, 0.304, sk, vhem)]
        loft(bm, dl, [Ring((0, 0, z), Z, rx + off, ry + off, w, m) for z, rx, ry, w, m in rs],
             n=nseg, arc=(ang - wid, ang + wid) if nseg > 2 else (ang - 0.07, ang + 0.07), mats=[mat] * 4, solidify=thick)
    for ang in (FRONT, BACK):
        layer(0.045, ang, 0.60, 5, 6, 0.008)
        layer(0.058, ang, 0.07, 2, 2, 0.004)   # gold centre braid, proud of the panel
    # sleeves: bell sleeves with a lighter lining cuff
    for s in (1, -1):
        sl = arm_rings(s, infl=0.028, radii=(0.052, 0.050, 0.050, 0.056, 0.062), flare=0.06)
        loft(bm, dl, sl, n=10, mats=[0, 0, 0, 0, 0, 1])
        sd = side_of(s)
        sh, el, wr, hd = arm_path(s); a2 = (wr - el).normalized()
        loft(bm, dl, [Ring(wr + a2 * 0.01, a2, 0.118, 0.118, W(**{sd + "LowerArm": 0.5, sd + "Hand": 0.5})),
                      Ring(wr - a2 * 0.045, a2, 0.108, 0.108, W(**{sd + "LowerArm": 1}))], n=10, mats=[2])
    # belt, sash tails, pouch, scroll case and an amulet
    loft(bm, dl, [Ring((0, 0, 1.065), Z, 0.196, 0.140, W(Spine=0.5, Hips=0.5)), Ring((0, 0, 1.115), Z, 0.183, 0.130, W(Spine=1))],
         n=16, mats=[3])
    chamfer_block(bm, dl, (0, -0.146, 1.09), (0.058, 0.014, 0.058), W(Spine=1), mat=2)
    for sx in (-1, 1):
        def tail(a, sx=sx):
            return (1.0, 0.0)
        loft(bm, dl, [Ring((0, 0, 1.10), Z, 0.200, 0.146, W(Spine=1)), Ring((0, 0, 0.85), Z, 0.250, 0.190, sk), Ring((0, 0, 0.60), Z, 0.292, 0.268, sk),
                      Ring((0, 0, 0.42), Z, 0.328, 0.302, sk, lambda a, sx=sx: (1.0, -0.14 * (1.0 - abs(a - (FRONT + sx * 0.13)) / 0.075)))],
             n=2, arc=(FRONT + sx * 0.13 - 0.075, FRONT + sx * 0.13 + 0.075), mats=[3, 3, 3], solidify=0.008)
    chamfer_block(bm, dl, (0.215, -0.060, 0.99), (0.070, 0.090, 0.090), W(Hips=1), mat=3)
    loft(bm, dl, [Ring((-0.20, 0.10, 0.96), (1, 0, -0.25), 0.032, 0.032, W(Hips=1)), Ring((-0.36, 0.10, 1.02), (1, 0, -0.25), 0.032, 0.032, W(Hips=1))],
         n=6, cap0=True, cap1=True, mats=[3])
    ico = bmesh.ops.create_icosphere(bm, subdivisions=1, radius=0.036)
    for v in ico["verts"]:
        v.co += Vector((0, -0.160, 1.33))
        for bn, wt in W(Chest=1).items():
            v[dl][BI[bn]] = wt
    for f in set(f for v in ico["verts"] for f in v.link_faces):
        f.material_index = 4
    loft(bm, dl, [Ring((0, 0, 1.525), Z, 0.140, 0.116, W(Chest=1)), Ring((0, 0, 1.50), Z, 0.170, 0.140, W(Chest=1))], n=12, mats=[2])
build("ROBE_Mage", [M_Robe, M_RobeTrim, M_Gold, M_Sash, M_Gem, M_Charcoal], robe)

def mantle(bm, dl):
    Z = (0, 0, 1)
    def side_w(p):
        out = smooth(0.17, 0.30, abs(p.x))
        sd = "Left" if p.x > 0 else "Right"
        return W(Chest=1 - out * 0.6, **{sd + "Shoulder": out * 0.3, sd + "UpperArm": out * 0.3})
    def jag(a):
        k = int(round(a * 14 / PI))
        return (1.0, -0.055 if k % 2 == 0 else 0.0)
    rings = [Ring((0, 0, 1.565), Z, 0.118, 0.100, W(Chest=1)), Ring((0, 0, 1.52), Z, 0.230, 0.170, side_w),
             Ring((0, 0, 1.44), Z, 0.318, 0.220, side_w), Ring((0, 0, 1.36), Z, 0.352, 0.236, side_w, jag)]
    loft(bm, dl, rings, n=14, mats=[1, 0, 0])
    loft(bm, dl, [Ring((0, 0, 1.36), Z, 0.350, 0.234, side_w, jag), Ring((0, 0, 1.285), Z, 0.372, 0.250, side_w, jag)], n=14, mats=[1])
build("ARM_Mantle", [M_Robe, M_RobeTrim], mantle)

def hood(bm, dl):
    Z = (0, 0, 1)
    def folds(a):
        return (1.0 + 0.03 * (1 if int(round(a * 12 / PI)) % 2 == 0 else -1), 0.0)
    rings = [
        Ring((0, 0.00, 1.47), Z, 0.250, 0.185, W(Chest=1), folds),
        Ring((0, 0.00, 1.56), Z, 0.175, 0.140, W(Chest=0.5, Neck=0.5), folds),
        Ring((0, 0.00, 1.64), Z, 0.138, 0.148, W(Neck=0.4, Head=0.6)),
        Ring((0, 0.00, 1.72), Z, 0.130, 0.148, W(Head=1), folds),
        Ring((0, 0.005, 1.80), Z, 0.116, 0.136, W(Head=1)),
        Ring((0, 0.02, 1.87), Z, 0.082, 0.108, W(Head=1)),
        Ring((0, 0.06, 1.93), Z, 0.044, 0.070, W(Head=1)),
        Ring((0, 0.13, 1.96), Z, 0.022, 0.040, W(Head=1)),
        Ring((0, 0.21, 1.93), Z, 0.008, 0.016, W(Head=1)),
    ]
    loft(bm, dl, rings, n=12, cap1=True)
    kill = []
    for f in bm.faces:
        c = f.calc_center_median()
        if c.y < -0.07 and 1.645 < c.z < 1.85 and abs(c.x) < 0.095:
            kill.append(f)
    bmesh.ops.delete(bm, geom=kill, context='FACES_ONLY')
    orphan = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=orphan, context='VERTS')
    # a thick rolled rim around the face opening
    rim = [Ring((0, -0.115, 1.655 + 0.2 * t), Z, 0.014, 0.014, W(Head=1)) for t in (0.0,)]
    for side in (1, -1):
        pts = [Vector((side * 0.088, -0.095, 1.65)), Vector((side * 0.098, -0.105, 1.72)), Vector((side * 0.094, -0.108, 1.80)), Vector((side * 0.070, -0.112, 1.855))]
        rs = [Ring(p, pts[min(i + 1, 3)] - pts[max(i - 1, 0)], 0.016, 0.014, W(Head=1)) for i, p in enumerate(pts)]
        loft(bm, dl, rs, n=4, cap0=True, cap1=True, rot=PI / 4)
    brow = [Vector((0.070, -0.112, 1.855)), Vector((0.0, -0.118, 1.872)), Vector((-0.070, -0.112, 1.855))]
    rs = [Ring(p, brow[min(i + 1, 2)] - brow[max(i - 1, 0)], 0.016, 0.014, W(Head=1)) for i, p in enumerate(brow)]
    loft(bm, dl, rs, n=4, cap0=True, cap1=True, rot=PI / 4)
build("HLM_Hood", [M_Robe], hood)

def cap(bm, dl):
    Z = (0, 0, 1); H = W(Head=1)
    def brim(a):
        return (1.0, 0.012 * math.sin(a * 3))
    rings = [Ring((0, -0.005, 1.765), Z, 0.100, 0.116, H), Ring((0, -0.005, 1.775), Z, 0.150, 0.170, H, brim),
             Ring((0, -0.005, 1.790), Z, 0.140, 0.158, H, brim), Ring((0, -0.005, 1.800), Z, 0.100, 0.116, H),
             Ring((0, 0.0, 1.845), Z, 0.092, 0.108, H), Ring((0, 0.01, 1.895), Z, 0.060, 0.074, H),
             Ring((0, 0.03, 1.925), Z, 0.026, 0.034, H)]
    loft(bm, dl, rings, n=10, cap1=True, mats=[0, 0, 0, 0, 0, 0])
    # band and a swept feather
    loft(bm, dl, [Ring((0, -0.005, 1.800), Z, 0.104, 0.120, H), Ring((0, -0.005, 1.822), Z, 0.102, 0.118, H)], n=10, mats=[1])
    fp = [Vector((0.095, 0.01, 1.82)), Vector((0.125, 0.05, 1.90)), Vector((0.118, 0.11, 1.96)), Vector((0.08, 0.17, 1.97))]
    rs = [Ring(p, fp[min(i + 1, 3)] - fp[max(i - 1, 0)], 0.034 * (1 - i / 4.0) + 0.006, 0.006, H) for i, p in enumerate(fp)]
    loft(bm, dl, rs, n=4, cap1=True, mats=[2, 2, 2], rot=PI / 4)
build("HLM_Cap", [M_LeatherBr, M_LeatherDk, M_Moss], cap)

def kettle(bm, dl):
    Z = (0, 0, 1); H = W(Head=1)
    rings = [
        Ring((0, -0.005, 1.745), Z, 0.120, 0.135, H),
        Ring((0, -0.005, 1.752), Z, 0.215, 0.235, H),
        Ring((0, -0.005, 1.766), Z, 0.215, 0.235, H),
        Ring((0, -0.005, 1.780), Z, 0.126, 0.142, H),
        Ring((0, -0.005, 1.805), Z, 0.116, 0.132, H),
        Ring((0, -0.003, 1.850), Z, 0.096, 0.112, H),
        Ring((0, 0.0, 1.895), Z, 0.050, 0.062, H),
    ]
    loft(bm, dl, rings, n=10, cap1=True)
    box(bm, dl, (0, 0.0, 1.885), (0.020, 0.200, 0.040), H)      # ridge
build("HLM_Kettle", [M_Steel], kettle)
