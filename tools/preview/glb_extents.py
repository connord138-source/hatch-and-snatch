"""Prints `Name = Vector3.new(x, y, z),` for every GLB in a folder: each model's
extents from its POSITION bounds (Tripo GLBs carry no node transforms), so the
preview's stand-in props have the real models' proportions (props_stub.luau)."""
import json
import pathlib
import struct
import sys

for path in sorted(pathlib.Path(sys.argv[1]).glob("*.glb")):
    data = path.read_bytes()
    length = struct.unpack("<I", data[12:16])[0]
    gltf = json.loads(data[20 : 20 + length])
    lo, hi = [1e9] * 3, [-1e9] * 3
    for mesh in gltf.get("meshes", []):
        for prim in mesh["primitives"]:
            acc = gltf["accessors"][prim["attributes"]["POSITION"]]
            lo = [min(a, b) for a, b in zip(lo, acc["min"])]
            hi = [max(a, b) for a, b in zip(hi, acc["max"])]
    ext = [max(h - l, 1e-3) for l, h in zip(lo, hi)]
    print(f"{path.stem} = Vector3.new({ext[0]:.4f}, {ext[1]:.4f}, {ext[2]:.4f}),")
