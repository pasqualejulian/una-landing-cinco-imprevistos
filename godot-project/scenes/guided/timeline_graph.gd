extends Control

signal commit_selected(commit_hash)

const FONT_BODY = preload("res://fonts/default.tres")
const FONT_MONO = preload("res://fonts/monospace.tres")
const GREEN = Color("44633f")
const ORANGE = Color("d96c3b")
const MUTED = Color("8b8376")
const PAPER = Color("fffaf0")

var _commits = []
var _positions = {}


func configure(commits, branches):
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_commits = commits.duplicate(true)
	_commits.invert()
	_positions = {}
	var feature_hashes = _feature_lane_hashes(commits, branches)
	rect_min_size = Vector2(max(840, 180 + _commits.size() * 205), 142)

	var main_label = _lane_label("main", GREEN)
	main_label.rect_position = Vector2(0, 15)
	add_child(main_label)
	var feature_name = "exploracion-cta" if branches.has("exploracion-cta") else "Sin exploración"
	var feature_label = _lane_label(feature_name, ORANGE if branches.has("exploracion-cta") else MUTED)
	feature_label.rect_position = Vector2(0, 88)
	add_child(feature_label)

	for index in range(_commits.size()):
		var commit = _commits[index]
		var commit_hash = str(commit.get("hash", ""))
		var lane_y = 82 if feature_hashes.has(commit_hash) else 8
		var position = Vector2(175 + index * 205, lane_y)
		_positions[commit_hash] = position + Vector2(92, 28)
		var button = Button.new()
		button.rect_position = position
		button.rect_size = Vector2(184, 58)
		button.rect_min_size = Vector2(184, 58)
		var short_message = str(commit.get("message", "versión"))
		button.text = ""
		var caption = Label.new()
		caption.rect_position = Vector2(8, 2)
		caption.rect_size = Vector2(168, 54)
		caption.align = HALIGN_CENTER
		caption.valign = VALIGN_CENTER
		caption.clip_text = true
		caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var display_message = short_message if short_message.length() <= 18 else short_message.substr(0, 17) + "…"
		caption.text = display_message + "\n" + commit_hash.substr(0, 7)
		caption.set("custom_fonts/font", FONT_BODY)
		caption.set("custom_colors/font_color", ORANGE if feature_hashes.has(commit_hash) else GREEN)
		button.add_child(caption)
		button.clip_text = true
		button.hint_tooltip = "%s\nAbrir sin cambiar de rama" % short_message
		button.set("custom_fonts/font", FONT_MONO)
		var node_color = ORANGE if feature_hashes.has(commit_hash) else GREEN
		button.set("custom_colors/font_color", node_color)
		button.set("custom_colors/font_color_hover", node_color)
		button.add_stylebox_override("normal", _button_style(PAPER, node_color, 2))
		button.add_stylebox_override("hover", _button_style(Color("f6eddc"), node_color, 3))
		button.add_stylebox_override("pressed", _button_style(Color("eadfc9"), node_color, 3))
		button.connect("pressed", self, "_select_commit", [commit_hash])
		add_child(button)
	update()


func _draw():
	if _commits.empty():
		return
	for commit in _commits:
		var child_hash = str(commit.get("hash", ""))
		if not _positions.has(child_hash):
			continue
		for parent_hash_value in commit.get("parents", []):
			var parent_hash = str(parent_hash_value)
			if not _positions.has(parent_hash):
				continue
			var start = _positions[parent_hash]
			var finish = _positions[child_hash]
			var color = ORANGE if abs(start.y - finish.y) > 4 else (ORANGE if finish.y > 70 else GREEN)
			var bend_a = Vector2(start.x + 42, start.y)
			var bend_b = Vector2(finish.x - 42, finish.y)
			draw_polyline(PoolVector2Array([start, bend_a, bend_b, finish]), color, 4, true)


func _feature_lane_hashes(commits, branches):
	var by_hash = {}
	for commit in commits:
		by_hash[str(commit.get("hash", ""))] = commit
	var feature_head = str(branches.get("exploracion-cta", ""))
	if feature_head == "":
		return {}
	var main_first_parent = {}
	var cursor = str(branches.get("main", ""))
	while cursor != "" and by_hash.has(cursor):
		main_first_parent[cursor] = true
		var parents = by_hash[cursor].get("parents", [])
		cursor = str(parents[0]) if parents.size() > 0 else ""
	var feature = {}
	cursor = feature_head
	while cursor != "" and by_hash.has(cursor) and not main_first_parent.has(cursor):
		feature[cursor] = true
		var parents = by_hash[cursor].get("parents", [])
		cursor = str(parents[0]) if parents.size() > 0 else ""
	return feature


func _lane_label(text, color):
	var label = Label.new()
	label.rect_size = Vector2(160, 58)
	label.text = text
	label.valign = VALIGN_CENTER
	label.set("custom_fonts/font", FONT_MONO)
	label.set("custom_colors/font_color", color)
	return label


func _button_style(color, border_color, border_width):
	var style = StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border_color
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(3)
	return style


func _select_commit(commit_hash):
	emit_signal("commit_selected", commit_hash)
