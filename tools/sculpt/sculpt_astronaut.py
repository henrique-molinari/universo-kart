"""Astronauta do Universo: traje espacial no estilo do EMU da NASA (branco, volumoso, módulo de controle
no peito, mochila de suporte de vida, anéis de junta azuis, luvas e botas), com os emblemas da NASA
trocados pelo emblema da UNIFEOB (superfície "patch", textura gerada no Godot), e capacete com concha
branca, viseira dourada espelhada e lanternas. Exporta assets/characters/astronaut.glb.

Nós (mesmo rig do piloto): Suit, Helmet (espaço do pivô do pescoço), UpperArm, Forearm, HandL, HandR, Finger.
Materiais: fabric (tecido branco), metal (anéis), hard (plásticos/mochila), glove, visor, shell, lamp, patch.
Uso: python tools/sculpt/sculpt_astronaut.py
"""
import os
import sys
import time
import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from sdf import (Sculpt, GlbWriter, ellipsoid, sphere, round_cone, round_box, v3, norm, rot_x, rot_z, smoothstep,
                 noise3, split_by_material, surface_patch, param_ellipsoid, tube, merge)
from sculpt_characters import ORIGIN, HEAD_PIVOT, SHOULDER, L1, L2, TORSO_TILT, OUT, limb_folds

WHITE = v3(0.9, 0.9, 0.88)
METAL = v3(0.16, 0.3, 0.78)       # anéis de junta (azul anodizado, cor UNIFEOB)
GREY = v3(0.55, 0.57, 0.6)
DARK = v3(0.18, 0.19, 0.21)
HELMET_C = v3(0, 0.3, 0.0)


def colorize(S, cols, ao_d=0.012, sigma=0.004):
    def color(Vm, Nm, mat):
        W = S.weights(Vm, sigma)
        a = S.ao(Vm, Nm, ao_d)
        c = np.zeros((len(Vm), 3))
        for l, w in W.items():
            col = cols[l](Vm) if callable(cols[l]) else np.tile(cols[l], (len(Vm), 1))
            c += col * w[:, None]
        c = c * (0.55 + 0.45 * a[:, None]) * (0.985 + 0.015 * noise3(Vm, 50.0))[:, None]
        return np.hstack([np.clip(c, 0, 1), np.ones((len(Vm), 1))])
    return color


def build_suit():
    o = -ORIGIN
    tb = rot_x(TORSO_TILT)
    S = Sculpt()
    S.add(ellipsoid(o + v3(0, 0.5, 0.32), (0.19, 0.13, 0.17)), "fabric")
    torso_c = o + v3(0, 0.7, 0.3)
    S.add(ellipsoid(torso_c, (0.205, 0.245, 0.175), tb), "fabric", 0.05)        # tronco rígido (HUT)
    S.add(ellipsoid(torso_c + tb @ v3(0, 0.06, -0.06), (0.18, 0.13, 0.12), tb), "fabric", 0.04)
    S.add(round_cone(o + v3(0, 0.555, 0.31), o + v3(0, 0.585, 0.31), 0.2, 0.2), "metal", 0.006)   # anel da cintura
    # Anel do pescoço (onde o capacete encaixa).
    S.add(round_cone(o + v3(0, 0.885, 0.275), o + v3(0, 0.93, 0.27), 0.125, 0.12), "metal", 0.008)
    # Módulo de controle no peito (DCM) com botões.
    n = tb @ v3(0, 0, -1)
    dcm = torso_c + tb @ v3(0, -0.02, -0.165)
    S.add(round_box(dcm, (0.11, 0.065, 0.045), 0.015, tb), "hard", 0.01)
    for i, (dx, dy) in enumerate(((-0.06, 0.02), (-0.02, 0.025), (0.03, 0.02), (0.065, 0.015), (-0.04, -0.03), (0.05, -0.03))):
        S.add(sphere(dcm + tb @ v3(dx, dy, -0.048), 0.011), "knob%d" % (i % 3), 0.003)
    # Mochila de suporte de vida (acima do encosto do banco).
    S.add(round_box(o + v3(0, 0.99, 0.53), (0.165, 0.13, 0.07), 0.035), "hard", 0.02)
    for s in (-1.0, 1.0):
        sh = o + v3(s * SHOULDER[0], SHOULDER[1], SHOULDER[2])
        S.add(sphere(sh, 0.08), "fabric", 0.04)
        hip = o + v3(s * 0.09, 0.5, 0.28)
        knee = o + v3(s * 0.16, 0.645, -0.36)
        ankle = o + v3(s * 0.15, 0.42, -0.56)
        S.add(round_cone(hip, knee, 0.088, 0.078), "fabric", 0.035)
        S.add(round_cone(knee, ankle, 0.074, 0.062), "fabric", 0.02)
        S.disp(limb_folds(hip, knee, 0.083, 0.008))
        S.disp(limb_folds(knee, ankle, 0.068, 0.007))
        S.add(ellipsoid(knee + v3(0, 0.012, -0.012), (0.082, 0.08, 0.068)), "fabric", 0.02)
        S.add(round_cone(ankle + v3(0, 0.05, 0.03), ankle + v3(0, -0.04, 0), 0.07, 0.074), "fabric", 0.01)
        S.add(ellipsoid(o + v3(s * 0.15, 0.36, -0.64), (0.075, 0.068, 0.112)), "fabric", 0.025)       # bota
        S.add(round_box(o + v3(s * 0.15, 0.322, -0.64), (0.078, 0.018, 0.115), 0.015), "sole", 0.006)
    V, F, N = S.mesh(0.003, 16000)
    mats = np.array(["fabric"] * len(F))   # um material: transições de cor suaves (sem serrilhado)
    cols = {"fabric": WHITE, "metal": METAL, "hard": lambda Vm: np.tile(v3(0.86, 0.86, 0.84), (len(Vm), 1)),
            "sole": GREY, "knob0": v3(0.8, 0.12, 0.12), "knob1": v3(0.95, 0.75, 0.1), "knob2": DARK}
    parts = split_by_material(V, F, N, mats, colorize(S, cols, 0.015, 0.005))
    # Emblemas UNIFEOB (no lugar do logo da NASA): peito direito e mochila.
    patches = []
    pc = torso_c + tb @ v3(0.11, 0.13, -0.12)
    pn = norm(tb @ v3(0.55, 0.25, -1.0))
    patches.append(surface_patch(S, pc, pn, v3(0, 1, 0), 0.042))
    patches.append(surface_patch(S, o + v3(0, 1.02, 0.6), v3(0, 0, 1), v3(0, 1, 0), 0.06))
    for Vp, Fp, Np, UVp in patches:
        parts.append(("patch", Vp, Np, np.ones((len(Vp), 4)), Fp, UVp))
    return parts


def build_helmet():
    """Capacete estilizado (padrão de personagem AAA, tipo Astro Bot): casco liso e arredondado, viseira
    grande de cantos suaves com aro chanfrado em volta, vidro dourado em degradê com reflexos pintados,
    "orelhas" redondas com o emblema da UNIFEOB e lanterna, e anel azul no pescoço."""
    R = v3(0.285, 0.29, 0.29)
    S = Sculpt()
    shell = ellipsoid(HELMET_C, R)
    S.add(shell, "shell")
    # Viseira: superelipse vista de frente (cantos bem arredondados), só na metade da frente.
    A, B, Y0 = 0.2, 0.15, -0.005

    def window(P):
        q = P - HELMET_C
        e = (np.abs(q[:, 0] / A) ** 4 + np.abs((q[:, 1] - Y0) / B) ** 4) ** 0.25 - 1.0
        return np.maximum(e * 0.14, q[:, 2] + 0.1)
    window.bounds = (HELMET_C - 0.35, HELMET_C + 0.35)
    S.sub(window, 0.006)
    # Aro chanfrado seguindo a borda da viseira sobre o casco.
    rim = []
    for j in range(73):
        th = 2 * np.pi * j / 72
        cx, cy = np.cos(th), np.sin(th)
        x = A * np.sign(cx) * np.abs(cx) ** 0.5
        y = Y0 + B * np.sign(cy) * np.abs(cy) ** 0.5
        d = v3(x, y, -np.sqrt(max(R[2] ** 2 - x * x - y * y, 0.0)))
        rim.append(HELMET_C + d / np.linalg.norm(d / R))
    S.add(tube(rim, 0.016), "shell", 0.014)
    # Anel do pescoço.
    S.add(round_cone(HELMET_C + v3(0, -0.262, 0.015), HELMET_C + v3(0, -0.225, 0.015), 0.155, 0.175), "metal", 0.012)
    # "Orelhas": discos laterais arredondados (o emblema vai na face de fora).
    ears = []
    for s in (-1.0, 1.0):
        ec = HELMET_C + v3(s * 0.258, -0.01, 0.015)
        S.add(round_cone(ec - v3(s * 0.02, 0, 0), ec + v3(s * 0.012, 0, 0), 0.064, 0.057), "ear", 0.012)
        ears.append((ec + v3(s * 0.012, 0, 0), s))
        # Lanterninha no alto da orelha, apontando para a frente.
        S.add(round_box(ec + v3(s * 0.01, 0.08, -0.03), (0.018, 0.016, 0.03), 0.008), "ear", 0.008)
    V, F, N = S.mesh(0.002, 18000, nrm_eps=0.003)
    cols = {"shell": v3(0.94, 0.94, 0.93), "metal": METAL, "ear": v3(0.9, 0.9, 0.9)}
    parts = split_by_material(V, F, N, np.array(["shell"] * len(F)), colorize(S, cols, 0.012, 0.003))
    # Vidro da viseira (elipsoide liso por dentro do casco) em degradê dourado: escuro em cima, claro embaixo.
    Vv, Fv, Nv, qv = param_ellipsoid(HELMET_C + v3(0, 0, 0.004), np.eye(3), R - 0.006, 64, 44)
    g = np.clip((qv[:, 1] + 0.6) / 1.2, 0, 1)[:, None]
    col = v3(0.95, 0.66, 0.24) * (1 - g) + v3(0.32, 0.18, 0.06) * g
    parts.append(("visor", Vv, Nv, np.hstack([col, np.ones((len(Vv), 1))]), Fv))
    # Reflexos pintados no vidro (faixa diagonal + ponto), como na arte de personagem estilizada.
    gl = []
    for (u, v, a_, b_, rot) in ((-0.42, 0.28, 0.07, 0.014, 0.6), (-0.3, 0.42, 0.03, 0.008, 0.6), (0.4, -0.3, 0.014, 0.014, 0.0)):
        x, y = A * u * 1.6, Y0 + B * v * 1.6
        d = v3(x, y, -np.sqrt(max((R[2] - 0.006) ** 2 - x * x - y * y, 0.0)))
        p = HELMET_C + v3(0, 0, 0.004) + d / np.linalg.norm(d / (R - 0.006))
        n = norm(d / (R - 0.006) ** 2)
        ex = norm(np.cross(v3(0, 1, 0), n))
        ey = np.cross(n, ex)
        ex, ey = ex * np.cos(rot) + ey * np.sin(rot), -ex * np.sin(rot) + ey * np.cos(rot)
        Vg, Fg, Ng, _ = param_ellipsoid(p + n * 0.0015, np.stack([ex, ey, n], 1), v3(a_, b_, 0.001), 20, 8)
        gl.append((Vg, Fg, Ng, np.tile([1.0, 0.97, 0.9, 1.0], (len(Vg), 1))))
    Vx, Fx, Nx, Cx = merge(gl)
    parts.append(("glint", Vx, Nx, Cx, Fx))
    # Lentes das lanternas e emblemas UNIFEOB nas orelhas.
    for ec, s in ears:
        Vl, Fl, Nl, _ = param_ellipsoid(ec + v3(-s * 0.02, 0.08, -0.062), np.eye(3), v3(0.012, 0.011, 0.005), 16, 10)
        parts.append(("lamp", Vl, Nl, np.tile([1.0, 0.97, 0.85, 1.0], (len(Vl), 1)), Fl))
        Vp, Fp, Np, UVp = surface_patch(S, ec, v3(s, 0, 0), v3(0, 1, 0), 0.044, 14, 0.0025, 0.14)
        parts.append(("patch", Vp, Np, np.ones((len(Vp), 4)), Fp, UVp))
    # Escala a partir do pivô do pescoço: cabe no kart com folga (largura < 0,8 m).
    k = 0.94
    return [(p[0], p[1] * k) + tuple(p[2:]) for p in parts]


def build_arm(fore):
    S = Sculpt()
    if not fore:
        S.add(round_cone(v3(0, 0, 0), v3(0, L1, 0), 0.068, 0.058), "fabric")
        S.add(ellipsoid(v3(0, 0.11, 0), (0.07, 0.08, 0.068)), "fabric", 0.03)
        S.add(round_cone(v3(0, 0.02, 0), v3(0, 0.045, 0), 0.072, 0.072), "metal", 0.004)   # rolamento do ombro
        S.add(sphere(v3(0, L1, 0), 0.058), "fabric", 0.015)
        S.disp(limb_folds(v3(0, 0, 0), v3(0, L1, 0), 0.064, 0.007))
    else:
        S.add(round_cone(v3(0, 0, 0), v3(0, L2 - 0.06, 0), 0.058, 0.05), "fabric")
        S.add(ellipsoid(v3(0, 0.07, 0), (0.062, 0.075, 0.06)), "fabric", 0.03)
        S.add(round_cone(v3(0, L2 - 0.065, 0), v3(0, L2 - 0.04, 0), 0.06, 0.06), "metal", 0.004)   # anel do punho
        S.add(round_cone(v3(0, L2 - 0.045, 0), v3(0, L2 - 0.004, 0), 0.054, 0.058), "glove", 0.006)  # cano da luva
        S.disp(limb_folds(v3(0, 0, 0), v3(0, L2 - 0.06, 0), 0.056, 0.006, ((0.08, 0.03, 0.0, 1.0), (0.16, 0.035, 2.0, 0.7), (0.3, 0.05, 4.1, 0.3))))
    V, F, N = S.mesh(0.002, 2400)
    mats = np.array(["fabric"] * len(F))
    parts = split_by_material(V, F, N, mats, colorize(S, {"fabric": WHITE, "metal": METAL, "glove": WHITE}, 0.01, 0.003))
    if not fore:
        # Emblema UNIFEOB no braço (lado de fora: +X local do braço não é fixo; disco nos dois lados).
        for sx in (-1.0, 1.0):
            Vp, Fp, Np, UVp = surface_patch(S, v3(sx * 0.07, 0.1, 0), v3(sx, 0, 0), v3(0, 1, 0), 0.034)
            parts.append(("patch", Vp, Np, np.ones((len(Vp), 4)), Fp, UVp))
    return parts


def build_hand(s):
    S = Sculpt()
    S.add(ellipsoid(v3(0, 0.045, 0), (0.046, 0.052, 0.03)), "glove")
    S.add(ellipsoid(v3(0, 0.012, 0), (0.04, 0.032, 0.03)), "glove", 0.015)
    S.add(ellipsoid(v3(0, 0.05, -0.022), (0.036, 0.04, 0.01)), "palm", 0.006)         # palma cinza
    for j in range(2):
        fx = s * (0.013 + 0.021 * j)
        S.add(ellipsoid(v3(fx, 0.082, -0.017), (0.013, 0.024, 0.016), rot_x(-0.9)), "glove", 0.01)
    tb_ = v3(-s * 0.034, 0.03, -0.013)
    tt = v3(-s * 0.019, 0.074, -0.04)
    S.add(round_cone(tb_, tt, 0.017, 0.014), "glove", 0.012)
    S.add(sphere(tt, 0.016), "glove", 0.006)
    V, F, N = S.mesh(0.0012, 2000)
    return split_by_material(V, F, N, np.array(["glove"] * len(F)), colorize(S, {"glove": WHITE, "palm": GREY}, 0.006, 0.003))


def build_finger():
    S = Sculpt()
    S.add(round_cone(v3(0, 0, 0), v3(0, 0.05, 0), 0.0148, 0.0132), "glove")
    S.add(sphere(v3(0, 0.026, 0.003), 0.0138), "glove", 0.008)
    S.add(ellipsoid(v3(0, 0.03, -0.01), (0.011, 0.025, 0.006)), "palm", 0.004)
    V, F, N = S.mesh(0.0008, 600)
    return split_by_material(V, F, N, np.array(["glove"] * len(F)), colorize(S, {"glove": WHITE, "palm": GREY}, 0.004, 0.002))


if __name__ == "__main__":
    t0 = time.time()
    w = GlbWriter()
    for name, fn in [("Suit", build_suit), ("Helmet", build_helmet), ("UpperArm", lambda: build_arm(False)),
                     ("Forearm", lambda: build_arm(True)), ("HandL", lambda: build_hand(-1.0)),
                     ("HandR", lambda: build_hand(1.0)), ("Finger", build_finger)]:
        t1 = time.time()
        parts = fn()
        w.add_node(name, parts)
        print("  %-9s %6d tris  %s  (%.1f s)" % (name, sum(len(p[4]) for p in parts), "/".join(p[0] for p in parts), time.time() - t1))
    path = os.path.join(OUT, "astronaut.glb")
    w.save(path)
    print("astronauta -> %s (%.1f s)" % (path, time.time() - t0))
