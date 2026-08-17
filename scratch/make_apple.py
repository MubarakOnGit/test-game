import bpy
import math

def hex_to_rgba(h):
    h = h.lstrip('#')
    return (int(h[0:2],16)/255, int(h[2:4],16)/255, int(h[4:6],16)/255, 1.0)

# Colors
APPLE_COLOR = hex_to_rgba('e74c3c')  # Red
STEM_COLOR  = hex_to_rgba('5d4037')  # Brown
LEAF_COLOR  = hex_to_rgba('4caf50')  # Green

def paint_obj(obj, color):
    mesh = obj.data
    if not mesh.vertex_colors:
        mesh.vertex_colors.new(name="Col")
    col = mesh.vertex_colors.active
    
    for poly in mesh.polygons:
        if poly.normal.z > 0.8:
            shade = 1.0    
        elif abs(poly.normal.z) < 0.2:
            shade = 0.85    
        else:
            shade = 0.7    
            
        r, g, b = color[0]*shade, color[1]*shade, color[2]*shade
        for li in poly.loop_indices:
            col.data[li].color = (r, g, b, 1.0)

def make_apple(name, path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    
    parts = []
    
    # 1. Apple Body (Red Cube)
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.125))
    body = bpy.context.active_object
    body.scale = (0.25, 0.25, 0.25)
    bpy.ops.object.transform_apply(scale=True)
    paint_obj(body, APPLE_COLOR)
    parts.append(body)
    
    # 2. Stem (Brown)
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.28))
    stem = bpy.context.active_object
    stem.scale = (0.04, 0.04, 0.06)
    bpy.ops.object.transform_apply(scale=True)
    paint_obj(stem, STEM_COLOR)
    parts.append(stem)
    
    # 3. Leaf (Green)
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0.04, 0, 0.28))
    leaf = bpy.context.active_object
    leaf.scale = (0.08, 0.04, 0.02)
    bpy.ops.object.transform_apply(scale=True)
    paint_obj(leaf, LEAF_COLOR)
    parts.append(leaf)

    # Join all
    bpy.ops.object.select_all(action='DESELECT')
    for p in parts:
        p.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    
    combined = bpy.context.active_object
    combined.name = name
    
    # Center origin to center of mass for proper physics tumbling
    bpy.ops.object.origin_set(type='ORIGIN_CENTER_OF_VOLUME', center='BOUNDS')
    # Move object so origin is at (0,0,0)
    combined.location = (0, 0, 0)
    bpy.ops.object.transform_apply(location=True)

    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB')
    print(f"Exported {name}: {len(combined.data.vertices)} verts")

make_apple("Apple", r"c:\Repo\test-game\assets\apple.glb")
print("Apple exported!")
