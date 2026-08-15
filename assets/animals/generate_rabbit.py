import bpy
import math
import os

# ============================================================
# BLOCKY RABBIT v2 — FIXED BACK LEGS + SEAMLESS LOOP
# ============================================================
# Fixes:
# 1. Back legs now have proper rabbit anatomy (large thigh + shin + foot)
# 2. Animation is a seamless 12-frame loop with NO pause
# 3. Action named with "-loop" suffix for Godot auto-detection
# 4. Last frame does NOT equal first frame — Godot interpolates the gap

# Clear scene (Context-safe)
for obj in bpy.data.objects:
    bpy.data.objects.remove(obj, do_unlink=True)

for block in [bpy.data.meshes, bpy.data.materials, bpy.data.textures, 
              bpy.data.curves, bpy.data.actions, bpy.data.armatures]:
    for item in list(block):
        if item.users == 0:
            block.remove(item)

# ============================================================
# MATERIALS
# ============================================================
def create_mat(name, color, roughness=0.7):
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Roughness"].default_value = roughness
    return mat

mat_brown = create_mat("Brown", (0.72, 0.52, 0.35, 1.0), 0.6)
mat_brown_dark = create_mat("BrownDark", (0.58, 0.40, 0.26, 1.0), 0.7)
mat_white = create_mat("White", (0.95, 0.95, 0.92, 1.0), 0.5)
mat_black = create_mat("Black", (0.06, 0.06, 0.06, 1.0), 0.3)
mat_pink = create_mat("Pink", (0.88, 0.68, 0.68, 1.0), 0.5)

# ============================================================
# HELPER: Create box with origin control
# ============================================================
def create_box(name, w, h, d, mat, origin_at_bottom=True):
    mesh = bpy.data.meshes.new(name + "_mesh")
    hw, hh, hd = w/2, h/2, d/2
    if origin_at_bottom:
        verts = [
            (-hw, -hd, 0), (hw, -hd, 0), (hw, hd, 0), (-hw, hd, 0),
            (-hw, -hd, h), (hw, -hd, h), (hw, hd, h), (-hw, hd, h),
        ]
    else:
        verts = [
            (-hw, -hh, -hd), (hw, -hh, -hd), (hw, hh, -hd), (-hw, hh, -hd),
            (-hw, -hh, hd), (hw, -hh, hd), (hw, hh, hd), (-hw, hh, hd),
        ]
    faces = [(0,1,2,3), (4,5,6,7), (0,1,5,4), (2,3,7,6), (0,3,7,4), (1,2,6,5)]
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    return obj

# ============================================================
# BUILD RABBIT BODY PARTS
# ============================================================
parts = {}

# --- BODY (oval-ish torso) ---
body = create_box("Body", 0.52, 0.48, 0.70, mat_brown, origin_at_bottom=False)
body.location = (0, 0, 0.60)
parts["body"] = body

# --- HEAD ---
head = create_box("Head", 0.44, 0.40, 0.40, mat_brown, origin_at_bottom=False)
head.location = (0, -0.38, 1.02)
parts["head"] = head

# --- SNOUT ---
snout = create_box("Snout", 0.20, 0.14, 0.16, mat_brown_dark, origin_at_bottom=False)
snout.location = (0, -0.62, 0.94)
parts["snout"] = snout

# --- NOSE ---
nose = create_box("Nose", 0.07, 0.05, 0.05, mat_black, origin_at_bottom=False)
nose.location = (0, -0.71, 0.98)
parts["nose"] = nose

# --- EYES ---
eye_l = create_box("Eye_L", 0.07, 0.07, 0.03, mat_black, origin_at_bottom=False)
eye_l.location = (0.15, -0.58, 1.08)
parts["eye_l"] = eye_l

eye_r = create_box("Eye_R", 0.07, 0.07, 0.03, mat_black, origin_at_bottom=False)
eye_r.location = (-0.15, -0.58, 1.08)
parts["eye_r"] = eye_r

# --- EARS ---
ear_l = create_box("Ear_L", 0.11, 0.50, 0.09, mat_brown, origin_at_bottom=False)
ear_l.location = (0.13, -0.22, 1.45)
ear_l.rotation_euler = (0.12, 0, -0.08)
parts["ear_l"] = ear_l

ear_l_inner = create_box("Ear_L_Inner", 0.07, 0.40, 0.05, mat_pink, origin_at_bottom=False)
ear_l_inner.location = (0.13, -0.26, 1.45)
ear_l_inner.rotation_euler = (0.12, 0, -0.08)
parts["ear_l_inner"] = ear_l_inner

ear_r = create_box("Ear_R", 0.11, 0.50, 0.09, mat_brown, origin_at_bottom=False)
ear_r.location = (-0.13, -0.22, 1.45)
ear_r.rotation_euler = (0.12, 0, 0.08)
parts["ear_r"] = ear_r

ear_r_inner = create_box("Ear_R_Inner", 0.07, 0.40, 0.05, mat_pink, origin_at_bottom=False)
ear_r_inner.location = (-0.13, -0.26, 1.45)
ear_r_inner.rotation_euler = (0.12, 0, 0.08)
parts["ear_r_inner"] = ear_r_inner

# --- FRONT LEGS ---
# Left Front
leg_fl = create_box("Leg_FL", 0.11, 0.38, 0.11, mat_brown, origin_at_bottom=True)
leg_fl.location = (0.16, -0.28, 0)
parts["leg_fl"] = leg_fl

paw_fl = create_box("Paw_FL", 0.13, 0.07, 0.13, mat_white, origin_at_bottom=True)
paw_fl.location = (0.16, -0.31, 0)
parts["paw_fl"] = paw_fl

# Right Front
leg_fr = create_box("Leg_FR", 0.11, 0.38, 0.11, mat_brown, origin_at_bottom=True)
leg_fr.location = (-0.16, -0.28, 0)
parts["leg_fr"] = leg_fr

paw_fr = create_box("Paw_FR", 0.13, 0.07, 0.13, mat_white, origin_at_bottom=True)
paw_fr.location = (-0.16, -0.31, 0)
parts["paw_fr"] = paw_fr

# --- BACK LEGS (FIXED: proper rabbit anatomy) ---
# Rabbits have LARGE thighs at the back, folded under body when sitting
# Thigh is big and angled, shin extends down, foot at bottom

# LEFT BACK THIGH — large block at rear of body
thigh_bl = create_box("Thigh_BL", 0.22, 0.28, 0.32, mat_brown, origin_at_bottom=False)
thigh_bl.location = (0.24, 0.18, 0.42)
# Rotate so thigh points backward and slightly down
thigh_bl.rotation_euler = (0.25, 0, -0.15)
parts["thigh_bl"] = thigh_bl

# LEFT BACK SHIN — extends from thigh downward
shin_bl = create_box("Shin_BL", 0.10, 0.28, 0.10, mat_brown, origin_at_bottom=True)
shin_bl.location = (0.26, 0.22, 0.15)
shin_bl.rotation_euler = (-0.1, 0, -0.05)
parts["shin_bl"] = shin_bl

# LEFT BACK FOOT
foot_bl = create_box("Foot_BL", 0.14, 0.07, 0.18, mat_white, origin_at_bottom=True)
foot_bl.location = (0.26, 0.18, 0)
foot_bl.rotation_euler = (0, 0, -0.05)
parts["foot_bl"] = foot_bl

# RIGHT BACK THIGH
thigh_br = create_box("Thigh_BR", 0.22, 0.28, 0.32, mat_brown, origin_at_bottom=False)
thigh_br.location = (-0.24, 0.18, 0.42)
thigh_br.rotation_euler = (0.25, 0, 0.15)
parts["thigh_br"] = thigh_br

# RIGHT BACK SHIN
shin_br = create_box("Shin_BR", 0.10, 0.28, 0.10, mat_brown, origin_at_bottom=True)
shin_br.location = (-0.26, 0.22, 0.15)
shin_br.rotation_euler = (-0.1, 0, 0.05)
parts["shin_br"] = shin_br

# RIGHT BACK FOOT
foot_br = create_box("Foot_BR", 0.14, 0.07, 0.18, mat_white, origin_at_bottom=True)
foot_br.location = (-0.26, 0.18, 0)
foot_br.rotation_euler = (0, 0, 0.05)
parts["foot_br"] = foot_br

# --- TAIL ---
tail = create_box("Tail", 0.14, 0.14, 0.14, mat_white, origin_at_bottom=False)
tail.location = (0, 0.42, 0.65)
parts["tail"] = tail

# ============================================================
# CREATE ARMATURE
# ============================================================
bpy.ops.object.armature_add(enter_editmode=True, location=(0, 0, 0))
armature = bpy.context.active_object
armature.name = "RabbitArmature"
arm = armature.data

for bone in list(arm.edit_bones):
    arm.edit_bones.remove(bone)

def add_bone(name, head, tail, parent=None, roll=0):
    bone = arm.edit_bones.new(name)
    bone.head = head
    bone.tail = tail
    bone.roll = roll
    if parent:
        bone.parent = parent
        bone.use_connect = False
    return bone

# ROOT
root = add_bone("Root", (0, 0, 0.35), (0, 0, 0.55))

# SPINE
spine = add_bone("Spine", (0, 0, 0.60), (0, -0.12, 0.82), parent=root)

# HEAD
neck = add_bone("Neck", (0, -0.25, 0.88), (0, -0.40, 1.00), parent=spine)
head_bone = add_bone("Head", (0, -0.40, 1.00), (0, -0.55, 1.18), parent=neck)

# EARS
ear_l_bone = add_bone("Ear_L", (0.13, -0.22, 1.45), (0.13, -0.22, 1.90), parent=head_bone)
ear_r_bone = add_bone("Ear_R", (-0.13, -0.22, 1.45), (-0.13, -0.22, 1.90), parent=head_bone)

# FRONT LEGS
leg_fl_bone = add_bone("Leg_FL", (0.16, -0.28, 0.38), (0.16, -0.28, 0.0), parent=root)
leg_fr_bone = add_bone("Leg_FR", (-0.16, -0.28, 0.38), (-0.16, -0.28, 0.0), parent=root)

# BACK LEGS — Thigh → Shin → Foot chain
# The thigh bone goes from hip to knee
thigh_l_bone = add_bone("Thigh_BL", (0.20, 0.10, 0.50), (0.28, 0.28, 0.30), parent=root)
shin_l_bone = add_bone("Shin_BL", (0.28, 0.28, 0.30), (0.28, 0.22, 0.05), parent=thigh_l_bone)
foot_l_bone = add_bone("Foot_BL", (0.28, 0.22, 0.05), (0.28, 0.15, 0.0), parent=shin_l_bone)

thigh_r_bone = add_bone("Thigh_BR", (-0.20, 0.10, 0.50), (-0.28, 0.28, 0.30), parent=root)
shin_r_bone = add_bone("Shin_BR", (-0.28, 0.28, 0.30), (-0.28, 0.22, 0.05), parent=thigh_r_bone)
foot_r_bone = add_bone("Foot_BR", (-0.28, 0.22, 0.05), (-0.28, 0.15, 0.0), parent=shin_r_bone)

# TAIL
tail_bone = add_bone("Tail", (0, 0.38, 0.65), (0, 0.50, 0.72), parent=spine)

bpy.ops.object.mode_set(mode='OBJECT')

# ============================================================
# PARENT MESHES TO ARMATURE
# ============================================================
for name, obj in parts.items():
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    armature.select_set(True)
    bpy.context.view_layer.objects.active = armature
    bpy.ops.object.parent_set(type='ARMATURE_NAME')

bone_name_map = {
    "body": "Spine",
    "head": "Head", "snout": "Head", "nose": "Head",
    "eye_l": "Head", "eye_r": "Head",
    "ear_l": "Ear_L", "ear_l_inner": "Ear_L",
    "ear_r": "Ear_R", "ear_r_inner": "Ear_R",
    "leg_fl": "Leg_FL", "paw_fl": "Leg_FL",
    "leg_fr": "Leg_FR", "paw_fr": "Leg_FR",
    "thigh_bl": "Thigh_BL", "shin_bl": "Shin_BL", "foot_bl": "Foot_BL",
    "thigh_br": "Thigh_BR", "shin_br": "Shin_BR", "foot_br": "Foot_BR",
    "tail": "Tail",
}

for part_name, bone_name in bone_name_map.items():
    obj = parts[part_name]
    if bone_name not in obj.vertex_groups:
        vg = obj.vertex_groups.new(name=bone_name)
    else:
        vg = obj.vertex_groups[bone_name]
    vg.add(range(len(obj.data.vertices)), 1.0, 'REPLACE')

# ============================================================
# ANIMATION — SEAMLESS 12-FRAME HOP LOOP
# ============================================================
# CRITICAL: No "rest" phase. The rabbit is ALWAYS moving.
# Frame 1 and Frame 12 are DIFFERENT — Godot interpolates between them.
# This prevents the "stutter/pause" at loop point.
#
# Cycle: LANDED → PUSH → AIR → LAND (continuous)
# Frame:   1      4     7     10    12(→1)

# Set default keyframe interpolation to LINEAR (Blender 5.2 compatible)
bpy.context.preferences.edit.keyframe_new_interpolation_type = 'LINEAR'

armature.animation_data_create()

# Name with "-loop" suffix so Godot auto-detects looping
action_hop = bpy.data.actions.new(name="Rabbit_Hop-loop")
armature.animation_data.action = action_hop

pb = armature.pose.bones

def key_bone(bone_name, frame, loc=None, rot=None, scale=None):
    bone = pb[bone_name]
    bone.rotation_mode = 'XYZ'
    if loc is not None:
        bone.location = loc
        bone.keyframe_insert(data_path="location", frame=frame)
    if rot is not None:
        bone.rotation_euler = rot
        bone.keyframe_insert(data_path="rotation_euler", frame=frame)
    if scale is not None:
        bone.scale = scale
        bone.keyframe_insert(data_path="scale", frame=frame)

# Linear interpolation is already set globally at the top

# ============================================================
# POSE DEFINITIONS (Euler angles in radians)
# ============================================================

# --- ROOT (body bounce) ---
# Frame 1: Just landed, body compressed low
key_bone("Root", 1,  loc=(0, 0, -0.06), rot=(0.08, 0, 0), scale=(1.08, 0.92, 1.08))
# Frame 4: Pushing off — body rising, stretching
key_bone("Root", 4,  loc=(0, 0, 0.15),  rot=(-0.10, 0, 0), scale=(0.95, 1.05, 0.95))
# Frame 7: Peak of jump — body high, stretched
key_bone("Root", 7,  loc=(0, 0, 0.45),  rot=(-0.15, 0, 0), scale=(0.92, 1.08, 0.92))
# Frame 10: Coming down — body descending
key_bone("Root", 10, loc=(0, 0, 0.10),  rot=(-0.05, 0, 0), scale=(0.98, 1.02, 0.98))
# Frame 12: ALMOST landed — slightly higher than frame 1 so Godot interpolates the last bit
key_bone("Root", 12, loc=(0, 0, -0.02), rot=(0.04, 0, 0), scale=(1.04, 0.96, 1.04))

# --- SPINE (body tilt) ---
# Tilts back when landing, forward when pushing
key_bone("Spine", 1,  rot=(0.10, 0, 0))
key_bone("Spine", 4,  rot=(-0.15, 0, 0))
key_bone("Spine", 7,  rot=(-0.20, 0, 0))
key_bone("Spine", 10, rot=(-0.05, 0, 0))
key_bone("Spine", 12, rot=(0.06, 0, 0))

# --- HEAD (counter-rotation to stay level) ---
key_bone("Head", 1,  rot=(-0.05, 0, 0))
key_bone("Head", 4,  rot=(0.10, 0, 0))
key_bone("Head", 7,  rot=(0.15, 0, 0))
key_bone("Head", 10, rot=(0.03, 0, 0))
key_bone("Head", 12, rot=(-0.03, 0, 0))

# --- EARS (physics bounce — lag behind body) ---
# Ears tilt back on landing, flop forward in air
key_bone("Ear_L", 1,  rot=(0.30, 0, -0.08))
key_bone("Ear_L", 4,  rot=(-0.05, 0, -0.10))
key_bone("Ear_L", 7,  rot=(-0.25, 0, -0.12))
key_bone("Ear_L", 10, rot=(-0.10, 0, -0.10))
key_bone("Ear_L", 12, rot=(0.20, 0, -0.08))

key_bone("Ear_R", 1,  rot=(0.30, 0, 0.08))
key_bone("Ear_R", 4,  rot=(-0.05, 0, 0.10))
key_bone("Ear_R", 7,  rot=(-0.25, 0, 0.12))
key_bone("Ear_R", 10, rot=(-0.10, 0, 0.10))
key_bone("Ear_R", 12, rot=(0.20, 0, 0.08))

# --- FRONT LEGS ---
# Frame 1: On ground, slightly back
key_bone("Leg_FL", 1,  rot=(0.15, 0, 0), loc=(0, 0, 0))
# Frame 4: Lifting off ground, reaching forward
key_bone("Leg_FL", 4,  rot=(-0.30, 0, 0), loc=(0, 0, 0.05))
# Frame 7: Tucked in air
key_bone("Leg_FL", 7,  rot=(-0.45, 0, 0), loc=(0, 0, 0.08))
# Frame 10: Reaching down to land
key_bone("Leg_FL", 10, rot=(-0.15, 0, 0), loc=(0, 0, 0.03))
# Frame 12: Almost on ground
key_bone("Leg_FL", 12, rot=(0.08, 0, 0), loc=(0, 0, 0.01))

# Right front (slight offset for natural feel)
key_bone("Leg_FR", 1,  rot=(0.10, 0, 0), loc=(0, 0, 0))
key_bone("Leg_FR", 4,  rot=(-0.25, 0, 0), loc=(0, 0, 0.04))
key_bone("Leg_FR", 7,  rot=(-0.40, 0, 0), loc=(0, 0, 0.07))
key_bone("Leg_FR", 10, rot=(-0.12, 0, 0), loc=(0, 0, 0.02))
key_bone("Leg_FR", 12, rot=(0.06, 0, 0), loc=(0, 0, 0.01))

# --- BACK LEGS (the rabbit power!) ---
# Frame 1: Just landed — thighs angled back, shins compressed
key_bone("Thigh_BL", 1,  rot=(-0.40, 0, 0))
key_bone("Shin_BL", 1,   rot=(0.70, 0, 0))
key_bone("Foot_BL", 1,   rot=(0.20, 0, 0))

# Frame 4: Pushing off — thighs rotating down/back, shins extending
key_bone("Thigh_BL", 4,  rot=(0.20, 0, 0))
key_bone("Shin_BL", 4,   rot=(0.10, 0, 0))
key_bone("Foot_BL", 4,   rot=(0.05, 0, 0))

# Frame 7: Peak air — thighs tucked forward, shins bent
key_bone("Thigh_BL", 7,  rot=(0.50, 0, 0))
key_bone("Shin_BL", 7,   rot=(-0.30, 0, 0))
key_bone("Foot_BL", 7,   rot=(-0.10, 0, 0))

# Frame 10: Descending — reaching forward to land
key_bone("Thigh_BL", 10, rot=(0.10, 0, 0))
key_bone("Shin_BL", 10,  rot=(0.40, 0, 0))
key_bone("Foot_BL", 10,  rot=(0.15, 0, 0))

# Frame 12: ALMOST landed — NOT identical to frame 1
key_bone("Thigh_BL", 12, rot=(-0.25, 0, 0))
key_bone("Shin_BL", 12,  rot=(0.55, 0, 0))
key_bone("Foot_BL", 12,  rot=(0.18, 0, 0))

# Right back (mirrored, slight offset)
key_bone("Thigh_BR", 1,  rot=(-0.35, 0, 0))
key_bone("Shin_BR", 1,   rot=(0.65, 0, 0))
key_bone("Foot_BR", 1,   rot=(0.18, 0, 0))

key_bone("Thigh_BR", 4,  rot=(0.15, 0, 0))
key_bone("Shin_BR", 4,   rot=(0.15, 0, 0))
key_bone("Foot_BR", 4,   rot=(0.03, 0, 0))

key_bone("Thigh_BR", 7,  rot=(0.45, 0, 0))
key_bone("Shin_BR", 7,   rot=(-0.25, 0, 0))
key_bone("Foot_BR", 7,   rot=(-0.08, 0, 0))

key_bone("Thigh_BR", 10, rot=(0.05, 0, 0))
key_bone("Shin_BR", 10,  rot=(0.35, 0, 0))
key_bone("Foot_BR", 10,  rot=(0.12, 0, 0))

key_bone("Thigh_BR", 12, rot=(-0.20, 0, 0))
key_bone("Shin_BR", 12,  rot=(0.50, 0, 0))
key_bone("Foot_BR", 12,  rot=(0.16, 0, 0))

# --- TAIL (wiggle) ---
key_bone("Tail", 1,  rot=(0.15, 0, 0.05))
key_bone("Tail", 4,  rot=(-0.10, 0, -0.05))
key_bone("Tail", 7,  rot=(-0.20, 0, 0.08))
key_bone("Tail", 10, rot=(0.05, 0, -0.03))
key_bone("Tail", 12, rot=(0.12, 0, 0.04))

# ============================================================
# IDLE ANIMATION — "Look Around" (Add this after the hop animation)
# ============================================================
# Creates a new action: "Rabbit_Idle-loop"
# The rabbit subtly looks left → right → center with ear twitches and breathing
# 60 frames @ 30fps = 2 seconds, seamless loop

# Switch to the new idle action
action_idle = bpy.data.actions.new(name="Rabbit_Idle-loop")
armature.animation_data.action = action_idle

# --- FRAME 1: Neutral ---
key_bone("Root",   1,  loc=(0, 0, 0),       rot=(0, 0, 0),       scale=(1, 1, 1))
key_bone("Spine",  1,  rot=(0, 0, 0))
key_bone("Head",   1,  rot=(0, 0, 0))
key_bone("Neck",   1,  rot=(0, 0, 0))
key_bone("Ear_L",  1,  rot=(0.12, 0, -0.08))
key_bone("Ear_R",  1,  rot=(0.12, 0, 0.08))
key_bone("Leg_FL", 1,  rot=(0, 0, 0), loc=(0, 0, 0))
key_bone("Leg_FR", 1,  rot=(0, 0, 0), loc=(0, 0, 0))
key_bone("Thigh_BL", 1, rot=(-0.10, 0, 0))
key_bone("Shin_BL",  1, rot=(0.20, 0, 0))
key_bone("Foot_BL",  1, rot=(0.05, 0, 0))
key_bone("Thigh_BR", 1, rot=(-0.10, 0, 0))
key_bone("Shin_BR",  1, rot=(0.20, 0, 0))
key_bone("Foot_BR",  1, rot=(0.05, 0, 0))
key_bone("Tail",   1,  rot=(0, 0, 0))

# --- FRAME 15: Look LEFT + ear perk ---
key_bone("Root",   15, loc=(0, 0, 0.01),    rot=(0, 0, 0),       scale=(1.01, 0.99, 1.01))
key_bone("Spine",  15, rot=(0, 0, 0.05))
key_bone("Head",   15, rot=(0, 0.10, -0.35))   # Head turns left
key_bone("Neck",   15, rot=(0, 0, -0.15))
key_bone("Ear_L",  15, rot=(0.05, 0, -0.15))   # Left ear perks forward
key_bone("Ear_R",  15, rot=(0.20, 0, 0.05))     # Right ear swivels back
key_bone("Tail",   15, rot=(0.05, 0, 0.10))

# --- FRAME 25: Hold left look + subtle breathing ---
key_bone("Root",   25, loc=(0, 0, 0.02),    rot=(0, 0, 0),       scale=(1.02, 0.98, 1.02))
key_bone("Head",   25, rot=(0, 0.08, -0.38))
key_bone("Ear_L",  25, rot=(0.08, 0, -0.12))
key_bone("Ear_R",  25, rot=(0.18, 0, 0.08))

# --- FRAME 35: Look RIGHT + ear twitch ---
key_bone("Root",   35, loc=(0, 0, 0.01),    rot=(0, 0, 0),       scale=(1.01, 0.99, 1.01))
key_bone("Spine",  35, rot=(0, 0, -0.05))
key_bone("Head",   35, rot=(0, -0.05, 0.35))   # Head turns right
key_bone("Neck",   35, rot=(0, 0, 0.15))
key_bone("Ear_L",  35, rot=(0.22, 0, -0.05))    # Left ear swivels back
key_bone("Ear_R",  35, rot=(0.03, 0, 0.18))     # Right ear perks forward
key_bone("Tail",   35, rot=(0.05, 0, -0.08))

# --- FRAME 45: Hold right look ---
key_bone("Root",   45, loc=(0, 0, 0.02),    rot=(0, 0, 0),       scale=(1.02, 0.98, 1.02))
key_bone("Head",   45, rot=(0, -0.03, 0.38))
key_bone("Ear_L",  45, rot=(0.20, 0, -0.08))
key_bone("Ear_R",  45, rot=(0.05, 0, 0.15))

# --- FRAME 55: Return to center + ears relax ---
key_bone("Root",   55, loc=(0, 0, 0.005),   rot=(0, 0, 0),       scale=(1.005, 0.995, 1.005))
key_bone("Spine",  55, rot=(0, 0, 0))
key_bone("Head",   55, rot=(0, 0, 0.05))
key_bone("Neck",   55, rot=(0, 0, 0.02))
key_bone("Ear_L",  55, rot=(0.14, 0, -0.06))
key_bone("Ear_R",  55, rot=(0.14, 0, 0.06))
key_bone("Tail",   55, rot=(0.02, 0, 0))

# --- FRAME 60: ALMOST back to neutral (seamless loop gap) ---
# NOT identical to frame 1 — Godot interpolates 60→1
key_bone("Root",   60, loc=(0, 0, 0.008),   rot=(0, 0, 0),       scale=(1.008, 0.992, 1.008))
key_bone("Spine",  60, rot=(0, 0, 0.01))
key_bone("Head",   60, rot=(0, 0, 0.02))
key_bone("Ear_L",  60, rot=(0.13, 0, -0.07))
key_bone("Ear_R",  60, rot=(0.13, 0, 0.07))
key_bone("Tail",   60, rot=(0.01, 0, 0.01))

# Legs stay planted but shift weight slightly
key_bone("Thigh_BL", 15, rot=(-0.15, 0, 0))
key_bone("Shin_BL",  15, rot=(0.25, 0, 0))
key_bone("Thigh_BL", 35, rot=(-0.05, 0, 0))
key_bone("Shin_BL",  35, rot=(0.18, 0, 0))
key_bone("Thigh_BL", 55, rot=(-0.12, 0, 0))
key_bone("Shin_BL",  55, rot=(0.22, 0, 0))
key_bone("Thigh_BL", 60, rot=(-0.11, 0, 0))
key_bone("Shin_BL",  60, rot=(0.21, 0, 0))

key_bone("Thigh_BR", 15, rot=(-0.05, 0, 0))
key_bone("Shin_BR",  15, rot=(0.18, 0, 0))
key_bone("Thigh_BR", 35, rot=(-0.15, 0, 0))
key_bone("Shin_BR",  35, rot=(0.25, 0, 0))
key_bone("Thigh_BR", 55, rot=(-0.08, 0, 0))
key_bone("Shin_BR",  55, rot=(0.20, 0, 0))
key_bone("Thigh_BR", 60, rot=(-0.09, 0, 0))
key_bone("Shin_BR",  60, rot=(0.20, 0, 0))

# ============================================================
# SCENE SETUP
# ============================================================
scene = bpy.context.scene
scene.frame_start = 1
scene.frame_end = 12
scene.render.fps = 30

# ============================================================
# EXPORT
# ============================================================
bpy.ops.object.select_all(action='DESELECT')
armature.select_set(True)
for obj in parts.values():
    obj.select_set(True)

export_path = r"c:\Repo\test-game\assets\animals\blocky_rabbit.glb"
os.makedirs(os.path.dirname(export_path), exist_ok=True)

bpy.ops.export_scene.gltf(
    filepath=export_path,
    export_format='GLB',
    use_selection=True,
    export_animations=True,
    export_animation_mode='ACTIONS',
    export_nla_strips=False,
    export_skins=True,
    export_all_influences=True,
    export_yup=True,
)

print("=" * 60)
print(f"✅ EXPORTED: {export_path}")
print(f"📊 Bones: {len(armature.data.bones)}")
print(f"📊 Parts: {len(parts)}")
print(f"🎬 Animation: 'Rabbit_Hop-loop' (12 frames, seamless)")
print(f"🐇 Back legs: Large thigh + shin + foot (rabbit anatomy)")
print("=" * 60)