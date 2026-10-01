"""Reader for Ogre-Next binary meshes ([MeshSerializer_v2.1 R2]), as shipped by Stunt Rally 3.

Format reference: OGRECave/ogre-next OgreMain/src/OgreMesh2SerializerImpl.cpp (chunks: uint16 id + uint32 size).
Only what we need: per submesh -> material name, LOD0 positions/normals/uvs/indices.
"""
import struct

M_HEADER, M_MESH, M_SUBMESH, M_SUBMESH_LOD = 0x1000, 0x3000, 0x4000, 0x4300
M_LOD_OP, M_GEOM, M_GEOM_DECL, M_GEOM_VB, M_GEOM_EXT = 0x4310, 0x4330, 0x4331, 0x4332, 0x4340

# VertexElementType -> (struct fmt, count, normalise divisor or None)
VET = {
	0: ("f", 1, None), 1: ("f", 2, None), 2: ("f", 3, None), 3: ("f", 4, None),
	4: ("B", 4, 255.0), 6: ("h", 2, None), 8: ("h", 4, None), 9: ("B", 4, None),
	10: ("B", 4, 255.0), 11: ("B", 4, 255.0), 17: ("H", 2, None), 19: ("H", 4, None),
	20: ("i", 1, None), 21: ("i", 2, None), 22: ("i", 3, None), 23: ("i", 4, None),
	24: ("I", 1, None), 25: ("I", 2, None), 26: ("I", 3, None), 27: ("I", 4, None),
	28: ("b", 4, None), 29: ("b", 4, 127.0), 30: ("B", 4, 255.0), 31: ("h", 2, 32767.0),
	32: ("h", 4, 32767.0), 33: ("H", 2, 65535.0), 34: ("H", 4, 65535.0), 35: ("e", 2, None), 36: ("e", 4, None),
}
VES_POSITION, VES_NORMAL, VES_DIFFUSE, VES_TEXCOORD, VES_TANGENT = 1, 4, 5, 7, 9


class _R:
	def __init__(self, data: bytes):
		self.d, self.p = data, 0

	def u8(self):
		self.p += 1
		return self.d[self.p - 1]

	def u16(self):
		v = struct.unpack_from("<H", self.d, self.p)[0]
		self.p += 2
		return v

	def u32(self):
		v = struct.unpack_from("<I", self.d, self.p)[0]
		self.p += 4
		return v

	def string(self):
		e = self.d.index(b"\n", self.p)
		s = self.d[self.p:e].decode("utf-8", "replace")
		self.p = e + 1
		return s

	def chunk(self):
		return self.u16(), self.u32()

	def eof(self):
		return self.p >= len(self.d)


def _qtangent_to_normal(q):
	x, y, z, w = q
	# Ogre QTangent: normal = quaternion's X axis
	return (1 - 2 * (y * y + z * z), 2 * (x * y + w * z), 2 * (x * z - w * y))


def _decode(decls, buffers, nverts):
	out = {"pos": [], "nrm": [], "uv": [], "col": []}
	for src, elems in enumerate(decls):
		buf = buffers[src]
		layout, uv_seen = [], 0
		for t, sem in elems:
			fmt, n, div = VET[t]
			layout.append((sem, fmt, n, div, t))
		stride = sum(struct.calcsize("<" + f * n) for _, f, n, _, _ in layout)
		for i in range(nverts):
			off = i * stride
			uv_seen = 0
			for sem, fmt, n, div, t in layout:
				vals = struct.unpack_from("<" + fmt * n, buf, off)
				off += struct.calcsize("<" + fmt * n)
				if div:
					vals = tuple(max(-1.0, v / div) for v in vals)
				if sem == VES_POSITION:
					out["pos"].append(vals[:3])
				elif sem == VES_NORMAL:
					out["nrm"].append(_qtangent_to_normal(vals) if n == 4 else vals[:3])
				elif sem == VES_TEXCOORD:
					if uv_seen == 0:
						out["uv"].append(vals[:2])
					uv_seen += 1
				elif sem == VES_DIFFUSE:
					out["col"].append(vals[:4])
	return out


def read_mesh(path):
	"""Returns list of submeshes: {material, pos, nrm, uv, col, idx}."""
	r = _R(open(path, "rb").read())
	if r.u16() != M_HEADER:
		raise ValueError("not an Ogre mesh: " + path)
	ver = r.string()
	if "v2.1" not in ver:
		raise ValueError("unsupported mesh version %s in %s" % (ver, path))
	cid, _ = r.chunk()
	assert cid == M_MESH
	r.string()  # lod strategy
	passes = r.u8()
	subs = []
	while not r.eof():
		start = r.p
		cid, size = r.chunk()
		if cid != M_SUBMESH:
			r.p = start + size
			continue
		mat = r.string()
		nb = r.u8()
		r.p += 2 * nb
		nlod = r.u8()
		lods = []
		for _ in range(passes * nlod):
			cid2, _ = r.chunk()
			assert cid2 == M_SUBMESH_LOD, hex(cid2)
			nidx = r.u32()
			idx = []
			if nidx:
				i32 = r.u8()
				fmt = "<%d%s" % (nidx, "I" if i32 else "H")
				idx = list(struct.unpack_from(fmt, r.d, r.p))
				r.p += struct.calcsize(fmt)
			lod = {"idx": idx, "geom": None, "ext": None}
			while not r.eof():
				p0 = r.p
				c, s = r.chunk()
				if c == M_GEOM:
					nv = r.u32()
					ns = r.u8()
					decls, bufs = [None] * ns, [None] * ns
					while True:
						p1 = r.p
						c2, s2 = r.chunk()
						if c2 == M_GEOM_DECL:
							for k in range(ns):
								decls[k] = [(r.u8(), r.u8()) for _ in range(r.u8())]
						elif c2 == M_GEOM_VB:
							src, bpv = r.u8(), r.u8()
							bufs[src] = r.d[r.p:r.p + bpv * nv]
							r.p += bpv * nv
						else:
							r.p = p1
							break
					lod["geom"] = (decls, bufs, nv)
				elif c == M_GEOM_EXT:
					lod["ext"] = r.u8()
				elif c == M_LOD_OP:
					r.u16()
				else:
					r.p = p0
					break
			lods.append(lod)
		l0 = lods[0]
		decls, bufs, nv = l0["geom"]
		sub = _decode(decls, bufs, nv)
		sub["idx"], sub["material"] = l0["idx"], mat
		subs.append(sub)
	return subs


if __name__ == "__main__":
	import sys
	for s in read_mesh(sys.argv[1]):
		print(s["material"], "verts", len(s["pos"]), "tris", len(s["idx"]) // 3, "uv", len(s["uv"]), "nrm", len(s["nrm"]),
			"first", s["pos"][:1], s["nrm"][:1])
