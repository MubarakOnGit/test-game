"""
Creates a blocky/pixelated voxel grass tuft mesh and exports it as a GLB.
The tuft has 3 stacked box layers - widest at bottom, narrowest at top -
giving a stepped/pixelated appearance that matches the game's voxel aesthetic.

Run with:
  blender --background --python scratch/make_grass_tuft.py
"""

import bpy
import math

# --- Clear scene ---
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete()

OUTPUT_PATH = r"c:\Repo\test-game\assets\grass_tuft.glb"

def hex_to_rgba(hex_str):
    h = hex_str.lstrip('#')
    return (int(h[0:2],16)/255, int(h[2:4],16)/255, int(h[4:6],16)/255, 1.0)

# Colors: bright tip -> dark base
COLORS = [
    hex_to_rgba('63ad26'),  # Bright tip
    hex_to_rgba('549e1e'),  # Mid
    hex_to_rgba('407d15'),  # Dark base
]

# Each layer: (width_x, height_y, depth_z, center_y_offset)
# Stacked upward, each narrower than the one below
LAYERS = [
    (0.40, 0.20, 0.40, 0.10),   # Bottom — widest
    (0.28, 0.22, 0.28, 0.31),   # Middle
    (0.16, 0.20, 0.16, 0.52),   # Top — narrowest
]

meshes = []
for i, (sx, sy, sz, cy) in enumerate(LAYERS):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, cy))
    obj = bpy.context.active_object
    obj.scale = (sx, sz, sy)  # Blender Y=forward, Z=up
    bpy.ops.object.transform_apply(scale=True)
    obj.name = f"GrassLayer_{i}"
    meshes.append(obj)

# Join all layers into one mesh
bpy.ops.object.select_all(action='DESELECT')
for obj in meshes:
    obj.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
bpy.ops.object.join()

combined = bpy.context.active_object
combined.name = "GrassTuft"

mesh_data = combined.data
mesh_data.vertex_colors.new(name="Col")
color_layer = mesh_data.vertex_colors.active

# Assign vertex colors based on Z height (bottom=dark, top=bright)
min_z = min(v.co.z for v in mesh_data.vertices)
max_z = max(v.co.z for v in mesh_data.vertices)
z_range = max_z - min_z

for poly in mesh_data.polygons:
    center_z = sum(mesh_data.vertices[vi].co.z for vi in poly.vertices) / len(poly.vertices)
    t = (center_z - min_z) / z_range  # 0 = bottom, 1 = top
    
    # Shade sides darker than top
    is_side = abs(poly.normal.z) < 0.5
    shade_factor = 0.72 if is_side else 1.0
    
    # Pick color from bottom dark to top bright
    idx = min(int(t * 2.99), 2)
    # Reverse: idx 0 = bright (top), idx 2 = dark (bottom)
    color_idx = 2 - idx
    r, g, b, a = COLORS[color_idx]
    final_color = (r * shade_factor, g * shade_factor, b * shade_factor, 1.0)
    
    for loop_idx in poly.loop_indices:
        color_layer.data[loop_idx].color = final_color

# Export
bpy.ops.export_scene.gltf(
    filepath=OUTPUT_PATH,
    export_format='GLB',
)
print(f"Exported grass tuft to: {OUTPUT_PATH}")
