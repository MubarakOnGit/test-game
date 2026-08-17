"""
Recreate the thick grass clump as a blocky/voxel version matching the game's aesthetic.

Based on inspection:
  - Width: ~1.5 units, Depth: ~1.5 units, Height: ~1.7 units
  - It's a THICK clump, not individual blades — several blades bunched together

Voxel recreation: A cluster of 3-5 thin tall boxes arranged like a fan/bunch,
each box slightly offset and rotated, giving a pixelated grass clump look.
"""

import bpy
import math
import random

OUTPUT_PATH = r"c:\Repo\test-game\assets\grass\grass_tuft_voxel.glb"

def hex_to_rgba(h):
    h = h.lstrip('#')
    return (int(h[0:2],16)/255, int(h[2:4],16)/255, int(h[4:6],16)/255, 1.0)

# Grass colors — same palette as ground shader, slightly brighter for grass blades
COLORS = {
    'tip':   hex_to_rgba('63ad26'),   # Bright green tip
    'mid':   hex_to_rgba('549e1e'),   # Mid green
    'base':  hex_to_rgba('3a7012'),   # Dark base
    'dark':  hex_to_rgba('2d5a0e'),   # Shadow side
}

bpy.ops.wm.read_factory_settings(use_empty=True)

def paint_by_height(obj, min_z, max_z):
    """Paint vertex colors: tip=bright, base=dark, sides=slightly darker."""
    mesh = obj.data
    if not mesh.vertex_colors:
        mesh.vertex_colors.new(name="Col")
    col_layer = mesh.vertex_colors.active
    z_range = max_z - min_z

    for poly in mesh.polygons:
        cz = sum(mesh.vertices[vi].co.z for vi in poly.vertices) / len(poly.vertices)
        t = (cz - min_z) / z_range if z_range > 0 else 0.5
        is_side = abs(poly.normal.z) < 0.3
        shade = 0.7 if is_side else 1.0

        if t > 0.7:
            r, g, b, _ = COLORS['tip']
        elif t > 0.4:
            r, g, b, _ = COLORS['mid']
        else:
            r, g, b, _ = COLORS['base']

        for loop_idx in poly.loop_indices:
            col_layer.data[loop_idx].color = (r * shade, g * shade, b * shade, 1.0)

all_objects = []

# ── Blade definition: (offset_x, offset_z, rot_y_deg, scale_x, scale_z, height) ──
# Creates a bunch that looks like thick grass viewed from any angle
BLADES = [
    # Center upright blades
    ( 0.00,  0.00,   0, 0.12, 0.10, 1.00),
    ( 0.00,  0.00,  45, 0.12, 0.10, 0.95),
    # Left cluster
    (-0.18, -0.05,  15, 0.10, 0.09, 0.85),
    (-0.24,  0.10, -10, 0.09, 0.08, 0.78),
    # Right cluster
    ( 0.18,  0.05, -15, 0.10, 0.09, 0.88),
    ( 0.22, -0.08,  10, 0.09, 0.08, 0.75),
    # Front/back fill
    ( 0.05,  0.20,  60, 0.10, 0.08, 0.82),
    (-0.05, -0.20, -60, 0.10, 0.08, 0.80),
    # Wide low blades leaning outward
    (-0.30,  0.00,  25, 0.14, 0.08, 0.60),
    ( 0.30,  0.00, -25, 0.14, 0.08, 0.60),
    ( 0.00,  0.28,  80, 0.14, 0.08, 0.58),
    ( 0.00, -0.28, -80, 0.14, 0.08, 0.58),
]

for (ox, oz, ry, sx, sz, h) in BLADES:
    # Each blade is a thin tall box
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(ox, oz, h * 0.5))
    obj = bpy.context.active_object
    # Scale: x=thin, y=thin, z=tall
    obj.scale = (sx, sz, h * 0.5)
    # Lean slightly outward from center (tilt = rotation around X or Y)
    lean_angle = math.radians(ry)
    obj.rotation_euler = (0, 0, lean_angle)
    bpy.ops.object.transform_apply(scale=True, rotation=True)
    all_objects.append(obj)

# ── Small base block to anchor the clump ──────────────────────────────────────
bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.06))
base = bpy.context.active_object
base.scale = (0.45, 0.45, 0.06)
bpy.ops.object.transform_apply(scale=True)
all_objects.append(base)

# Join all into one mesh
bpy.ops.object.select_all(action='DESELECT')
for obj in all_objects:
    obj.select_set(True)
bpy.context.view_layer.objects.active = all_objects[0]
bpy.ops.object.join()

combined = bpy.context.active_object
combined.name = "GrassTuft"

# Get actual Z range after join
verts = [v.co.z for v in combined.data.vertices]
paint_by_height(combined, min(verts), max(verts))

bpy.ops.export_scene.gltf(
    filepath=OUTPUT_PATH,
    export_format='GLB',
)
print(f"Exported voxel grass to: {OUTPUT_PATH}")
print(f"Verts: {len(combined.data.vertices)}, Faces: {len(combined.data.polygons)}")
