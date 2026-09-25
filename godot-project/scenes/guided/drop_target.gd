extends PanelContainer

signal activated(target_id)
signal card_dropped(card_id, target_id)

var target_id = ""


func configure(new_id, text):
	target_id = new_id
	$Label.text = text


func _gui_input(event):
	if event is InputEventMouseButton and event.button_index == BUTTON_LEFT and event.pressed:
		emit_signal("activated", target_id)
		accept_event()


func can_drop_data(_position, data):
	return typeof(data) == TYPE_DICTIONARY and data.get("kind", "") == "guided_card"


func drop_data(_position, data):
	emit_signal("card_dropped", data.get("card_id", ""), target_id)

