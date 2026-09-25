extends "res://scenes/guided/engine.gd"

# Reuse the story's HTML, choices and Git invariants, without its execution
# path or Continue steps. The original terminal is the only command runner.
func start_or_resume():
	if _started:
		return snapshot()
	if repo_path == "":
		repo_path = game.tmp_prefix + "first-mission/"
	progress_path = "user://first-mission-progress.json" if progress_path == DEFAULT_PROGRESS_PATH else progress_path
	if not repo_path.ends_with("/"):
		repo_path += "/"
	_load_progress()
	Directory.new().make_dir_recursive(repo_path)
	_shell = game.new_shell()
	_shell.cd(repo_path)
	if not _git_dir_exists():
		_state = _fresh_state()
		_initialize_repository()
	_started = true
	_refresh_snapshot()
	return snapshot()

func _refresh_snapshot():
	if _shell == null:
		return
	var chosen = str(_state["decisions"].get("title", "")) != ""
	var prepared = chosen and _stage0_prepared()
	var complete = chosen and _stage0_committed()
	_state["step"] = "stage_0_done" if complete else ("commit_title" if prepared else ("add_title" if chosen else "choose_title"))
	_state["completed"] = complete
	_snapshot_cache = {
		"step": _state["step"], "chosen": chosen, "prepared": prepared,
		"completed": complete, "can_continue": false,
		"preview": _preview_snapshot(), "feedback": _feedback_text,
		"commits": _git("rev-list --count HEAD").strip_edges(),
		"head": _head(), "clean": _clean()
	}
	_save_progress()

func observe_result():
	_refresh_snapshot()
	return snapshot()

func validate_command(command):
	command = command.strip_edges()
	# A bounded first mission: no shell pipelines, editor, alternate repository,
	# extra commit options or commands that could mutate another checkout.
	if command in ["git status", "git status --short", "git log", "git log --oneline", "git diff", "git diff --cached", "git show", "git show HEAD"]:
		return ""
	var add_pattern = RegEx.new()
	add_pattern.compile("^git add [a-zA-Z0-9_.-]+$")
	if add_pattern.search(command):
		if not _snapshot_cache.get("chosen", false):
			return "Primero elegí uno de los títulos de la misión."
		if _snapshot_cache.get("completed", false):
			return "Ya guardaste tu versión. Podés consultar Git o reiniciar la misión."
		return ""
	var commit_pattern = RegEx.new()
	commit_pattern.compile("^git commit -m (\"[^\"$`\\\\\r\n]+\"|'[^'\r\n]+')$")
	if commit_pattern.search(command):
		if not _snapshot_cache.get("chosen", false):
			return "Primero elegí un título."
		if _snapshot_cache.get("completed", false):
			return "Ya guardaste tu versión. Podés consultar Git o reiniciar la misión."
		return ""
	return "Probá git add index.html o git commit -m \"Elegir hero\". También podés consultar status, log, diff y show."

func restart_mission():
	# Only the isolated exercise repository is reset, never the source checkout.
	var base = _checkpoint_hash(0)
	if not _is_hex_hash(base):
		return false
	_git("reset --hard -q " + base)
	if _shell.exit_code != 0:
		return false
	_state = _fresh_state()
	_state["checkpoints"]["0"] = base
	_feedback_text = "Volviste a la landing inicial. Elegí un título para probar de nuevo."
	_refresh_snapshot()
	return true
