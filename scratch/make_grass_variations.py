"""
Creates 3 distinct voxel grass mesh variations matching the game's blocky aesthetic.
Instead of stretched single boxes, each grass blade is built from a stack of small 
cubic blocks that shift position as they go up, creating a jagged, pixel-art/Minecraft-like 
voxel blade.
"""
import bpy
import math
import random

def hex_to_rgba(h):
    h = h.lstrip('#')
    return (int(h[0:2],16)/255, int(h[2:4],16)/255, int(h[4:6],16)/255, 1.0)

COLORS = {
    'tip':    hex_to_rgba('a7c15b'),   # Bright green tip
    'mid':    hex_to_rgba('708d49'),   # Mid green
    'base':   hex_to_rgba('528530'),   # Dark base
    'young':  hex_to_rgba('a7c15b'),   
    'old':    hex_to_rgba('528530'),   
}

def paint_mesh(obj, min_z, max_z, tint='normal'):
    mesh = obj.data
    if not mesh.vertex_colors:
        mesh.vertex_colors.new(name="Col")
    col = mesh.vertex_colors.active
    z_range = max_z - min_z or 1.0
    for poly in mesh.polygons:
        cz = sum(mesh.vertices[vi].co.z for vi in poly.vertices) / len(poly.vertices)
        t = (cz - min_z) / z_range
        is_side = abs(poly.normal.z) < 0.3
        shade = 0.68 if is_side else 1.0
        
        tip_c = COLORS['tip']
        base_c = COLORS['base']
        if tint == 'young':
            base_c = COLORS['mid']
        elif tint == 'old':
            tip_c = COLORS['mid']
            
        r = (tip_c[0] * t + base_c[0] * (1-t)) * shade
        g = (tip_c[1] * t + base_c[1] * (1-t)) * shade
        b = (tip_c[2] * t + base_c[2] * (1-t)) * shade
        for li in poly.loop_indices:
            col.data[li].color = (r, g, b, 1.0)

def make_jagged_blade(ox, oz, ry_deg, block_size, height, tilt_out):
    """
    Builds a blade out of several stacked cubic blocks.
    The blade bends outward depending on tilt_out and ry_deg.
    """
    blocks = []
    num_blocks = int(max(1, height / block_size))
    
    # Calculate the bending direction vector in the XZ plane
    dir_x = math.cos(math.radians(ry_deg))
    dir_z = math.sin(math.radians(ry_deg))
    
    # How much horizontal shift per vertical block step
    # tilt_out is roughly an angle, we map it to a horizontal offset
    shift_per_step = math.tan(math.radians(tilt_out)) * block_size
    
    # We want a slight gravity droop, so shift increases more towards the top (quadratic curve)
    current_x = ox
    current_z = oz
    
    for i in range(num_blocks):
        # Current height center for this block
        current_y = (i + 0.5) * block_size
        
        # Calculate horizontal shift for this step.
        # Make the bending curve quadratic so it droops nicely at the top
        curve_factor = (i / max(1, num_blocks - 1)) 
        step_shift = shift_per_step * (0.5 + curve_factor * 1.5)
        
        # Add random jaggedness (pixel offset) to make it look voxel-y
        # Snap the shift to a rough "voxel grid" relative to the block size
        current_x += dir_x * step_shift
        current_z += dir_z * step_shift
        
        # Create the cube block
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(current_x, current_z, current_y))
        obj = bpy.context.active_object
        
        # Scale to block size. Maybe slightly thinner at the top!
        taper = 1.0 - (curve_factor * 0.4) 
        obj.scale = (block_size * taper, block_size * taper, block_size)
        
        # Keep them axis-aligned or slightly rotated? 
        # Axis-aligned blocks stacked diagonally gives a pure voxel Minecraft look.
        # Let's rotate them to face the cluster outward direction just for consistency,
        # but keep them vertically straight.
        obj.rotation_euler = (0, 0, math.radians(ry_deg))
        bpy.ops.object.transform_apply(scale=True, rotation=True)
        
        blocks.append(obj)
        
    # Join all blocks of this blade into one object
    if not blocks:
        return None
        
    bpy.ops.object.select_all(action='DESELECT')
    for b in blocks:
        b.select_set(True)
    bpy.context.view_layer.objects.active = blocks[0]
    bpy.ops.object.join()
    
    return bpy.context.active_object

def join_and_export(objects, name, path, tint='normal'):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objects:
        if o: o.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    combined = bpy.context.active_object
    combined.name = name
    vz = [v.co.z for v in combined.data.vertices]
    paint_mesh(combined, min(vz), max(vz), tint)
    
    # Optional: Decimate slightly to remove hidden internal faces from the stacked blocks
    # This keeps performance good since stacking blocks creates a lot of overlapping internal faces.
    bpy.ops.object.modifier_add(type='DECIMATE')
    combined.modifiers["Decimate"].ratio = 0.5
    bpy.ops.object.modifier_apply(modifier="Decimate")
    
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB')
    print(f"Exported {name}: {len(combined.data.vertices)} verts, {len(combined.data.polygons)} faces")
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete()

def generate_jagged_cluster(num_blades, radius, height_range, block_size_range, name, path, tint):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    blades = []
    for i in range(num_blades):
        angle = (i / num_blades) * 360 + random.uniform(-15, 15)
        rad = random.uniform(0, radius)
        ox = math.cos(math.radians(angle)) * rad
        oz = math.sin(math.radians(angle)) * rad
        
        tilt = (rad / radius) * random.uniform(15, 45) # more tilt for outer blades
        h = random.uniform(*height_range)
        b_size = random.uniform(*block_size_range)
        ry = angle + random.uniform(-20, 20)
        
        blade = make_jagged_blade(ox, oz, ry, b_size, h, tilt_out=tilt)
        if blade:
            blades.append(blade)
        
    join_and_export(blades, name, path, tint)

# Using fewer blades because each blade is now made of multiple blocks,
# which fills space much more effectively and looks thicker.
generate_jagged_cluster(25, 1.2, (0.4, 0.7), (0.08, 0.12), "GrassA", r"c:\Repo\test-game\assets\grass\grass_a.glb", 'young')
generate_jagged_cluster(30, 1.3, (0.6, 1.0), (0.08, 0.12), "GrassB", r"c:\Repo\test-game\assets\grass\grass_b.glb", 'normal')
generate_jagged_cluster(20, 1.4, (0.9, 1.4), (0.06, 0.10), "GrassC", r"c:\Repo\test-game\assets\grass\grass_c.glb", 'old')

print("All 3 grass variations exported!")
