"""
Inspect the downloaded grass model to understand its dimensions and shape,
then recreate it as a blocky/voxel version matching the game's aesthetic.
"""
import bpy
import os

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=r"c:\Repo\test-game\assets\grass\tickg-grass_shaded.glb")

for obj in bpy.context.scene.objects:
    if obj.type == 'MESH':
        mesh = obj.data
        verts = [v.co for v in mesh.vertices]
        min_x = min(v.x for v in verts)
        max_x = max(v.x for v in verts)
        min_y = min(v.y for v in verts)
        max_y = max(v.y for v in verts)
        min_z = min(v.z for v in verts)
        max_z = max(v.z for v in verts)
        print(f"Object: {obj.name}")
        print(f"  Verts: {len(verts)}, Faces: {len(mesh.polygons)}")
        print(f"  X: {min_x:.3f} to {max_x:.3f} (width: {max_x-min_x:.3f})")
        print(f"  Y: {min_y:.3f} to {max_y:.3f} (depth: {max_y-min_y:.3f})")
        print(f"  Z: {min_z:.3f} to {max_z:.3f} (height: {max_z-min_z:.3f})")
        # Check materials
        for slot in obj.material_slots:
            if slot.material:
                m = slot.material
                print(f"  Material: {m.name}")
                if m.use_nodes:
                    for node in m.node_tree.nodes:
                        print(f"    Node: {node.type} - {node.name}")
