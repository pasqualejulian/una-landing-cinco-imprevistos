extends Node

# The exported first mission has no OS process runner, TCP editor or filesystem
# access outside its browser repository. Desktop autoloads remain unchanged.
var tmp_prefix = "/repo/"
var _file = "user://first-mission-web-ui.json"
var state = {}
var energy = 2
var used_cards = false
var dragged_object = null
var current_chapter = 0
var current_level = 0
var skipped_title = true
var global_shell

func _ready():
	state = _initial_state()
	global_shell = new_shell()

func _initial_state():
	return {"history": [], "solved_levels": [], "received_hints": [], "cli_badge": [], "played_cards": []}

func save_state():
	pass # Durable Git/progress belongs to the browser runtime, not Godot IDBFS.

func new_shell():
	return preload("res://web/godot/shell.gd").new()

func notify(text, target = null, hint_slug = null):
	if hint_slug:
		if hint_slug in state["received_hints"]:
			return
		state["received_hints"].append(hint_slug)
	var notification = preload("res://scenes/notification.tscn").instance()
	notification.text = text
	if not target:
		target = get_tree().root
	target.call_deferred("add_child", notification)

func toggle_music():
	var music = $Music
	music.volume_db = -115 if music.volume_db > -20 else -15

func open_survey():
	pass
