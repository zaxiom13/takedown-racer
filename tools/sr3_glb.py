"""Shared helpers for converting Stunt Rally 3 meshes/materials to glTF binary (.glb). Stdlib only."""
import glob, json, os, struct


def load_materials(sr3):
	"""Merge all Ogre-Next PBS material definitions (name -> dict) from data/materials/**.material.json."""
	mats = {}
	for path in glob.glob(os.path.join(sr3, "data", "materials", "**", "*.material.json"), recursive=True):
		try:
			mats.update(json.load(open(path)).get("pbs", {}))
		except (ValueError, OSError):
			pass
	return mats


_tex_index = {}


def find_texture(sr3, name):
	"""Locate a texture file by name anywhere under data/ (SR3 resolves textures by name only)."""
	if not _tex_index:
		for root, _, files in os.walk(os.path.join(sr3, "data")):
			for f in files:
				_tex_index.setdefault(f, os.path.join(root, f))
	return _tex_index.get(name)


def write_glb(path, subs, materials, flip=True, tex_dir_rel=""):
	"""flip=True rotates 180 deg about Y (SR3 car meshes face +Z; Godot cars face -Z)."""
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
		sx = -1.0 if flip else 1.0
		pos = [(sx * x, y, sx * z) for x, y, z in s["pos"]]
		attrs = {"POSITION": add_acc(pos, 3, minmax=True)}
		if s["nrm"]:
			nrm = []
			for x, y, z in s["nrm"]:
				l = (x * x + y * y + z * z) ** 0.5 or 1.0
				nrm.append((sx * x / l, y / l, sx * z / l))
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
			if m.get("alpha_test"):
				gm["alphaMode"] = "MASK"
				gm["alphaCutoff"] = float(m["alpha_test"][1])
				gm["doubleSided"] = True
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


