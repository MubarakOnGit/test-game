class_name CommandSystem
extends Node

var _history: Array = []
var _index: int = -1

func execute(command: Object) -> void:
	# Discard redo history if we make a new action
	if _index < _history.size() - 1:
		_history.resize(_index + 1)
	
	command.execute()
	_history.append(command)
	_index += 1

func undo() -> void:
	if _index >= 0:
		_history[_index].undo()
		_index -= 1

func redo() -> void:
	if _index < _history.size() - 1:
		_index += 1
		_history[_index].execute()

class DigCommand:
	var world_x: int
	var world_z: int
	var old_height: float
	var new_height: float
	var database: WorldDatabase

	func _init(db: WorldDatabase, x: int, z: int, diff: float):
		database = db
		world_x = x
		world_z = z
		old_height = database.get_height_at_world(world_x, world_z)
		new_height = old_height - diff

	func execute():
		database.modify_height(world_x, world_z, new_height)

	func undo():
		database.modify_height(world_x, world_z, old_height)

class BuildCommand:
	var world_x: int
	var world_z: int
	var old_height: float
	var new_height: float
	var database: WorldDatabase

	func _init(db: WorldDatabase, x: int, z: int, diff: float):
		database = db
		world_x = x
		world_z = z
		old_height = database.get_height_at_world(world_x, world_z)
		new_height = old_height + diff

	func execute():
		database.modify_height(world_x, world_z, new_height)

	func undo():
		database.modify_height(world_x, world_z, old_height)
