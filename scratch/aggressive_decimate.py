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
            
            # Merge close vertices to fix tiny gaps before decimation
            bpy.ops.object.mode_set(mode='EDIT')
            bpy.ops.mesh.select_all(action='SELECT')
            bpy.ops.mesh.remove_doubles(threshold=0.01)
            bpy.ops.object.mode_set(mode='OBJECT')
            
            # Aggressive Planar Decimation (up to 35 degrees)
            mod = obj.modifiers.new(name="DecimatePlanar", type='DECIMATE')
            mod.decimate_type = 'DISSOLVE'
            mod.angle_limit = 0.610865 # 35 degrees
            bpy.ops.object.modifier_apply(modifier="DecimatePlanar")
            
            # Small collapse pass to safely remove any remaining redundant geometry
            mod2 = obj.modifiers.new(name="DecimateCollapse", type='DECIMATE')
            mod2.decimate_type = 'COLLAPSE'
            mod2.ratio = 0.3 # Leave 30% of remaining
            bpy.ops.object.modifier_apply(modifier="DecimateCollapse")
            
    total_polys_after = sum([len(obj.data.polygons) for obj in bpy.context.scene.objects if obj.type == 'MESH'])
    
    bpy.ops.export_scene.gltf(filepath=filepath, export_format='GLB')
    return f"{os.path.basename(filepath)}: {total_polys_before} -> {total_polys_after} polygons"

res1 = process_file(r"c:\Repo\test-game\assets\trees\pine-base_basic_shaded.glb")
res2 = process_file(r"c:\Repo\test-game\assets\trees\oak-base_basic_shaded.glb")
print(res1)
print(res2)
