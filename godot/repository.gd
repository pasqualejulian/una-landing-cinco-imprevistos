extends "res://scenes/repository.gd"

var graph = {}

func update_everything():
	graph = parse_json(JavaScript.eval("JSON.stringify(window.OMG.graph())"))
	var old_ids = objects.keys()
	.update_everything()
	var depth = {}
	for commit in graph["commits"]:
		var d = 0
		for parent in commit["parents"]:
			d = max(d, depth.get(parent, 0) + 1)
		depth[commit["hash"]] = d
		var item = objects[commit["hash"]]
		item.get_node("ID").text = commit["caption"]
		if not commit["hash"] in old_ids:
			item.position = Vector2(250 + d * 155, 300 if commit["caption"].begins_with("02") else 445)
	for ref in graph["refs"]:
		var key = "refs/heads/" + ref
		if not key in old_ids:
			objects[key].position = objects[graph["refs"][ref]].position + Vector2(100, -60)
		if ref == "experimento-wording":
			objects[key].get_node("ID").text = "wording"

func there_is_a_git():
	return true

func all_objects():
	var result = {}
	for commit in graph["commits"]:
		result[commit["hash"]] = ""
	return result

func all_refs():
	var result = {}
	for ref in graph["refs"]:
		result["refs/heads/" + ref] = ""
	return result

func object_type(_id):
	return "commit"

func object_content(id):
	for commit in graph["commits"]:
		if commit["hash"] == id:
			return commit["caption"] + "\n" + commit["message"]
	return ""

func commit_parents(id):
	for commit in graph["commits"]:
		if commit["hash"] == id:
			return commit["parents"]
	return []

func ref_target(ref):
	if ref == "HEAD":
		return "refs/heads/" + graph["branch"]
	return graph["refs"].get(ref.replace("refs/heads/", ""), graph["head"])

func update_node_positions():
	# First positions are assigned above. Later refreshes keep original physics
	# and existing instances, so the player's timeline does not get rebuilt.
	pass
