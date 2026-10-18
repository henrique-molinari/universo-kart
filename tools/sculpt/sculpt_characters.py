"""Esculpe os ETs (Visitante e Turista) e exporta assets/characters/et_<nome>.glb.

Uso: python tools/sculpt/sculpt_characters.py [visitante|turista ...]

As peças seguem exatamente o rig do AlienDriver (mesmas medidas/pivôs), então IK, poses, testes de
colisão com o kart e animações continuam valendo. Nós do .glb:
  Suit     (espaço do Driver: tronco, quadril, pernas, botas, cinto, gola, ombreiras, pescoço)
  Head     (espaço do pivô do pescoço: crânio em gota invertida, aros dos olhos, sobrancelhas,
            maçãs, nariz, narinas, boca esculpida, lábios/rugas conforme o personagem)
  UpperArm / Forearm (ao longo de +Y), HandL / HandR (dedos para +Y, dorso +Z), Finger.
Os olhos (íris/córnea), cílios, laço, painel do peito, LEDs e fivela continuam no Godot (MeshKit),
posicionados na mesma superfície analítica da cabeça.
"""
import os
import sys
import time
import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from sdf import (Sculpt, GlbWriter, ellipsoid, sphere, round_cone, round_box, tube, v3, norm, rot_x, rot_z,
                 smoothstep, noise3, split_by_material)

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "characters")

ORIGIN = v3(0, 0.5, 0.3)
HEAD_PIVOT = v3(0, 0.96, 0.25)
HEAD_C = v3(0, 0.36, -0.01)
HR = v3(0.33, 0.34, 0.29)
SHOULDER = v3(0.17, 0.83, 0.2)
L1 = 0.27
L2 = 0.27
TORSO_TILT = -0.22

SKIN = {"visitante": v3(0.34, 0.76, 0.13), "turista": v3(1.0, 0.42, 0.66)}
SUIT = {"visitante": v3(0.05, 0.3, 0.12), "turista": v3(0.6, 0.06, 0.3)}
TRIM = v3(0.13, 0.14, 0.16)
PIPING = v3(0.93, 0.94, 0.95)


def lighten(c, a):
    return c + (1.0 - c) * a


def darken(c, a):
    return c * (1.0 - a)


# ------------------------------------------------------------------ cabeça (estilo ET da UNIFEOB)

from head_unifeob import build_head  # noqa: E402


# ------------------------------------------------------------------ corpo (traje)

def limb_folds(a, b, r_mean, depth, creases=((0.1, 0.03, 0.0, 1.0), (0.19, 0.035, 2.1, 0.75), (0.31, 0.05, 4.0, 0.35),
                                             (0.7, 0.05, 1.0, 0.35), (0.81, 0.035, 3.3, 0.8), (0.9, 0.03, 5.2, 1.0))):
    """Vincos de tecido ao longo do segmento a->b (deslocamento positivo = sulco)."""
    a = np.asarray(a, float)
    b = np.asarray(b, float)
    ax = b - a
    L = np.linalg.norm(ax)
    ax = ax / L
    ref = v3(1, 0, 0) if abs(ax[0]) < 0.9 else v3(0, 0, 1)
    e1 = norm(np.cross(ax, ref))
    e2 = np.cross(ax, e1)

    def f(P):
        q = P - a
        t = (q @ ax) / L
        radial = q - np.outer(q @ ax, ax)
        rl = np.linalg.norm(radial, axis=1)
        ang = np.arctan2(radial @ e2, radial @ e1)
        near = np.clip(1.0 - np.abs(rl - r_mean) / (r_mean * 0.8), 0, 1) * (t > -0.05) * (t < 1.05)
        fv = np.zeros(len(P))
        for c, w, ph, k in creases:
            fv += np.exp(-((t - c) / w) ** 2) * k * (0.5 + 0.5 * np.cos(ang - ph))
        return fv * depth * near
    return f


def build_suit(who):
    o = -ORIGIN
    tb = rot_x(TORSO_TILT)
    kc = SUIT[who]
    panel = lighten(kc, 0.22)
    S = Sculpt()
    S.add(ellipsoid(o + v3(0, 0.5, 0.32), (0.18, 0.12, 0.16)), "hip")
    torso_c = o + v3(0, 0.7, 0.3)
    S.add(ellipsoid(torso_c, (0.19, 0.23, 0.155), tb), "torso", 0.05)
    # Peitoral/costas levemente marcados.
    S.add(ellipsoid(torso_c + tb @ v3(0, 0.05, -0.06), (0.16, 0.12, 0.11), tb), "torso", 0.04)
    S.add(ellipsoid(o + v3(0, 0.56, 0.31), (0.19, 0.036, 0.167)), "belt", 0.006)
    S.add(ellipsoid(o + v3(0, 0.9, 0.255), (0.11, 0.042, 0.1)), "collar", 0.01)
    S.add(ellipsoid(o + v3(0, 0.925, 0.257), (0.092, 0.024, 0.084)), "collar_in", 0.006)
    S.add(round_cone(o + v3(0, 0.86, 0.26), o + HEAD_PIVOT + v3(0, 0.08, 0), 0.066, 0.058), "neck", 0.015)
    for s in (-1.0, 1.0):
        sh = o + v3(s * SHOULDER[0], SHOULDER[1], SHOULDER[2])
        S.add(sphere(sh, 0.07), "torso", 0.04)
        S.add(ellipsoid(sh + v3(-s * 0.015, 0.048, 0.0), (0.085, 0.024, 0.06), rot_z(s * 0.35)), "pad", 0.012)
        hip = o + v3(s * 0.09, 0.5, 0.28)
        knee = o + v3(s * 0.16, 0.645, -0.36)
        ankle = o + v3(s * 0.15, 0.4, -0.56)
        S.add(round_cone(hip, knee, 0.081, 0.071), "leg", 0.035)
        S.add(round_cone(knee, ankle, 0.068, 0.054), "leg", 0.02)
        S.disp(limb_folds(hip, knee, 0.075, 0.006))
        S.disp(limb_folds(knee, ankle, 0.062, 0.005))
        S.add(ellipsoid(knee + v3(0, 0.012, -0.012), (0.078, 0.078, 0.064)), "kneepad", 0.01)
        S.add(round_cone(ankle + v3(0, 0.05, 0.03), ankle + v3(0, -0.04, 0), 0.062, 0.067), "boot", 0.01)
        S.add(ellipsoid(o + v3(s * 0.15, 0.36, -0.63), (0.069, 0.063, 0.104)), "boot", 0.02)
        S.add(round_box(o + v3(s * 0.15, 0.322, -0.632), (0.071, 0.016, 0.106), 0.014), "sole", 0.006)
    # Dobras horizontais do macacão na cintura (frente).
    def waist(P):
        q = (P - torso_c) @ tb
        band = np.exp(-((q[:, 1] + 0.15) / 0.05) ** 2) * np.clip(-q[:, 2] / 0.15, 0, 1)
        return 0.0022 * band * (0.5 + 0.5 * np.sin(q[:, 1] * 160.0))
    S.disp(waist)
    V, F, N = S.mesh(0.003, 15000)
    lab_tri = S.label(V[F].mean(axis=1))
    mat_of = {"neck": "skin", "boot": "rubber", "sole": "rubber", "kneepad": "rubber", "belt": "rubber"}
    mats = np.array([mat_of.get(l, "fabric") for l in lab_tri])

    def color(Vm, Nm, mat):
        W = S.weights(Vm, 0.005)
        a = S.ao(Vm, Nm, 0.015)
        q = (Vm - torso_c) @ tb / v3(0.19, 0.23, 0.155)
        d = q / np.maximum(np.linalg.norm(q, axis=1, keepdims=True), 1e-9)
        ax = np.abs(d[:, 0])
        # Tronco: painel lateral claro com filete branco (transições suaves), zíper frontal.
        torso = kc[None, :] * (1 - 0.18 * np.clip(-d[:, 1] - 0.4, 0, 1))[:, None]
        pip = smoothstep(0.78, 0.8, ax) * (1 - smoothstep(0.84, 0.86, ax))
        pan = smoothstep(0.84, 0.86, ax)
        torso = torso * (1 - pip - pan)[:, None] + PIPING * pip[:, None] + panel * pan[:, None]
        zip_ = (1 - smoothstep(0.025, 0.04, ax)) * smoothstep(-0.25, -0.35, d[:, 2]) * (1 - smoothstep(0.15, 0.25, d[:, 1]))
        torso = torso * (1 - zip_)[:, None] + TRIM * zip_[:, None]
        # Ombreira com borda inferior em filete.
        pad_edge = 1 - smoothstep(o[1] + SHOULDER[1] + 0.03, o[1] + SHOULDER[1] + 0.04, Vm[:, 1])
        pad = panel[None, :] * (1 - pad_edge)[:, None] + PIPING * pad_edge[:, None]
        cols = {"hip": np.tile(kc, (len(Vm), 1)), "torso": torso, "leg": np.tile(kc, (len(Vm), 1)), "pad": pad,
                "collar": np.tile(PIPING, (len(Vm), 1)), "collar_in": np.tile(darken(kc, 0.25), (len(Vm), 1)),
                "belt": np.tile(TRIM, (len(Vm), 1)), "kneepad": np.tile(TRIM, (len(Vm), 1)),
                "boot": np.tile(TRIM, (len(Vm), 1)), "sole": np.tile(PIPING, (len(Vm), 1)),
                "neck": np.tile(darken(SKIN[who], 0.08), (len(Vm), 1))}
        c = np.zeros((len(Vm), 3))
        for l, w in W.items():
            c += cols[l] * w[:, None]
        c = c * (0.55 + 0.45 * a[:, None]) * (0.98 + 0.02 * noise3(Vm, 60.0))[:, None]
        return np.hstack([np.clip(c, 0, 1), np.ones((len(Vm), 1))])
    return split_by_material(V, F, N, mats, color)


# ------------------------------------------------------------------ braços e mãos

def build_arm(who, fore):
    kc = SUIT[who]
    S = Sculpt()
    if not fore:
        S.add(round_cone(v3(0, 0, 0), v3(0, L1, 0), 0.058, 0.05), "arm")
        S.add(ellipsoid(v3(0, 0.11, 0), (0.062, 0.075, 0.06)), "arm", 0.03)     # bíceps/ombro
        S.add(sphere(v3(0, L1, 0), 0.053), "elbow", 0.015)
        S.disp(limb_folds(v3(0, 0, 0), v3(0, L1, 0), 0.055, 0.005))
    else:
        S.add(round_cone(v3(0, 0, 0), v3(0, L2 - 0.03, 0), 0.051, 0.044), "arm")
        S.add(ellipsoid(v3(0, 0.07, 0), (0.056, 0.07, 0.054)), "arm", 0.03)     # antebraço mais cheio perto do cotovelo
        S.add(round_cone(v3(0, L2 - 0.05, 0), v3(0, L2 - 0.004, 0), 0.0485, 0.0475), "cuff", 0.004)
        S.disp(limb_folds(v3(0, 0, 0), v3(0, L2, 0), 0.05, 0.0045, ((0.08, 0.03, 0.0, 1.0), (0.16, 0.035, 2.0, 0.7), (0.3, 0.05, 4.1, 0.3))))
    V, F, N = S.mesh(0.002, 2200)

    def color(Vm, Nm, mat):
        W = S.weights(Vm, 0.004)
        a = S.ao(Vm, Nm, 0.01)
        n = len(Vm)
        cuff = TRIM[None, :] * np.ones((n, 1))
        band = smoothstep(L2 - 0.052, L2 - 0.047, Vm[:, 1]) * (1 - smoothstep(L2 - 0.042, L2 - 0.037, Vm[:, 1]))
        cuff = cuff * (1 - band)[:, None] + PIPING * band[:, None]
        cols = {"arm": np.tile(kc, (n, 1)), "elbow": np.tile(darken(kc, 0.12), (n, 1)), "cuff": cuff}
        c = np.zeros((n, 3))
        for l, w in W.items():
            c += cols[l] * w[:, None]
        c = c * (0.55 + 0.45 * a[:, None])
        return np.hstack([np.clip(c, 0, 1), np.ones((n, 1))])
    lab_tri = S.label(V[F].mean(axis=1))
    mats = np.array(["rubber" if l == "cuff" else "fabric" for l in lab_tri])
    return split_by_material(V, F, N, mats, color)


def build_hand(who, s):
    skin = SKIN[who]
    S = Sculpt()
    S.add(ellipsoid(v3(0, 0.045, 0), (0.043, 0.05, 0.027)), "skin")
    S.add(ellipsoid(v3(0, 0.012, 0.0), (0.036, 0.03, 0.026)), "skin", 0.015)               # punho
    S.add(ellipsoid(v3(s * 0.03, 0.082, -0.018), (0.014, 0.024, 0.017), rot_x(-0.9)), "skin", 0.012)   # dedo dobrado
    tb_ = v3(-s * 0.032, 0.03, -0.012)
    tt = v3(-s * 0.018, 0.075, -0.04)
    S.add(round_cone(tb_, tt, 0.017, 0.014), "skin", 0.012)
    S.add(sphere(tt + v3(0, 0.004, -0.003), 0.0175), "skin", 0.006)                      # ponta de ET no polegar
    for k in (-1, 1):   # nós dos dedos no dorso
        S.add(sphere(v3(k * 0.016, 0.086, 0.012), 0.012), "skin", 0.012)
    V, F, N = S.mesh(0.0012, 2200)

    def color(Vm, Nm, mat):
        a = S.ao(Vm, Nm, 0.006)
        c = skin[None, :] * (0.96 + 0.04 * noise3(Vm, 80.0))[:, None]
        c = c * (0.6 + 0.4 * a[:, None])
        return np.hstack([np.clip(c, 0, 1), np.ones((len(Vm), 1))])
    return split_by_material(V, F, N, np.array(["skin"] * len(F)), color)


def build_finger(who):
    skin = SKIN[who]
    S = Sculpt()
    S.add(round_cone(v3(0, 0, 0), v3(0, 0.058, 0), 0.0145, 0.0125), "skin")
    S.add(sphere(v3(0, 0.064, 0), 0.0185), "skin", 0.008)      # ponta arredondada de ET
    S.add(sphere(v3(0, 0.03, 0.004), 0.0135), "skin", 0.01)     # articulação
    V, F, N = S.mesh(0.0008, 700)

    def color(Vm, Nm, mat):
        a = S.ao(Vm, Nm, 0.004)
        tip = smoothstep(0.05, 0.075, Vm[:, 1])
        c = skin[None, :] * (1.0 + 0.04 * tip)[:, None] * (0.65 + 0.35 * a[:, None])
        return np.hstack([np.clip(c, 0, 1), np.ones((len(Vm), 1))])
    return split_by_material(V, F, N, np.array(["skin"] * len(F)), color)


def build(who):
    t0 = time.time()
    w = GlbWriter()
    for name, fn in [("Suit", lambda: build_suit(who)), ("Head", lambda: build_head(who)),
                     ("UpperArm", lambda: build_arm(who, False)), ("Forearm", lambda: build_arm(who, True)),
                     ("HandL", lambda: build_hand(who, -1.0)), ("HandR", lambda: build_hand(who, 1.0)),
                     ("Finger", lambda: build_finger(who))]:
        t1 = time.time()
        parts = fn()
        w.add_node(name, parts)
        print("  %-9s %6d tris  %s  (%.1f s)" % (name, sum(len(p[4]) for p in parts), "/".join(p[0] for p in parts), time.time() - t1))
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, "et_%s.glb" % who)
    w.save(path)
    print("%s -> %s (%.1f s)" % (who, path, time.time() - t0))


if __name__ == "__main__":
    for who in (sys.argv[1:] or ["visitante", "turista"]):
        build(who)
