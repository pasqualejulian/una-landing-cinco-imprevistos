# Appended to the copied mission script only for read-only browser QA.
var _web_diagnostic_time = 0.0
func _process(delta):
	_web_diagnostic_time += delta
	if _web_diagnostic_time < 0.15:
		return
	_web_diagnostic_time = 0
	var info = {"size": [1920, 1080], "busy": terminal.busy, "completed": completed,
		"feedback": feedback.text, "instruction": instruction.text,
		"file_state": file_state.text, "command_count": command_count,
		"file_target": _web_rect(file_target), "commit_target": _web_rect(commit_target),
		"input": _web_rect(terminal.input), "choices": [], "cards": {}, "nodes": {},
		"restart": _web_rect($Menu/ReloadButton2), "music": _web_rect($Menu/Button3),
		"music_db": game.get_node("Music").volume_db, "message_visible": message_dialog.visible,
		"message_input": _web_rect(message_input), "cancel": _web_rect(message_dialog.get_cancel()),
		"confirm": _web_rect(message_dialog.get_ok())}
	if get("next_button") != null:
		info["next"] = _web_rect(get("next_button"))
		info["chapter"] = get("state")["chapter"]
		info["phase"] = get("state")["phase"]
		info["restart_confirm"] = _web_rect(get("restart_dialog").get_ok())
	for choice in choices.get_children():
		info["choices"].append(_web_rect(choice))
	for card in cards.hand_cards():
		var center = card.to_global(Vector2(0, -140))
		info["cards"][card.id] = [center.x, center.y]
	for id in repository.objects:
		var node = repository.objects[id]
		info["nodes"][id] = {"instance": node.get_instance_id(), "x": node.global_position.x, "y": node.global_position.y}
	JavaScript.eval("window.OMG.ui=" + to_json(info))

func _web_rect(control):
	var rect = control.get_global_rect()
	return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
