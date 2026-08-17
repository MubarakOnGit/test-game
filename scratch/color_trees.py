import bpy
import os

def hex_to_rgb(hex_str):
    hex_str = hex_str.lstrip('#')
    return tuple(int(hex_str[i:i+2], 16)/255.0 for i in (0, 2, 4)) + (1.0,)

pine_colors = {
    'leaf': hex_to_rgb('45702b'),
    'leaf_shade': hex_to_rgb('2f4922'),
    'trunk': hex_to_rgb('5a3f20'),
    'trunk_shade': hex_to_rgb('3b2a18')
}
oak_colors = {
    'leaf': hex_to_rgb('597f29'),
    'leaf_shade': hex_to_rgb('355319'),
    'trunk': hex_to_rgb('6b4b25'),
    'trunk_shade': hex_to_rgb('433119')
}

def process_file(filepath, colors):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    try:
        bpy.ops.import_scene.gltf(filepath=filepath)
    except Exception as e:
        return f"Failed to load {filepath}: {e}"
    
    for obj in bpy.context.scene.objects:
        if obj.type == 'MESH':
            mesh = obj.data
            
            min_z = min([v.co.z for v in mesh.vertices])
            max_z = max([v.co.z for v in mesh.vertices])
            height = max_z - min_z
            
            # Detect trunk width dynamically by looking at the very bottom of the tree
            bottom_verts = [v for v in mesh.vertices if v.co.z < min_z + (height * 0.1)]
            if not bottom_verts:
                bottom_verts = mesh.vertices
            max_trunk_x = max([abs(v.co.x) for v in bottom_verts]) * 1.5 # 50% margin just in case
            max_trunk_y = max([abs(v.co.y) for v in bottom_verts]) * 1.5
            
            if not mesh.vertex_colors:
                mesh.vertex_colors.new(name="Col")
            color_layer = mesh.vertex_colors.active
            
            for poly in mesh.polygons:
                # Trunk is near the center XY and below 45% of the tree's height
                is_trunk = (poly.center.z < min_z + (height * 0.45)) and \
                           (abs(poly.center.x) <= max_trunk_x) and \
                           (abs(poly.center.y) <= max_trunk_y)
                
                is_shade = (poly.normal.z < -0.1) or (poly.normal.x < -0.1) or (poly.normal.y < -0.1)
                
                if is_trunk:
                    c = colors['trunk_shade'] if is_shade else colors['trunk']
                else:
                    c = colors['leaf_shade'] if is_shade else colors['leaf']
                    
                for loop_idx in poly.loop_indices:
                    color_layer.data[loop_idx].color = c
            
    bpy.ops.export_scene.gltf(filepath=filepath, export_format='GLB')
    return f"Colored {os.path.basename(filepath)}"

res1 = process_file(r"c:\Repo\test-game\assets\trees\pine-base_basic_shaded.glb", pine_colors)
res2 = process_file(r"c:\Repo\test-game\assets\trees\oak-base_basic_shaded.glb", oak_colors)
print(res1)
print(res2)
