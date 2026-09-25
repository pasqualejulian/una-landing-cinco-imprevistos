extends "res://scenes/shell_command.gd"

var request_id = -1

func start(kind, value):
	request_id = int(JavaScript.eval("window.OMG.request(" + to_json(kind) + "," + to_json(value) + ")"))

func _process(_delta):
	if request_id < 0:
		return
	var response = JavaScript.eval("window.OMG.poll(" + str(request_id) + ")")
	if response == null or response == "":
		return
	var result = parse_json(response)
	request_id = -1
	output = result.get("output", "")
	if output != "" and not output.ends_with("\n"):
		output += "\n"
	exit_code = int(result.get("exit_code", 1))
	emit_signal("done")
