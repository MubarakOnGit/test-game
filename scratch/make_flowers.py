"""
Creates voxel flowers.
- Stem: 1, 2, or 3 small green cubes stacked vertically.
- Center: 1 large yellow cube (same size as petals).
- Petals: 4 large colored cubes surrounding the center yellow cube.
"""
import bpy
import math

def hex_to_rgba(h):
    h = h.lstrip('#')
    return (int(h[0:2],16)/255, int(h[2:4],16)/255, int(h[4:6],16)/255, 1.0)

# Colors
STEM_COLOR   = hex_to_rgba('639a3f') 
CENTER_COLOR = hex_to_rgba('f4d03f') 

PETAL_COLORS = {
    'red':   hex_to_rgba('e74c3c'),
    'white': hex_to_rgba('ecf0f1'),
    'blue':  hex_to_rgba('3498db'),
    'pink':  hex_to_rgba('a569bd')
}

def paint_obj(obj, color):
    mesh = obj.data
    if not mesh.vertex_colors:
        mesh.vertex_colors.new(name="Col")
    col = mesh.vertex_colors.active
    
    for poly in mesh.polygons:
        if poly.normal.z > 0.8:
            shade = 1.0    
        elif abs(poly.normal.z) < 0.2:
            shade = 0.8    
        else:
            shade = 0.6    
            
        r, g, b = color[0]*shade, color[1]*shade, color[2]*shade
        for li in poly.loop_indices:
            col.data[li].color = (r, g, b, 1.0)

def make_flower(name, path, petal_color, stem_blocks):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    
    parts = []
    
    small_bs = 0.08 
    large_bs = 0.16 
    
    def add_block(x, y, z, size, color):
        bpy.ops.mesh.primitive_cube_add(size=size, location=(x, y, z))
        obj = bpy.context.active_object
        paint_obj(obj, color)
        parts.append(obj)

    # 1. Stem: variable height stacked cubes
    for i in range(stem_blocks):
        add_block(0, 0, (i + 0.5) * small_bs, small_bs, STEM_COLOR)
    
    # 2. Center: 1 yellow cube (same size as petals)
    # The center is placed directly on top of the stem
    center_z = (stem_blocks * small_bs) + (large_bs * 0.5)
    add_block(0, 0, center_z, large_bs, CENTER_COLOR)
    
    # 3. Petals: 4 colored cubes around the center (also large_bs)
    offset = large_bs
    petal_z = center_z
    
    add_block( offset,  0,       petal_z, large_bs, petal_color)
    add_block(-offset,  0,       petal_z, large_bs, petal_color)
    add_block( 0,       offset,  petal_z, large_bs, petal_color)
    add_block( 0,      -offset,  petal_z, large_bs, petal_color)
        
    # Join all
    bpy.ops.object.select_all(action='DESELECT')
    for p in parts:
        p.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    
    combined = bpy.context.active_object
    combined.name = name
    
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB')
    print(f"Exported {name}: {len(combined.data.vertices)} verts")

for c_name, c_val in PETAL_COLORS.items():
    for height in [1, 2, 3]:
        file_path = fr"c:\Repo\test-game\assets\flower_{c_name}_{height}.glb"
        make_flower(f"Flower_{c_name}_{height}", file_path, c_val, height)

print("All flowers exported!")
