#!/usr/bin/env python3
"""Convert one Stunt Rally 3 car into Godot-ready files.

Usage: tools/sr3_car_to_glb.py <stuntrally3 repo> <CAR_ID> [out_dir]
Writes  <out>/<ID>_<part>.glb  (body, glass, interior, wheel...),  diffuse textures,  and  <ID>.car.json
(parsed .car sim file from data/carsim/normal, positions converted to Godot axes).

Axes: SR3 car meshes (rot_fix cars) are +Y up, +Z front, +X left. Godot cars: +Y up, -Z front, +X right
=> rotate 180 deg about Y: (x, y, z) -> (-x, y, -z).
.car positions are (x right, y front, z up) -> Godot (x, z, -y).
"""
import json, os, re, shutil, sys
sys.path.insert(0, os.path.dirname(__file__))
from ogre_mesh import read_mesh
from sr3_glb import load_materials, write_glb


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
