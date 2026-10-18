"""Esculpe o corpo dos pilotos (macacão, HANS, braços, luvas) e exporta assets/characters/pilot_<n>.glb,
um arquivo por esquema de cores (PilotDriver.SCHEMES). O capacete continua no Godot (peça rígida).

Uso: python tools/sculpt/sculpt_pilots.py
"""
import os
import sys
import time
import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from sdf import Sculpt, GlbWriter, ellipsoid, sphere, round_cone, round_box, v3, rot_x, rot_z, smoothstep, noise3, split_by_material
from sculpt_characters import ORIGIN, HEAD_PIVOT, SHOULDER, L1, L2, TORSO_TILT, OUT, darken, limb_folds

SCHEMES = [
    {"suit": v3(0.8, 0.07, 0.09), "stripe": v3(1.0, 0.84, 0.08), "accent": v3(0.97, 0.97, 0.97), "glove": v3(0.1, 0.1, 0.11), "rainbow": False},
    {"suit": v3(0.07, 0.32, 0.82), "stripe": v3(0.15, 0.88, 1.0), "accent": v3(0.97, 0.97, 0.97), "glove": v3(0.06, 0.2, 0.55), "rainbow": False},
    {"suit": v3(0.05, 0.5, 0.25), "stripe": v3(0.07, 0.07, 0.08), "accent": v3(1.0, 0.78, 0.18), "glove": v3(0.07, 0.07, 0.08), "rainbow": False},
    {"suit": v3(0.95, 0.95, 0.95), "stripe": v3(0.55, 0.2, 0.85), "accent": v3(0.97, 0.97, 0.97), "glove": v3(0.55, 0.2, 0.85), "rainbow": True},
]
RAINBOW = np.array([v3(0.92, 0.12, 0.15), v3(1.0, 0.55, 0.05), v3(1.0, 0.88, 0.1), v3(0.15, 0.75, 0.3), v3(0.1, 0.45, 0.95), v3(0.55, 0.2, 0.85)])
BLACK = v3(0.07, 0.07, 0.08)


def suit_sculpt():
    o = -ORIGIN
    tb = rot_x(TORSO_TILT)
    S = Sculpt()
    S.add(ellipsoid(o + v3(0, 0.5, 0.32), (0.17, 0.12, 0.155)), "hip")
    torso_c = o + v3(0, 0.69, 0.3)
    S.add(ellipsoid(torso_c, (0.175, 0.225, 0.15), tb), "torso", 0.05)
    S.add(ellipsoid(torso_c + tb @ v3(0, 0.05, -0.055), (0.15, 0.12, 0.105), tb), "torso", 0.04)
    S.add(ellipsoid(o + v3(0, 0.56, 0.31), (0.182, 0.034, 0.162)), "belt", 0.006)
    S.add(round_box(o + v3(0, 0.555, 0.15), (0.05, 0.03, 0.012), 0.008, rot_x(-0.15)), "buckle", 0.003)
    S.add(ellipsoid(o + v3(0, 0.895, 0.29), (0.15, 0.042, 0.13), rot_x(-0.15)), "hans", 0.012)
    for s in (-1.0, 1.0):
        S.add(ellipsoid(o + v3(s * 0.06, 0.93, 0.36), (0.026, 0.036, 0.021)), "hans", 0.01)
    S.add(round_cone(o + v3(0, 0.86, 0.26), o + HEAD_PIVOT + v3(0, 0.1, 0), 0.055, 0.05), "neck", 0.012)
    for s in (-1.0, 1.0):
        sh = o + v3(s * SHOULDER[0], SHOULDER[1], SHOULDER[2])
        S.add(sphere(sh, 0.068), "torso", 0.04)
        S.add(ellipsoid(sh + v3(-s * 0.02, 0.05, 0.0), (0.078, 0.018, 0.048), rot_z(s * 0.35)), "dragona", 0.01)
        hip = o + v3(s * 0.09, 0.5, 0.28)
        knee = o + v3(s * 0.16, 0.645, -0.36)
        ankle = o + v3(s * 0.15, 0.42, -0.56)
        S.add(round_cone(hip, knee, 0.078, 0.068), "leg", 0.035)
        S.add(round_cone(knee, ankle, 0.065, 0.052), "leg", 0.02)
        S.disp(limb_folds(hip, knee, 0.072, 0.006))
        S.disp(limb_folds(knee, ankle, 0.06, 0.005))
        S.add(ellipsoid(knee + v3(0, 0.01, -0.01), (0.072, 0.072, 0.06)), "knee", 0.015)
        S.add(round_cone(ankle + v3(0, 0.05, 0.03), ankle + v3(0, -0.04, 0), 0.062, 0.066), "boot", 0.01)
        S.add(ellipsoid(o + v3(s * 0.15, 0.365, -0.63), (0.067, 0.061, 0.101)), "boot", 0.02)
        S.add(round_box(o + v3(s * 0.15, 0.33, -0.632), (0.07, 0.016, 0.104), 0.014), "sole", 0.006)
    return S, torso_c, tb


def suit_color(S, torso_c, tb, sc):
    o = -ORIGIN
    kc = sc["suit"]

    def color(Vm, Nm, mat):
        W = S.weights(Vm, 0.005)
        a = S.ao(Vm, Nm, 0.015)
        n = len(Vm)
        q = (Vm - torso_c) @ tb / v3(0.175, 0.225, 0.15)
        d = q / np.maximum(np.linalg.norm(q, axis=1, keepdims=True), 1e-9)
        ax = np.abs(d[:, 0])
        if sc["rainbow"]:
            base = RAINBOW[np.clip(((d[:, 0] * 0.5 + 0.5) * 6).astype(int), 0, 5)]
        else:
            base = np.tile(kc, (n, 1))
        acc = smoothstep(0.75, 0.77, ax) * (1 - smoothstep(0.83, 0.85, ax))
        stp = smoothstep(0.83, 0.85, ax)
        torso = base * (1 - acc - stp)[:, None] + sc["accent"] * acc[:, None] + sc["stripe"] * stp[:, None]
        zip_ = (1 - smoothstep(0.035, 0.05, ax)) * smoothstep(-0.2, -0.3, d[:, 2]) * (1 - smoothstep(0.7, 0.75, d[:, 1]))
        torso = torso * (1 - zip_)[:, None] + darken(kc, 0.55) * zip_[:, None]
        patch = smoothstep(-0.25, -0.35, d[:, 2]) * smoothstep(0.03, 0.07, d[:, 1]) * (1 - smoothstep(0.4, 0.44, d[:, 1])) \
            * smoothstep(0.24, 0.28, ax) * (1 - smoothstep(0.58, 0.62, ax))
        pc = np.where((d[:, 0] > 0)[:, None], sc["accent"][None, :], sc["stripe"][None, :])
        torso = torso * (1 - patch)[:, None] + pc * patch[:, None]
        # Faixa no lado de fora da coxa (eixo da coxa: x de 0.09 no quadril a 0.16 no joelho).
        side = np.sign(Vm[:, 0])
        axis_x = (0.09 + 0.07 * np.clip((Vm[:, 2] - (o[2] + 0.28)) / (-0.64), 0, 1)) * side
        lstripe = smoothstep(0.05, 0.06, (Vm[:, 0] - axis_x) * side) * smoothstep(o[2] - 0.38, o[2] - 0.3, Vm[:, 2])
        leg = np.tile(kc, (n, 1)) * (1 - lstripe)[:, None] + sc["stripe"] * lstripe[:, None]
        cols = {"hip": np.tile(kc, (n, 1)), "torso": torso, "leg": leg, "belt": np.tile(BLACK, (n, 1)),
                "buckle": np.tile(v3(0.75, 0.76, 0.78), (n, 1)), "hans": np.tile(BLACK, (n, 1)),
                "neck": np.tile(v3(0.12, 0.12, 0.13), (n, 1)), "dragona": np.tile(sc["stripe"], (n, 1)),
                "knee": np.tile(darken(kc, 0.12), (n, 1)), "boot": np.tile(sc["glove"], (n, 1)),
                "sole": np.tile(v3(0.95, 0.95, 0.95), (n, 1))}
        c = np.zeros((n, 3))
        for l, w in W.items():
            c += cols[l] * w[:, None]
        c = c * (0.55 + 0.45 * a[:, None]) * (0.98 + 0.02 * noise3(Vm, 60.0))[:, None]
        return np.hstack([np.clip(c, 0, 1), np.ones((n, 1))])
    return color


def arm_sculpt(fore):
    S = Sculpt()
    if not fore:
        S.add(round_cone(v3(0, 0, 0), v3(0, L1, 0), 0.056, 0.048), "arm")
        S.add(ellipsoid(v3(0, 0.11, 0), (0.06, 0.072, 0.058)), "arm", 0.03)
        S.add(round_cone(v3(0, L1 * 0.55, 0), v3(0, L1 * 0.55 + 0.028, 0), 0.0545, 0.053), "band", 0.004)
        S.add(sphere(v3(0, L1, 0), 0.051), "elbow", 0.015)
        S.disp(limb_folds(v3(0, 0, 0), v3(0, L1, 0), 0.053, 0.005))
    else:
        S.add(round_cone(v3(0, 0, 0), v3(0, L2 - 0.07, 0), 0.049, 0.043), "arm")
        S.add(ellipsoid(v3(0, 0.07, 0), (0.054, 0.068, 0.052)), "arm", 0.03)
        S.add(round_cone(v3(0, L2 - 0.085, 0), v3(0, L2 - 0.004, 0), 0.05, 0.058), "glove", 0.006)
        S.add(round_cone(v3(0, L2 - 0.062, 0), v3(0, L2 - 0.046, 0), 0.0585, 0.06), "accent", 0.003)
        S.disp(limb_folds(v3(0, 0, 0), v3(0, L2 - 0.07, 0), 0.048, 0.0045, ((0.08, 0.03, 0.0, 1.0), (0.16, 0.035, 2.0, 0.7))))
    return S


def hand_sculpt(s):
    S = Sculpt()
    S.add(ellipsoid(v3(0, 0.045, 0), (0.042, 0.048, 0.025)), "glove")
    S.add(ellipsoid(v3(0, 0.012, 0), (0.036, 0.03, 0.026)), "glove", 0.015)
    S.add(ellipsoid(v3(0, 0.06, 0.02), (0.034, 0.02, 0.009)), "pad", 0.004)
    for j in range(2):
        fx = s * (0.012 + 0.02 * j)
        S.add(ellipsoid(v3(fx, 0.08, -0.016), (0.012, 0.022, 0.015), rot_x(-0.9)), "glove", 0.01)
    tb_ = v3(-s * 0.032, 0.03, -0.012)
    tt = v3(-s * 0.018, 0.072, -0.038)
    S.add(round_cone(tb_, tt, 0.016, 0.013), "glove", 0.012)
    S.add(sphere(tt, 0.015), "glove", 0.006)
    for k in (-1, 1):
        S.add(sphere(v3(k * 0.016, 0.084, 0.01), 0.011), "glove", 0.01)
    return S


def finger_sculpt():
    S = Sculpt()
    S.add(round_cone(v3(0, 0, 0), v3(0, 0.05, 0), 0.0138, 0.0122), "glove")
    S.add(sphere(v3(0, 0.026, 0.003), 0.0128), "glove", 0.008)
    return S


def build_pilots():
    t0 = time.time()
    S, torso_c, tb = suit_sculpt()
    V, F, N = S.mesh(0.003, 14000)
    lab_tri = S.label(V[F].mean(axis=1))
    mat_of = {"belt": "rubber", "hans": "rubber", "neck": "rubber", "buckle": "rubber", "boot": "glove", "sole": "glove"}
    suit_mats = np.array([mat_of.get(l, "fabric") for l in lab_tri])
    parts = {"UpperArm": (arm_sculpt(False), 0.002, 2200), "Forearm": (arm_sculpt(True), 0.002, 2200),
             "HandL": (hand_sculpt(-1.0), 0.0012, 2000), "HandR": (hand_sculpt(1.0), 0.0012, 2000),
             "Finger": (finger_sculpt(), 0.0008, 600)}
    meshes = {}
    for k, (Sx, h, tris) in parts.items():
        V2, F2, N2 = Sx.mesh(h, tris)
        lab = Sx.label(V2[F2].mean(axis=1))
        meshes[k] = (Sx, V2, F2, N2, np.array(["glove" if l in ("glove", "accent", "pad") else "fabric" for l in lab]))
    print("  geometria em %.1f s" % (time.time() - t0))
    for i, sc in enumerate(SCHEMES):
        w = GlbWriter()
        w.add_node("Suit", split_by_material(V, F, N, suit_mats, suit_color(S, torso_c, tb, sc)))
        for name, (Sx, V2, F2, N2, mats2) in meshes.items():
            cols = {"arm": sc["suit"], "elbow": darken(sc["suit"], 0.1), "band": sc["stripe"], "glove": sc["glove"],
                    "accent": sc["accent"], "pad": sc["stripe"]}

            def color(Vm, Nm, mat, Sx=Sx, cols=cols):
                W = Sx.weights(Vm, 0.003)
                a = Sx.ao(Vm, Nm, 0.008)
                c = np.zeros((len(Vm), 3))
                for l, wv in W.items():
                    c += cols[l][None, :] * wv[:, None]
                c = c * (0.55 + 0.45 * a[:, None])
                return np.hstack([np.clip(c, 0, 1), np.ones((len(Vm), 1))])
            w.add_node(name, split_by_material(V2, F2, N2, mats2, color))
        path = os.path.join(OUT, "pilot_%d.glb" % i)
        w.save(path)
        print("  pilot_%d -> %s" % (i, path))
    print("pilotos em %.1f s" % (time.time() - t0))


if __name__ == "__main__":
    build_pilots()
