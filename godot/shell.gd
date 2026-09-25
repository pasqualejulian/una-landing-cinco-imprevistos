extends Node

var exit_code = 0
var _cwd = "/repo/"

func cd(path):
	_cwd = path

func run(command, _crash_on_fail = true):
	# Only the inherited terminal's file completion uses this synchronous path.
	if command == "find . -type f":
		return "./index.html\n./styles.css\n"
	exit_code = 1
	push_error("Unexpected synchronous web shell query: " + command)
	return ""

func run_async(_command, pretty_command = null, _crash_on_fail = true):
	var result = preload("res://web/godot/command.gd").new()
	result.command = pretty_command
	result.pretty_command = pretty_command
	game.add_child(result)
	result.start("execute", pretty_command)
	return result
