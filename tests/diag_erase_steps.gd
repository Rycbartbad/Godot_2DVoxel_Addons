extends SceneTree
## Editor.erase 内部逐步计时 —— 不再猜，直接量。
const AddonWorld := preload("res://src/nodes/pixel_world.gd")
const AddonBody := preload("res://src/nodes/pixel_body_2d.gd")
const AddonShape := preload("res://src/nodes/pixel_shape_2d.gd")
const Destruction := preload("res://src/core/destruction.gd")

func _initialize() -> void:
	print("=== Editor.erase 内部逐步（内部擦除，局部 y=50）===")
	var pw = AddonWorld.new()
	var g = AddonBody.new(); g.position = Vector2(0, 220); g.is_static = true
	pw.add_child(g)
	var gs = AddonShape.new(); gs.rect_size = Vector2i(768, 100); g.add_child(gs)
	get_root().add_child(pw)
	await process_frame
	await process_frame
	pw.rebuild()
	var ground = null
	for b in pw.world.bodies:
		if b.is_static: ground = b; break

	print("笔画  数前  segment  fracture  数后  数碎片  合计")
	for i in 6:
		var wx := 80.0 + i * 90.0
		var wy := 270.0
		var t0 := Time.get_ticks_usec()
		var before := 0
		for s in ground.shapes: before += s.pixel_count()
		var t1 := Time.get_ticks_usec()
		var d = Destruction.Damage.segment(
			ground.to_local(Vector2(wx, wy)), ground.to_local(Vector2(wx, wy + 1)), 6.0)
		var t2 := Time.get_ticks_usec()
		var spawned: Array = pw.world.fracture(ground, d, 25.0)
		var t3 := Time.get_ticks_usec()
		var after := 0
		for s2 in ground.shapes: after += s2.pixel_count()
		var t4 := Time.get_ticks_usec()
		var moved := 0
		for f in spawned:
			for sf in f.shapes: moved += sf.pixel_count()
		var t5 := Time.get_ticks_usec()
		print("%3d  %5.2f  %6.2f  %7.2f  %5.2f  %6.2f  %6.2f" % [
			i, (t1-t0)/1000.0, (t2-t1)/1000.0, (t3-t2)/1000.0,
			(t4-t3)/1000.0, (t5-t4)/1000.0, (t5-t0)/1000.0])
	quit(0)
