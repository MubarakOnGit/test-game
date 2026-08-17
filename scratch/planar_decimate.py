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
            
            mod = obj.modifiers.new(name="Decimate", type='DECIMATE')
            mod.decimate_type = 'DISSOLVE' # Planar mode
            mod.angle_limit = 0.0872665 # 5 degrees
            
            bpy.ops.object.modifier_apply(modifier="Decimate")
            
    total_polys_after = sum([len(obj.data.polygons) for obj in bpy.context.scene.objects if obj.type == 'MESH'])
    
    bpy.ops.export_scene.gltf(filepath=filepath, export_format='GLB')
    return f"{os.path.basename(filepath)}: {total_polys_before} -> {total_polys_after} polygons"

res1 = process_file(r"c:\Repo\test-game\assets\trees\pine-base_basic_shaded.glb")
res2 = process_file(r"c:\Repo\test-game\assets\trees\oak-base_basic_shaded.glb")
print(res1)
print(res2)
