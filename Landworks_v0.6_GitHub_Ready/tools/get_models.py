#!/usr/bin/env python3
"""Fetch the two independently licensed CC0 donor GLBs for local review.

Third-party URLs are pinned to the source's download redirect endpoints.
The script validates actual GLB magic/chunks and avoids writing HTML error
responses into the Godot project. Files are never executed.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import struct
import sys
import urllib.error
import urllib.request

PROJECT = Path(__file__).resolve().parents[1]
SOURCE = PROJECT / "landworks" / "assets" / "source"
ASSETS = {
    "tractor": (
        "garden-tractor-with-trailer.glb",
        "https://www.innerscene.com/api/library/garden-tractor-with-trailer-40bf3bb8/download",
        "https://www.innerscene.com/tools/library/3d-parts/garden-tractor-with-trailer-40bf3bb8",
    ),
    "excavator": (
        "compact-tracked-excavator.glb",
        "https://www.innerscene.com/api/library/compact-tracked-excavator-76c41cd5/download",
        "https://www.innerscene.com/tools/library/3d-parts/compact-tracked-excavator-76c41cd5",
    ),
}
MAX_BYTES = 48 * 1024 * 1024


def glb_metadata(path: Path) -> dict:
    """Parse GLB JSON chunk without Blender, external modules or mesh processing."""
    with path.open("rb") as f:
        header = f.read(12)
        if len(header) != 12:
            raise ValueError("GLB is shorter than its required header")
        magic, version, length = struct.unpack("<4sII", header)
        if magic != b"glTF" or version != 2 or length != path.stat().st_size:
            raise ValueError("Not a complete glTF 2 GLB (magic/version/length mismatch)")
        chunk_head = f.read(8)
        if len(chunk_head) != 8:
            raise ValueError("GLB has no first chunk")
        chunk_length, chunk_type = struct.unpack("<I4s", chunk_head)
        if chunk_type != b"JSON" or chunk_length > MAX_BYTES or chunk_length > length - 20:
            raise ValueError("GLB JSON chunk is invalid")
        data = json.loads(f.read(chunk_length).decode("utf-8"))
    nodes = data.get("nodes", [])
    materials = data.get("materials", [])
    return {
        "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        "bytes": path.stat().st_size,
        "nodes": len(nodes),
        "meshes": len(data.get("meshes", [])),
        "materials": len(materials),
        "animations": len(data.get("animations", [])),
        "node_names": [node.get("name", f"unnamed_{i}") for i, node in enumerate(nodes)],
        "mesh_names": [mesh.get("name", f"unnamed_{i}") for i, mesh in enumerate(data.get("meshes", []))],
    }


def download(url: str, dest: Path) -> None:
    temp = dest.with_suffix(".download")
    req = urllib.request.Request(url, headers={"User-Agent": "Landworks-AssetFetch/0.2"})
    try:
        with urllib.request.urlopen(req, timeout=60) as response, temp.open("wb") as target:
            count = 0
            while True:
                block = response.read(131072)
                if not block:
                    break
                count += len(block)
                if count > MAX_BYTES:
                    raise ValueError(f"Asset exceeds {MAX_BYTES // 1024 // 1024} MB cap")
                target.write(block)
        glb_metadata(temp)
        os.replace(temp, dest)
    finally:
        temp.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--inspect-only", action="store_true", help="Never download, validate existing files")
    parser.add_argument("--force", action="store_true", help="Redownload even when validated file exists")
    args = parser.parse_args()
    SOURCE.mkdir(parents=True, exist_ok=True)
    manifest = {}
    problems = []
    for kind, (name, url, page) in ASSETS.items():
        dest = SOURCE / name
        print(f"[{kind}] {name}")
        try:
            if (args.force or not dest.exists()) and not args.inspect_only:
                print(f"  Downloading from {url}")
                download(url, dest)
            if not dest.exists():
                raise FileNotFoundError(f"Missing {dest}. Download from {page}")
            info = glb_metadata(dest)
            info.update({"license": "CC0 1.0 per source listing", "source_page": page, "download": url})
            manifest[kind] = info
            print(f"  OK: {info['bytes']:,} bytes, {info['nodes']} nodes, {info['meshes']} meshes, SHA256 {info['sha256'][:16]}...")
            print("  Named components: " + ", ".join(info["node_names"][:28]))
        except Exception as exc:
            problems.append(f"{kind}: {exc}")
            print(f"  FAILED: {exc}", file=sys.stderr)
    if manifest:
        report = SOURCE / "download_report.json"
        report.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
        print(f"Saved model inspection report: {report}")
    if problems:
        print("Download issues: use the source links in docs/ASSET_SOURCES.md and place GLB files manually.")
        return 1
    print("Both validated. Import project.godot in Godot, run asset_lab.tscn (F6) to inspect.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
