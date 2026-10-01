#!/usr/bin/env python3
"""Convert one Stunt Rally 3 car into Godot-ready files.

Usage: tools/sr3_car_to_glb.py <stuntrally3 repo> <CAR_ID> [out_dir]
Writes  <out>/<ID>_<part>.glb  (body, glass, interior, wheel...),  diffuse textures,  and  <ID>.car.json
(parsed .car sim file from data/carsim/normal, positions converted to Godot axes).

Axes: SR3 car meshes (rot_fix cars) are +Y up, +Z front, +X left. Godot cars: +Y up, -Z front, +X right
=> rotate 180 deg about Y: (x, y, z) -> (-x, y, -z).
.car positions are (x right, y front, z up) -> Godot (x, z, -y).
"""
import json, os, re, shutil, struct, sys
sys.path.insert(0, os.path.dirname(__file__))
from ogre_mesh import read_mesh


def load_materials(sr3):
	path = os.path.join(sr3, "data/materials/Pbs/vehicle.material.json")
	return json.load(open(path))["pbs"]


def write_glb(path, subs, materials, tex_dir_rel=""):
	bin_ = bytearray()
	views, accessors, meshes_prims, mats, images, textures = [], [], [], [], [], []
	mat_index = {}

	def add_view(data, target=None):
		while len(bin_) % 4:
			bin_.append(0)
		views.append({"buffer": 0, "byteOffset": len(bin_), "byteLength": len(data), **({"target": target} if target else {})})
		bin_.extend(data)
		return len(views) - 1

	def add_acc(values, comps, ctype=5126, target=34962, minmax=False):
		fmt = {5126: "f", 5125: "I"}[ctype]
		flat = [c for v in values for c in (v if comps > 1 else (v,))]
		view = add_view(struct.pack("<%d%s" % (len(flat), fmt), *flat), target)
		acc = {"bufferView": view, "componentType": ctype, "count": len(values),
			"type": {1: "SCALAR", 2: "VEC2", 3: "VEC3", 4: "VEC4"}[comps]}
		if minmax:
			acc["min"] = [min(v[i] for v in values) for i in range(comps)]
			acc["max"] = [max(v[i] for v in values) for i in range(comps)]
		accessors.append(acc)
		return len(accessors) - 1

	for s in subs:
		pos = [(-x, y, -z) for x, y, z in s["pos"]]
		attrs = {"POSITION": add_acc(pos, 3, minmax=True)}
		if s["nrm"]:
			nrm = []
			for x, y, z in s["nrm"]:
				l = (x * x + y * y + z * z) ** 0.5 or 1.0
				nrm.append((-x / l, y / l, -z / l))
			attrs["NORMAL"] = add_acc(nrm, 3)
		if s["uv"]:
			attrs["TEXCOORD_0"] = add_acc(s["uv"], 2)
		idx = add_acc(s["idx"], 1, 5125, 34963)
		name = s["material"]
		if name not in mat_index:
			m = materials.get(name, {})
			gm = {"name": name, "pbrMetallicRoughness": {"metallicFactor": 0.0,
				"roughnessFactor": float(m.get("roughness", {}).get("value", 0.5))}}
			if m.get("paint"):
				gm["pbrMetallicRoughness"].update(metallicFactor=0.3, roughnessFactor=0.25)
			tex = m.get("diffuse", {}).get("texture")
			if tex:
				images.append({"uri": tex_dir_rel + tex})
				textures.append({"source": len(images) - 1})
				gm["pbrMetallicRoughness"]["baseColorTexture"] = {"index": len(textures) - 1}
			else:
				c = m.get("diffuse", {}).get("value", [0.8, 0.8, 0.8])
				gm["pbrMetallicRoughness"]["baseColorFactor"] = list(c[:3]) + [1.0]
			tr = m.get("transparency")
			if tr:
				gm["alphaMode"] = "BLEND"
				f = gm["pbrMetallicRoughness"].setdefault("baseColorFactor", [1, 1, 1, 1])
				f[3] = 1.0 - float(tr.get("value", 0.5)) * 0.5
			mats.append(gm)
			mat_index[name] = len(mats) - 1
		meshes_prims.append({"attributes": attrs, "indices": idx, "material": mat_index[name]})

	base = os.path.splitext(os.path.basename(path))[0]
	gltf = {"asset": {"version": "2.0", "generator": "takedown-racer sr3_car_to_glb"},
		"scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"name": base, "mesh": 0}],
		"meshes": [{"name": base, "primitives": meshes_prims}], "materials": mats,
		"buffers": [{"byteLength": len(bin_)}], "bufferViews": views, "accessors": accessors}
	if images:
		gltf["images"], gltf["textures"] = images, textures
	js = json.dumps(gltf, separators=(",", ":")).encode()
	js += b" " * (-len(js) % 4)
	while len(bin_) % 4:
		bin_.append(0)
	with open(path, "wb") as f:
		f.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(bin_)))
		f.write(struct.pack("<II", len(js), 0x4E4F534A) + js)
		f.write(struct.pack("<II", len(bin_), 0x004E4942) + bytes(bin_))
	return [im["uri"] for im in images]


def parse_car(path):
	data, sec = {}, ""
	for line in open(path):
		line = line.split("#")[0].strip()
		if not line:
			continue
		m = re.match(r"\[\s*(.+?)\s*\]", line)
		if m:
			sec = m.group(1)
			data.setdefault(sec, {})
			continue
		if "=" in line:
			k, v = [t.strip() for t in line.split("=", 1)]
			parts = [p.strip() for p in v.split(",")]
			try:
				nums = [float(p) for p in parts]
				val = nums[0] if len(nums) == 1 else nums
			except ValueError:
				val = v
			data.setdefault(sec, {})[k] = val
	# convert all 3-vectors that are positions to Godot axes
	for sec, kv in data.items():
		for k, v in kv.items():
			if (k == "position" or k.endswith("-pos") or re.match(r".*-pos\d$", k)) and isinstance(v, list) and len(v) == 3:
				kv[k] = [v[0], v[2], -v[1]]
	return data


def main():
	sr3, cid = sys.argv[1], sys.argv[2]
	out = sys.argv[3] if len(sys.argv) > 3 else os.path.join(os.path.dirname(__file__), "..", "assets", "cars", cid)
	os.makedirs(out, exist_ok=True)
	src = os.path.join(sr3, "data", "cars", cid)
	mats = load_materials(sr3)
	for fn in sorted(os.listdir(src)):
		if not fn.endswith(".mesh"):
			continue
		subs = read_mesh(os.path.join(src, fn))
		glb = os.path.join(out, fn[:-5] + ".glb")
		for uri in write_glb(glb, subs, mats):
			shutil.copy(os.path.join(src, "textures", uri), os.path.join(out, uri))
		print("wrote", glb, sum(len(s["idx"]) // 3 for s in subs), "tris")
	shutil.copy(os.path.join(src, "about.txt"), os.path.join(out, "about.txt"))
	car = parse_car(os.path.join(sr3, "data", "carsim", "normal", "cars", cid + ".car"))
	json.dump(car, open(os.path.join(out, cid + ".car.json"), "w"), indent=1)
	print("wrote", cid + ".car.json")


if __name__ == "__main__":
	main()
