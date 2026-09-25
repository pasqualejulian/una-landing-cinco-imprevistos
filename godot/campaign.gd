extends "res://scenes/first_mission/mission.gd"

var chapter_label
var narrative
var preview_cta
var target_label
var next_button
var timeline_label
var drawn_cards = ""
var choice_signature = ""
var state = {}
var restart_dialog

func _ready():
	cards.card_store["merge"]["description"] = "Integra el trabajo de otra rama en la actual. Puede crear un commit con dos padres."
	cards.card_store["checkout"]["description"] = "Mové HEAD a otra rama y recuperá sus archivos. Tus commits siguen guardados."
	drawn_cards = ""
	OS.set_window_title("Una landing, cinco imprevistos · Oh My Git!")
	$Menu/ReloadButton2.text = "Nueva historia"
	timeline_label = _label(self, "", 60)
	timeline_label.rect_position = Vector2(24, 80)
	timeline_label.rect_size.x = 1180
	timeline_label.add_color_override("font_color", Color("adc6f7"))
	update_repos()
	feedback.text = "Retomaste tu historia. Tu timeline se conserva." if state["commits"] != "1" else "Arrancá por elegir un hero. Después llegan los imprevistos."

func _build_panel():
	var panel = VBoxContainer.new()
	panel.name = "MissionPanel"
	panel.add_constant_override("separation", 10)
	panel.size_flags_vertical = SIZE_EXPAND_FILL
	$Rows/Columns/RightSide.add_child(panel)
	chapter_label = _label(panel, "", 30)
	chapter_label.add_color_override("font_color", Color("adc6f7"))
	narrative = _label(panel, "", 96)
	narrative.add_color_override("font_color", Color("d4d9e3"))
	instruction = _label(panel, "", 78)
	choices = VBoxContainer.new()
	choices.add_constant_override("separation", 8)
	panel.add_child(choices)
	var preview = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color("f7f3ff")
	for edge in ["left", "right", "top", "bottom"]:
		style.set("content_margin_" + edge, 14)
	preview.add_stylebox_override("panel", style)
	panel.add_child(preview)
	var content = VBoxContainer.new()
	preview.add_child(content)
	var eyebrow = _label(content, "TU LANDING · RAMA ACTUAL", 22)
	eyebrow.add_color_override("font_color", Color("746783"))
	preview_title = _label(content, "", 40)
	preview_title.add_color_override("font_color", Color("211a2d"))
	preview_title.add_font_override("font", preload("res://fonts/big.tres"))
	preview_cta = _label(content, "", 30)
	file_target = PanelContainer.new()
	file_target.mouse_filter = MOUSE_FILTER_IGNORE
	panel.add_child(file_target)
	file_state = _label(file_target, "", 58)
	commit_target = PanelContainer.new()
	commit_target.mouse_filter = MOUSE_FILTER_IGNORE
	panel.add_child(commit_target)
	target_label = _label(commit_target, "", 64)
	feedback = _label(panel, "", 60)
	feedback.add_color_override("font_color", Color("f4cd79"))
	next_button = Button.new()
	next_button.rect_min_size.y = 48
	next_button.connect("pressed", self, "advance")
	panel.add_child(next_button)
	var hand_label = _label(cards, "TUS CARTAS\n\nEl próximo paso\nse juega acá.", 140)
	hand_label.rect_position = Vector2(18, 24)
	hand_label.rect_size.x = 240
	message_dialog = ConfirmationDialog.new()
	message_dialog.window_title = "Guardar versión · mensaje del commit"
	message_dialog.rect_min_size = Vector2(680, 180)
	message_dialog.get_ok().text = "Guardar"
	message_dialog.get_cancel().text = "Cancelar"
	message_dialog.popup_exclusive = true
	add_child(message_dialog)
	message_input = LineEdit.new()
	message_input.margin_left = 22
	message_input.margin_top = 40
	message_input.margin_right = 658
	message_input.margin_bottom = 90
	message_dialog.add_child(message_input)
	message_dialog.connect("confirmed", self, "_confirm_message")
	message_dialog.connect("popup_hide", self, "_message_hidden")
	message_input.connect("text_entered", self, "_message_entered")
	restart_dialog = ConfirmationDialog.new()
	restart_dialog.window_title = "Empezar otra historia"
	restart_dialog.dialog_text = "Vas a volver a la landing inicial.\nLa partida actual de este navegador se reinicia."
	restart_dialog.get_ok().text = "Empezar de nuevo"
	restart_dialog.get_cancel().text = "Seguir jugando"
	restart_dialog.connect("confirmed", self, "_restart_confirmed")
	add_child(restart_dialog)
	_targets("")

func update_repos():
	if not repository:
		return
	state = engine.observe_result()
	repository.update_everything()
	completed = state["completed"]
	chapter_label.text = "CAPÍTULO %02d / 05 · %s" % [state["chapter_number"], state["chapter_title"]]
	narrative.text = state["sender"] + "\n" + state["story"]
	instruction.text = state["instruction"]
	preview_title.text = state["preview"]["title"]
	preview_cta.text = "●  " + state["preview"]["button"]
	preview_cta.add_color_override("font_color", Color(state["preview"]["color"]))
	var signature = to_json(state["choices"])
	if signature != choice_signature:
		choice_signature = signature
		for child in choices.get_children():
			choices.remove_child(child)
			child.queue_free()
		for option in state["choices"]:
			var button = Button.new()
			button.text = option["label"]
			button.rect_min_size.y = 44
			button.connect("pressed", self, "choose", [option["id"]])
			choices.add_child(button)
	choices.visible = state["phase"] == "choose"
	file_target.visible = state["phase"] in ["add", "commit"]
	commit_target.visible = not state["cards"].empty()
	file_state.text = state["file"] + (" · Preparado\nAhora guardá un commit." if state["prepared"] else " · Modificado\nSoltá acá la carta add.")
	target_label.text = state["target"] + "\n" + state["command"]
	next_button.visible = state["can_continue"]
	next_button.text = state["next_label"]
	next_button.disabled = terminal.busy
	var hand = to_json(state["cards"])
	if hand != drawn_cards:
		drawn_cards = hand
		cards.draw(state["cards"])
	if timeline_label:
		timeline_label.text = "TU TIMELINE · %s %s · HEAD en %s\nArrastrá los nodos. Pasá el mouse para leer cada versión." % [state["commits"], "commit" if state["commits"] == "1" else "commits", state["branch"]]

func _run_action(kind, value = ""):
	if terminal.busy or message_dialog.visible:
		return
	terminal.busy = true
	$Menu/ReloadButton2.disabled = true
	next_button.disabled = true
	feedback.text = "Actualizando tu historia…"
	var result = engine.action(kind, value)
	if result is GDScriptFunctionState:
		result = yield(result, "completed")
	terminal.busy = false
	$Menu/ReloadButton2.disabled = false
	update_repos()
	feedback.text = result["output"] if result["exit_code"] != 0 else state["feedback"]
	if result["exit_code"] != 0:
		terminal.get_node("ErrorSound").play()

func choose(value):
	_run_action("choose", value)

func advance():
	_run_action("advance")

func begin_card(card):
	if terminal.busy or message_dialog.visible or restart_dialog.visible:
		_rejected("Terminá la acción actual antes de jugar otra carta.")
		return false
	if completed or not card.id in state["cards"]:
		return false
	_targets(card.id)
	if card.id != "add":
		var style = commit_target.get_stylebox("panel").duplicate()
		style.border_color = Color("77e3bc")
		commit_target.add_stylebox_override("panel", style)
	feedback.text = "Soltá add sobre " + state["file"] + "." if card.id == "add" else state["target"]
	return true

func release_card(card, at):
	_targets("")
	card.move_back()
	if terminal.busy or message_dialog.visible:
		return
	var target = file_target if card.id == "add" else commit_target
	if not target.visible or not target.get_global_rect().has_point(at):
		_rejected("La carta volvió a tu mano. Soltala en el destino indicado a la derecha.")
		return
	pending_card = card
	if card.id == "commit":
		message_input.text = state["default_message"]
		message_dialog.popup_centered()
		message_input.grab_focus()
		message_input.select_all()
	elif card.id == "add":
		terminal.send_command("git add " + state["file"])
	else:
		terminal.send_command(state["command"])

func _finished(cmd):
	# Feedback happens before replacing the hand: old cards may be freed.
	if is_instance_valid(pending_card) and cmd.exit_code == 0:
		pending_card.mission_success()
	pending_card = null
	update_repos()
	$Menu/ReloadButton2.disabled = false
	$Menu/BackButton.disabled = false
	feedback.text = cmd.output if cmd.exit_code != 0 else state["feedback"]
	if cmd.exit_code != 0:
		terminal.get_node("ErrorSound").play()
	elif completed and not cmd.pretty_command.begins_with("git log") and not cmd.pretty_command.begins_with("git show") and not cmd.pretty_command.begins_with("git status"):
		$SuccessSound.play()

func reload_level():
	if not terminal.busy and not message_dialog.visible:
		restart_dialog.popup_centered(Vector2(660, 180))

func _restart_confirmed():
	terminal.clear()
	_run_action("restart")

func back():
	if not terminal.busy:
		JavaScript.eval("window.location.reload()")
