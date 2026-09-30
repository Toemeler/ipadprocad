"""Point-in-solid by ray parity against a closed triangle mesh."""
import numpy as np


class MeshSolid:
    def __init__(self, V, T):
        self.a = V[T[:, 0]]
        self.e1 = V[T[:, 1]] - self.a
        self.e2 = V[T[:, 2]] - self.a
        self.lo, self.hi = V.min(0), V.max(0)

    def _hits(self, p, d):
        h = np.cross(d, self.e2)
        det = np.einsum('ij,ij->i', self.e1, h)
        ok = np.abs(det) > 1e-14
        inv = np.where(ok, 1.0 / np.where(ok, det, 1.0), 0.0)
        s = p - self.a
        u = np.einsum('ij,ij->i', s, h) * inv
        q = np.cross(s, self.e1)
        v = (q @ d) * inv
        t = np.einsum('ij,ij->i', self.e2, q) * inv
        return int(np.sum(ok & (u >= 0) & (v >= 0) & (u + v <= 1) & (t > 1e-9)))

    def contains(self, p):
        p = np.asarray(p, float)
        if np.any(p < self.lo) or np.any(p > self.hi):
            return False
        votes = 0
        for d in ((0.5773, 0.5774, 0.5775), (-0.3, 0.8, 0.52), (0.71, -0.4, -0.58)):
            d = np.array(d) / np.linalg.norm(d)
            votes += self._hits(p, d) % 2
        return votes >= 2
