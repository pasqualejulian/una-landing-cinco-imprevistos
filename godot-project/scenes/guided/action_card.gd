extends PanelContainer

signal selected(card_id)

var card_id = ""
var title = ""
var destination = ""


func configure(new_id, new_title, new_destination):
	card_id = new_id
	title = new_title
	destination = new_destination
	$Margin/Rows/Title.text = title
	$Margin/Rows/Destination.text = "Llevar a: " + destination
	$Margin/Rows/Hint.text = "Click o arrastrar"


func _gui_input(event):
	if event is InputEventMouseButton and event.button_index == BUTTON_LEFT and event.pressed:
		emit_signal("selected", card_id)
		accept_event()


func get_drag_data(_position):
	var preview = PanelContainer.new()
	preview.rect_min_size = Vector2(190, 54)
	var label = Label.new()
	label.text = title
	label.align = HALIGN_CENTER
	label.valign = VALIGN_CENTER
	label.set("custom_fonts/font", preload("res://fonts/default.tres"))
	preview.add_child(label)
	set_drag_preview(preview)
	return {"kind": "guided_card", "card_id": card_id}

