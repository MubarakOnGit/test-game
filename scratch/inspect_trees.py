import bpy
import sys

def inspect_file(filepath):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=filepath)
    
    print(f"--- Inspecting {filepath} ---")
    for obj in bpy.context.scene.objects:
        if obj.type == 'MESH':
            print(f"Object: {obj.name}, Polygons: {len(obj.data.polygons)}")
            for mat_slot in obj.material_slots:
                print(f"  Material: {mat_slot.name}")
                
inspect_file(r"c:\Repo\test-game\assets\trees\pine-base_basic_shaded.glb")
