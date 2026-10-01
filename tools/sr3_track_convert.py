#!/usr/bin/env python3
"""Convert one Stunt Rally 3 track into Godot-ready data.

Usage: tools/sr3_track_convert.py <stuntrally3 repo> <tracks3 repo> <TrackDir> [out_dir]

Reads   heightmap.f32 + scene.xml + road.xml  (see docs/SR3_SURVEY.md)
Writes  <out>/terrain.f32       heights in Godot row order (row index along +Z, see "terrain" in track.json);
                                the game builds the render mesh + HeightMapShape3D from it at load
        <out>/splat.png         RGBA weights of the (max 4) terrain texture layers, same grid
        <out>/road.glb          road ribbon (UV.x across 0..1, UV.y metres along)
        <out>/track.json        start, checkpoints, racing line, lighting, vegetation instances, layer textures
        <out>/tex/*.jpg         terrain layer textures,  <out>/sky.jpg  sky panorama
        <out>/veg/*.glb         vegetation meshes (only licence-cleared ones, see VEG_ALLOWED)

Coordinates: SR3/Ogre world space is +Y up and matches Godot directly.
The heightmap row index runs along -Z: height(x, z) = H[row = (size/2 - z)/tri][col = (x + size/2)/tri]
(verified on Atm2-RedOakPark: start position and bridge clearances match only this mapping).
"""
import json, math, os, random, shutil, struct, subprocess, sys, zlib
import xml.etree.ElementTree as ET
sys.path.insert(0, os.path.dirname(__file__))
from ogre_mesh import read_mesh
from sr3_glb import find_texture, load_materials, write_glb

# Vegetation we have checked licences for (see CREDITS.md). Anything else in a track's layers is skipped.
VEG_ALLOWED = {
	"treeAR-26oakWide", "treeAO-25oakWMed", "treeAOY-27mplMed", "treeARk-12oakSm", "treeAOR-13oakWBig",
}
ROAD_LIFT = 0.12          # road surface above terrain (m)
VEG_LIMIT = 2600          # cap on total vegetation instances (performance budget)
VEG_GLOBAL_DENSITY = 1.0  # SR3 "trees" graphics setting


class Terrain:
	def __init__(self, path, tri):
		data = open(path, "rb").read()
		self.n = int(math.isqrt(len(data) // 4))
		self.h = struct.unpack("<%df" % (self.n * self.n), data)
		self.tri = tri
		self.size = self.n * tri

	def at(self, x, z):
		"""Bilinear height at world x, z."""
		n = self.n
		gx = (x + self.size / 2) / self.tri
		gz = (self.size / 2 - z) / self.tri
		gx = min(max(gx, 0.0), n - 1.001)
		gz = min(max(gz, 0.0), n - 1.001)
		ix, iz = int(gx), int(gz)
		fx, fz = gx - ix, gz - iz
		h = self.h
		a = h[iz * n + ix] * (1 - fx) + h[iz * n + ix + 1] * fx
		b = h[(iz + 1) * n + ix] * (1 - fx) + h[(iz + 1) * n + ix + 1] * fx
		return a * (1 - fz) + b * fz

	def vertex(self, col, row):
		"""World position of heightmap sample (col, row)."""
		return (col * self.tri - self.size / 2, self.h[row * self.n + col], self.size / 2 - row * self.tri)

	def normal(self, x, z):
		s = self.tri
		dx = self.at(x + s, z) - self.at(x - s, z)
		dz = self.at(x, z + s) - self.at(x, z - s)
		nx, ny, nz = -dx, 2 * s, -dz
		l = math.sqrt(nx * nx + ny * ny + nz * nz)
		return (nx / l, ny / l, nz / l)

	def angle(self, x, z):
		return math.degrees(math.acos(max(-1.0, min(1.0, self.normal(x, z)[1]))))


def smooth_band(v, lo, hi, sm):
	"""1 inside [lo, hi], fading out over sm outside (SR3-style layer range)."""
	if sm <= 0:
		return 1.0 if lo <= v <= hi else 0.0
	return max(0.0, min(1.0, (v - lo) / sm + 1.0)) * max(0.0, min(1.0, (hi - v) / sm + 1.0))


def value_noise(x, z, freq, seed):
	"""Cheap smooth 2D value noise in [0, 1]."""
	x, z = x * freq / 512.0, z * freq / 512.0
	ix, iz = math.floor(x), math.floor(z)
	fx, fz = x - ix, z - iz

	def r(i, j):
		v = math.sin(i * 127.1 + j * 311.7 + seed * 74.7) * 43758.5453
		return v - math.floor(v)
	ux, uz = fx * fx * (3 - 2 * fx), fz * fz * (3 - 2 * fz)
	a = r(ix, iz) * (1 - ux) + r(ix + 1, iz) * ux
	b = r(ix, iz + 1) * (1 - ux) + r(ix + 1, iz + 1) * ux
	return a * (1 - uz) + b * uz


def floats(s):
	return [float(t) for t in s.split()]


# ------------------------------------------------------------------ road spline
def hermite(p1, p2, t1, t2, t):
	t2_, t3 = t * t, t * t * t
	a, b, c, d = 2 * t3 - 3 * t2_ + 1, -2 * t3 + 3 * t2_, t3 - 2 * t2_ + t, t3 - t2_
	return a * p1 + b * p2 + c * t1 + d * t2


def build_road(road_xml, ter):
	root = ET.parse(road_xml).getroot()
	pts = []
	for p in root.iter("P"):
		x, y, z = floats(p.get("pos"))
		on_ter = int(p.get("onTer", "1")) == 1
		if on_ter:
			y = ter.at(x, z) + ROAD_LIFT
		pts.append({"pos": (x, y, z), "w": float(p.get("w", "7")), "onTer": on_ter,
			"roll": float(p.get("ar", "0")), "chkR": float(p.get("chkR", "0"))})
	geom = root.find("geom")
	idir = int(geom.get("iDir", "-1")) if geom is not None else -1
	dim = root.find("dim")
	len_dim = float(dim.get("lenDim", "1")) if dim is not None else 1.0
	wsteps = int(dim.get("widthSteps", "6")) if dim is not None else 6
	n = len(pts)
	tan = []
	for i in range(n):
		a, b = pts[(i - 1) % n]["pos"], pts[(i + 1) % n]["pos"]
		tan.append(tuple(0.5 * (b[k] - a[k]) for k in range(3)))
	wtan = [0.5 * (pts[(i + 1) % n]["w"] - pts[(i - 1) % n]["w"]) for i in range(n)]

	# sample centre line
	samples = []  # (pos, width, roll_deg, on_ter_weight, ctrl_index, t)
	for i in range(n):
		j = (i + 1) % n
		p1, p2 = pts[i]["pos"], pts[j]["pos"]
		seg_len = math.dist(p1, p2)
		steps = max(2, int(math.ceil(seg_len / max(len_dim, 1.0))))
		for s in range(steps):
			t = s / steps
			pos = tuple(hermite(p1[k], p2[k], tan[i][k], tan[j][k], t) for k in range(3))
			w = hermite(pts[i]["w"], pts[j]["w"], wtan[i], wtan[j], t)
			roll = pts[i]["roll"] * (1 - t) + pts[j]["roll"] * t
			ot = (1.0 if pts[i]["onTer"] else 0.0) * (1 - t) + (1.0 if pts[j]["onTer"] else 0.0) * t
			samples.append((pos, w, roll, ot, i, t))
	m = len(samples)

	verts, norms, uvs, idx = [], [], [], []
	rows = []
	along = 0.0
	for k in range(m + 1):
		pos, w, roll, ot, _, _ = samples[k % m]
		prv, nxt = samples[(k - 1) % m][0], samples[(k + 1) % m][0]
		if k > 0:
			along += math.dist(samples[(k - 1) % m][0], pos)
		tx, tz = nxt[0] - prv[0], nxt[2] - prv[2]
		tl = math.hypot(tx, tz) or 1.0
		sx, sz = -tz / tl, tx / tl  # flat side vector (right of travel in point order)
		row = []
		for c in range(wsteps + 1):
			u = c / wsteps
			off = (u - 0.5) * w
			x, z = pos[0] + sx * off, pos[2] + sz * off
			y_spline = pos[1] - math.sin(math.radians(roll)) * off
			y_ter = ter.at(x, z) + ROAD_LIFT
			y = y_ter * ot + y_spline * (1 - ot)
			row.append((x, y, z, u, along))
		rows.append(row)
	# smooth vertex normals from grid
	for k, row in enumerate(rows):
		for c, (x, y, z, u, v) in enumerate(row):
			verts.append((x, y, z))
			uvs.append((u, v))
	cols = wsteps + 1
	for k in range(len(rows)):
		for c in range(cols):
			a = rows[k][max(c - 1, 0)]
			b = rows[k][min(c + 1, cols - 1)]
			d = rows[max(k - 1, 0)][c]
			e = rows[min(k + 1, len(rows) - 1)][c]
			ux, uy, uz = b[0] - a[0], b[1] - a[1], b[2] - a[2]
			vx, vy, vz = e[0] - d[0], e[1] - d[1], e[2] - d[2]
			nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
			if ny < 0:
				nx, ny, nz = -nx, -ny, -nz
			l = math.sqrt(nx * nx + ny * ny + nz * nz) or 1.0
			norms.append((nx / l, ny / l, nz / l))
	for k in range(len(rows) - 1):
		for c in range(cols - 1):
			a, b = k * cols + c, k * cols + c + 1
			d, e = (k + 1) * cols + c, (k + 1) * cols + c + 1
			idx += [a, b, e, a, e, d]
	# fix winding so faces point up
	ax, ay, az = verts[idx[0]]; bx, by, bz = verts[idx[1]]; cx, cy, cz = verts[idx[2]]
	ny = (bz - az) * (cx - ax) - (bx - ax) * (cz - az)
	if ny < 0:  # glTF front face = counter-clockwise seen from the normal side
		for t in range(0, len(idx), 3):
			idx[t + 1], idx[t + 2] = idx[t + 2], idx[t + 1]
	# skirts: drop 1.2 m below each edge, facing outwards
	skirt_v, skirt_n, skirt_uv, skirt_i = [], [], [], []
	base = len(verts)
	for side, c in ((0, 0), (1, cols - 1)):
		start = base + len(skirt_v)
		for k, row in enumerate(rows):
			x, y, z, u, v = row[c]
			o = row[cols - 1 if c == 0 else 0]
			dx, dz = x - o[0], z - o[2]
			dl = math.hypot(dx, dz) or 1.0
			nrm = (dx / dl, 0.0, dz / dl)
			skirt_v += [(x, y, z), (x + nrm[0] * 0.8, y - 1.2, z + nrm[2] * 0.8)]
			skirt_n += [nrm, nrm]
			skirt_uv += [(u, v), (u + (-0.05 if c == 0 else 0.05), v)]
		for k in range(len(rows) - 1):
			a, b = start + 2 * k, start + 2 * k + 1
			d, e = a + 2, b + 2
			tri = [a, d, b, b, d, e] if side == 1 else [a, b, d, b, e, d]
			skirt_i += tri
	verts += skirt_v; norms += skirt_n; uvs += skirt_uv; idx += skirt_i
	road = {"pos": verts, "nrm": norms, "uv": uvs, "idx": idx, "col": [], "material": "road"}

	# guard rails along elevated (not on-terrain) stretches, a few samples past each end
	elevated = [samples[k % m][3] < 0.999 for k in range(m + 1)]
	near = [any(elevated[(k + d) % (m + 1)] for d in range(-4, 5)) for k in range(m + 1)]
	rv, rn, ruv, ri = [], [], [], []
	for c in (0, cols - 1):
		run = []
		for k in range(m + 1):
			if near[k]:
				run.append(k)
			if run and (not near[k] or k == m):
				if len(run) > 1:
					start = len(rv)
					for kk in run:
						x, y, z, u, v = rows[kk][c]
						o = rows[kk][cols - 1 if c == 0 else 0]
						dx, dz = o[0] - x, o[2] - z
						dl = math.hypot(dx, dz) or 1.0
						nrm = (dx / dl, 0.0, dz / dl)  # faces the road
						rv += [(x, y - 0.3, z), (x, y + 1.0, z)]
						rn += [nrm, nrm]
						ruv += [(v * 0.5, 0.0), (v * 0.5, 1.0)]
					for q in range(len(run) - 1):
						a = start + 2 * q
						ri += [a, a + 1, a + 2, a + 1, a + 3, a + 2]
				run = []
	rail = {"pos": rv, "nrm": rn, "uv": ruv, "idx": ri, "col": [], "material": "rail", "name": "rail"} if ri else None

	# racing line (centre) in driving order, checkpoints
	order = list(range(m)) if idir > 0 else [0] + list(range(m - 1, 0, -1))
	line = [{"p": [round(c, 3) for c in samples[k][0]], "w": round(samples[k][1], 2)} for k in order]
	checks = []
	ctrl_order = list(range(n)) if idir > 0 else [0] + list(range(n - 1, 0, -1))
	for i in ctrl_order:
		if pts[i]["chkR"] > 0:
			checks.append({"p": [round(c, 3) for c in pts[i]["pos"]], "r": round(pts[i]["chkR"] * pts[i]["w"], 2)})
	return road, rail, line, checks, samples


def fix_skirt_winding(road):
	"""Ensure every triangle's winding agrees with its vertex normals (glTF: CCW = front)."""
	v, nr, idx = road["pos"], road["nrm"], road["idx"]
	for t in range(0, len(idx), 3):
		a, b, c = idx[t], idx[t + 1], idx[t + 2]
		ux, uy, uz = (v[b][k] - v[a][k] for k in range(3))
		wx, wy, wz = (v[c][k] - v[a][k] for k in range(3))
		fn = (uy * wz - uz * wy, uz * wx - ux * wz, ux * wy - uy * wx)
		vn = nr[a]
		if fn[0] * vn[0] + fn[1] * vn[1] + fn[2] * vn[2] < 0:
			idx[t + 1], idx[t + 2] = c, b


# ------------------------------------------------------------------ terrain
def layer_weights(ter, layers, col, row):
	"""SR3-style layer blend at a heightmap sample: by slope angle, height and noise; later layers paint over."""
	x, y, z = ter.vertex(col, row)
	ang = ter.angle(x, z)
	w = []
	for li, L in enumerate(layers):
		v = smooth_band(ang, L["angMin"], L["angMax"], L["angSm"]) * smooth_band(y, L["hMin"], L["hMax"], L["hSm"])
		if L["noise"] > 0 and li > 0:
			v *= 1.0 - L["noise"] * (1.0 - value_noise(x, z, L["frq"], li) ** 0.7) * 0.8
		w.append(v)
	out = [0.0] * 4
	rest = 1.0
	for li in range(len(layers) - 1, -1, -1):
		take = rest * (w[li] if li > 0 else 1.0)
		out[li] = take
		rest -= take
	return out


def write_splat_png(path, ter, layers):
	"""RGBA8 PNG, pixel (col, godot_row) = weights; godot_row = n-1-row (row index along +Z)."""
	n = ter.n
	raw = bytearray()
	for gr in range(n):
		r = n - 1 - gr
		raw.append(0)  # filter: none
		for c in range(n):
			w = layer_weights(ter, layers, c, r)
			raw += bytes(int(max(0.0, min(1.0, v)) * 255 + 0.5) for v in w)
	def chunk(tag, data):
		return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
	png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", n, n, 8, 6, 0, 0, 0))
	png += chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b"")
	open(path, "wb").write(png)


def write_multi_glb(path, meshes):
	"""Write several meshes (each its own node) with vertex colours. Material 'name' only, no textures."""
	bin_ = bytearray()
	views, accessors, gl_meshes, nodes, mats = [], [], [], [], []
	mat_index = {}

	def acc(values, comps, ctype=5126, target=34962, minmax=False):
		fmt = {5126: "f", 5125: "I"}[ctype]
		flat = [c for v in values for c in (v if comps > 1 else (v,))]
		while len(bin_) % 4:
			bin_.append(0)
		data = struct.pack("<%d%s" % (len(flat), fmt), *flat)
		views.append({"buffer": 0, "byteOffset": len(bin_), "byteLength": len(data), "target": target})
		bin_.extend(data)
		a = {"bufferView": len(views) - 1, "componentType": ctype, "count": len(values),
			"type": {1: "SCALAR", 2: "VEC2", 3: "VEC3", 4: "VEC4"}[comps]}
		if minmax:
			a["min"] = [min(v[i] for v in values) for i in range(comps)]
			a["max"] = [max(v[i] for v in values) for i in range(comps)]
		accessors.append(a)
		return len(accessors) - 1

	for m in meshes:
		attrs = {"POSITION": acc(m["pos"], 3, minmax=True), "NORMAL": acc(m["nrm"], 3)}
		if m.get("uv"):
			attrs["TEXCOORD_0"] = acc(m["uv"], 2)
		if m.get("col"):
			attrs["COLOR_0"] = acc(m["col"], 4)
		if m["material"] not in mat_index:
			mats.append({"name": m["material"], "pbrMetallicRoughness": {"metallicFactor": 0.0, "roughnessFactor": 0.9}})
			mat_index[m["material"]] = len(mats) - 1
		prim = {"attributes": attrs, "indices": acc(m["idx"], 1, 5125, 34963), "material": mat_index[m["material"]]}
		gl_meshes.append({"name": m.get("name", m["material"]), "primitives": [prim]})
		nodes.append({"name": m.get("name", m["material"]), "mesh": len(gl_meshes) - 1})
	gltf = {"asset": {"version": "2.0", "generator": "takedown-racer sr3_track_convert"},
		"scene": 0, "scenes": [{"nodes": list(range(len(nodes)))}], "nodes": nodes, "meshes": gl_meshes,
		"materials": mats, "buffers": [{"byteLength": len(bin_)}], "bufferViews": views, "accessors": accessors}
	js = json.dumps(gltf, separators=(",", ":")).encode()
	js += b" " * (-len(js) % 4)
	while len(bin_) % 4:
		bin_.append(0)
	with open(path, "wb") as f:
		f.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(bin_)))
		f.write(struct.pack("<II", len(js), 0x4E4F534A) + js)
		f.write(struct.pack("<II", len(bin_), 0x004E4942) + bytes(bin_))


# ------------------------------------------------------------------ vegetation
def place_vegetation(scene, ter, samples, tws):
	veg = scene.find("veget")
	dens_trees = float(veg.get("densTrees2", "1")) if veg is not None else 1.0
	tr_rd = float(veg.get("trRdDist", "0")) if veg is not None else 0.0
	f_trees = VEG_GLOBAL_DENSITY * dens_trees / 1e6 * tws * tws
	# road proximity buckets (16 m) of (x, z, half width)
	buckets = {}
	for pos, w, *_ in samples[::2]:
		buckets.setdefault((int(pos[0] // 16), int(pos[2] // 16)), []).append((pos[0], pos[2], w * 0.5))

	def road_dist(x, z):
		bx, bz = int(x // 16), int(z // 16)
		best = 1e9
		for i in (-2, -1, 0, 1, 2):
			for j in (-2, -1, 0, 1, 2):
				for px, pz, hw in buckets.get((bx + i, bz + j), ()):
					best = min(best, math.hypot(x - px, z - pz) - hw)
		return best

	px_m = tws / 1024.0  # SR3 roadDensity.png pixel ~ this many metres
	rng = random.Random(1234)
	out = {}
	total = 0
	for lay in scene.iter("layer"):
		name = (lay.get("name") or "").replace(".mesh", "")
		if lay.get("on") != "1" or not name:
			continue
		if name not in VEG_ALLOWED:
			print("  skip vegetation (licence not cleared):", name)
			continue
		dens = float(lay.get("dens"))
		cnt = int(6000 * dens * f_trees)
		mn, mx = float(lay.get("minScale")), float(lay.get("maxScale"))
		max_ang = float(lay.get("maxTerAng", "90"))
		min_h, max_h = float(lay.get("minTerH", "-1e9")), float(lay.get("maxTerH", "1e9"))
		add_rd = float(lay.get("addTrRdDist", "0"))
		max_rd = float(lay.get("maxRdist", "100"))
		inst = []
		for _ in range(cnt):
			x = (rng.random() - 0.5) * tws
			z = (rng.random() - 0.5) * tws
			yaw = rng.random() * 360.0
			s = mn + rng.random() * (mx - mn)
			if ter.angle(x, z) > max_ang:
				continue
			y = ter.at(x, z)
			if y < min_h or y > max_h:
				continue
			d = road_dist(x, z)
			if d <= (tr_rd + add_rd) * px_m + 2.0:
				continue
			if max_rd < 20 and d > (tr_rd + add_rd + max_rd + 1) * px_m * 3:
				continue
			inst.append([round(x, 2), round(y - 0.1, 2), round(z, 2), round(yaw, 1), round(s, 3)])
		out[name] = inst
		total += len(inst)
	if total > VEG_LIMIT:  # thin uniformly to the performance budget
		keep = VEG_LIMIT / total
		for k in out:
			out[k] = [i for i in out[k] if rng.random() < keep]
	return out


def convert_veg_mesh(sr3, name, out_dir, mats):
	path = None
	for root, _, files in os.walk(os.path.join(sr3, "data", "models")):
		if name + ".mesh" in files:
			path = os.path.join(root, name + ".mesh")
			break
	subs = read_mesh(path)
	for uri in write_glb(os.path.join(out_dir, name + ".glb"), subs, mats, flip=False):
		src = find_texture(sr3, uri)
		if src:
			shutil.copy(src, os.path.join(out_dir, uri))
		else:
			print("  WARNING: texture not found", uri)


# ------------------------------------------------------------------ main
def color(attr):
	v = floats(attr)
	return [round(c, 3) for c in v[:3]]


def main():
	sr3, tracks, track = sys.argv[1], sys.argv[2], sys.argv[3]
	out = sys.argv[4] if len(sys.argv) > 4 else os.path.join(os.path.dirname(__file__), "..", "assets", "tracks", track)
	src = os.path.join(tracks, track)
	os.makedirs(os.path.join(out, "tex"), exist_ok=True)
	os.makedirs(os.path.join(out, "veg"), exist_ok=True)
	scene = ET.parse(os.path.join(src, "scene.xml")).getroot()
	td = scene.find("terrains/terrain")
	tri = float(td.get("triangle"))
	ter = Terrain(os.path.join(src, "heightmap.f32"), tri)
	print("terrain %dx%d, %.1f m" % (ter.n, ter.n, ter.size))

	# layers (max 4, enabled ones in order)
	layers = []
	for t in td.findall("texture"):
		if t.get("on") != "1" or not t.get("file"):
			continue
		nz = t.find("noise")
		layers.append({"file": t.get("file"), "scale": float(t.get("scale")),
			"angMin": float(t.get("angMin")), "angMax": float(t.get("angMax")), "angSm": float(t.get("angSm")),
			"hMin": float(t.get("hMin")), "hMax": float(t.get("hMax")), "hSm": float(t.get("hSm")),
			"noise": float(t.get("noise", "0")), "frq": float(nz.get("frq0", "30")) if nz is not None else 30.0})
	layers = layers[:4]
	for L in layers:
		srcf = find_texture(sr3, L["file"])
		shutil.copy(srcf, os.path.join(out, "tex", L["file"]))

	write_splat_png(os.path.join(out, "splat.png"), ter, layers)
	print("wrote splat.png")
	# collision heights in Godot HeightMapShape3D order (row index along +Z)
	n = ter.n
	with open(os.path.join(out, "terrain.f32"), "wb") as f:
		for r in range(n - 1, -1, -1):
			f.write(struct.pack("<%df" % n, *ter.h[r * n:(r + 1) * n]))

	road, rail, line, checks, samples = build_road(os.path.join(src, "road.xml"), ter)
	fix_skirt_winding(road)
	parts = [road]
	if rail:
		fix_skirt_winding(rail)
		parts.append(rail)
	write_multi_glb(os.path.join(out, "road.glb"), parts)
	print("wrote road.glb: %d tris, %d checkpoints, line %d pts" % (len(road["idx"]) // 3, len(checks), len(line)))

	# start: pos in Bullet coords (z up) -> Ogre/Godot (x, z, -y); car forward = Bullet +X rotated by quat
	st = scene.find("start")
	bx, by, bz = floats(st.get("pos"))
	qx, qy, qz, qw = floats(st.get("rot"))
	fx = 1 - 2 * (qy * qy + qz * qz)
	fy = 2 * (qx * qy + qz * qw)
	fwd = [fx, 0.0, -fy]
	fl = math.hypot(fwd[0], fwd[2]) or 1.0
	start = {"p": [bx, max(bz, ter.at(bx, -by) + 0.6), -by], "fwd": [fwd[0] / fl, 0.0, fwd[2] / fl]}

	veg = place_vegetation(scene, ter, samples, ter.size)
	mats = load_materials(sr3)
	for name in veg:
		convert_veg_mesh(sr3, name, os.path.join(out, "veg"), mats)
	print("vegetation:", {k: len(v) for k, v in veg.items()})

	# sky: SR3 skies are top-hemisphere strips (4:1); pad to a 2:1 panorama
	sky = scene.find("sky")
	sky_name = sky.get("material", "").split("/")[-1] if sky is not None else ""
	sky_src = find_texture(sr3, sky_name + ".jpg") if sky_name else None
	if sky_src:
		subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", sky_src, "-vf",
			"scale=4096:1024,pad=4096:2048:0:0:color=0x8a9aa8", "-q:v", "3", os.path.join(out, "sky.jpg")], check=True)

	fog = scene.find("fog")
	light = scene.find("light")
	info = {
		"name": track,
		"terrain": {"size": n, "spacing": tri, "origin": [-ter.size / 2, 0.0, -ter.size / 2 + tri],
			"layers": [{"file": "tex/" + L["file"], "scale": L["scale"]} for L in layers]},
		"start": start,
		"checkpoints": checks,
		"line": line,
		"sky": {"file": "sky.jpg" if sky_src else "", "yaw": float(sky.get("skyYaw", "0")) if sky is not None else 0.0},
		"fog": {"color": color(fog.get("color2", "0.6 0.7 0.8")), "start": float(fog.get("linStart", "100")),
			"end": float(fog.get("linEnd", "800"))} if fog is not None else None,
		"light": {"pitch": float(light.get("pitch", "45")), "yaw": float(light.get("yaw", "0"))} if light is not None else None,
		"vegetation": veg,
	}
	json.dump(info, open(os.path.join(out, "track.json"), "w"), separators=(",", ":"))
	print("wrote track.json")


if __name__ == "__main__":
	main()
