import bpy
import os

def inspect_parts(filepath):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=filepath)
    
    obj = bpy.context.scene.objects[0]
    bpy.context.view_layer.objects.active = obj
    
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.separate(type='LOOSE')
    bpy.ops.object.mode_set(mode='OBJECT')
    
    print(f"Parts in {filepath}:")
    for o in bpy.context.scene.objects:
        if o.type == 'MESH':
            print(f"  {o.name}: {len(o.data.polygons)} polys, center z: {o.location.z}")

inspect_parts(r"c:\Repo\test-game\assets\trees\pine-base_basic_shaded.glb")
