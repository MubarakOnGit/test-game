import bpy
import math
import os

# ============================================================
# BLOCKY WOLF v2 — Matches Minecraft-style reference image
# ============================================================
# Colors: dark grey body/thighs, medium grey chest/head,
#         light grey/white belly + lower legs, brown snout, black nose/eyes
# Legs sit flat on ground (Z=0), body elevated on top

# Clear scene (Context-safe)
for obj in bpy.data.objects:
    bpy.data.objects.remove(obj, do_unlink=True)

for block in [bpy.data.meshes, bpy.data.materials, bpy.data.textures,
              bpy.data.curves, bpy.data.actions, bpy.data.armatures]:
    for item in list(block):
        if item.users == 0:
            block.remove(item)

# Set default keyframe interpolation to LINEAR (Blender 5.2 compatible)
bpy.context.preferences.edit.keyframe_new_interpolation_type = 'LINEAR'

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

mat_grey_top    = create_mat("GreyTop",    (0.45, 0.47, 0.50, 1.0), 0.70)  # Dark grey (saddle/back)
mat_grey_mid    = create_mat("GreyMid",    (0.62, 0.64, 0.68, 1.0), 0.65)  # Medium grey (head/chest)
mat_grey_light  = create_mat("GreyLight",  (0.85, 0.86, 0.88, 1.0), 0.55)  # Light grey/white (belly/lower legs)
mat_grey_dark   = create_mat("GreyDark",   (0.32, 0.34, 0.36, 1.0), 0.75)  # Very dark (upper legs/thighs)
mat_nose        = create_mat("NoseBrown",  (0.60, 0.50, 0.38, 1.0), 0.50)  # Tan/brown muzzle
mat_black       = create_mat("Black",      (0.05, 0.05, 0.05, 1.0), 0.30)  # Eyes/nose tip

# ============================================================
# HELPER: Create box mesh (origin_at_bottom=True means Z=0 is the floor)
# ============================================================
def create_box(name, w, d, h, mat, origin_at_bottom=True):
    # w=X width, d=Y depth, h=Z height
    mesh = bpy.data.meshes.new(name + "_mesh")
    hw, hd, hh = w/2, d/2, h/2
    if origin_at_bottom:
        verts = [
            (-hw, -hd, 0), (hw, -hd, 0), (hw, hd, 0), (-hw, hd, 0),
            (-hw, -hd, h), (hw, -hd, h), (hw, hd, h), (-hw, hd, h),
        ]
    else:
        verts = [
            (-hw, -hd, -hh), (hw, -hd, -hh), (hw, hd, -hh), (-hw, hd, -hh),
            (-hw, -hd,  hh), (hw, -hd,  hh), (hw, hd,  hh), (-hw, hd,  hh),
        ]
    faces = [(0,1,2,3),(4,5,6,7),(0,1,5,4),(2,3,7,6),(0,3,7,4),(1,2,6,5)]
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    return obj

# ============================================================
# BUILD WOLF BODY PARTS
# Wolf faces -Y direction. Z=up. Ground = Z=0.
# ============================================================
parts = {}

BZ = 0.50  # body base Z (how high legs lift body)

# ─── TORSO ──────────────────────────────────────────────────
# Main back/saddle block (dark grey, spans most of body length)
body = create_box("Body", 0.60, 1.10, 0.55, mat_grey_top, origin_at_bottom=True)
body.location = (0, -0.10, BZ)
parts["body"] = body

# Chest block (medium grey, slightly taller at front)
chest = create_box("Chest", 0.60, 0.55, 0.58, mat_grey_mid, origin_at_bottom=True)
chest.location = (0, -0.75, BZ)
parts["chest"] = chest

# Belly strip (light grey, thin, runs under body)
belly = create_box("Belly", 0.54, 1.55, 0.12, mat_grey_light, origin_at_bottom=True)
belly.location = (0, -0.75, BZ)
parts["belly"] = belly

# ─── HEAD ───────────────────────────────────────────────────
# Main head block (medium grey)
head = create_box("Head", 0.52, 0.52, 0.52, mat_grey_mid, origin_at_bottom=True)
head.location = (0, -1.04, BZ + 0.30)
parts["head"] = head

# Upper head / skull patch (dark grey, sits on top)
head_top = create_box("HeadTop", 0.52, 0.42, 0.14, mat_grey_top, origin_at_bottom=True)
head_top.location = (0, -1.04, BZ + 0.68)
parts["head_top"] = head_top

# Snout / muzzle (brown/tan)
snout = create_box("Snout", 0.32, 0.28, 0.26, mat_nose, origin_at_bottom=True)
snout.location = (0, -1.42, BZ + 0.18)
parts["snout"] = snout

# Nose tip (black)
nose = create_box("Nose", 0.14, 0.06, 0.10, mat_black, origin_at_bottom=True)
nose.location = (0, -1.66, BZ + 0.28)
parts["nose"] = nose

# Eyes
eye_l = create_box("Eye_L", 0.08, 0.04, 0.08, mat_black, origin_at_bottom=True)
eye_l.location = (0.20, -1.16, BZ + 0.60)
parts["eye_l"] = eye_l

eye_r = create_box("Eye_R", 0.08, 0.04, 0.08, mat_black, origin_at_bottom=True)
eye_r.location = (-0.20, -1.16, BZ + 0.60)
parts["eye_r"] = eye_r

# ─── EARS ───────────────────────────────────────────────────
# Two small blocky ears (light grey, sitting on head top)
ear_l = create_box("Ear_L", 0.16, 0.14, 0.22, mat_grey_light, origin_at_bottom=True)
ear_l.location = (0.17, -1.06, BZ + 0.82)
parts["ear_l"] = ear_l

ear_r = create_box("Ear_R", 0.16, 0.14, 0.22, mat_grey_light, origin_at_bottom=True)
ear_r.location = (-0.17, -1.06, BZ + 0.82)
parts["ear_r"] = ear_r

# ─── NECK FUR ───────────────────────────────────────────────
# Light patch on throat/neck
neck_fluff = create_box("NeckFluff", 0.50, 0.20, 0.34, mat_grey_light, origin_at_bottom=True)
neck_fluff.location = (0, -0.72, BZ + 0.30)
parts["neck_fluff"] = neck_fluff

# ─── FRONT LEGS ─────────────────────────────────────────────
# Upper leg = dark grey, lower = light grey (white)
for side, sx in [("FL", 0.22), ("FR", -0.22)]:
    up = create_box(f"Leg_{side}_Upper", 0.18, 0.18, 0.28, mat_grey_dark, origin_at_bottom=True)
    up.location = (sx, -0.72, 0.22)
    parts[f"leg_{side.lower()}_upper"] = up

    lo = create_box(f"Leg_{side}_Lower", 0.16, 0.16, 0.24, mat_grey_light, origin_at_bottom=True)
    lo.location = (sx, -0.72, 0)
    parts[f"leg_{side.lower()}_lower"] = lo

# ─── BACK LEGS ──────────────────────────────────────────────
# Upper (thigh) = dark grey, lower = light grey
for side, sx in [("BL", 0.22), ("BR", -0.22)]:
    up = create_box(f"Thigh_{side}", 0.20, 0.20, 0.30, mat_grey_dark, origin_at_bottom=True)
    up.location = (sx, 0.52, 0.22)
    parts[f"thigh_{side.lower()}"] = up

    lo = create_box(f"Shin_{side}", 0.18, 0.18, 0.24, mat_grey_light, origin_at_bottom=True)
    lo.location = (sx, 0.52, 0)
    parts[f"shin_{side.lower()}"] = lo

# ─── TAIL ───────────────────────────────────────────────────
# 3 segments curving up and forward (like reference)
tail_base = create_box("Tail_Base", 0.18, 0.18, 0.32, mat_grey_top, origin_at_bottom=True)
tail_base.location = (0, 0.72, BZ + 0.10)
tail_base.rotation_euler = (-0.70, 0, 0)
parts["tail_base"] = tail_base

tail_mid = create_box("Tail_Mid", 0.16, 0.16, 0.28, mat_grey_mid, origin_at_bottom=True)
tail_mid.location = (0, 0.96, BZ + 0.48)
tail_mid.rotation_euler = (-0.30, 0, 0)
parts["tail_mid"] = tail_mid

tail_tip = create_box("Tail_Tip", 0.14, 0.14, 0.22, mat_grey_light, origin_at_bottom=True)
tail_tip.location = (0, 1.06, BZ + 0.76)
tail_tip.rotation_euler = (0.15, 0, 0)
parts["tail_tip"] = tail_tip

# ============================================================
# CREATE ARMATURE
# ============================================================
bpy.ops.object.armature_add(enter_editmode=True, location=(0, 0, 0))
armature = bpy.context.active_object
armature.name = "WolfArmature"
arm = armature.data

for bone in list(arm.edit_bones):
    arm.edit_bones.remove(bone)

def add_bone(name, head, tail, parent=None):
    bone = arm.edit_bones.new(name)
    bone.head = head
    bone.tail = tail
    if parent:
        bone.parent = parent
        bone.use_connect = False
    return bone

# ROOT
root = add_bone("Root", (0, 0, BZ + 0.25), (0, 0, BZ + 0.45))

# SPINE
spine1 = add_bone("Spine1", (0, 0.20, BZ + 0.35), (0, 0.40, BZ + 0.42), parent=root)
spine2 = add_bone("Spine2", (0, -0.20, BZ + 0.40), (0, -0.40, BZ + 0.48), parent=spine1)

# NECK + HEAD
neck = add_bone("Neck", (0, -0.60, BZ + 0.48), (0, -0.80, BZ + 0.68), parent=spine2)
head_bone = add_bone("Head", (0, -0.90, BZ + 0.52), (0, -1.10, BZ + 0.75), parent=neck)
snout_bone = add_bone("Snout", (0, -1.20, BZ + 0.30), (0, -1.55, BZ + 0.30), parent=head_bone)

# EARS
ear_l_bone = add_bone("Ear_L", (0.17, -1.06, BZ + 0.82), (0.17, -1.06, BZ + 1.08), parent=head_bone)
ear_r_bone = add_bone("Ear_R", (-0.17, -1.06, BZ + 0.82), (-0.17, -1.06, BZ + 1.08), parent=head_bone)

# FRONT LEGS (Shoulder → Elbow)
shoulder_fl = add_bone("Shoulder_FL", (0.22, -0.72, BZ), (0.22, -0.72, 0.22), parent=root)
elbow_fl    = add_bone("Elbow_FL",    (0.22, -0.72, 0.22), (0.22, -0.72, 0.0),  parent=shoulder_fl)

shoulder_fr = add_bone("Shoulder_FR", (-0.22, -0.72, BZ), (-0.22, -0.72, 0.22), parent=root)
elbow_fr    = add_bone("Elbow_FR",    (-0.22, -0.72, 0.22), (-0.22, -0.72, 0.0),  parent=shoulder_fr)

# BACK LEGS (Hip → Knee)
hip_bl  = add_bone("Hip_BL",  (0.22, 0.52, BZ), (0.22, 0.52, 0.22),  parent=root)
knee_bl = add_bone("Knee_BL", (0.22, 0.52, 0.22), (0.22, 0.52, 0.0), parent=hip_bl)

hip_br  = add_bone("Hip_BR",  (-0.22, 0.52, BZ), (-0.22, 0.52, 0.22),  parent=root)
knee_br = add_bone("Knee_BR", (-0.22, 0.52, 0.22), (-0.22, 0.52, 0.0), parent=hip_br)

# TAIL
tail1 = add_bone("Tail1", (0, 0.72, BZ + 0.10), (0, 0.90, BZ + 0.38), parent=spine1)
tail2 = add_bone("Tail2", (0, 0.90, BZ + 0.38), (0, 1.00, BZ + 0.62), parent=tail1)
tail3 = add_bone("Tail3", (0, 1.00, BZ + 0.62), (0, 1.06, BZ + 0.84), parent=tail2)

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

# Vertex group mapping
bone_name_map = {
    "body":            "Spine1",
    "head_top":        "Head",
    "chest":           "Spine2",
    "belly":           "Spine1",
    "neck_fluff":      "Neck",
    "head":            "Head",
    "snout":           "Snout",
    "nose":            "Snout",
    "eye_l":           "Head",
    "eye_r":           "Head",
    "ear_l":           "Ear_L",
    "ear_r":           "Ear_R",
    "leg_fl_upper":    "Shoulder_FL",
    "leg_fl_lower":    "Elbow_FL",
    "leg_fr_upper":    "Shoulder_FR",
    "leg_fr_lower":    "Elbow_FR",
    "thigh_bl":        "Hip_BL",
    "shin_bl":         "Knee_BL",
    "thigh_br":        "Hip_BR",
    "shin_br":         "Knee_BR",
    "tail_base":       "Tail1",
    "tail_mid":        "Tail2",
    "tail_tip":        "Tail3",
}

for part_name, bone_name in bone_name_map.items():
    obj = parts[part_name]
    if bone_name not in obj.vertex_groups:
        vg = obj.vertex_groups.new(name=bone_name)
    else:
        vg = obj.vertex_groups[bone_name]
    vg.add(range(len(obj.data.vertices)), 1.0, 'REPLACE')

# ============================================================
# ANIMATION HELPER
# ============================================================
armature.animation_data_create()

def key_bone(pb, bone_name, frame, loc=None, rot=None, scale=None):
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

pb = armature.pose.bones

# ============================================================
# WALK CYCLE — 16 frames, seamless loop
# ============================================================
action_walk = bpy.data.actions.new(name="Wolf_Walk-loop")
armature.animation_data.action = action_walk

key_bone(pb, "Root", 1,  loc=(0,0,0),    rot=(0,0,0))
key_bone(pb, "Root", 5,  loc=(0,0,0.03), rot=(0.03,0,0))
key_bone(pb, "Root", 9,  loc=(0,0,0),    rot=(0,0,0))
key_bone(pb, "Root", 13, loc=(0,0,0.03), rot=(0.03,0,0))
key_bone(pb, "Root", 16, loc=(0,0,0.01), rot=(0.01,0,0))

key_bone(pb, "Spine1", 1,  rot=(0,0,0))
key_bone(pb, "Spine1", 5,  rot=(0.04,0,0))
key_bone(pb, "Spine1", 9,  rot=(0,0,0))
key_bone(pb, "Spine1", 13, rot=(0.04,0,0))
key_bone(pb, "Spine1", 16, rot=(0.01,0,0))

key_bone(pb, "Spine2", 1,  rot=(0,0,0))
key_bone(pb, "Spine2", 5,  rot=(-0.02,0,0))
key_bone(pb, "Spine2", 9,  rot=(0,0,0))
key_bone(pb, "Spine2", 13, rot=(-0.02,0,0))
key_bone(pb, "Spine2", 16, rot=(-0.01,0,0))

key_bone(pb, "Head", 1,  rot=(0,0,0))
key_bone(pb, "Head", 5,  rot=(-0.03,0,0))
key_bone(pb, "Head", 9,  rot=(0,0,0))
key_bone(pb, "Head", 13, rot=(-0.03,0,0))
key_bone(pb, "Head", 16, rot=(-0.01,0,0))

key_bone(pb, "Neck", 1,  rot=(0,0,0))
key_bone(pb, "Neck", 5,  rot=(-0.02,0,0))
key_bone(pb, "Neck", 9,  rot=(0,0,0))
key_bone(pb, "Neck", 13, rot=(-0.02,0,0))
key_bone(pb, "Neck", 16, rot=(-0.01,0,0))

key_bone(pb, "Ear_L", 1,  rot=(0,0,-0.15))
key_bone(pb, "Ear_L", 5,  rot=(0.05,0,-0.12))
key_bone(pb, "Ear_L", 9,  rot=(0,0,-0.15))
key_bone(pb, "Ear_L", 13, rot=(0.05,0,-0.12))
key_bone(pb, "Ear_L", 16, rot=(0.02,0,-0.14))

key_bone(pb, "Ear_R", 1,  rot=(0,0,0.15))
key_bone(pb, "Ear_R", 5,  rot=(0.05,0,0.12))
key_bone(pb, "Ear_R", 9,  rot=(0,0,0.15))
key_bone(pb, "Ear_R", 13, rot=(0.05,0,0.12))
key_bone(pb, "Ear_R", 16, rot=(0.02,0,0.14))

# Front Left (reaches forward on odd, back on even)
key_bone(pb, "Shoulder_FL", 1,  rot=(0,0,0),     loc=(0,0,0))
key_bone(pb, "Shoulder_FL", 5,  rot=(-0.25,0,0), loc=(0,0,0.02))
key_bone(pb, "Shoulder_FL", 9,  rot=(0.15,0,0),  loc=(0,0,0))
key_bone(pb, "Shoulder_FL", 13, rot=(0.10,0,0),  loc=(0,0,0))
key_bone(pb, "Shoulder_FL", 16, rot=(0.03,0,0),  loc=(0,0,0))
key_bone(pb, "Elbow_FL", 1,  rot=(0,0,0))
key_bone(pb, "Elbow_FL", 5,  rot=(0.20,0,0))
key_bone(pb, "Elbow_FL", 9,  rot=(0.05,0,0))
key_bone(pb, "Elbow_FL", 13, rot=(0.02,0,0))
key_bone(pb, "Elbow_FL", 16, rot=(0.01,0,0))

# Front Right (offset half cycle)
key_bone(pb, "Shoulder_FR", 1,  rot=(0.15,0,0),  loc=(0,0,0))
key_bone(pb, "Shoulder_FR", 5,  rot=(0.10,0,0),  loc=(0,0,0))
key_bone(pb, "Shoulder_FR", 9,  rot=(-0.25,0,0), loc=(0,0,0.02))
key_bone(pb, "Shoulder_FR", 13, rot=(0.15,0,0),  loc=(0,0,0))
key_bone(pb, "Shoulder_FR", 16, rot=(0.10,0,0),  loc=(0,0,0))
key_bone(pb, "Elbow_FR", 1,  rot=(0.05,0,0))
key_bone(pb, "Elbow_FR", 5,  rot=(0.02,0,0))
key_bone(pb, "Elbow_FR", 9,  rot=(0.20,0,0))
key_bone(pb, "Elbow_FR", 13, rot=(0.05,0,0))
key_bone(pb, "Elbow_FR", 16, rot=(0.03,0,0))

# Back Left (same phase as FR)
key_bone(pb, "Hip_BL", 1,  rot=(0.10,0,0), loc=(0,0,0))
key_bone(pb, "Hip_BL", 5,  rot=(0.05,0,0), loc=(0,0,0))
key_bone(pb, "Hip_BL", 9,  rot=(-0.30,0,0),loc=(0,0,0.02))
key_bone(pb, "Hip_BL", 13, rot=(0.15,0,0), loc=(0,0,0))
key_bone(pb, "Hip_BL", 16, rot=(0.08,0,0), loc=(0,0,0))
key_bone(pb, "Knee_BL", 1,  rot=(0.05,0,0))
key_bone(pb, "Knee_BL", 5,  rot=(0.02,0,0))
key_bone(pb, "Knee_BL", 9,  rot=(0.35,0,0))
key_bone(pb, "Knee_BL", 13, rot=(0.10,0,0))
key_bone(pb, "Knee_BL", 16, rot=(0.04,0,0))

# Back Right (same phase as FL)
key_bone(pb, "Hip_BR", 1,  rot=(-0.30,0,0),loc=(0,0,0.02))
key_bone(pb, "Hip_BR", 5,  rot=(0.15,0,0), loc=(0,0,0))
key_bone(pb, "Hip_BR", 9,  rot=(0.10,0,0), loc=(0,0,0))
key_bone(pb, "Hip_BR", 13, rot=(0.05,0,0), loc=(0,0,0))
key_bone(pb, "Hip_BR", 16, rot=(-0.15,0,0),loc=(0,0,0.01))
key_bone(pb, "Knee_BR", 1,  rot=(0.35,0,0))
key_bone(pb, "Knee_BR", 5,  rot=(0.10,0,0))
key_bone(pb, "Knee_BR", 9,  rot=(0.05,0,0))
key_bone(pb, "Knee_BR", 13, rot=(0.02,0,0))
key_bone(pb, "Knee_BR", 16, rot=(0.20,0,0))

# Tail wag
key_bone(pb, "Tail1", 1,  rot=(0.35,0,0))
key_bone(pb, "Tail1", 5,  rot=(0.35,0.10,0))
key_bone(pb, "Tail1", 9,  rot=(0.35,0,0))
key_bone(pb, "Tail1", 13, rot=(0.35,-0.10,0))
key_bone(pb, "Tail1", 16, rot=(0.35,-0.05,0))
key_bone(pb, "Tail2", 1,  rot=(0.10,0,0))
key_bone(pb, "Tail2", 5,  rot=(0.10,0.15,0))
key_bone(pb, "Tail2", 9,  rot=(0.10,0,0))
key_bone(pb, "Tail2", 13, rot=(0.10,-0.15,0))
key_bone(pb, "Tail2", 16, rot=(0.10,-0.08,0))
key_bone(pb, "Tail3", 1,  rot=(0.05,0,0))
key_bone(pb, "Tail3", 5,  rot=(0.05,0.20,0))
key_bone(pb, "Tail3", 9,  rot=(0.05,0,0))
key_bone(pb, "Tail3", 13, rot=(0.05,-0.20,0))
key_bone(pb, "Tail3", 16, rot=(0.05,-0.10,0))

# ============================================================
# IDLE ANIMATION — Look Around + Tail Wag (60 frames)
# ============================================================
action_idle = bpy.data.actions.new(name="Wolf_Idle-loop")
armature.animation_data.action = action_idle

key_bone(pb, "Root", 1,  loc=(0,0,0), scale=(1,1,1))
key_bone(pb, "Root", 20, loc=(0,0,0.015), scale=(1.015,0.985,1.015))
key_bone(pb, "Root", 40, loc=(0,0,0.01),  scale=(1.01,0.99,1.01))
key_bone(pb, "Root", 60, loc=(0,0,0.005), scale=(1.005,0.995,1.005))

key_bone(pb, "Head", 1,  rot=(0,0,0))
key_bone(pb, "Head", 15, rot=(0,0.08,-0.30))
key_bone(pb, "Head", 25, rot=(0,0.06,-0.35))
key_bone(pb, "Head", 35, rot=(0,-0.05,0.30))
key_bone(pb, "Head", 45, rot=(0,-0.03,0.35))
key_bone(pb, "Head", 55, rot=(0,0,0.05))
key_bone(pb, "Head", 60, rot=(0,0,0.02))

key_bone(pb, "Neck", 1,  rot=(0,0,0))
key_bone(pb, "Neck", 15, rot=(0,0,-0.15))
key_bone(pb, "Neck", 35, rot=(0,0,0.15))
key_bone(pb, "Neck", 55, rot=(0,0,0.02))
key_bone(pb, "Neck", 60, rot=(0,0,0.01))

key_bone(pb, "Ear_L", 1,  rot=(0,0,-0.15))
key_bone(pb, "Ear_L", 15, rot=(0.10,0,-0.25))
key_bone(pb, "Ear_L", 35, rot=(0.15,0,-0.05))
key_bone(pb, "Ear_L", 60, rot=(0.02,0,-0.12))

key_bone(pb, "Ear_R", 1,  rot=(0,0,0.15))
key_bone(pb, "Ear_R", 15, rot=(0.15,0,0.05))
key_bone(pb, "Ear_R", 35, rot=(0.10,0,0.25))
key_bone(pb, "Ear_R", 60, rot=(0.02,0,0.12))

key_bone(pb, "Tail1", 1,  rot=(0.35,0,0))
key_bone(pb, "Tail1", 8,  rot=(0.35,0.20,0))
key_bone(pb, "Tail1", 15, rot=(0.35,0,0))
key_bone(pb, "Tail1", 23, rot=(0.35,-0.20,0))
key_bone(pb, "Tail1", 30, rot=(0.35,0,0))
key_bone(pb, "Tail1", 38, rot=(0.35,0.20,0))
key_bone(pb, "Tail1", 45, rot=(0.35,0,0))
key_bone(pb, "Tail1", 53, rot=(0.35,-0.20,0))
key_bone(pb, "Tail1", 60, rot=(0.35,-0.10,0))
key_bone(pb, "Tail2", 1,  rot=(0.10,0,0))
key_bone(pb, "Tail2", 8,  rot=(0.10,0.30,0))
key_bone(pb, "Tail2", 15, rot=(0.10,0,0))
key_bone(pb, "Tail2", 23, rot=(0.10,-0.30,0))
key_bone(pb, "Tail2", 30, rot=(0.10,0,0))
key_bone(pb, "Tail2", 38, rot=(0.10,0.30,0))
key_bone(pb, "Tail2", 45, rot=(0.10,0,0))
key_bone(pb, "Tail2", 53, rot=(0.10,-0.30,0))
key_bone(pb, "Tail2", 60, rot=(0.10,-0.15,0))
key_bone(pb, "Tail3", 1,  rot=(0.05,0,0))
key_bone(pb, "Tail3", 8,  rot=(0.05,0.40,0))
key_bone(pb, "Tail3", 15, rot=(0.05,0,0))
key_bone(pb, "Tail3", 23, rot=(0.05,-0.40,0))
key_bone(pb, "Tail3", 30, rot=(0.05,0,0))
key_bone(pb, "Tail3", 38, rot=(0.05,0.40,0))
key_bone(pb, "Tail3", 45, rot=(0.05,0,0))
key_bone(pb, "Tail3", 53, rot=(0.05,-0.40,0))
key_bone(pb, "Tail3", 60, rot=(0.05,-0.20,0))

key_bone(pb, "Shoulder_FL", 1,  rot=(0,0,0))
key_bone(pb, "Shoulder_FL", 20, rot=(0.03,0,0))
key_bone(pb, "Shoulder_FL", 60, rot=(0.01,0,0))
key_bone(pb, "Shoulder_FR", 1,  rot=(0,0,0))
key_bone(pb, "Shoulder_FR", 30, rot=(0.03,0,0))
key_bone(pb, "Shoulder_FR", 60, rot=(0.01,0,0))
key_bone(pb, "Hip_BL", 1,  rot=(0,0,0))
key_bone(pb, "Hip_BL", 35, rot=(0.02,0,0))
key_bone(pb, "Hip_BL", 60, rot=(0.01,0,0))
key_bone(pb, "Hip_BR", 1,  rot=(0,0,0))
key_bone(pb, "Hip_BR", 40, rot=(0.02,0,0))
key_bone(pb, "Hip_BR", 60, rot=(0.01,0,0))

# ============================================================
# SCENE SETUP & EXPORT
# ============================================================
scene = bpy.context.scene
scene.frame_start = 1
scene.frame_end = 16
scene.render.fps = 30

bpy.ops.object.select_all(action='DESELECT')
armature.select_set(True)
for obj in parts.values():
    obj.select_set(True)

export_path = r"c:\Repo\test-game\assets\animals\blocky_wolf.glb"
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
print(f"🎬 Animations: 'Wolf_Walk-loop' (16f), 'Wolf_Idle-loop' (60f)")
print("=" * 60)
