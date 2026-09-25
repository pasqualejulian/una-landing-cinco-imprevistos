extends Control

var engine = preload("res://scenes/first_mission/engine.gd").new()
var repository
var pending_card = null
var message_dialog
var message_input
var feedback
var instruction
var preview_title
var file_state
var file_target
var commit_target
var choices
var hand_drawn = false
var completed = false
var command_count = 0
var qa = false
onready var terminal = $Rows/Controls/Terminal
onready var cards = $Rows/Controls/Cards
onready var file_browser = $Rows/Columns/RightSide/FileBrowser

func _ready():
	OS.set_window_title("Primera misión · Oh My Git!")
	# Preserve the pilot's history and played-card progress.
	game._file = "user://first-mission-savegame.json"
	game.state = game._initial_state()
	game.state["received_hints"] = ["cards", "terminal", "file-browser", "remote", "nodes", "head", "ref", "commit", "drag-nodes"]
	if qa:
		game._file = "user://first-mission-qa-savegame.json"
	cards.action_adapter = self
	terminal.command_guard = engine
	terminal.feedback_managed = true
	terminal.connect("command_started", self, "_started")
	terminal.connect("command_finished", self, "_finished")
	terminal.connect("command_rejected", self, "_rejected")
	# One refresh, owned here after Git's result and validation.
	terminal.disconnect("command_done", self, "update_repos")
	$Menu/NextLevelButton.hide()
	$Menu/CLIBadge.hide()
	$Menu.get_node("Tip!").hide()
	$Menu/BackButton.text = "Salir"
	$Menu/ReloadButton2.text = "Reiniciar misión"
	$Rows/Columns/RightSide/LevelInfo.hide()
	file_browser.hide()
	_build_panel()
	engine.start_or_resume()
	repository = preload("res://scenes/repository.tscn").instance()
	repository.set_script(preload("res://scenes/first_mission/repository.gd"))
	repository.label = "yours"
	repository.path = engine.repo_path
	repository.size_flags_vertical = SIZE_EXPAND_FILL
	$Rows/Columns/Repositories.add_child(repository)
	terminal.repository = repository
	update_repos()
	var state = engine.snapshot()
	if state["completed"]:
		feedback.text = "Retomaste tu punto seguro. El commit sigue guardado en Git."
	elif state["prepared"]:
		feedback.text = "Retomaste el archivo preparado. Falta crear el commit con tu mensaje."
	elif state["chosen"]:
		feedback.text = "Retomaste tu título elegido. Prepará index.html con add."
	else:
		feedback.text = "Elegí un título. El juego aplica el cambio en index.html por vos."

func _build_panel():
	var panel = VBoxContainer.new()
	panel.name = "MissionPanel"
	panel.add_constant_override("separation", 14)
	panel.size_flags_vertical = SIZE_EXPAND_FILL
	$Rows/Columns/RightSide.add_child(panel)
	_label(panel, "MISIÓN 01  ·  TU PRIMER PUNTO SEGURO", 32)
	instruction = _label(panel, "", 80)
	choices = VBoxContainer.new()
	choices.add_constant_override("separation", 8)
	panel.add_child(choices)
	for choice in [["idea_vida", engine._title_value("idea_vida")], ["idea_proxima", engine._title_value("idea_proxima")]]:
		var button = Button.new()
		button.text = choice[1]
		button.rect_min_size.y = 48
		button.connect("pressed", self, "choose", [choice[0]])
		choices.add_child(button)
	var preview = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color("f7f3ff")
	for edge in ["left", "right", "top", "bottom"]:
		style.set("content_margin_" + edge, 18)
	preview.add_stylebox_override("panel", style)
	panel.add_child(preview)
	var content = VBoxContainer.new()
	preview.add_child(content)
	var eyebrow = _label(content, "VISTA PREVIA · LANDING", 24)
	eyebrow.add_color_override("font_color", Color("746783"))
	preview_title = _label(content, "", 54)
	preview_title.add_color_override("font_color", Color("211a2d"))
	preview_title.add_font_override("font", preload("res://fonts/big.tres"))
	var cta = _label(content, "●  Empezá ahora", 28)
	cta.add_color_override("font_color", Color("6750a4"))
	file_target = PanelContainer.new()
	file_target.name = "PrepareTarget"
	file_target.mouse_filter = MOUSE_FILTER_IGNORE
	panel.add_child(file_target)
	var file_row = HBoxContainer.new()
	file_row.mouse_filter = MOUSE_FILTER_IGNORE
	file_target.add_child(file_row)
	var icon = TextureRect.new()
	icon.texture = preload("res://images/file.svg")
	icon.rect_min_size = Vector2(54, 54)
	icon.expand = true
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = MOUSE_FILTER_IGNORE
	file_row.add_child(icon)
	file_state = _label(file_row, "index.html", 82)
	file_state.size_flags_horizontal = SIZE_EXPAND_FILL
	commit_target = PanelContainer.new()
	commit_target.name = "CommitTarget"
	commit_target.mouse_filter = MOUSE_FILTER_IGNORE
	panel.add_child(commit_target)
	_label(commit_target, "Guardar versión\nSoltá acá la carta commit", 76)
	feedback = _label(panel, "", 90)
	feedback.add_color_override("font_color", Color("f4cd79"))
	var hand_label = _label(cards, "TUS CARTAS\n\nArrastralas a las zonas de la misión →", 140)
	hand_label.rect_position = Vector2(18, 24)
	hand_label.rect_size.x = 270
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
	message_input.placeholder_text = "Qué cambió en esta versión"
	message_dialog.add_child(message_input)
	message_dialog.connect("confirmed", self, "_confirm_message")
	message_dialog.connect("popup_hide", self, "_message_hidden")
	message_input.connect("text_entered", self, "_message_entered")
	_targets("")

func _label(parent, text, height):
	var label = Label.new()
	label.text = text
	label.autowrap = true
	label.rect_min_size.y = height
	label.mouse_filter = MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func _targets(active):
	for pair in [[file_target, "add"], [commit_target, "commit"]]:
		var style = StyleBoxFlat.new()
		style.bg_color = Color("263b42") if active == pair[1] else Color("202636")
		style.border_color = Color("77e3bc") if active == pair[1] else Color("536078")
		for edge in ["left", "right", "top", "bottom"]:
			style.set("border_width_" + edge, 3 if active == pair[1] else 1)
			style.set("content_margin_" + edge, 12)
		pair[0].add_stylebox_override("panel", style)

func choose(value):
	if terminal.busy or message_dialog.visible:
		return
	engine.choose(value)
	update_repos()
	feedback.text = "Cambió index.html. Preparalo con add. El historial todavía tiene una sola versión."

func update_repos():
	if not repository:
		return
	var state = engine.observe_result()
	repository.update_everything()
	preview_title.text = state["preview"]["title"]
	choices.visible = not state["chosen"]
	completed = state["completed"]
	if completed:
		instruction.text = "MISIÓN CUMPLIDA\nEste es tu punto seguro. El nuevo nodo guarda el título que elegiste."
		file_state.text = "index.html · Guardado\nTu trabajo coincide con el último commit."
	elif state["prepared"]:
		instruction.text = "3 · Guardá tu versión\nArrastrá commit a Guardar versión.\nO tipeá: git commit -m \"Elegir hero\""
		file_state.text = "index.html · Preparado\nYa elegiste qué guardar. Todavía no creaste un commit."
	elif state["chosen"]:
		instruction.text = "2 · Prepará el cambio\nArrastrá add a index.html.\nO tipeá: git add index.html"
		file_state.text = "index.html · Modificado\nSoltá acá add para preparar el archivo."
	else:
		instruction.text = "1 · Elegí un título\nLa IA propone dos títulos para tu landing. ¿Cuál querés probar?"
		file_state.text = "index.html · Guardado\nPrimero elegí un título arriba."
	if state["chosen"] and not hand_drawn:
		hand_drawn = true
		cards.draw(["add", "commit"])
	for card in cards.hand_cards():
		card.visible = state["chosen"]

func begin_card(card):
	if terminal.busy or message_dialog.visible:
		_rejected("Git está trabajando o hay un mensaje abierto. Terminá esa acción primero.")
		return false
	if completed:
		_rejected("Ya guardaste esta versión. Podés explorar el nodo o reiniciar la misión.")
		return false
	_targets(card.id)
	feedback.text = "Soltá acá para preparar index.html →" if card.id == "add" else "Soltá commit en Guardar versión. Después escribí un mensaje."
	return true

func release_card(card, at):
	_targets("")
	card.move_back()
	if terminal.busy or message_dialog.visible:
		_rejected("Esperá a que termine la acción actual.")
		return
	var target = file_target if card.id == "add" else commit_target
	if not target.get_global_rect().has_point(at):
		_rejected("La carta volvió a tu mano. Soltá add sobre index.html." if card.id == "add" else "La carta volvió a tu mano. Soltá commit en Guardar versión.")
		return
	pending_card = card
	if card.id == "add":
		terminal.send_command("git add index.html")
	else:
		message_input.text = "Elegir hero"
		message_dialog.popup_centered()
		message_input.grab_focus()
		message_input.select_all()

func _confirm_message():
	var message = message_input.text.strip_edges()
	if message == "" or '"' in message or "\\" in message or "$" in message or "`" in message:
		_rejected("Escribí un mensaje breve sin comillas dobles, barras ni operadores de shell.")
		pending_card = null
		return
	terminal.send_command('git commit -m "' + message + '"')

func _message_entered(_text):
	_confirm_message()
	message_dialog.hide()

func _message_hidden():
	call_deferred("_after_message_hidden")

func _after_message_hidden():
	if not terminal.busy and pending_card != null:
		pending_card = null
		feedback.text = "No se creó un commit. Podés volver a jugar commit cuando quieras."

func _started(_command):
	command_count += 1
	$Menu/ReloadButton2.disabled = true
	$Menu/BackButton.disabled = true
	feedback.text = "Git está trabajando…"

func _finished(cmd):
	update_repos()
	var state = engine.snapshot()
	$Menu/ReloadButton2.disabled = false
	$Menu/BackButton.disabled = false
	if cmd.exit_code != 0:
		terminal.get_node("ErrorSound").play()
		feedback.text = "Git no pudo completar la acción. Revisá la salida de la terminal. " + ("Primero prepará index.html con add." if not state["prepared"] else "")
	elif state["completed"]:
		feedback.text = "Este es tu punto seguro. El commit contiene el hero elegido y el repositorio quedó limpio."
		if cmd.pretty_command.begins_with("git commit"):
			$SuccessSound.play()
	elif state["prepared"]:
		feedback.text = "Ya elegiste qué guardar. Todavía no creaste un commit. Ahora jugá commit."
	else:
		feedback.text = "Comando terminado. Mirá su salida en la terminal."
	if is_instance_valid(pending_card) and cmd.exit_code == 0 and (state["completed"] or state["prepared"]):
		pending_card.mission_success()
	pending_card = null

func _rejected(message):
	feedback.text = message

func reload_level():
	if terminal.busy or message_dialog.visible:
		return
	if engine.restart_mission():
		terminal.clear()
		update_repos()
		feedback.text = "Volviste a la landing inicial. Elegí un título para probar de nuevo."
	else:
		feedback.text = "Git no pudo reiniciar. Tu avance se conservó. Revisá si hay otra operación Git en curso."

func back():
	if not terminal.busy:
		get_tree().quit()

func toggle_cards():
	pass
func new_tip():
	pass
func load_next_level():
	pass

func _input(event):
	if message_dialog and message_dialog.visible and event.is_action_pressed("ui_cancel"):
		message_dialog.hide()
		get_tree().set_input_as_handled()
