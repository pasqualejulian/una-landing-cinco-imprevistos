extends Reference

signal changed
signal feedback(message)

const DEFAULT_PROGRESS_PATH = "user://guided-story-progress.json"
const DEFAULT_REPO_NAME = "guided-story"
const BASE_TITLE = "Dale lugar a tu idea"
const BASE_BUTTON = "Empezá ahora"
const BASE_COLOR = "#6750a4"
const BRANCH_NAME = "exploracion-cta"

# Tests and embedders may override these before start_or_resume().
var repo_path = ""
var progress_path = DEFAULT_PROGRESS_PATH

var _shell = null
var _started = false
var _busy = false
var _feedback_text = ""
var _snapshot_cache = {}
var _state = {}
var _loaded_progress = false


func _init():
	_state = _fresh_state()


func start_or_resume():
	if _started:
		return snapshot()
	if repo_path == "":
		repo_path = game.tmp_prefix + DEFAULT_REPO_NAME + "/"
	elif not repo_path.ends_with("/"):
		repo_path += "/"
	_load_progress()
	var wanted_stage = int(_state.get("stage", 0))
	var wanted_completed = bool(_state.get("completed", false))
	var directory = Directory.new()
	directory.make_dir_recursive(repo_path)
	_shell = game.new_shell()
	_shell.cd(repo_path)
	var created = not _git_dir_exists()
	if created:
		_initialize_repository()
		if wanted_stage > 0 or wanted_completed:
			_reconstruct_completed_stages(wanted_stage, wanted_completed)
	else:
		_recover_checkpoint_refs()
		if _loaded_progress and not bool(_state.get("completed", false)):
			_restore_stage_entry_on_reopen()
	_started = true
	_refresh_snapshot()
	emit_signal("changed")
	return snapshot()


func choose(value):
	_ensure_started()
	if _busy:
		return snapshot()
	if bool(_snapshot_cache.get("can_continue", false)):
		_set_feedback("Leé el resultado y pulsá Continuar antes de hacer otro cambio.")
		_refresh_snapshot()
		_emit_updates()
		return snapshot()
	_feedback_text = ""
	var accepted = false
	match str(_state.get("step", "")):
		"choose_title":
			if str(_state["decisions"].get("title", "")) != "":
				_feedback_text = "Ya aplicaste una elección en este paso. Reiniciá la etapa si querés cambiarla."
			elif not _clean() or _current_branch() != "main" or _head() != _checkpoint_hash(0):
				_feedback_text = "El repositorio no está en el punto seguro de esta elección. Reiniciá la etapa para continuar."
			elif value == "idea_vida" or value == "idea_proxima":
				_state["decisions"]["title"] = value
				_write_html()
				_feedback_text = "Elegiste un título nuevo. Prepará index.html para incluirlo en la próxima versión."
				accepted = true
		"choose_button":
			if str(_state["decisions"].get("button", "")) != "":
				_feedback_text = "Ya aplicaste una elección en este paso. Reiniciá la etapa si querés cambiarla."
			elif not _clean() or _current_branch() != "main" or _head() != _checkpoint_hash(1):
				_feedback_text = "El repositorio no está en el punto seguro de esta elección. Reiniciá la etapa para continuar."
			elif value == "quiero_empezar" or value == "proba_idea":
				_state["decisions"]["button"] = value
				_write_html()
				_feedback_text = "El botón cambió en tu mesa de trabajo. Todavía falta prepararlo y guardarlo."
				accepted = true
		"choose_color":
			if str(_state["decisions"].get("color", "")) != "":
				_feedback_text = "Ya aplicaste una elección en este paso. Reiniciá la etapa si querés cambiarla."
			elif not _on_fresh_exploration():
				_feedback_text = "Primero volvé al punto seguro de exploracion-cta. Podés reiniciar la etapa."
			elif value == "verde" or value == "naranja":
				_state["decisions"]["color"] = value
				_write_css()
				_feedback_text = "Probaste otro color en la rama de exploración."
				accepted = true
	if not accepted:
		if _feedback_text == "":
			_feedback_text = "Esa opción no está disponible en este paso."
	_state["feedback"] = _feedback_text
	_save_progress()
	_refresh_snapshot()
	_emit_updates()
	return snapshot()


func execute(command):
	_ensure_started()
	command = str(command).strip_edges()
	if _busy:
		return snapshot()
	var validation = _validate_command(command)
	if validation != "":
		_set_feedback(validation)
		_refresh_snapshot()
		_emit_updates()
		return snapshot()
	var previous_can_continue = bool(_snapshot_cache.get("can_continue", false))
	var verb = _command_verb(command)
	if previous_can_continue and not verb in ["status", "log", "diff", "show"]:
		if verb == "add":
			_set_feedback("El archivo ya estaba preparado. Leé el resultado y pulsá Continuar.")
		else:
			_set_feedback("Leé el resultado y pulsá Continuar antes de ejecutar otra acción.")
		_refresh_snapshot()
		_emit_updates()
		return snapshot()
	_busy = true
	_refresh_snapshot()
	emit_signal("changed")
	var output = _shell.run(command, false)
	var exit_code = _shell.exit_code
	_busy = false
	_refresh_snapshot()
	if exit_code != 0:
		_feedback_text = _friendly_git_error(output)
	elif verb == "status" or verb == "log" or verb == "diff" or verb == "show":
		_feedback_text = output.strip_edges()
		if _feedback_text == "":
			_feedback_text = "El comando terminó sin mostrar cambios."
	elif previous_can_continue and verb == "add" and bool(_snapshot_cache.get("can_continue", false)):
		_feedback_text = "El archivo ya estaba preparado. Podés continuar."
	elif bool(_snapshot_cache.get("can_continue", false)):
		_feedback_text = _success_feedback_for_step()
	elif verb == "commit":
		_feedback_text = "Ese commit no coincide con el objetivo de este paso. Reiniciá la etapa para volver al último punto seguro."
	else:
		_feedback_text = "Git aceptó el comando, pero el repositorio todavía no cumple este paso. Revisá el estado o reiniciá la etapa."
	_state["feedback"] = _feedback_text
	_save_progress()
	_refresh_snapshot()
	_emit_updates()
	return snapshot()


func continue_step():
	_ensure_started()
	if _busy:
		return snapshot()
	_refresh_snapshot()
	if not bool(_snapshot_cache.get("can_continue", false)):
		_set_feedback("Todavía falta completar la acción de este paso.")
		_refresh_snapshot()
		_emit_updates()
		return snapshot()
	match str(_state.get("step", "")):
		"choose_title":
			_advance("add_title")
		"add_title":
			_advance("commit_title")
		"commit_title":
			_advance("stage_0_done")
		"stage_0_done":
			_set_checkpoint(1, _head())
			_state["stage"] = 1
			_advance("choose_button")
		"choose_button":
			_advance("add_button")
		"add_button":
			_advance("commit_button")
		"commit_button":
			_advance("stage_1_done")
		"stage_1_done":
			_set_checkpoint(2, _head())
			_state["stage"] = 2
			_advance("create_branch")
		"create_branch":
			_advance("checkout_branch")
		"checkout_branch":
			_advance("choose_color")
		"choose_color":
			_advance("add_color")
		"add_color":
			_advance("commit_color")
		"commit_color":
			_advance("checkout_main")
		"checkout_main":
			_advance("merge_branch")
		"merge_branch":
			_state["completed"] = true
			_advance("story_done")
	_save_progress()
	_refresh_snapshot()
	_emit_updates()
	return snapshot()


func hint():
	_ensure_started()
	var level = min(3, int(_state.get("hint_level", 0)) + 1)
	_state["hint_level"] = level
	_feedback_text = _hint_for_step(str(_state.get("step", "")), level)
	_state["feedback"] = _feedback_text
	_save_progress()
	_refresh_snapshot()
	_emit_updates()
	return snapshot()


func restart_stage():
	_ensure_started()
	if _busy:
		return snapshot()
	var stage = int(_state.get("stage", 0))
	var checkpoint = _checkpoint_hash(stage)
	if checkpoint == "":
		_set_feedback("No encontré el punto seguro de esta etapa. El repositorio quedó intacto.")
		_refresh_snapshot()
		_emit_updates()
		return snapshot()
	# Restart is the only operation that intentionally discards the current stage.
	_shell.run("git merge --abort", false)
	_shell.run("git rebase --abort", false)
	_shell.run("git cherry-pick --abort", false)
	_shell.run("git reset --hard -q", false)
	_shell.run("git checkout -q main", false)
	_shell.run("git reset --hard -q " + checkpoint, false)
	_shell.run("git clean -fdq", false)
	if _branch_hash(BRANCH_NAME) != "":
		_shell.run("git branch -D " + BRANCH_NAME, false)
	if stage < 2:
		_delete_checkpoint(2)
	if stage < 1:
		_delete_checkpoint(1)
	_clear_stage_decisions(stage)
	_state["step"] = ["choose_title", "choose_button", "create_branch"][stage]
	_state["hint_level"] = 0
	_state["completed"] = false
	_feedback_text = "Volviste al inicio de esta etapa. Las etapas anteriores siguen guardadas."
	_state["feedback"] = _feedback_text
	_save_progress()
	_refresh_snapshot()
	_emit_updates()
	return snapshot()


func snapshot() -> Dictionary:
	_ensure_started()
	return _snapshot_cache.duplicate(true)


func inspect_commit(commit_hash) -> Dictionary:
	_ensure_started()
	commit_hash = str(commit_hash).strip_edges()
	if not _is_hex_hash(commit_hash):
		return {}
	var raw = _git("show -s --format=%H%x1f%s%x1f%P%x1fEND " + commit_hash)
	if _shell.exit_code != 0 or raw.strip_edges() == "":
		return {}
	var parts = raw.strip_edges().split("\u001f")
	if parts.size() < 4:
		return {}
	var files = []
	var changed = _git("diff-tree --root --no-commit-id --name-status -r " + str(parts[0]))
	for line in changed.split("\n", false):
		var columns = line.split("\t", false)
		if columns.size() >= 2:
			files.append({"name": columns[columns.size() - 1], "state": columns[0]})
	var html = _git("show " + str(parts[0]) + ":index.html")
	var css = _git("show " + str(parts[0]) + ":styles.css")
	return {
		"hash": parts[0],
		"message": parts[1],
		"parents": Array(str(parts[2]).split(" ", false)),
		"files": files,
		"preview": {
			"title": _between(html, "<h1>", "</h1>", BASE_TITLE),
			"button": _between(html, "<button>", "</button>", BASE_BUTTON),
			"color": _css_color(css)
		}
	}


func _fresh_state():
	return {
		"version": 1,
		"stage": 0,
		"step": "choose_title",
		"decisions": {"title": "", "button": "", "color": ""},
		"checkpoints": {},
		"hint_level": 0,
		"feedback": "",
		"completed": false
	}


func _ensure_started():
	if not _started:
		start_or_resume()


func _initialize_repository():
	_git("init -q")
	_git("symbolic-ref HEAD refs/heads/main")
	_git("config user.name 'Oh My Git'")
	_git("config user.email guided@ohmygit.invalid")
	_write_text(repo_path + "index.html", _html(BASE_TITLE, BASE_BUTTON))
	_write_text(repo_path + "styles.css", _css(BASE_COLOR))
	_git("add index.html styles.css")
	_git("commit -q -m 'Base de la landing'")
	_set_checkpoint(0, _head())


func _reconstruct_completed_stages(wanted_stage, wanted_completed):
	var decisions = _state.get("decisions", {})
	var saved_title = str(decisions.get("title", ""))
	var saved_button = str(decisions.get("button", ""))
	var saved_color = str(decisions.get("color", ""))
	if (wanted_stage >= 1 or wanted_completed) and not saved_title in ["idea_vida", "idea_proxima"]:
		saved_title = "idea_vida"
	if (wanted_stage >= 2 or wanted_completed) and not saved_button in ["quiero_empezar", "proba_idea"]:
		saved_button = "quiero_empezar"
	if wanted_completed and not saved_color in ["verde", "naranja"]:
		saved_color = "verde"
	if not wanted_completed:
		if wanted_stage == 0:
			saved_title = ""
			saved_button = ""
			saved_color = ""
		elif wanted_stage == 1:
			saved_button = ""
			saved_color = ""
		else:
			saved_color = ""
	decisions["title"] = saved_title
	decisions["button"] = ""
	decisions["color"] = ""
	_state["decisions"] = decisions
	if wanted_stage >= 1 or wanted_completed:
		if str(decisions.get("title", "")) == "":
			decisions["title"] = "idea_vida"
		_write_html()
		_git("add index.html")
		_git("commit -q -m 'Guardar título elegido'")
		_set_checkpoint(1, _head())
	if wanted_stage >= 2 or wanted_completed:
		decisions["button"] = saved_button if saved_button != "" else "quiero_empezar"
		_write_html()
		_git("add index.html")
		_git("commit -q -m 'Guardar texto del botón'")
		_set_checkpoint(2, _head())
	if not wanted_completed:
		decisions["title"] = saved_title
		decisions["button"] = saved_button
		decisions["color"] = saved_color
		_state["stage"] = wanted_stage
		_state["step"] = ["choose_title", "choose_button", "create_branch"][wanted_stage]
		_state["completed"] = false
		_feedback_text = "Reconstruí las etapas guardadas. La etapa actual vuelve a empezar desde su punto seguro."
	if wanted_completed:
		decisions["color"] = saved_color if saved_color != "" else "verde"
		_git("branch " + BRANCH_NAME)
		_git("checkout -q " + BRANCH_NAME)
		_write_css()
		_git("add styles.css")
		_git("commit -q -m 'Explorar color del CTA'")
		_git("checkout -q main")
		_git("merge --no-ff " + BRANCH_NAME + " -m 'Integrar exploración'")
		_state["stage"] = 2
		_state["step"] = "story_done"
		_state["completed"] = true
	_state["decisions"] = decisions
	_state["feedback"] = _feedback_text
	_save_progress()


func _recover_checkpoint_refs():
	for stage in range(3):
		var ref = _checkpoint_ref(stage)
		if _ref_hash(ref) != "":
			continue
		var saved = str(_state.get("checkpoints", {}).get(str(stage), ""))
		if _commit_exists(saved):
			_git("update-ref " + ref + " " + saved)
	if _checkpoint_hash(0) == "":
		var roots = _git("rev-list --max-parents=0 --reverse --all")
		var lines = roots.split("\n", false)
		if lines.size() > 0 and _is_hex_hash(lines[0]):
			_set_checkpoint(0, lines[0])


func _load_progress():
	_state = _fresh_state()
	_loaded_progress = false
	var file = File.new()
	if not file.file_exists(progress_path):
		return
	if file.open(progress_path, File.READ) != OK:
		return
	var parsed = parse_json(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	_loaded_progress = true
	for key in _state.keys():
		if parsed.has(key):
			_state[key] = parsed[key]
	_state["stage"] = int(clamp(int(_state.get("stage", 0)), 0, 2))
	if typeof(_state.get("decisions")) != TYPE_DICTIONARY:
		_state["decisions"] = {"title": "", "button": "", "color": ""}
	if typeof(_state.get("checkpoints")) != TYPE_DICTIONARY:
		_state["checkpoints"] = {}
	_feedback_text = str(_state.get("feedback", ""))


func _restore_stage_entry_on_reopen():
	var stage = int(_state.get("stage", 0))
	var checkpoint = _checkpoint_hash(stage)
	if checkpoint == "":
		_feedback_text = "No encontré el punto seguro guardado. El repositorio quedó intacto; podés reiniciar la etapa."
		_state["feedback"] = _feedback_text
		_save_progress()
		return
	_shell.run("git merge --abort", false)
	_shell.run("git rebase --abort", false)
	_shell.run("git cherry-pick --abort", false)
	_shell.run("git reset --hard -q", false)
	_shell.run("git checkout -q main", false)
	_shell.run("git reset --hard -q " + checkpoint, false)
	_shell.run("git clean -fdq", false)
	if _branch_hash(BRANCH_NAME) != "":
		_shell.run("git branch -D " + BRANCH_NAME, false)
	_clear_stage_decisions(stage)
	_state["step"] = ["choose_title", "choose_button", "create_branch"][stage]
	_state["hint_level"] = 0
	_feedback_text = "Retomaste desde el inicio de la etapa guardada. Los pasos que habían quedado incompletos se reiniciaron."
	_state["feedback"] = _feedback_text
	_save_progress()


func _save_progress():
	var file = File.new()
	if file.open(progress_path, File.WRITE) == OK:
		file.store_string(to_json(_state))
		file.close()


func _advance(step):
	_state["step"] = step
	_state["hint_level"] = 0
	_feedback_text = ""
	_state["feedback"] = ""


func _clear_stage_decisions(stage):
	if stage == 0:
		_state["decisions"]["title"] = ""
		_state["decisions"]["button"] = ""
		_state["decisions"]["color"] = ""
	elif stage == 1:
		_state["decisions"]["button"] = ""
		_state["decisions"]["color"] = ""
	else:
		_state["decisions"]["color"] = ""


func _refresh_snapshot():
	if _shell == null:
		return
	var step = str(_state.get("step", "choose_title"))
	var copy = _copy_for_step(step)
	_snapshot_cache = {
		"stage": int(_state.get("stage", 0)),
		"step": step,
		"title": copy["title"],
		"instruction": copy["instruction"],
		"command_hint": _command_hint(step),
		"feedback": _feedback_text,
		"busy": _busy,
		"choices": _choices_for_step(step),
		"files": _files_snapshot(),
		"commits": _commits_snapshot(),
		"branches": _branches_snapshot(),
		"current_branch": _current_branch(),
		"preview": _preview_snapshot(),
		"can_continue": _can_continue(step),
		"completed": bool(_state.get("completed", false)),
		"hint_level": int(_state.get("hint_level", 0))
	}


func _copy_for_step(step):
	var all = {
		"choose_title": {"title": "Elegí un título", "instruction": "Elegí la frase principal de la landing. El cambio aparecerá primero en tu mesa de trabajo."},
		"add_title": {"title": "Prepará el título", "instruction": "Elegiste un título nuevo. Prepará index.html para incluirlo en la próxima versión."},
		"commit_title": {"title": "Guardá el título", "instruction": "Guardá lo preparado con un mensaje que explique el cambio."},
		"stage_0_done": {"title": "Confirmá el avance", "instruction": "El título ya forma parte de la historia. Continuá para trabajar sobre el botón."},
		"choose_button": {"title": "Elegí el llamado", "instruction": "Elegí cómo invita a avanzar el botón. Este cambio parte de la versión que ya guardaste."},
		"add_button": {"title": "Prepará el botón", "instruction": "El botón cambió en tu mesa de trabajo. Prepará el archivo correcto para la próxima versión."},
		"commit_button": {"title": "Guardá el botón", "instruction": "Creá una versión que conserve el nuevo llamado a la acción."},
		"stage_1_done": {"title": "Confirmá el avance", "instruction": "La landing tiene un nuevo título y un nuevo botón. Continuá para explorar un color sin tocar main."},
		"create_branch": {"title": "Creá la rama", "instruction": "Creá exploracion-cta para probar otra dirección."},
		"checkout_branch": {"title": "Cambiá de rama", "instruction": "Cambiate a exploracion-cta antes de modificar el botón."},
		"choose_color": {"title": "Probá un color", "instruction": "Elegí un color para el CTA en la rama de exploración."},
		"add_color": {"title": "Prepará el color", "instruction": "Prepará styles.css para guardar la dirección elegida."},
		"commit_color": {"title": "Guardá la exploración", "instruction": "Creá una versión del color en exploracion-cta."},
		"checkout_main": {"title": "Volvé a main", "instruction": "Volvé a main para comparar con la versión aprobada."},
		"merge_branch": {"title": "Integrá la exploración", "instruction": "Integrá exploracion-cta en main. Conservaremos visible el camino de la exploración."},
		"story_done": {"title": "Historia completa", "instruction": "La landing evolucionó sin perder su recorrido. Podés inspeccionar cada versión y sus ramas."}
	}
	return all.get(step, {"title": "Revisá el repositorio", "instruction": "El progreso guardado no coincide con un paso conocido. Reiniciá la etapa para continuar."})


func _choices_for_step(step):
	match step:
		"choose_title":
			return [{"id": "idea_vida", "label": "Dale vida a tu idea"}, {"id": "idea_proxima", "label": "Tu próxima idea empieza acá"}]
		"choose_button":
			return [{"id": "quiero_empezar", "label": "Quiero empezar"}, {"id": "proba_idea", "label": "Probá tu idea"}]
		"choose_color":
			return [{"id": "verde", "label": "Verde · #146c43"}, {"id": "naranja", "label": "Naranja · #b54708"}]
	return []


func _command_hint(step):
	if step == "add_title":
		return "git add index.html"
	if step == "commit_title":
		return "git commit -m \"Actualizar título\""
	if int(_state.get("hint_level", 0)) < 3 and int(_state.get("stage", 0)) == 1:
		return ""
	var hints = {
		"add_button": "git add index.html",
		"commit_button": "git commit -m \"Actualizar botón\"",
		"create_branch": "git branch exploracion-cta",
		"checkout_branch": "git checkout exploracion-cta",
		"add_color": "git add styles.css",
		"commit_color": "git commit -m \"Explorar color del CTA\"",
		"checkout_main": "git checkout main",
		"merge_branch": "git merge --no-ff exploracion-cta -m \"Integrar exploración\""
	}
	return hints.get(step, "")


func _hint_for_step(step, level):
	var hints = {
		"add_button": ["Preparar separa lo que querés guardar del resto de la mesa.", "El cambio del botón vive en index.html.", "Probá: git add index.html"],
		"commit_button": ["Un commit convierte lo preparado en una versión de la historia.", "El destino es la línea de tiempo de main.", "Probá: git commit -m \"Actualizar botón\""],
		"create_branch": ["Una rama abre otro camino desde la versión actual.", "El nuevo camino debe llamarse exploracion-cta.", "Probá: git branch exploracion-cta"],
		"checkout_branch": ["Crear una rama no te mueve hacia ella.", "El destino es exploracion-cta.", "Probá: git checkout exploracion-cta"],
		"add_color": ["Prepará solamente el archivo donde vive el color.", "El color está en styles.css.", "Probá: git add styles.css"],
		"commit_color": ["Guardá la exploración antes de volver a main.", "El commit debe quedar en exploracion-cta.", "Probá: git commit -m \"Explorar color del CTA\""],
		"checkout_main": ["Para comparar, cambiá al camino aprobado.", "El destino es main.", "Probá: git checkout main"],
		"merge_branch": ["Integrar reúne ambos caminos en una versión con dos padres.", "Traé exploracion-cta a main sin ocultar la bifurcación.", "Probá: git merge --no-ff exploracion-cta -m \"Integrar exploración\""],
		"add_title": ["Prepará el archivo modificado.", "El título vive en index.html.", "Probá: git add index.html"],
		"commit_title": ["Guardá lo que ya preparaste.", "La versión debe quedar en main.", "Probá: git commit -m \"Actualizar título\""]
	}
	var values = hints.get(step, ["Observá el objetivo y el estado actual.", "Revisá la rama y los archivos pendientes.", "Reiniciá la etapa si el repositorio quedó en otro estado."])
	return values[clamp(level - 1, 0, 2)]


func _can_continue(step):
	match step:
		"choose_title":
			return _title_choice_valid()
		"add_title":
			return _stage0_prepared()
		"commit_title", "stage_0_done":
			return _stage0_committed()
		"choose_button":
			return _button_choice_valid()
		"add_button":
			return _stage1_prepared()
		"commit_button", "stage_1_done":
			return _stage1_committed()
		"create_branch":
			return _branch_created()
		"checkout_branch":
			return _on_fresh_exploration()
		"choose_color":
			return _color_choice_valid()
		"add_color":
			return _stage2_prepared()
		"commit_color":
			return _exploration_committed()
		"checkout_main":
			return _back_on_main()
		"merge_branch":
			return _merge_valid()
	return false


func _title_choice_valid():
	var decision = str(_state["decisions"].get("title", ""))
	return decision != "" and _current_branch() == "main" and _head() == _checkpoint_hash(0) and _preview_snapshot()["title"] == _title_value(decision)


func _stage0_prepared():
	return _current_branch() == "main" and _head() == _checkpoint_hash(0) and _staged_files() == ["index.html"] and _unstaged_files().empty() and _title_choice_valid() and _preview_matches_decisions()


func _stage0_committed():
	var checkpoint = _checkpoint_hash(0)
	return _single_commit_after(checkpoint) and _current_branch() == "main" and _clean() and _changed_files(checkpoint, _head()) == ["index.html"] and _preview_matches_decisions()


func _button_choice_valid():
	var decision = str(_state["decisions"].get("button", ""))
	return decision != "" and _current_branch() == "main" and _head() == _checkpoint_hash(1) and _preview_snapshot()["button"] == _button_value(decision)


func _stage1_prepared():
	return _current_branch() == "main" and _head() == _checkpoint_hash(1) and _staged_files() == ["index.html"] and _unstaged_files().empty() and _button_choice_valid() and _preview_matches_decisions()


func _stage1_committed():
	var checkpoint = _checkpoint_hash(1)
	return _single_commit_after(checkpoint) and _current_branch() == "main" and _clean() and _changed_files(checkpoint, _head()) == ["index.html"] and _preview_matches_decisions()


func _branch_created():
	var checkpoint = _checkpoint_hash(2)
	return _current_branch() == "main" and _head() == checkpoint and _branch_hash("main") == checkpoint and _branch_hash(BRANCH_NAME) == checkpoint and _clean()


func _on_fresh_exploration():
	return _current_branch() == BRANCH_NAME and _head() == _checkpoint_hash(2) and _clean() and _branch_hash("main") == _checkpoint_hash(2)


func _color_choice_valid():
	var decision = str(_state["decisions"].get("color", ""))
	return decision != "" and _current_branch() == BRANCH_NAME and _head() == _checkpoint_hash(2) and _preview_snapshot()["color"] == _color_value(decision) and _unstaged_files() == ["styles.css"] and _staged_files().empty()


func _stage2_prepared():
	return _current_branch() == BRANCH_NAME and _head() == _checkpoint_hash(2) and _staged_files() == ["styles.css"] and _unstaged_files().empty() and _preview_snapshot()["color"] == _color_value(str(_state["decisions"].get("color", ""))) and _preview_matches_decisions()


func _exploration_committed():
	var checkpoint = _checkpoint_hash(2)
	var branch_head = _branch_hash(BRANCH_NAME)
	return _current_branch() == BRANCH_NAME and _head() == branch_head and branch_head != checkpoint and _branch_hash("main") == checkpoint and _clean() and _single_commit_after(checkpoint) and _changed_files(checkpoint, branch_head) == ["styles.css"] and _preview_matches_decisions()


func _back_on_main():
	return _current_branch() == "main" and _head() == _checkpoint_hash(2) and _branch_hash("main") == _checkpoint_hash(2) and _clean() and _exploration_branch_valid()


func _merge_valid():
	if _current_branch() != "main" or not _clean() or not _exploration_branch_valid():
		return false
	var merge_head = _head()
	var parents = _parents(merge_head)
	var branch_head = _branch_hash(BRANCH_NAME)
	if parents.size() != 2 or parents[0] != _checkpoint_hash(2) or parents[1] != branch_head or _commit_message(merge_head).strip_edges() == "":
		return false
	_git("diff --quiet " + merge_head + " " + branch_head)
	return _shell.exit_code == 0 and _preview_matches_decisions()


func _exploration_branch_valid():
	var checkpoint = _checkpoint_hash(2)
	var branch_head = _branch_hash(BRANCH_NAME)
	if branch_head == "" or branch_head == checkpoint:
		return false
	var parents = _parents(branch_head)
	if parents.size() != 1 or parents[0] != checkpoint or _changed_files(checkpoint, branch_head) != ["styles.css"]:
		return false
	var css = _git("show " + branch_head + ":styles.css")
	return _color_value(str(_state["decisions"].get("color", ""))) in css


func _single_commit_after(checkpoint):
	var head = _head()
	if head == "" or head == checkpoint or _commit_message(head).strip_edges() == "":
		return false
	var parents = _parents(head)
	return parents.size() == 1 and parents[0] == checkpoint


func _preview_matches_decisions():
	var decisions = _state.get("decisions", {})
	var expected_html = _html(_title_value(str(decisions.get("title", ""))), _button_value(str(decisions.get("button", ""))))
	var expected_css = _css(_color_value(str(decisions.get("color", ""))))
	return _read_text(repo_path + "index.html") == expected_html and _read_text(repo_path + "styles.css") == expected_css


func _success_feedback_for_step():
	match str(_state.get("step", "")):
		"add_title", "add_button", "add_color":
			return "Archivo preparado. Todavía no creaste una versión."
		"commit_title", "commit_button", "commit_color":
			return "Creaste una versión. Ya aparece en la línea de tiempo."
		"create_branch":
			return "La rama existe. Todavía estás en main."
		"checkout_branch":
			return "Ahora estás en exploracion-cta. main conserva la versión aprobada."
		"checkout_main":
			return "Volviste a main. La exploración sigue visible en su rama."
		"merge_branch":
			return "Integraste la exploración y conservaste visibles ambos caminos."
	return "El repositorio ya cumple este paso."


func _validate_command(command):
	if command == "":
		return "Escribí un comando de Git."
	if not command.begins_with("git "):
		return "En esta historia solo podés ejecutar comandos que empiecen con git."
	for forbidden in ["\n", "\r", ";", "&&", "||", "|", ">", "<", "`", "$", "\\"]:
		if forbidden in command:
			return "Usá un solo comando de Git, sin operadores de shell."
	var verb = _command_verb(command)
	if not verb in ["status", "log", "diff", "show", "branch", "checkout", "switch", "add", "commit", "merge"]:
		return "Ese comando de Git no está disponible en la experiencia guiada."
	for unsafe_option in ["--git-dir", "--work-tree", "--exec-path", "--config-env", "--output", "--edit-description"]:
		if unsafe_option in command:
			return "Ese modificador no está disponible en el repositorio guiado."
	if verb == "commit" and not _has_message_option(command):
		return "Agregá -m con un mensaje para que el commit no abra un editor, o usá la carta sugerida."
	if verb == "merge" and not _has_message_option(command):
		return "Agregá -m con un mensaje para integrar sin abrir un editor, o usá la carta sugerida."
	return ""


func _has_message_option(command):
	return " -m " in command or " --message " in command or " --message=" in command


func _command_verb(command):
	var words = command.split(" ", false)
	if words.size() < 2 or words[0] != "git":
		return ""
	if str(words[1]).begins_with("-"):
		return ""
	return str(words[1])


func _friendly_git_error(output):
	var clean_output = str(output).strip_edges()
	if clean_output == "":
		return "Git no pudo completar el comando. Revisá la sintaxis o reiniciá la etapa."
	return clean_output


func _files_snapshot():
	var status_by_name = {}
	var porcelain = _git("status --porcelain --untracked-files=all")
	for line in porcelain.split("\n", false):
		if line.length() < 4:
			continue
		var code = line.substr(0, 2)
		var name = line.substr(3, line.length() - 3)
		if " -> " in name:
			name = name.split(" -> ", false)[1]
		var state = "modified"
		if code == "??":
			state = "untracked"
		elif code.substr(0, 1) != " " and code.substr(1, 1) != " ":
			state = "staged+modified"
		elif code.substr(0, 1) != " ":
			state = "staged"
		elif code.substr(1, 1) == "D":
			state = "deleted"
		status_by_name[name] = state
	var names = []
	for name in _git("ls-files").split("\n", false):
		if not name in names:
			names.append(name)
	for name in status_by_name.keys():
		if not name in names:
			names.append(name)
	names.sort()
	var files = []
	for name in names:
		files.append({"name": name, "state": status_by_name.get(name, "tracked")})
	return files


func _branches_snapshot():
	var branches = {}
	var raw = _git("for-each-ref --format='%(refname:short)%09%(objectname)' refs/heads")
	for line in raw.split("\n", false):
		var pieces = line.split("\t", false)
		if pieces.size() == 2:
			branches[pieces[0]] = pieces[1]
	return branches


func _commits_snapshot():
	var branches = _branches_snapshot()
	var labels = {}
	for branch in branches:
		var branch_commit = branches[branch]
		if not labels.has(branch_commit):
			labels[branch_commit] = []
		labels[branch_commit].append(branch)
	var commits = []
	var raw = _git("log --all --date-order --pretty=format:'%H%x1f%s%x1f%P%x1fEND%x1e'")
	for record in raw.split("\u001e", false):
		var clean = record.strip_edges()
		if clean == "":
			continue
		var parts = clean.split("\u001f")
		if parts.size() < 4:
			continue
		var item = {"hash": parts[0], "message": parts[1], "parents": Array(str(parts[2]).split(" ", false))}
		if labels.has(parts[0]):
			item["branch"] = PoolStringArray(labels[parts[0]]).join(", ")
		commits.append(item)
	return commits


func _preview_snapshot():
	var html = _read_text(repo_path + "index.html")
	var css = _read_text(repo_path + "styles.css")
	return {
		"title": _between(html, "<h1>", "</h1>", BASE_TITLE),
		"button": _between(html, "<button>", "</button>", BASE_BUTTON),
		"color": _css_color(css)
	}


func _staged_files():
	return _sorted_lines(_git("diff --cached --name-only"))


func _unstaged_files():
	var names = _sorted_lines(_git("diff --name-only"))
	var untracked = _sorted_lines(_git("ls-files --others --exclude-standard"))
	for name in untracked:
		if not name in names:
			names.append(name)
	names.sort()
	return names


func _changed_files(from_hash, to_hash):
	if from_hash == "" or to_hash == "":
		return []
	return _sorted_lines(_git("diff --name-only " + from_hash + " " + to_hash))


func _sorted_lines(text):
	var result = []
	for line in str(text).split("\n", false):
		var clean = line.strip_edges()
		if clean != "":
			result.append(clean)
	result.sort()
	return result


func _clean():
	return _git("status --porcelain --untracked-files=all").strip_edges() == ""


func _current_branch():
	return _git("symbolic-ref --quiet --short HEAD").strip_edges()


func _head():
	return _git("rev-parse --verify HEAD").strip_edges()


func _branch_hash(branch):
	var value = _git("rev-parse --verify refs/heads/" + branch).strip_edges()
	return value if _shell.exit_code == 0 else ""


func _parents(commit_hash):
	if not _is_hex_hash(commit_hash):
		return []
	var values = _git("show -s --format=%P " + commit_hash).strip_edges()
	return Array(values.split(" ", false))


func _commit_message(commit_hash):
	if not _is_hex_hash(commit_hash):
		return ""
	return _git("show -s --format=%s " + commit_hash)


func _commit_exists(commit_hash):
	if not _is_hex_hash(commit_hash):
		return false
	_git("cat-file -e " + commit_hash + "^{commit}")
	return _shell.exit_code == 0


func _checkpoint_ref(stage):
	return "refs/guided/checkpoints/stage-" + str(stage)


func _checkpoint_hash(stage):
	return _ref_hash(_checkpoint_ref(stage))


func _set_checkpoint(stage, commit_hash):
	if not _is_hex_hash(commit_hash):
		return
	_git("update-ref " + _checkpoint_ref(stage) + " " + commit_hash)
	_state["checkpoints"][str(stage)] = commit_hash
	_save_progress()


func _delete_checkpoint(stage):
	_git("update-ref -d " + _checkpoint_ref(stage))
	_state["checkpoints"].erase(str(stage))


func _ref_hash(ref):
	var value = _git("rev-parse --verify " + ref).strip_edges()
	return value if _shell.exit_code == 0 else ""


func _git_dir_exists():
	return Directory.new().dir_exists(repo_path + ".git")


func _git(args):
	return _shell.run("git " + args, false)


func _set_feedback(message):
	_feedback_text = message
	_state["feedback"] = message
	_save_progress()


func _emit_updates():
	emit_signal("feedback", _feedback_text)
	emit_signal("changed")


func _write_html():
	var title = _title_value(str(_state["decisions"].get("title", "")))
	var button = _button_value(str(_state["decisions"].get("button", "")))
	_write_text(repo_path + "index.html", _html(title, button))


func _write_css():
	var color = _color_value(str(_state["decisions"].get("color", "")))
	_write_text(repo_path + "styles.css", _css(color))


func _title_value(choice):
	if choice == "idea_vida":
		return "Dale vida a tu idea"
	if choice == "idea_proxima":
		return "Tu próxima idea empieza acá"
	return BASE_TITLE


func _button_value(choice):
	if choice == "quiero_empezar":
		return "Quiero empezar"
	if choice == "proba_idea":
		return "Probá tu idea"
	return BASE_BUTTON


func _color_value(choice):
	if choice == "verde":
		return "#146c43"
	if choice == "naranja":
		return "#b54708"
	return BASE_COLOR


func _html(title, button):
	return """<!doctype html>
<html lang="es">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Mi idea</title>
  <link rel="stylesheet" href="styles.css">
</head>
<body>
  <main>
    <p class="eyebrow">Una idea lista para crecer</p>
    <h1>%s</h1>
    <button>%s</button>
  </main>
</body>
</html>
""" % [title, button]


func _css(color):
	return """:root { --cta: %s; }
* { box-sizing: border-box; }
body { margin: 0; min-height: 100vh; display: grid; place-items: center; font-family: sans-serif; background: #f7f3ff; color: #211a2d; }
main { width: min(38rem, 88vw); padding: 4rem; border-radius: 2rem; background: white; box-shadow: 0 1.5rem 4rem rgba(40, 20, 70, .12); }
.eyebrow { color: #746783; }
h1 { font-size: clamp(2.5rem, 8vw, 5rem); line-height: .95; }
button { border: 0; border-radius: 999px; padding: 1rem 1.5rem; color: white; background: var(--cta); font: inherit; font-weight: 700; }
""" % color


func _write_text(path, content):
	var file = File.new()
	if file.open(path, File.WRITE) == OK:
		file.store_string(content)
		file.close()


func _read_text(path):
	var file = File.new()
	if file.open(path, File.READ) != OK:
		return ""
	var content = file.get_as_text()
	file.close()
	return content


func _between(text, start, finish, fallback):
	var first = text.find(start)
	if first < 0:
		return fallback
	first += start.length()
	var last = text.find(finish, first)
	if last < 0:
		return fallback
	return text.substr(first, last - first).strip_edges()


func _css_color(css):
	for color in ["#146c43", "#b54708", BASE_COLOR]:
		if color in css:
			return color
	return BASE_COLOR


func _is_hex_hash(value):
	value = str(value)
	if value.length() < 4 or value.length() > 40:
		return false
	for character in value.to_lower():
		if not character in "0123456789abcdef":
			return false
	return true
