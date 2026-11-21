@tool
extends Container

func _get_minimum_size() -> Vector2:
	return Vector2(0, 350)

func _notification(what: int) -> void:
	if what != NOTIFICATION_SORT_CHILDREN or get_child_count() < 2: return
	var width := (size.x - 10) / 2
	fit_child_in_rect(get_child(0), Rect2(0, 0, width, size.y))
	fit_child_in_rect(get_child(1), Rect2(width + 10, 0, width, size.y))
