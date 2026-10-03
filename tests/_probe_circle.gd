extends SceneTree
func _initialize() -> void:
	var Body := load("res://src/nodes/pixel_body_2d.gd")
	var b: Node2D = Body.new()
	b.source = 1          # Source.CIRCLE
	b.radius = 8.0
	b.scale = Vector2(1, 1)
	var s1 = b.get_shape()
	print("  1:1  外接 ", s1.get_bounds(), " 体素 ", s1.count_solid())
	b.scale = Vector2(2, 1)
	var s2 = b.get_shape()
	print("  2:1  外接 ", s2.get_bounds(), " 体素 ", s2.count_solid())
	var bd = s2.get_bounds()
	print("  宽高比 = ", float(bd.size.x) / float(bd.size.y), "（2:1 缩放应当约等于 2）")
	b.free()
	quit(0)
