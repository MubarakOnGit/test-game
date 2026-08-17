import bpy
import os

def process_file(filepath):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    try:
        bpy.ops.import_scene.gltf(filepath=filepath)
    except Exception as e:
        return f"Failed to load {filepath}: {e}"
    
    total_polys_before = sum([len(obj.data.polygons) for obj in bpy.context.scene.objects if obj.type == 'MESH'])
    
    for obj in bpy.context.scene.objects:
        if obj.type == 'MESH':
            bpy.ops.object.select_all(action='DESELECT')
            obj.select_set(True)
            bpy.context.view_layer.objects.active = obj
            
            # 1. Remesh into perfect blocks
            mod_remesh = obj.modifiers.new(name="RemeshBlocks", type='REMESH')
            mod_remesh.mode = 'BLOCKS'
            mod_remesh.octree_depth = 7  # High enough to capture the shape, low enough to be clean voxels
            bpy.ops.object.modifier_apply(modifier="RemeshBlocks")
            
            # 2. Planar merge to wipe out internal triangles and coplanar box sides
            mod_planar = obj.modifiers.new(name="DecimatePlanar", type='DECIMATE')
            mod_planar.decimate_type = 'DISSOLVE'
            mod_planar.angle_limit = 0.0872665 # 5 degrees (perfect for 90-degree boxes)
            bpy.ops.object.modifier_apply(modifier="DecimatePlanar")
            
    total_polys_after = sum([len(obj.data.polygons) for obj in bpy.context.scene.objects if obj.type == 'MESH'])
    
    bpy.ops.export_scene.gltf(filepath=filepath, export_format='GLB')
    return f"{os.path.basename(filepath)}: {total_polys_before} -> {total_polys_after} polygons"

res1 = process_file(r"c:\Repo\test-game\assets\trees\pine-base_basic_shaded.glb")
res2 = process_file(r"c:\Repo\test-game\assets\trees\oak-base_basic_shaded.glb")
print(res1)
print(res2)
