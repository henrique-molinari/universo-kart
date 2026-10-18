"""Escultura por campos de distância (SDF) -> malha (marching cubes) -> redução -> glTF (.glb).

Biblioteca usada por tools/sculpt/sculpt_characters.py. Formas orgânicas contínuas: primitivas
(elipsoides, cones arredondados, tubos ao longo de curvas, caixas arredondadas) combinadas com
união suave (smin), subtração suave e deslocamentos (vincos, rugas). As normais finais vêm do
gradiente do próprio campo (superfície lisa, sem facetas), cores por vértice com oclusão ambiente
"assada" (sondagem do campo ao longo da normal), um material por região (rótulo do primitivo mais
próximo).

Dependências: pip install numpy scipy scikit-image fast-simplification pygltflib
Regerar os modelos: python tools/sculpt/sculpt_characters.py && python tools/sculpt/sculpt_pilots.py
(o Godot reimporta os .glb de assets/characters e gera os LODs automaticamente).
"""
import numpy as np
from skimage.measure import marching_cubes
import fast_simplification
import pygltflib

BIG = 1.0


def v3(*a):
    return np.array(a, dtype=np.float64)


def norm(v):
    v = np.asarray(v, dtype=np.float64)
    return v / np.linalg.norm(v)


def rot_x(a):
    c, s = np.cos(a), np.sin(a)
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]], dtype=np.float64)


def rot_y(a):
    c, s = np.cos(a), np.sin(a)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]], dtype=np.float64)


def rot_z(a):
    c, s = np.cos(a), np.sin(a)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]], dtype=np.float64)


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def smin(a, b, k):
    if k <= 0.0:
        return np.minimum(a, b)
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
    return b * (1 - h) + a * h - k * h * (1.0 - h)


def ssub(a, b, k):
    """Subtrai b de a com borda suave."""
    if k <= 0.0:
        return np.maximum(a, -b)
    h = np.clip(0.5 - 0.5 * (a + b) / k, 0.0, 1.0)
    return a * (1 - h) + (-b) * h + k * h * (1.0 - h)


# ------------------------------------------------------------------ primitivas (P: (N,3))

def ellipsoid(c, r, B=None):
    c = np.asarray(c, float)
    r = np.asarray(r, float)

    def f(P):
        q = P - c
        if B is not None:
            q = q @ B
        k0 = np.linalg.norm(q / r, axis=1)
        k1 = np.linalg.norm(q / (r * r), axis=1)
        return k0 * (k0 - 1.0) / np.maximum(k1, 1e-9)
    f.bounds = (c - r.max(), c + r.max())
    return f


def sphere(c, r):
    c = np.asarray(c, float)

    def f(P):
        return np.linalg.norm(P - c, axis=1) - r
    f.bounds = (c - r, c + r)
    return f


def round_cone(a, b, r1, r2):
    """Cone arredondado (iq): esfera r1 em a, esfera r2 em b, tangentes ligando."""
    a = np.asarray(a, float)
    b = np.asarray(b, float)
    ba = b - a
    l2 = ba @ ba
    rr = r1 - r2
    a2 = l2 - rr * rr
    il2 = 1.0 / l2

    def f(P):
        pa = P - a
        y = pa @ ba
        z = y - l2
        x = pa * l2 - y[:, None] * ba
        x2 = np.einsum("ij,ij->i", x, x)
        y2 = y * y * l2
        z2 = z * z * l2
        k = np.sign(rr) * rr * rr * x2
        d3 = (np.sqrt(np.maximum(x2 * a2 * il2, 0.0)) + y * rr) * il2 - r1
        d = np.where(np.sign(y) * a2 * y2 < k, np.sqrt(x2 + y2) * il2 - r1, d3)
        d = np.where(np.sign(z) * a2 * z2 > k, np.sqrt(x2 + z2) * il2 - r2, d)
        return d
    m = max(r1, r2)
    f.bounds = (np.minimum(a, b) - m, np.maximum(a, b) + m)
    return f


def round_box(c, half, r, B=None):
    c = np.asarray(c, float)
    half = np.asarray(half, float)

    def f(P):
        q = P - c
        if B is not None:
            q = q @ B
        q = np.abs(q) - half + r
        return np.linalg.norm(np.maximum(q, 0.0), axis=1) + np.minimum(q.max(axis=1), 0.0) - r
    e = np.linalg.norm(half)
    f.bounds = (c - e, c + e)
    return f


def tube(points, radii):
    """Tubo ao longo de uma polilinha (raio interpolado por segmento)."""
    pts = np.asarray(points, float)
    rad = np.asarray(radii, float) * np.ones(len(pts))

    def f(P):
        d = np.full(len(P), 1e9)
        for i in range(len(pts) - 1):
            a, b = pts[i], pts[i + 1]
            ba = b - a
            t = np.clip(((P - a) @ ba) / (ba @ ba), 0.0, 1.0)
            q = P - (a + t[:, None] * ba)
            d = np.minimum(d, np.linalg.norm(q, axis=1) - (rad[i] + (rad[i + 1] - rad[i]) * t))
        return d
    m = rad.max()
    f.bounds = (pts.min(axis=0) - m, pts.max(axis=0) + m)
    return f


def local(f, margin):
    """Só avalia f dentro da caixa (bounds + margem); fora devolve um valor grande (mais rápido)."""
    lo = f.bounds[0] - margin
    hi = f.bounds[1] + margin

    def g(P):
        inside = np.all((P >= lo) & (P <= hi), axis=1)
        out = np.full(len(P), BIG)
        if inside.any():
            out[inside] = f(P[inside])
        return out
    g.bounds = (lo, hi)
    return g


# ------------------------------------------------------------------ escultura

class Sculpt:
    """Sequência de operações: união suave rotulada, subtração suave e deslocamento."""

    def __init__(self):
        self.ops = []

    def add(self, f, label, k=0.0):
        self.ops.append(("u", local(f, k + 0.02), label, k))
        return self

    def sub(self, f, k=0.0):
        self.ops.append(("s", local(f, k + 0.02), None, k))
        return self

    def disp(self, f):
        self.ops.append(("d", f, None, 0.0))
        return self

    def sdf(self, P):
        d = None
        for op, f, _, k in self.ops:
            if op == "u":
                x = f(P)
                d = x if d is None else smin(d, x, k)
            elif op == "s":
                d = ssub(d, f(P), k)
            else:
                d = d + f(P)
        return d

    def label(self, P):
        best = np.full(len(P), np.inf)
        lab = np.empty(len(P), dtype=object)
        for op, f, l, _ in self.ops:
            if op == "u":
                x = f(P)
                m = x < best
                best[m] = x[m]
                lab[m] = l
        return lab

    def weights(self, P, sigma=0.004):
        """Pesos suaves por rótulo (transições de cor sem serrilhado entre regiões)."""
        w = {}
        for op, f, l, _ in self.ops:
            if op == "u":
                x = np.exp(-np.maximum(f(P), 0.0) / sigma)
                w[l] = np.maximum(w[l], x) if l in w else x
        tot = sum(w.values())
        return {l: v / np.maximum(tot, 1e-12) for l, v in w.items()}

    def bounds(self):
        los = [f.bounds[0] for op, f, _, _ in self.ops if op == "u"]
        his = [f.bounds[1] for op, f, _, _ in self.ops if op == "u"]
        return np.min(los, axis=0), np.max(his, axis=0)

    def normals(self, P, h):
        e = h * 0.5
        g = np.zeros_like(P)
        for i in range(3):
            o = np.zeros(3)
            o[i] = e
            g[:, i] = self.sdf(P + o) - self.sdf(P - o)
        return g / np.maximum(np.linalg.norm(g, axis=1, keepdims=True), 1e-12)

    def ao(self, P, N, dist=0.012):
        """Oclusão: quanto o campo "abre" ao se afastar da superfície (0 = vinco fundo)."""
        a = np.clip(self.sdf(P + N * dist) / dist, 0.0, 1.0)
        b = np.clip(self.sdf(P + N * dist * 2.5) / (dist * 2.5), 0.0, 1.0)
        return np.clip(0.5 * a + 0.5 * b, 0.0, 1.0)

    def mesh(self, h, tris, coarse=4, nrm_eps=None):
        """Volume esparso (só perto da superfície) -> marching cubes -> redução para ~tris."""
        lo, hi = self.bounds()
        lo = lo - 2 * h * coarse
        hi = hi + 2 * h * coarse
        H = h * coarse
        cs = np.ceil((hi - lo) / H).astype(int) + 1
        ci = np.stack(np.meshgrid(*[np.arange(n) for n in cs], indexing="ij"), -1).reshape(-1, 3)
        dc = self.sdf(lo + ci * H).reshape(cs)
        near = np.abs(dc) < H * 2.5
        # Dilata 1 célula grossa (segurança na fronteira).
        from scipy.ndimage import binary_dilation
        near = binary_dilation(near, iterations=1)
        fs = (cs - 1) * coarse + 1
        sign = np.where(dc < 0, -H, H).astype(np.float32)
        vol = np.repeat(np.repeat(np.repeat(sign, coarse, 0), coarse, 1), coarse, 2)[: fs[0], : fs[1], : fs[2]]
        mask = np.repeat(np.repeat(np.repeat(near, coarse, 0), coarse, 1), coarse, 2)[: fs[0], : fs[1], : fs[2]]
        idx = np.argwhere(mask)
        for s in range(0, len(idx), 2_000_000):
            ii = idx[s: s + 2_000_000]
            vol[ii[:, 0], ii[:, 1], ii[:, 2]] = self.sdf(lo + ii * h).astype(np.float32)
        verts, faces, _, _ = marching_cubes(vol, 0.0, spacing=(h, h, h))
        verts = verts + lo
        if len(faces) > tris:
            verts, faces = fast_simplification.simplify(verts.astype(np.float32), faces.astype(np.int32), 1.0 - tris / len(faces), agg=7)
        verts = verts.astype(np.float64)
        # Projeta de volta na superfície exata (a redução tira os vértices um pouco do lugar).
        for _ in range(2):
            n = self.normals(verts, h)
            verts = verts - n * self.sdf(verts)[:, None]
        # Normais lisas: gradiente amostrado num raio maior que o voxel (suaviza vincos de união/subtração).
        n = self.normals(verts, nrm_eps * 2.0 if nrm_eps else h)
        # marching_cubes devolve triângulos no sentido horário visto de fora: Godot/glTF querem anti-horário.
        tri_n = np.cross(verts[faces[:, 1]] - verts[faces[:, 0]], verts[faces[:, 2]] - verts[faces[:, 0]])
        if np.einsum("ij,ij->i", tri_n, n[faces[:, 0]]).mean() < 0:
            faces = faces[:, ::-1]
        return verts, faces.astype(np.int64), n


# ------------------------------------------------------------------ ruído (variação de cor)

def noise3(P, freq, seed=0.0):
    """Ruído suave barato (soma de senos rotacionados), em [-1, 1]."""
    x = P * freq
    s = np.sin(x[:, 0] * 1.7 + seed) * np.sin(x[:, 1] * 1.3 + 0.7 + seed) * np.sin(x[:, 2] * 1.9 + 1.3)
    s += 0.5 * np.sin(x[:, 0] * 3.1 - x[:, 2] * 2.3 + 2.1 + seed) * np.sin(x[:, 1] * 2.9 + 0.4)
    s += 0.25 * np.sin((x[:, 0] + x[:, 1]) * 5.3 + seed * 2.0) * np.sin(x[:, 2] * 6.1 + 1.1)
    return s / 1.75


# ------------------------------------------------------------------ glTF

class GlbWriter:
    """Nós com malhas; cada malha com uma primitiva por material (vértices próprios por material:
    as costuras ficam na mesma posição e com a mesma normal, então não aparecem)."""

    def __init__(self):
        self.g = pygltflib.GLTF2(scene=0, scenes=[pygltflib.Scene(nodes=[])])
        self.blob = bytearray()
        self.mats = {}

    def _view(self, arr, target):
        data = arr.tobytes()
        while len(self.blob) % 4:
            self.blob.append(0)
        off = len(self.blob)
        self.blob.extend(data)
        self.g.bufferViews.append(pygltflib.BufferView(buffer=0, byteOffset=off, byteLength=len(data), target=target))
        return len(self.g.bufferViews) - 1

    def _acc(self, arr, ctype, typ, target, minmax=False):
        bv = self._view(arr, target)
        acc = pygltflib.Accessor(bufferView=bv, componentType=ctype, count=len(arr), type=typ)
        if minmax:
            acc.min = arr.min(axis=0).tolist()
            acc.max = arr.max(axis=0).tolist()
        self.g.accessors.append(acc)
        return len(self.g.accessors) - 1

    def material(self, name):
        if name not in self.mats:
            self.g.materials.append(pygltflib.Material(name=name, pbrMetallicRoughness=pygltflib.PbrMetallicRoughness(roughnessFactor=0.6, metallicFactor=0.0)))
            self.mats[name] = len(self.g.materials) - 1
        return self.mats[name]

    def add_node(self, name, parts):
        """parts: lista de (material, verts (N,3), normals (N,3), colors (N,4), faces (M,3)[, uv (N,2)])."""
        prims = []
        for part in parts:
            mat, V, N, C, F = part[:5]
            if len(F) == 0:
                continue
            a_pos = self._acc(V.astype(np.float32), pygltflib.FLOAT, pygltflib.VEC3, pygltflib.ARRAY_BUFFER, True)
            a_nrm = self._acc(N.astype(np.float32), pygltflib.FLOAT, pygltflib.VEC3, pygltflib.ARRAY_BUFFER)
            a_col = self._acc(C.astype(np.float32), pygltflib.FLOAT, pygltflib.VEC4, pygltflib.ARRAY_BUFFER)
            a_idx = self._acc(F.astype(np.uint32).reshape(-1), pygltflib.UNSIGNED_INT, pygltflib.SCALAR, pygltflib.ELEMENT_ARRAY_BUFFER)
            attrs = pygltflib.Attributes(POSITION=a_pos, NORMAL=a_nrm, COLOR_0=a_col)
            if len(part) > 5:
                attrs.TEXCOORD_0 = self._acc(part[5].astype(np.float32), pygltflib.FLOAT, pygltflib.VEC2, pygltflib.ARRAY_BUFFER)
            prims.append(pygltflib.Primitive(attributes=attrs, indices=a_idx, material=self.material(mat)))
        self.g.meshes.append(pygltflib.Mesh(name=name, primitives=prims))
        self.g.nodes.append(pygltflib.Node(name=name, mesh=len(self.g.meshes) - 1))
        self.g.scenes[0].nodes.append(len(self.g.nodes) - 1)

    def save(self, path):
        self.g.buffers = [pygltflib.Buffer(byteLength=len(self.blob))]
        self.g.set_binary_blob(bytes(self.blob))
        self.g.save_binary(path)


def srgb_to_linear(c):
    c = np.asarray(c, float)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def split_by_material(V, F, N, mats_per_face, color_fn):
    """Uma parte por material: copia os vértices usados e pinta com color_fn(V, N, material)."""
    parts = []
    for m in sorted(set(mats_per_face)):
        sel = F[mats_per_face == m]
        used, inv = np.unique(sel.reshape(-1), return_inverse=True)
        Vm, Nm = V[used], N[used]
        C = color_fn(Vm, Nm, m)
        parts.append((m, Vm, Nm, C, inv.reshape(-1, 3)))
    return parts


# ------------------------------------------------------------------ malhas paramétricas (peças lisas)

def param_ellipsoid(center, frame, radii, nu=40, nv=28):
    """Elipsoide (frame = matriz 3x3 com os eixos nas colunas). Devolve V, F, N e as coordenadas locais
    normalizadas (q no elipsoide unitário) para colorir."""
    center = np.asarray(center, float)
    radii = np.asarray(radii, float)
    us = np.linspace(0, 2 * np.pi, nu + 1)
    vs = np.linspace(0, np.pi, nv + 1)
    uu, vv = np.meshgrid(us, vs, indexing="ij")
    q = np.stack([np.cos(uu) * np.sin(vv), np.sin(uu) * np.sin(vv), np.cos(vv)], -1).reshape(-1, 3)
    V = center + (q * radii) @ frame.T
    N = (q / radii) @ frame.T
    N /= np.linalg.norm(N, axis=1, keepdims=True)
    F = []
    for i in range(nu):
        for j in range(nv):
            a = i * (nv + 1) + j
            b = (i + 1) * (nv + 1) + j
            F.append((a, b, a + 1))
            F.append((b, b + 1, a + 1))
    F = np.array(F, dtype=np.int64)
    tri_n = np.cross(V[F[:, 1]] - V[F[:, 0]], V[F[:, 2]] - V[F[:, 0]])
    if np.einsum("ij,ij->i", tri_n, N[F[:, 0]]).mean() < 0:
        F = F[:, ::-1]
    return V, F, N, q


def tube_mesh(points, radii, segs=8):
    """Tubo liso ao longo de uma polilinha (pontas fechadas em leque)."""
    P = np.asarray(points, float)
    R = np.asarray(radii, float) * np.ones(len(P))
    V, N = [], []
    for i in range(len(P)):
        t = P[min(i + 1, len(P) - 1)] - P[max(i - 1, 0)]
        t /= np.linalg.norm(t)
        ref = np.array([0, 1, 0]) if abs(t[1]) < 0.9 else np.array([1, 0, 0])
        e1 = np.cross(t, ref)
        e1 /= np.linalg.norm(e1)
        e2 = np.cross(t, e1)
        for k in range(segs):
            a = 2 * np.pi * k / segs
            d = e1 * np.cos(a) + e2 * np.sin(a)
            V.append(P[i] + d * R[i])
            N.append(d)
    F = []
    for i in range(len(P) - 1):
        for k in range(segs):
            a = i * segs + k
            b = i * segs + (k + 1) % segs
            F.append((a, a + segs, b))
            F.append((b, a + segs, b + segs))
    for end, sgn in ((0, -1), (len(P) - 1, 1)):
        t = P[end] - P[end - sgn] if sgn > 0 else P[0] - P[1]
        t /= np.linalg.norm(t)
        V.append(P[end] + t * R[end] * 0.6)
        N.append(t)
        c = len(V) - 1
        for k in range(segs):
            a = end * segs + k
            b = end * segs + (k + 1) % segs
            F.append((a, b, c) if sgn > 0 else (b, a, c))
    V, N, F = np.array(V), np.array(N), np.array(F, dtype=np.int64)
    tri_n = np.cross(V[F[:, 1]] - V[F[:, 0]], V[F[:, 2]] - V[F[:, 0]])
    cen = V[F].mean(axis=1)
    if np.einsum("ij,ij->i", tri_n, N[F[:, 0]]).mean() < 0:
        F = F[:, ::-1]
    return V, F, N


def surface_hit(sdf, origin, direction, far=1.0, steps=60):
    """Primeiro ponto da superfície ao longo do raio (bisseção entre dentro e fora)."""
    o = np.asarray(origin, float)
    d = np.asarray(direction, float) / np.linalg.norm(direction)
    ts = np.linspace(0, far, steps)
    vals = sdf(o + ts[:, None] * d)
    i = np.argmax(vals > 0)
    lo, hi = ts[max(i - 1, 0)], ts[i]
    for _ in range(40):
        m = 0.5 * (lo + hi)
        if sdf((o + m * d)[None, :])[0] > 0:
            hi = m
        else:
            lo = m
    return o + hi * d


def merge(parts):
    """Junta (V, F, N, C) em uma só lista de vértices/triângulos."""
    Vs, Fs, Ns, Cs, off = [], [], [], [], 0
    for V, F, N, C in parts:
        Vs.append(V)
        Fs.append(F + off)
        Ns.append(N)
        Cs.append(C)
        off += len(V)
    return np.vstack(Vs), np.vstack(Fs), np.vstack(Ns), np.vstack(Cs)


def surface_patch(S, center, normal, up, radius, res=12, lift=0.0015, start=0.05):
    """Emblema circular colado à superfície (disco projetado no campo S), com UV 0..1."""
    n = norm(normal)
    x = norm(np.cross(up, n))
    y = np.cross(n, x)
    V, UV = [], []
    for i in range(res + 1):
        for j in range(res + 1):
            u = i / res * 2 - 1
            v = j / res * 2 - 1
            # Parte de dentro do volume e sai pela normal (surface_hit espera a origem dentro).
            p0 = center + (x * u + y * v) * radius - n * 0.025
            p = surface_hit(S.sdf, p0, n, start + 0.1)
            V.append(p)
            UV.append((u * 0.5 + 0.5, 0.5 - v * 0.5))
    V = np.array(V)
    N = S.normals(V, 0.004)
    V = V + N * lift
    F = []
    for i in range(res):
        for j in range(res):
            a = i * (res + 1) + j
            b = a + res + 1
            F.append((a, b, a + 1))
            F.append((b, b + 1, a + 1))
    F = np.array(F, dtype=np.int64)
    tri_n = np.cross(V[F[:, 1]] - V[F[:, 0]], V[F[:, 2]] - V[F[:, 0]])
    if np.einsum("ij,ij->i", tri_n, N[F[:, 0]]).mean() < 0:
        F = F[:, ::-1]
    return V, F, N, np.array(UV)
