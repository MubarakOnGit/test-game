extends SceneTree

func _init():
	var scene = load("res://assets/animals/blocky_rabbit.glb")
	if not scene:
		print("Failed to load scene")
		quit()
		return
	
	var inst = scene.instantiate()
	print("Nodes in rabbit:")
	_print_tree(inst, "")
	
	var ap = _find_ap(inst)
	if ap:
		print("Animations:")
		for a in ap.get_animation_list():
			print("- ", a)
	else:
		print("No AnimationPlayer found!")
	
	quit()

func _print_tree(node, indent):
	print(indent + node.name + " (" + node.get_class() + ")")
	for c in node.get_children():
		_print_tree(c, indent + "  ")

func _find_ap(node):
	if node is AnimationPlayer: return node
	for c in node.get_children():
		var res = _find_ap(c)
		if res: return res
	return null
