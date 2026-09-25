extends Reference

var repo_path = "/repo/"
var _snapshot_cache = {}

func start_or_resume():
	return observe_result()

func observe_result():
	_snapshot_cache = parse_json(JavaScript.eval("JSON.stringify(window.OMG.snapshot())"))
	return snapshot()

func snapshot():
	return _snapshot_cache.duplicate(true)

func validate_command(command):
	return str(JavaScript.eval("window.OMG.validate(" + to_json(command) + ")"))

func action(kind, value = ""):
	var operation = preload("res://web/godot/command.gd").new()
	game.add_child(operation)
	operation.start(kind, value)
	yield(operation, "done")
	var result = {"exit_code": operation.exit_code, "output": operation.output}
	operation.queue_free()
	observe_result()
	return result

func choose(value):
	return action("choose", value)

func restart_mission():
	return action("restart")
