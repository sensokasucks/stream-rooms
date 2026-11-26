#!/usr/bin/env python3
"""Makes Route 81's photo textures (the "Detailed" look of the Pennsylvania highway).

Everything starts from CC0 (public domain) photos from Poly Haven, https://polyhaven.com. The
script downloads them, cuts them down to what the game needs and writes the files next to
itself. Run it again only to change a texture; the results are committed.

    python3 rooms/route81/textures/make_textures.py [cache folder]

Needs Python 3 with Pillow and numpy, and the internet (api.polyhaven.com, dl.polyhaven.org).
It borrows Route 22's helpers (rooms/route22/textures/make_textures.py: fetch, photo, detail,
normal), pointed at this folder.

What it writes (who reads it):
  rock_cut.jpg / rock_cut_nor.jpg     the blasted grey rock of the road cuts and tunnel faces
                                      (r81_terrain.gdshader, laid on from three sides)
  ground_verge.jpg                    mown roadside grass: shoulders and the median
  ground_leaves.jpg / _nor.jpg        the forest floor under the trees
  road_highway.jpg / _nor.jpg         the interstate's asphalt (r81_road.gdshader)
  tunnel_concrete.jpg                 the tunnels' lining and portals (r81_tunnel.gdshader), a
                                      "detail" texture: mid grey = no change
"""
import importlib.util
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("r22_textures", os.path.join(HERE, "..", "..", "route22", "textures", "make_textures.py"))
r22 = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(r22)
# Route 22's helpers write into their own HERE and cache: point both at this folder.
r22.HERE = HERE
r22.CACHE = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "_cache")

if __name__ == "__main__":
    r22.photo("rock_cut.jpg", "rock_face_03", gain=(0.92, 0.94, 1.0))
    r22.normal("rock_cut_nor.jpg", "rock_face_03")
    r22.photo("ground_verge.jpg", "sparse_grass", size=512)
    r22.photo("ground_leaves.jpg", "forest_leaves_02", size=1024)
    r22.normal("ground_leaves_nor.jpg", "forest_leaves_02", strength=0.7)
    r22.photo("road_highway.jpg", "asphalt_02", gain=(0.97, 0.97, 1.0))
    r22.normal("road_highway_nor.jpg", "asphalt_02", strength=0.6)
    r22.detail("tunnel_concrete.jpg", "concrete_wall_008", size=512, contrast=1.4)
