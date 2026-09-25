extends Control

const EngineScript = preload("res://scenes/guided/engine.gd")
const ActionCardScene = preload("res://scenes/guided/action_card.tscn")
const DropTargetScene = preload("res://scenes/guided/drop_target.tscn")
const TimelineGraph = preload("res://scenes/guided/timeline_graph.gd")
const FONT_BODY = preload("res://fonts/default.tres")
const FONT_BIG = preload("res://fonts/big.tres")
const FONT_MONO = preload("res://fonts/monospace.tres")

const INK = Color("231f1a")
const PAPER = Color("f4efe3")
const PAPER_LIGHT = Color("fffaf0")
const GREEN = Color("44633f")
const ORANGE = Color("d96c3b")
const BLUE = Color("315f73")
const MUTED = Color("716b61")
const ERROR = Color("a4362e")

export(String) var test_repo_path = ""
export(String) var test_progress_path = ""

var _engine = null
var _snapshot = {}
var _selected_card = ""
var _viewed_commit = ""
var _card_specs = {}

var _title_label
var _stage_label
var _instruction_label
var _command_hint
var _feedback_label
var _choices_box
var _cards_box
var _target_box
var _files_box
var _timeline_graph
var _preview_title
var _preview_button
var _preview_context
var _return_work_button
var _terminal_input
var _terminal_log
var _continue_button
var _hint_button
var _restart_button
var _commit_popup
var _commit_message
var _commit_error
var _active_target
var _local_busy = false


func _ready():
	_build_interface()
	if _engine == null:
		_engine = _make_engine()
	_connect_engine()
	_engine.start_or_resume()
	_refresh()


func _make_engine():
	# The default engine owns its isolated repository. Tests may replace the
	# engine before this scene enters the tree through set_engine().
	var instance = EngineScript.new()
	if test_repo_path != "":
		instance.repo_path = test_repo_path
	if test_progress_path != "":
		instance.progress_path = test_progress_path
	return instance


func set_engine(instance):
	_engine = instance


func get_engine():
	return _engine


func _connect_engine():
	if not _engine.is_connected("changed", self, "_on_engine_changed"):
		_engine.connect("changed", self, "_on_engine_changed")
	if not _engine.is_connected("feedback", self, "_on_engine_feedback"):
		_engine.connect("feedback", self, "_on_engine_feedback")


func _build_interface():
	var background = ColorRect.new()
	background.color = PAPER
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	add_child(background)

	var page = VBoxContainer.new()
	page.name = "Page"
	page.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	page.set("custom_constants/separation", 14)
	add_child(page)

	var header = HBoxContainer.new()
	header.rect_min_size.y = 72
	header.set("custom_constants/separation", 18)
	page.add_child(_margin(header, 24, 24, 12, 0))

	var back = _button("← Niveles", false)
	back.rect_min_size.x = 150
	back.connect("pressed", self, "_back")
	header.add_child(back)

	var brand = Label.new()
	brand.text = "GIT · HISTORIA GUIADA"
	brand.set("custom_fonts/font", FONT_MONO)
	brand.set("custom_colors/font_color", ORANGE)
	header.add_child(brand)

	_title_label = Label.new()
	_title_label.text = "Una landing, una decisión a la vez"
	_title_label.set("custom_fonts/font", FONT_BIG)
	_title_label.set("custom_colors/font_color", INK)
	_title_label.size_flags_horizontal = SIZE_EXPAND_FILL
	header.add_child(_title_label)

	_stage_label = Label.new()
	_stage_label.set("custom_fonts/font", FONT_BODY)
	_stage_label.set("custom_colors/font_color", GREEN)
	header.add_child(_stage_label)

	var body = HSplitContainer.new()
	body.name = "Body"
	body.size_flags_vertical = SIZE_EXPAND_FILL
	body.set("custom_constants/separation", 18)
	page.add_child(_margin(body, 24, 24, 0, 20))

	var workspace = VBoxContainer.new()
	workspace.name = "Workspace"
	workspace.rect_min_size.x = 1130
	workspace.size_flags_horizontal = SIZE_EXPAND_FILL
	workspace.set("custom_constants/separation", 14)
	body.add_child(workspace)

	_build_timeline(workspace)
	_build_workbench(workspace)
	_build_actions(workspace)
	_build_terminal(workspace)

	var mission = _panel(Color("e6dfcf"), INK, 2, 2)
	mission.name = "Mission"
	mission.rect_min_size.x = 500
	body.add_child(mission)
	var mission_margin = _margin(VBoxContainer.new(), 24, 24, 22, 22)
	mission.add_child(mission_margin)
	var mission_rows = mission_margin.get_child(0)
	mission_rows.set("custom_constants/separation", 16)

	var eyebrow = _label("TU ÚNICA TAREA AHORA", FONT_MONO, ORANGE)
	mission_rows.add_child(eyebrow)
	_instruction_label = _label("", FONT_BIG, INK)
	_instruction_label.autowrap = true
	mission_rows.add_child(_instruction_label)
	_command_hint = _label("", FONT_MONO, BLUE)
	_command_hint.autowrap = true
	mission_rows.add_child(_command_hint)
	var feedback_scroll = ScrollContainer.new()
	feedback_scroll.rect_min_size.y = 92
	feedback_scroll.size_flags_horizontal = SIZE_EXPAND_FILL
	mission_rows.add_child(feedback_scroll)
	_feedback_label = _label("", FONT_BODY, GREEN)
	_feedback_label.autowrap = true
	_feedback_label.size_flags_horizontal = SIZE_EXPAND_FILL
	feedback_scroll.add_child(_feedback_label)

	_choices_box = VBoxContainer.new()
	_choices_box.name = "Choices"
	_choices_box.set("custom_constants/separation", 8)
	mission_rows.add_child(_choices_box)

	var spacer = Control.new()
	spacer.size_flags_vertical = SIZE_EXPAND_FILL
	mission_rows.add_child(spacer)

	_continue_button = _button("Continuar", true)
	_continue_button.connect("pressed", self, "_continue")
	mission_rows.add_child(_continue_button)
	_hint_button = _button("Necesito una pista", false)
	_hint_button.connect("pressed", self, "_hint")
	mission_rows.add_child(_hint_button)
	_restart_button = _button("Reiniciar esta etapa", false)
	_restart_button.connect("pressed", self, "_restart")
	mission_rows.add_child(_restart_button)

	_build_commit_popup()


func _build_timeline(parent):
	var panel = _panel(PAPER_LIGHT, Color("b7ad9b"), 1, 2)
	panel.rect_min_size.y = 226
	parent.add_child(panel)
	var rows = VBoxContainer.new()
	rows.set("custom_constants/separation", 8)
	panel.add_child(_margin(rows, 18, 18, 12, 12))
	var heading = HBoxContainer.new()
	rows.add_child(heading)
	heading.add_child(_label("HISTORIA DEL PROYECTO", FONT_MONO, MUTED))
	_preview_context = _label("", FONT_BODY, GREEN)
	_preview_context.align = HALIGN_RIGHT
	_preview_context.size_flags_horizontal = SIZE_EXPAND_FILL
	heading.add_child(_preview_context)
	var scroll = ScrollContainer.new()
	scroll.name = "TimelineScroll"
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	rows.add_child(scroll)
	_timeline_graph = TimelineGraph.new()
	_timeline_graph.name = "Timeline"
	_timeline_graph.connect("commit_selected", self, "_inspect_commit")
	scroll.add_child(_timeline_graph)


func _build_workbench(parent):
	var split = HSplitContainer.new()
	split.rect_min_size.y = 300
	split.size_flags_vertical = SIZE_EXPAND_FILL
	split.set("custom_constants/separation", 14)
	parent.add_child(split)

	var files_panel = _panel(Color("ebe5d8"), Color("b7ad9b"), 1, 2)
	files_panel.rect_min_size.x = 345
	split.add_child(files_panel)
	var file_rows = VBoxContainer.new()
	file_rows.set("custom_constants/separation", 10)
	files_panel.add_child(_margin(file_rows, 18, 18, 16, 16))
	file_rows.add_child(_label("ARCHIVOS · SOLO LECTURA", FONT_MONO, MUTED))
	_files_box = VBoxContainer.new()
	_files_box.name = "Files"
	_files_box.set("custom_constants/separation", 7)
	file_rows.add_child(_files_box)

	var preview = _panel(Color("fdf7ea"), INK, 2, 2)
	preview.size_flags_horizontal = SIZE_EXPAND_FILL
	split.add_child(preview)
	var preview_rows = VBoxContainer.new()
	preview_rows.alignment = BoxContainer.ALIGN_CENTER
	preview_rows.set("custom_constants/separation", 18)
	preview.add_child(_margin(preview_rows, 40, 40, 22, 22))
	var preview_bar = HBoxContainer.new()
	preview_rows.add_child(preview_bar)
	preview_bar.add_child(_label("TU LANDING", FONT_MONO, MUTED))
	_return_work_button = _button("Ver trabajo actual", false)
	_return_work_button.size_flags_horizontal = SIZE_SHRINK_END
	_return_work_button.connect("pressed", self, "_return_to_work")
	preview_bar.add_child(_return_work_button)
	_preview_title = _label("", FONT_BIG, INK)
	_preview_title.align = HALIGN_CENTER
	_preview_title.autowrap = true
	_preview_rows_add(preview_rows, _preview_title)
	_preview_button = _button("", true)
	_preview_button.rect_min_size = Vector2(300, 62)
	_preview_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview_button.size_flags_horizontal = SIZE_SHRINK_CENTER
	preview_rows.add_child(_preview_button)


func _preview_rows_add(rows, child):
	child.size_flags_vertical = SIZE_EXPAND_FILL
	child.valign = VALIGN_CENTER
	rows.add_child(child)


func _build_actions(parent):
	var row = HBoxContainer.new()
	row.name = "CardActions"
	row.rect_min_size.y = 126
	row.set("custom_constants/separation", 14)
	parent.add_child(row)
	_cards_box = HBoxContainer.new()
	_cards_box.set("custom_constants/separation", 10)
	_cards_box.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(_cards_box)
	_target_box = HBoxContainer.new()
	_target_box.name = "Destination"
	_target_box.set("custom_constants/separation", 8)
	row.add_child(_target_box)


func _build_terminal(parent):
	var panel = _panel(Color("20211e"), Color("20211e"), 0, 2)
	panel.rect_min_size.y = 148
	parent.add_child(panel)
	var terminal_rows = VBoxContainer.new()
	terminal_rows.set("custom_constants/separation", 6)
	panel.add_child(_margin(terminal_rows, 16, 16, 10, 10))
	_terminal_log = RichTextLabel.new()
	_terminal_log.name = "TerminalLog"
	_terminal_log.rect_min_size.y = 54
	_terminal_log.size_flags_vertical = SIZE_EXPAND_FILL
	_terminal_log.scroll_active = true
	_terminal_log.scroll_following = true
	_terminal_log.set("custom_fonts/normal_font", FONT_MONO)
	_terminal_log.set("custom_colors/default_color", Color("c9d5bd"))
	_terminal_log.text = "Terminal lista. También podés resolver cada paso con las cartas."
	terminal_rows.add_child(_terminal_log)
	var row = HBoxContainer.new()
	row.set("custom_constants/separation", 10)
	terminal_rows.add_child(row)
	row.add_child(_label("$", FONT_MONO, Color("e9b872")))
	_terminal_input = LineEdit.new()
	_terminal_input.name = "TerminalInput"
	_terminal_input.placeholder_text = "Escribí un comando Git real"
	_terminal_input.set("custom_fonts/font", FONT_MONO)
	_terminal_input.set("custom_colors/font_color", Color("f4efe3"))
	_terminal_input.set("custom_colors/cursor_color", Color("e9b872"))
	_terminal_input.size_flags_horizontal = SIZE_EXPAND_FILL
	_terminal_input.connect("text_entered", self, "_terminal_submitted")
	row.add_child(_terminal_input)
	var run = _button("Ejecutar", true)
	run.connect("pressed", self, "_run_terminal")
	row.add_child(run)


func _build_commit_popup():
	_commit_popup = PopupPanel.new()
	_commit_popup.name = "CommitPopup"
	_commit_popup.rect_min_size = Vector2(620, 250)
	add_child(_commit_popup)
	var rows = VBoxContainer.new()
	rows.set("custom_constants/separation", 14)
	_commit_popup.add_child(_margin(rows, 24, 24, 22, 22))
	rows.add_child(_label("GUARDAR UNA VERSIÓN", FONT_MONO, ORANGE))
	rows.add_child(_label("Escribí el mensaje del commit", FONT_BIG, INK))
	_commit_message = LineEdit.new()
	_commit_message.set("custom_fonts/font", FONT_BODY)
	_commit_message.placeholder_text = "Qué decisión guardaste"
	_commit_message.connect("text_entered", self, "_confirm_commit")
	rows.add_child(_commit_message)
	_commit_error = _label("", FONT_BODY, ERROR)
	_commit_error.autowrap = true
	rows.add_child(_commit_error)
	var actions = HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGN_END
	rows.add_child(actions)
	var cancel = _button("Cancelar", false)
	cancel.connect("pressed", _commit_popup, "hide")
	actions.add_child(cancel)
	var save = _button("Ejecutar git commit", true)
	save.connect("pressed", self, "_confirm_commit_from_button")
	actions.add_child(save)


func _refresh():
	if _engine == null:
		return
	_snapshot = _engine.snapshot()
	_title_label.text = str(_snapshot.get("title", "Una landing, una decisión a la vez"))
	_stage_label.text = "ETAPA %d DE 3" % [int(_snapshot.get("stage", 0)) + 1]
	_instruction_label.text = str(_snapshot.get("instruction", ""))
	var hint_text = str(_snapshot.get("command_hint", ""))
	_command_hint.text = ("Terminal: " + hint_text) if hint_text != "" else ""
	_hint_button.visible = not bool(_snapshot.get("completed", false))
	_continue_button.visible = bool(_snapshot.get("can_continue", false))
	_continue_button.disabled = bool(_snapshot.get("busy", false))
	_terminal_input.editable = not bool(_snapshot.get("busy", false))
	var snapshot_feedback = str(_snapshot.get("feedback", ""))
	if snapshot_feedback != "":
		_show_feedback(snapshot_feedback, _looks_like_error(snapshot_feedback))
	else:
		_feedback_label.text = ""
	_render_choices()
	_render_files()
	_render_timeline()
	_render_preview()
	_render_card_action()


func _render_choices():
	_clear(_choices_box)
	for choice in _snapshot.get("choices", []):
		var button = _button(str(choice.get("label", choice.get("id", ""))), false)
		button.size_flags_horizontal = SIZE_EXPAND_FILL
		button.connect("pressed", self, "_choose", [str(choice.get("id", ""))])
		_choices_box.add_child(button)


func _render_files():
	_clear(_files_box)
	for file_state in _snapshot.get("files", []):
		var line = HBoxContainer.new()
		line.add_child(_label(str(file_state.get("name", "archivo")), FONT_MONO, INK))
		var raw_state = str(file_state.get("state", "clean"))
		var state = _label(_file_state_label(raw_state), FONT_BODY, _file_state_color(raw_state))
		state.align = HALIGN_RIGHT
		state.size_flags_horizontal = SIZE_EXPAND_FILL
		line.add_child(state)
		_files_box.add_child(line)
	if _files_box.get_child_count() == 0:
		_files_box.add_child(_label("Todavía no hay archivos", FONT_BODY, MUTED))


func _render_timeline():
	var commits = _snapshot.get("commits", [])
	if commits.empty():
		_timeline_graph.configure([], {})
		return
	_timeline_graph.configure(commits, _snapshot.get("branches", {}))


func _render_preview():
	var preview = _snapshot.get("preview", {})
	if _viewed_commit != "":
		var inspected = _engine.inspect_commit(_viewed_commit)
		if not inspected.empty():
			preview = inspected.get("preview", inspected)
			_preview_context.text = "Estás mirando %s" % _viewed_commit.substr(0, 7)
			_return_work_button.visible = true
		else:
			_viewed_commit = ""
	if _viewed_commit == "":
		_preview_context.text = "Estás trabajando en %s" % str(_snapshot.get("current_branch", "main"))
		_return_work_button.visible = false
	_preview_title.text = str(preview.get("title", "Tu producto merece una landing clara"))
	_preview_button.text = str(preview.get("button", "Sumarme"))
	var button_color = _safe_color(preview.get("color", "#d96c3b"), ORANGE)
	_preview_button.add_stylebox_override("normal", _style(button_color, button_color, 0, 3))
	_preview_button.add_stylebox_override("hover", _style(button_color.lightened(0.07), button_color, 0, 3))


func _render_card_action():
	_clear(_cards_box)
	_clear(_target_box)
	_card_specs.clear()
	_selected_card = ""
	_active_target = null
	var spec = _card_for_step(str(_snapshot.get("step", "")))
	if spec.empty():
		_cards_box.add_child(_label("Las cartas aparecen cuando una acción Git es necesaria.", FONT_BODY, MUTED))
		return
	_card_specs[spec.id] = spec
	var card = ActionCardScene.instance()
	card.configure(spec.id, spec.title, spec.destination)
	card.connect("selected", self, "select_card")
	_cards_box.add_child(card)
	var arrow = _label("→", FONT_BIG, ORANGE)
	arrow.valign = VALIGN_CENTER
	_target_box.add_child(arrow)
	var target = DropTargetScene.instance()
	target.configure(spec.target, spec.destination)
	target.connect("activated", self, "_destination_clicked")
	target.connect("card_dropped", self, "execute_card")
	_target_box.add_child(target)
	_active_target = target


func _card_for_step(step):
	if step in ["add_title", "add_button", "add_color"]:
		var filename = "styles.css" if step == "add_color" else "index.html"
		return {"id": "add", "title": "Preparar", "target": "file", "destination": filename + " · modificado"}
	if step in ["commit_title", "commit_button", "commit_color"]:
		return {"id": "commit", "title": "Guardar versión", "target": "execute", "destination": "Ejecutar"}
	if step == "create_branch":
		return {"id": "branch", "title": "Crear rama", "target": "execute", "destination": "Ejecutar"}
	if step in ["checkout_branch", "checkout_main"]:
		var branch = "exploracion-cta" if step == "checkout_branch" else "main"
		return {"id": "checkout", "title": "Cambiar rama", "target": branch, "destination": branch}
	if step == "merge_branch":
		return {"id": "merge", "title": "Integrar", "target": "exploracion-cta", "destination": "exploracion-cta (estando en main)"}
	return {}


func select_card(action_id):
	_selected_card = action_id
	var spec = _card_specs.get(action_id, {})
	if spec.empty():
		_show_feedback("Esa carta no corresponde a este paso.", true)
		return false
	_show_feedback("Carta seleccionada. Ahora elegí “%s”." % spec.destination, false)
	if is_instance_valid(_active_target):
		_active_target.modulate = Color("ffe08a")
	return true


func _destination_clicked(target_id):
	if _selected_card == "":
		_show_feedback("Primero elegí la carta. También podés arrastrarla hasta este destino.", true)
		return
	execute_card(_selected_card, target_id)


func execute_card(action_id, target_id, message = ""):
	var spec = _card_specs.get(action_id, _card_for_step(str(_snapshot.get("step", ""))))
	if spec.empty() or str(spec.id) != str(action_id):
		_show_feedback("Esa carta no está disponible en este momento.", true)
		return false
	if str(spec.target) != str(target_id):
		_show_feedback("Ese destino no sirve para esta carta. Buscá “%s”." % spec.destination, true)
		return false
	match action_id:
		"add":
			_queue_execute(_add_command_for_step(str(_snapshot.get("step", ""))))
		"commit":
			if message == "":
				_open_commit_popup()
				return true
			_queue_execute("git commit -m " + _shell_quote(message))
		"branch":
			_queue_execute("git branch exploracion-cta")
		"checkout":
			_queue_execute("git checkout " + str(target_id))
		"merge":
			_queue_execute("git merge --no-ff exploracion-cta -m " + _shell_quote("Integrar exploración de CTA"))
		_:
			_show_feedback("La carta no tiene una acción asociada.", true)
			return false
	return true


func _add_command_for_step(step):
	if step == "add_color":
		return "git add styles.css"
	return "git add index.html"


func _open_commit_popup():
	_commit_message.text = ""
	_commit_error.text = ""
	_commit_popup.popup_centered(Vector2(620, 250))
	_commit_message.grab_focus()


func _confirm_commit_from_button():
	_confirm_commit(_commit_message.text)


func _confirm_commit(message):
	var clean = str(message).strip_edges()
	if clean == "":
		var error_message = "El commit necesita un mensaje que explique la decisión."
		_commit_error.text = error_message
		_show_feedback(error_message, true)
		return
	_commit_popup.hide()
	execute_card("commit", "execute", clean)


func _shell_quote(value):
	return "'" + str(value).replace("'", "'\"'\"'") + "'"


func _terminal_submitted(command):
	execute_terminal(command)


func _run_terminal():
	execute_terminal(_terminal_input.text)


func execute_terminal(command):
	var clean = str(command).strip_edges()
	if clean == "":
		_show_feedback("Escribí un comando antes de ejecutar.", true)
		return false
	_terminal_input.text = ""
	_queue_execute(clean)
	return true


func _queue_execute(command):
	if _local_busy:
		_show_feedback("Hay un comando en curso. Esperá a que termine.", true)
		return false
	_local_busy = true
	_terminal_input.editable = false
	_append_terminal("$ " + command)
	_show_feedback("Ejecutando: " + command, false)
	call_deferred("_execute_after_frame", command)
	return true


func _execute_after_frame(command):
	yield(get_tree(), "idle_frame")
	_engine.execute(command)
	_local_busy = false
	_refresh()


func _choose(value):
	_engine.choose(value)


func _continue():
	_engine.continue_step()


func _hint():
	_engine.hint()


func _restart():
	_viewed_commit = ""
	_engine.restart_stage()


func _inspect_commit(commit_hash):
	_viewed_commit = commit_hash
	_render_preview()


func _return_to_work():
	_viewed_commit = ""
	_render_preview()


func _back():
	get_tree().change_scene("res://scenes/level_select.tscn")


func _on_engine_changed():
	_refresh()


func _on_engine_feedback(message):
	_append_terminal(str(message))
	_show_feedback(str(message), _looks_like_error(str(message)))


func _show_feedback(message, is_error):
	var brief = str(message)
	if brief.length() > 260:
		brief = brief.substr(0, 257) + "…"
	_feedback_label.text = brief
	_feedback_label.set("custom_colors/font_color", ERROR if is_error else GREEN)


func _append_terminal(message):
	if not is_instance_valid(_terminal_log):
		return
	var lines = Array((_terminal_log.text + "\n" + str(message)).split("\n"))
	while lines.size() > 20:
		lines.pop_front()
	_terminal_log.text = PoolStringArray(lines).join("\n")


func _looks_like_error(message):
	var lower = message.to_lower()
	return "error" in lower or "no corresponde" in lower or "no podés" in lower or "invál" in lower or "falló" in lower or "necesita" in lower


func can_drop_data(_position, data):
	return typeof(data) == TYPE_DICTIONARY and data.get("kind", "") == "guided_card"


func drop_data(_position, _data):
	_show_feedback("Soltaste la carta fuera de un destino. Usá el recuadro rotulado junto a la carta.", true)


func _file_state_color(state):
	var lower = state.to_lower()
	if "modif" in lower:
		return ORANGE
	if "prepar" in lower or "stage" in lower:
		return BLUE
	return GREEN


func _file_state_label(state):
	match state.to_lower():
		"modified":
			return "Cambio sin preparar"
		"staged":
			return "Preparado"
		"clean", "tracked":
			return "Guardado"
		"untracked":
			return "Nuevo"
		"staged+modified":
			return "Preparado + nuevos cambios"
		"deleted":
			return "Eliminado"
		_:
			return state


func _safe_color(value, fallback):
	var text = str(value)
	if text.begins_with("#") and (text.length() == 7 or text.length() == 9):
		return Color(text)
	return fallback


func _margin(child, left, right, top, bottom):
	var margin = MarginContainer.new()
	margin.set("custom_constants/margin_left", left)
	margin.set("custom_constants/margin_right", right)
	margin.set("custom_constants/margin_top", top)
	margin.set("custom_constants/margin_bottom", bottom)
	margin.add_child(child)
	return margin


func _panel(color, border_color, border_width, radius):
	var panel = PanelContainer.new()
	panel.add_stylebox_override("panel", _style(color, border_color, border_width, radius))
	return panel


func _style(color, border_color, border_width, radius):
	var style = StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border_color
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style


func _button(text, primary):
	var button = Button.new()
	button.text = text
	button.set("custom_fonts/font", FONT_BODY)
	button.rect_min_size.y = 48
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var bg = GREEN if primary else Color("efe8da")
	var fg = Color("fffaf0") if primary else INK
	button.set("custom_colors/font_color", fg)
	button.set("custom_colors/font_color_hover", fg)
	button.set("custom_colors/font_color_pressed", fg)
	button.add_stylebox_override("normal", _style(bg, INK, 1, 3))
	button.add_stylebox_override("hover", _style(bg.lightened(0.07), INK, 2, 3))
	button.add_stylebox_override("pressed", _style(bg.darkened(0.06), INK, 2, 3))
	return button


func _label(text, font, color):
	var label = Label.new()
	label.text = text
	label.set("custom_fonts/font", font)
	label.set("custom_colors/font_color", color)
	return label


func _clear(node):
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
