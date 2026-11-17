#!/usr/bin/env python3
"""Makes the Route 22 rooms' photo-scanned models from CC0 (public domain) Poly Haven assets,
https://polyhaven.com. Run it again only to change a model; the results are committed.

    python3 rooms/route22/models/make_models.py [cache folder]

Needs Python 3 with numpy, Pillow, trimesh and fast-simplification, and the internet
(api.polyhaven.com, dl.polyhaven.org).

Two kinds of model:
  rock_*.obj   scanned boulders and rock piles, cut down to a few thousand triangles, with no
        texture: they are drawn with our own red sandstone shader (r22_rock.gdshader), so they
        match the big formations. r22_geo.gd scan_rock() copies one into a rock Buf.
  prop_*.obj   scanned props kept with their photo textures (prop_<name>_diff/_nor/_arm.jpg):
        drawn by r22_scan.gdshader (r22_geo.gd scan_prop()). On both looks (Low skips the
        normal map).
models.json lists each model's size (metres) so the code can place them without loading them.
Every model sits on y = 0, centred in x and z, front = -z.
"""
import json
import os
import sys
import urllib.request

import fast_simplification
import numpy as np
import trimesh
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "_cache")
API = "https://api.polyhaven.com/files/"
UA = {"User-Agent": "model-bake-script"}

# name: (Poly Haven asset, triangles to keep)
ROCKS = {
    "boulder_a": ("namaqualand_boulder_02", 1800),
    "boulder_b": ("namaqualand_boulder_03", 1800),
    "boulder_c": ("namaqualand_boulder_04", 1800),
    "boulder_d": ("namaqualand_boulder_05", 1800),
    "boulder_e": ("namaqualand_boulder_06", 2200),
    "pile": ("namaqualand_rocks_01", 2400),
    "stones": ("namaqualand_stones_01", 1600),
}
# Patches painted over a prop's photo maps (in 1k pixels): [(from x, y), (to x, y), (w, h)].
# Barrel_01's only textures are its "explosive" set: the hazard triangles are covered with plain
# red paint from beside them, so it is an ordinary oil drum (no warning signs at a snack bar).
PATCHES = {
    "barrel": [((40, 60), (185, 60), (145, 150)), ((40, 535), (185, 535), (145, 150))],
}
# name: (Poly Haven asset, most triangles allowed: more = cut down, keeping the UVs)
PROPS = {
    "barrel": ("Barrel_01", 4000),
    "barrel_rusty": ("barrel_03", 4000),
    "dead_trunk": ("dead_quiver_trunk", 6000),
    "dry_branches": ("dry_branches_medium_01", 5000),
}


def get(url: str, path: str) -> str:
    if not os.path.exists(path):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        req = urllib.request.Request(url, headers=UA)
        with open(path, "wb") as f:
            f.write(urllib.request.urlopen(req, timeout=300).read())
    return path


def fetch_gltf(asset: str) -> str:
    """Downloads an asset's 1k glTF with its .bin and textures; returns the .gltf path."""
    files = json.load(urllib.request.urlopen(urllib.request.Request(API + asset, headers=UA), timeout=60))
    g = files["gltf"]["1k"]["gltf"]
    base = os.path.join(CACHE, asset)
    path = get(g["url"], os.path.join(base, os.path.basename(g["url"])))
    for rel, info in g["include"].items():
        get(info["url"], os.path.join(base, rel))
    return path


def load(asset: str) -> trimesh.Trimesh:
    """The asset as one mesh, in metres, standing on y = 0, centred in x and z."""
    scene = trimesh.load(fetch_gltf(asset), force="scene")
    meshes = []
    for node in scene.graph.nodes_geometry:
        xf, geom = scene.graph[node]
        m = scene.geometry[geom].copy()
        m.apply_transform(xf)
        meshes.append(m)
    mesh = meshes[0] if len(meshes) == 1 else trimesh.util.concatenate(meshes)
    lo, hi = mesh.bounds
    mesh.apply_translation([-(lo[0] + hi[0]) / 2.0, -lo[1], -(lo[2] + hi[2]) / 2.0])
    return mesh


def write_obj(path: str, v: np.ndarray, f: np.ndarray, n: np.ndarray, uv=None) -> None:
    with open(path, "w") as o:
        o.write("# Route 22 model from a CC0 Poly Haven scan (make_models.py)\n")
        for p in v:
            o.write("v %.4f %.4f %.4f\n" % tuple(p))
        for p in n:
            o.write("vn %.4f %.4f %.4f\n" % tuple(p))
        if uv is not None:
            for t in uv:
                o.write("vt %.5f %.5f\n" % (t[0], t[1]))
            for a, b, c in f + 1:
                o.write("f %d/%d/%d %d/%d/%d %d/%d/%d\n" % (a, a, a, b, b, b, c, c, c))
        else:
            for a, b, c in f + 1:
                o.write("f %d//%d %d//%d %d//%d\n" % (a, a, b, b, c, c))
    print("wrote", os.path.basename(path), len(f), "triangles")


def make_rock(name: str, asset: str, tris: int, info: dict) -> None:
    mesh = load(asset)
    mesh.merge_vertices(merge_tex=True, merge_norm=True)       # one surface, so cutting it down leaves no cracks
    v, f = mesh.vertices.astype(np.float32), mesh.faces.astype(np.int64)
    if len(f) > tris:
        v, f = fast_simplification.simplify(v, f, target_reduction=1.0 - tris / len(f))
    out = trimesh.Trimesh(v, f, process=True)
    trimesh.repair.fix_normals(out)
    write_obj(os.path.join(HERE, f"rock_{name}.obj"), out.vertices, out.faces, out.vertex_normals)
    info["rock_" + name] = {"size": [round(float(x), 3) for x in out.extents], "source": asset}


def make_prop(name: str, asset: str, most: int, info: dict) -> None:
    mesh = load(asset)
    uv = mesh.visual.uv if hasattr(mesh.visual, "uv") and mesh.visual.uv is not None else None
    v, f = mesh.vertices, mesh.faces
    if len(f) > most and uv is not None:
        # cut down keeping the UV seams: decimate, then give each new corner the UV of the
        # nearest point on the original surface
        nv, nf = fast_simplification.simplify(v.astype(np.float32), f.astype(np.int64), target_reduction=1.0 - most / len(f))
        closest, _, tri = trimesh.proximity.closest_point(mesh, nv)
        bary = trimesh.triangles.points_to_barycentric(mesh.triangles[tri], closest)
        uv = (uv[mesh.faces[tri]] * bary[:, :, None]).sum(axis=1)
        v, f = nv, nf
    out = trimesh.Trimesh(v, f, process=False)
    write_obj(os.path.join(HERE, f"prop_{name}.obj"), out.vertices, out.faces, out.vertex_normals,
              None if uv is None else np.column_stack([uv[:, 0], 1.0 - uv[:, 1]]))
    tex = os.path.join(CACHE, asset, "textures")
    for kind in ("diff", "nor_gl", "arm"):
        # the maps are <asset>_<kind>_1k.jpg, or <asset>_<variant>_<kind>_1k.jpg for an asset
        # that only comes in variants (Barrel_01_explosive_...)
        found = [f for f in sorted(os.listdir(tex)) if f.startswith(asset + "_") and f.endswith(f"_{kind}_1k.jpg")]
        if not found:
            continue
        img = Image.open(os.path.join(tex, found[0])).convert("RGB")
        for (fx, fy), (tx, ty), (w, h) in PATCHES.get(name, []):
            img.paste(img.crop((fx, fy, fx + w, fy + h)), (tx, ty))
        short = {"diff": "diff", "nor_gl": "nor", "arm": "arm"}[kind]
        img.resize((512, 512), Image.LANCZOS).save(
            os.path.join(HERE, f"prop_{name}_{short}.jpg"), quality=88, optimize=True)
    info["prop_" + name] = {"size": [round(float(x), 3) for x in out.extents], "source": asset}


if __name__ == "__main__":
    info: dict = {}
    for k, (a, t) in ROCKS.items():
        make_rock(k, a, t, info)
    for k, (a, t) in PROPS.items():
        make_prop(k, a, t, info)
    with open(os.path.join(HERE, "models.json"), "w") as o:
        json.dump(info, o, indent=1)
    print("wrote models.json")
