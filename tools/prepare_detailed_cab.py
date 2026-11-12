"""Separate existing cab controls without remodelling or deleting any triangles.

Runs with standard Python. The original GLB remains immutable. Connected
surface islands are classified using the approved source's furniture bounds.
Every source index must appear exactly once in the derived GLB.
"""
import copy
import hashlib
import json
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "landworks/assets/engineered"
source = ASSETS / "kx080_upper.glb"
raw = source.read_bytes()
json_length = struct.unpack_from("<I", raw, 12)[0]
doc = json.loads(raw[20:20 + json_length])
offset = 20 + json_length
binary_length = struct.unpack_from("<I", raw, offset)[0]
binary = bytearray(raw[offset + 8:offset + 8 + binary_length])

def accessor(index):
    a = doc["accessors"][index]
    view = doc["bufferViews"][a["bufferView"]]
    fmt = {5121: "B", 5123: "H", 5125: "I", 5126: "f"}[a["componentType"]]
    width = {"SCALAR": 1, "VEC3": 3}[a["type"]]
    size = struct.calcsize(fmt) * width
    start = view.get("byteOffset", 0) + a.get("byteOffset", 0)
    stride = view.get("byteStride", size)
    return [struct.unpack_from("<" + fmt * width, binary, start + n * stride)
            for n in range(a["count"])]

PIVOTS = {"CabLeftJoystick": (-.91, 1.69, -.17),
          "CabRightJoystick": (-.25, 1.69, -.17),
          "CabLeftTravel": (-.68, 1.30, -.75),
          "CabRightTravel": (-.47, 1.30, -.75)}
groups = {key: [] for key in ["UpperShell", *PIVOTS]}
counts = {key: 0 for key in groups}
source_count = 0

def classify(points):
    lo = [min(p[k] for p in points) for k in range(3)]
    hi = [max(p[k] for p in points) for k in range(3)]
    center = [(a + b) / 2 for a, b in zip(lo, hi)]
    if lo[1] > 1.67 and hi[1] < 1.96 and -.31 < center[2] < -.12:
        for x, name in [(-.91, "CabLeftJoystick"), (-.25, "CabRightJoystick")]:
            if abs(center[0] - x) < .035 and hi[0] - lo[0] < .09:
                return name
    if lo[1] > 1.25 and hi[1] < 1.74 and -.87 < center[2] < -.58:
        for x, name in [(-.68, "CabLeftTravel"), (-.47, "CabRightTravel")]:
            if abs(center[0] - x) < .035 and hi[0] - lo[0] < .16:
                return name
    return "UpperShell"

for primitive in doc["meshes"][0]["primitives"]:
    positions = accessor(primitive["attributes"]["POSITION"])
    indices = [v[0] for v in accessor(primitive["indices"])]
    source_count += len(indices)
    parent = list(range(len(positions)))
    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i
    def union(a, b):
        parent[find(a)] = find(b)
    welded = {}
    for i, p in enumerate(positions):
        key = tuple(round(x, 5) for x in p)
        if key in welded:
            union(i, welded[key])
        else:
            welded[key] = i
    for n in range(0, len(indices), 3):
        union(indices[n], indices[n + 1])
        union(indices[n], indices[n + 2])
    islands = {}
    for i in set(indices):
        islands.setdefault(find(i), []).append(positions[i])
    roles = {key: classify(points) for key, points in islands.items()}
    divided = {key: [] for key in groups}
    for n in range(0, len(indices), 3):
        divided[roles[find(indices[n])]].extend(indices[n:n + 3])
    assert sum(map(len, divided.values())) == len(indices)
    for name, subset in divided.items():
        if not subset:
            continue
        while len(binary) % 4:
            binary.append(0)
        start = len(binary)
        binary.extend(struct.pack("<" + "I" * len(subset), *subset))
        view = len(doc["bufferViews"])
        doc["bufferViews"].append({"buffer": 0, "byteOffset": start,
                                   "byteLength": len(subset) * 4, "target": 34963})
        a = len(doc["accessors"])
        doc["accessors"].append({"bufferView": view, "componentType": 5125,
                                 "count": len(subset), "type": "SCALAR"})
        result = copy.deepcopy(primitive)
        result["indices"] = a
        groups[name].append(result)
        counts[name] += len(subset)

assert sum(counts.values()) == source_count
assert all(counts[key] > 100 for key in PIVOTS), counts
doc["meshes"] = []
doc["nodes"] = [{"name": "kx080_upper_cab_rig", "children": []}]
for name, primitives in groups.items():
    mesh = len(doc["meshes"])
    doc["meshes"].append({"name": name, "primitives": primitives})
    node = len(doc["nodes"])
    doc["nodes"][0]["children"].append(node)
    if name in PIVOTS:
        pivot = PIVOTS[name]
        doc["nodes"].append({"name": name, "translation": pivot, "children": [node + 1]})
        doc["nodes"].append({"name": name + "Mesh", "mesh": mesh,
                              "translation": [-x for x in pivot]})
    else:
        doc["nodes"].append({"name": name, "mesh": mesh})
doc["scenes"] = [{"nodes": [0]}]
doc["scene"] = 0
doc["buffers"][0]["byteLength"] = len(binary)
encoded = json.dumps(doc, separators=(",", ":")).encode()
encoded += b" " * (-len(encoded) % 4)
binary.extend(b"\0" * (-len(binary) % 4))
result = (struct.pack("<III", 0x46546C67, 2, 28 + len(encoded) + len(binary))
          + struct.pack("<II", len(encoded), 0x4E4F534A) + encoded
          + struct.pack("<II", len(binary), 0x004E4942) + binary)
(ASSETS / "kx080_upper_cab_rig.glb").write_bytes(result)
report = {"source_sha256": hashlib.sha256(raw).hexdigest(),
          "triangles_before": source_count // 3,
          "triangles_after": sum(counts.values()) // 3,
          "triangles_by_part": {k: v // 3 for k, v in counts.items()},
          "positions_normals_uv_materials": "unchanged; only indices partitioned and pivot nodes added"}
(ROOT / "docs/detailed_cab_conversion.json").write_text(json.dumps(report, indent=2) + "\n")
print(json.dumps(report, indent=2))
