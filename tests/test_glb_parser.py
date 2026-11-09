"""Offline integrity tests for GLB validation; no external dependencies."""
import importlib.util
import json
import struct
from pathlib import Path
from tempfile import TemporaryDirectory

source = Path(__file__).resolve().parents[1] / "tools" / "get_models.py"
spec = importlib.util.spec_from_file_location("asset_downloader", source)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


def make_glb(data):
    json_bytes = json.dumps(data).encode("utf-8")
    json_bytes += b" " * ((4 - len(json_bytes) % 4) % 4)
    chunk = struct.pack("<I4s", len(json_bytes), b"JSON") + json_bytes
    return struct.pack("<4sII", b"glTF", 2, 12 + len(chunk)) + chunk

with TemporaryDirectory() as td:
    path = Path(td) / "test.glb"
    path.write_bytes(make_glb({"asset": {"version": "2.0"}, "nodes": [{"name": "FrontWheel"}], "meshes": [{}]}))
    report = mod.glb_metadata(path)
    assert report["nodes"] == 1
    assert report["node_names"] == ["FrontWheel"]
    assert report["meshes"] == 1
    assert len(report["sha256"]) == 64
    print("PASS valid glTF GLB 2 metadata extraction")

    path.write_bytes(b"<html>download blocked</html>")
    try:
        mod.glb_metadata(path)
    except ValueError:
        print("PASS refuses HTML/error page masquerading as GLB")
    else:
        raise AssertionError("HTML file should never validate")

    bad_length = bytearray(make_glb({"asset": {"version": "2.0"}}))
    struct.pack_into("<I", bad_length, 8, len(bad_length) + 30)
    path.write_bytes(bad_length)
    try:
        mod.glb_metadata(path)
    except ValueError:
        print("PASS rejects truncated GLB")
    else:
        raise AssertionError("Truncated GLB should never validate")
