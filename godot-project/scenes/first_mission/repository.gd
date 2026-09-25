extends "res://scenes/repository.gd"

# Scope filtering to this mission. Internal checkpoint refs and discarded
# attempts remain in Git but never appear as extra exercise nodes.
func all_objects():
	var result = {}
	for hash_id in git("rev-list HEAD", true):
		result[hash_id] = ""
	return result

func all_refs():
	return {"refs/heads/main": ""}
