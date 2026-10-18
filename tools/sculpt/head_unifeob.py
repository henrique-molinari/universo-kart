"""Cabeça dos ETs (estilo do ET da UNIFEOB), feita como em produção de personagem estilizado:
formas primárias limpas (crânio grande e cheio, rosto que afina num queixo pequeno e redondo,
bochechas macias) e olhos construídos anatomicamente: o globo ocular fica DENTRO da cabeça e as
pálpebras são a própria pele que o envolve (casca colada ao globo) com uma abertura em amêndoa
inclinada — sem aros nem focinho. Nariz mínimo (duas narinas) e boca pequena.

Tudo no espaço do pivô do pescoço (nó Head do AlienDriver). Superfícies da malha "Head":
  skin, iris (íris funda), cornea (casca de vidro), glint (brilhos), lash (cílios), bow (laço).
"""
import numpy as np

from sdf import (Sculpt, ellipsoid, sphere, tube, v3, norm, smoothstep, noise3, param_ellipsoid, tube_mesh,
                 surface_hit, merge)

CRANIUM_C = v3(0, 0.44, 0.02)
EGG_C = v3(0, 0.39, 0.0)
EGG_R = v3(0.29, 0.335, 0.285)
SKIN = {"visitante": v3(0.34, 0.76, 0.13), "turista": v3(1.0, 0.42, 0.66)}
IRIS = {"visitante": v3(0.04, 0.3, 0.42), "turista": v3(0.4, 0.08, 0.48)}
BALL_R = v3(0.136, 0.1, 0.078)    # globo ocular (eixo maior, menor, profundidade)
LID_T = 0.005                       # espessura da pálpebra (casca sobre o globo)
APERTURE = (0.124, 0.084, 0.052)     # abertura em amêndoa: meia largura, altura de cima, altura de baixo
HEAD_SCALE = 0.94
HEAD_BACK = v3(0, 0, 0.025)


def egg(P):
    """Ovo alto e liso (referência do cliente): largo e redondo em cima, afinando suave até um queixo
    arredondado. Elipsoide com largura que diminui para baixo (sem emendas entre volumes)."""
    q = P - EGG_C
    s = np.clip(q[:, 1] / EGG_R[1], -1.2, 1.2)
    w = 0.62 + 0.38 * smoothstep(-1.1, 0.45, s)
    r = np.stack([EGG_R[0] * w, np.full(len(P), EGG_R[1]), EGG_R[2] * (0.72 + 0.28 * w)], 1)
    k0 = np.linalg.norm(q / r, axis=1)
    k1 = np.linalg.norm(q / (r * r), axis=1)
    return k0 * (k0 - 1.0) / np.maximum(k1, 1e-9)


egg.bounds = (v3(0, 0.38, 0) - 0.45, v3(0, 0.38, 0) + 0.45)


def base_head():
    S = Sculpt()
    S.add(egg, "skin")
    return S


def eye_frame(S0, s):
    p = surface_hit(S0.sdf, v3(s * 0.143, 0.355, 0.0), v3(0, 0, -1), 0.6)
    n = norm(S0.normals(p[None, :], 0.002)[0] + v3(s * 0.18, 0.02, 0.0))
    ey0 = norm(v3(0, 1, 0) - n * n[1])
    ex = norm(np.cross(n, ey0))
    if ex[0] < 0:
        ex = -ex
    r = s * 0.36                                  # amêndoa inclinada (canto externo alto)
    a = norm(ex * np.cos(r) + ey0 * np.sin(r))
    b = norm(np.cross(n, a))
    if b[1] < 0:
        b = -b
    c = p - n * 0.05                             # centro do globo, dentro da cabeça
    return c, a, b, n


def almond(c, a, b, W, Hu, Hl):
    """Distância 2D (no plano a,b do olho) a uma amêndoa: arco de cima mais alto que o de baixo."""
    Ru = (W * W + Hu * Hu) / (2 * Hu)
    Rl = (W * W + Hl * Hl) / (2 * Hl)

    def f(P):
        q = P - c
        u = q @ a
        v = q @ b
        du = np.sqrt(u * u + (v + (Ru - Hu)) ** 2) - Ru
        dl = np.sqrt(u * u + (v - (Rl - Hl)) ** 2) - Rl
        return np.maximum(du, dl)
    return f, Ru, Rl


def build_head(who):
    fem = who == "turista"
    S0 = base_head()
    S = base_head()
    eyes = [eye_frame(S0, s) + (s,) for s in (-1.0, 1.0)]
    W, Hu, Hl = APERTURE
    for c, a, b, n, s in eyes:
        F3 = np.stack([a, b, n], 1)
        # Pálpebras: casca de pele colada ao globo, fundida ao rosto (forma a órbita naturalmente).
        S.add(ellipsoid(c, BALL_R + LID_T, F3), "skin", 0.045)
        # Abertura em amêndoa só na frente do globo: revela o olho com uma borda de pálpebra macia.
        alm, _, _ = almond(c, a, b, W, Hu, Hl)

        def cut(P, alm=alm, c=c, n=n):
            return np.maximum(alm(P), -((P - c) @ n))
        cut.bounds = (c - 0.15, c + 0.15)
        S.sub(cut, 0.01)
    # Sem nariz (como na referência). Sorriso simples, cantos para cima.
    nostrils = []
    smile = []
    for j in range(13):
        x = -0.075 + 0.15 * j / 12
        smile.append(surface_hit(S0.sdf, v3(x, 0.19 + 3.2 * x * x, -0.05), v3(0, -0.05, -1), 0.4))
    smile = np.array(smile)
    S.sub(tube(smile, [0.0015] + ([0.0022] if fem else [0.0036]) * 11 + [0.0015]), 0.01)

    V, F, N = S.mesh(0.0018, 26000, nrm_eps=0.004)
    skin = SKIN[who]
    smile_tube = tube(smile, 0.002)

    def skin_color(Vm, Nm):
        q = Vm - CRANIUM_C
        dn = q / np.linalg.norm(q, axis=1, keepdims=True)
        ao = S.ao(Vm, Nm, 0.012)
        shade = 0.97 + 0.015 * noise3(Vm, 30.0) + 0.025 * noise3(Vm, 7.0, 3.0)
        shade += 0.05 * np.clip(dn[:, 1], 0, 1) - 0.04 * np.clip(-dn[:, 1], 0, 1)
        c = skin[None, :] * shade[:, None]
        # Pele das pálpebras levemente mais escura (sombra de contato com o olho).
        for (ce, a, b, n, s) in eyes:
            dball = np.linalg.norm((Vm - ce) / (BALL_R + LID_T * 2), axis=1)
            lid = np.exp(-((dball - 1.0) / 0.08) ** 2)
            c = c * (1 - 0.12 * lid[:, None])
        if fem:
            for s in (-1.0, 1.0):
                cd = v3(s * 0.12, 0.235, -0.205)
                bl = np.exp(-np.sum((Vm - cd) ** 2, axis=1) / (2 * 0.03 ** 2))
                c = c * (1 - 0.45 * bl[:, None]) + v3(1.0, 0.38, 0.52) * (0.45 * bl[:, None])
        for pn in nostrils:   # sombra suave nas narinas
            nd = np.linalg.norm(Vm - pn, axis=1)
            c = c * (1 - 0.45 * (1 - smoothstep(0.004, 0.009, nd)))[:, None]
        mouth = 1.0 - smoothstep(0.0015, 0.006, smile_tube(Vm))
        mcol = v3(0.72, 0.12, 0.3) if fem else skin * 0.4
        c = c * (1 - 0.7 * mouth[:, None]) + mcol * (0.7 * mouth[:, None])
        if fem:
            # Lábios só pintados (sem volume), afinando nos cantos da boca.
            q = Vm - smile[len(smile) // 2]
            lip = (1 - smoothstep(0.004, 0.0085, smile_tube(Vm))) * (1 - smoothstep(0.03, 0.05, np.abs(q[:, 0])))
            c = c * (1 - lip[:, None]) + v3(0.86, 0.3, 0.46) * lip[:, None]
        c = c * (0.6 + 0.4 * ao[:, None])
        return np.hstack([np.clip(c, 0, 1), np.ones((len(Vm), 1))])

    parts = [("skin", V, N, skin_color(V, N), F)]
    iris_parts, cornea_parts, glint_parts, lash_parts = [], [], [], []
    ic = IRIS[who]
    for c, a, b, n, s in eyes:
        Fm = np.stack([a, b, n], 1)
        Vc, Fc, Nc, _ = param_ellipsoid(c, Fm, BALL_R, 40, 28)
        cornea_parts.append((Vc, Fc, Nc, np.ones((len(Vc), 4))))
        Vi, Fi, Ni, qi = param_ellipsoid(c - n * 0.008, Fm, BALL_R * v3(0.97, 0.97, 0.93), 40, 28)
        # Olho de ET: preto profundo, com um anel escuro de cor perto da borda (mais forte embaixo).
        rho = np.sqrt(qi[:, 0] ** 2 + qi[:, 1] ** 2)
        front = qi[:, 2] > 0
        th = np.arctan2(qi[:, 1], qi[:, 0])
        fib = 0.75 + 0.25 * np.sin(th * 31.0 + np.sin(th * 7.0) * 2.0)
        ring = smoothstep(0.55, 0.75, rho) * (1 - smoothstep(0.88, 0.97, rho)) * front
        low = 0.55 + 0.45 * smoothstep(0.3, -0.6, qi[:, 1])
        col = np.tile(v3(0.003, 0.003, 0.005), (len(Vi), 1)) + ic[None, :] * (0.1 * ring * fib * low)[:, None]
        iris_parts.append((Vi, Fi, Ni, np.hstack([col, np.ones((len(Vi), 1))])))
        # Brilho em meia-lua acompanhando a borda de cima do olho + ponto pequeno embaixo.
        for u, v_, sz in ((-0.12, 0.5, (0.055, 0.009)), (0.42, -0.32, (0.01, 0.008))):
            w = np.sqrt(max(1 - u * u - v_ * v_, 0.0))
            gp = c + Fm @ (v3(u, v_, w) * BALL_R)
            gn = norm(Fm @ (v3(u, v_, w) / BALL_R))
            gx = norm(a - gn * (a @ gn))
            gy = np.cross(gn, gx)
            Vg, Fg, Ng, _ = param_ellipsoid(gp + gn * 0.0012, np.stack([gx, gy, gn], 1), v3(sz[0], sz[1], 0.0012), 16, 8)
            glint_parts.append((Vg, Fg, Ng, np.tile([0.95, 0.97, 1.0, 1.0], (len(Vg), 1))))
        if fem:
            # Cílios saindo da borda da pálpebra de cima, no terço externo, curvando para fora/cima.
            _, Ru, _ = almond(c, a, b, W, Hu, Hl)
            for j, uf in enumerate((0.45, 0.68, 0.88)):
                u = s * uf * W
                v = -(Ru - Hu) + np.sqrt(max(Ru * Ru - u * u, 0.0))
                rr = BALL_R + LID_T
                z = np.sqrt(max(1.0 - (u / rr[0]) ** 2 - (v / rr[1]) ** 2, 0.0)) * rr[2]
                p0 = c + a * u + b * v + n * z
                outd = norm(a * np.sign(u) * 0.8 + b * 0.6)
                L = 0.026 + 0.008 * j
                p1 = p0 + norm(outd * 0.4 + n * 0.75) * L * 0.5
                p2 = p1 + norm(outd * 0.75 + b * 0.35 + n * 0.1) * L * 0.5
                Vl, Fl, Nl = tube_mesh([p0, p1, p2], [0.0032, 0.0024, 0.001], 6)
                lash_parts.append((Vl, Fl, Nl, np.tile([0.035, 0.02, 0.035, 1.0], (len(Vl), 1))))
    for name, lst in (("iris", iris_parts), ("cornea", cornea_parts), ("glint", glint_parts), ("lash", lash_parts)):
        if lst:
            Vx, Fx, Nx, Cx = merge(lst)
            parts.append((name, Vx, Nx, Cx, Fx))
    if fem:
        parts.append(build_bow(S0))
    # Escala final (a partir da base do pescoço) e recuo: cabe no kart com folga.
    pivot = v3(0, 0.1, 0)
    return [(m, (V_ - pivot) * HEAD_SCALE + pivot + HEAD_BACK, N_, C_, F_) for m, V_, N_, C_, F_ in parts]


def build_bow(S0):
    """Laço vermelho de bolinhas brancas no alto da cabeça, inclinado para a direita."""
    d = norm(v3(0.4, 0.88, 0.1))
    base = surface_hit(S0.sdf, CRANIUM_C, d, 0.5)
    bn = S0.normals(base[None, :], 0.002)[0]
    bt = norm(v3(1, -0.25, 0) - bn * (bn @ v3(1, -0.25, 0)))
    bb = np.cross(bn, bt)
    B = Sculpt()
    knot = base + bn * 0.03
    B.add(ellipsoid(knot, (0.034, 0.032, 0.028), np.stack([bt, bn, bb], 1)), "knot")
    dots = []
    for s in (-1.0, 1.0):
        ang = s * 0.28
        lt = norm(bt * np.cos(ang) + bn * np.sin(ang))
        lc = knot + lt * s * 0.07 + bn * 0.006
        B.add(ellipsoid(lc, (0.07, 0.05, 0.034), np.stack([lt, np.cross(bb, lt), bb], 1)), "lobe", 0.018)
        for q in ((0.35, 0.3), (0.7, -0.15), (0.25, -0.5), (0.65, 0.45)):
            for side in (-1.0, 1.0):
                dots.append(lc + lt * s * 0.07 * q[0] + np.cross(bb, lt) * 0.05 * q[1] + bb * side * 0.032)
    V, F, N = B.mesh(0.0016, 3500)
    dots = np.array(dots)
    dmin = np.min(np.linalg.norm(V[:, None, :] - dots[None, :, :], axis=2), axis=1)
    spot = 1 - smoothstep(0.009, 0.012, dmin)
    ao = B.ao(V, N, 0.008)
    red = v3(0.9, 0.06, 0.2)
    c = red[None, :] * (1 - spot)[:, None] + v3(1.0, 0.97, 0.97) * spot[:, None]
    c = c * (0.6 + 0.4 * ao[:, None])
    return ("bow", V, N, np.hstack([np.clip(c, 0, 1), np.ones((len(V), 1))]), F)
