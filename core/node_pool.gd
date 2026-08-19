extends Node

## Universal Object Pooling System
## Prevents frame stutters by avoiding instantiation and queue_free calls.

var _pools: Dictionary = {}

func get_pool_node(pool_name: String, packed_scene: PackedScene) -> Node:
	if not _pools.has(pool_name):
		_pools[pool_name] = []
		
	var pool: Array = _pools[pool_name]
	
	if pool.size() > 0:
		var node = pool.pop_back()
		if is_instance_valid(node):
			if node.has_method("_on_pool_acquire"):
				node._on_pool_acquire()
			return node
			
	# Create a new one if pool is empty
	if packed_scene:
		var node = packed_scene.instantiate()
		if node.has_method("_on_pool_acquire"):
			node._on_pool_acquire()
		return node
		
	return null

func release_node(pool_name: String, node: Node) -> void:
	if not is_instance_valid(node):
		return
		
	if node.get_parent():
		node.get_parent().remove_child(node)
		
	if node.has_method("_on_pool_release"):
		node._on_pool_release()
		
	if not _pools.has(pool_name):
		_pools[pool_name] = []
		
	_pools[pool_name].append(node)
