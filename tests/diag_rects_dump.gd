extends SceneTree
const AddonWorld := preload("res://src/nodes/pixel_world.gd")
const AddonBody := preload("res://src/nodes/pixel_body_2d.gd")
const AddonShape := preload("res://src/nodes/pixel_shape_2d.gd")

func _initialize() -> void:
	var pw = AddonWorld.new()
	var g = AddonBody.new(); g.position = Vector2(0, 220); g.is_static = true
	pw.add_child(g)
	var gs = AddonShape.new(); gs.rect_size = Vector2i(768, 100); g.add_child(gs)
	get_root().add_child(pw)
	await process_frame
	await process_frame
	pw.rebuild()
	var b = null
	for x in pw.world.bodies:
		if x.is_static: b = x; break
	print("形状 aabb = ", b.shapes[0].local_aabb(), "  px=", b.shapes[0].pixel_count())
	print("rects 数 = ", b.rects.size())
	for i in mini(4, b.rects.size()):
		print("  rect[%d] = %s" % [i, str(b.rects[i])])
	quit(0)
