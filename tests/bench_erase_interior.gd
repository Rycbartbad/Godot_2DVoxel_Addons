extends SceneTree
## 内部擦除 vs 边缘擦除 —— 分块贴图的收益只在**内部**才有。
##
## ⚠️ 为什么：擦到边缘会改变体局部 AABB，而 AABB 一变，块格覆盖范围就变，
##    只能全量重建（那是**正确行为**，不是退化）。
##    tests/bench_erase.gd 擦的是世界 y 200~260，地面在 y 220 ——
##    正好是地面的**上边缘**，所以它量到的一直是全量重建的成本。
const AddonWorld := preload("res://src/nodes/pixel_world.gd")
const AddonBody := preload("res://src/nodes/pixel_body_2d.gd")
const AddonShape := preload("res://src/nodes/pixel_shape_2d.gd")
const Editor := preload("res://src/core/pixel_editor.gd")

func _run(label: String, world_y: float) -> void:
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
	pw.renderer.sync(ground)
	var aabb0: Rect2i = pw.renderer._bounds.get(ground.id, Rect2i())

	var STEPS := 10
	var total := 0.0
	for i in STEPS:
		var from := Vector2(60.0 + i * 40.0, world_y)
		var t0 := Time.get_ticks_usec()
		Editor.erase(pw.world, from, from + Vector2(0, 1), 6.0, 25.0)
		pw.renderer.sync(ground)
		total += (Time.get_ticks_usec() - t0) / 1000.0
	var aabb1: Rect2i = pw.renderer._bounds.get(ground.id, Rect2i())
	print("  %-14s 世界 y=%5.0f | %6.2f ms/笔 | AABB %s -> %s" % [
		label, world_y, total / float(STEPS),
		"变" if aabb0 != aabb1 else "不变", "（局部 y=%d..%d）" % [aabb1.position.y, aabb1.position.y + aabb1.size.y]])

func _initialize() -> void:
	print("=== 内部 vs 边缘擦除（地面在 y=220，局部 0..100）===")
	await _run("边缘（上沿）", 200.0)
	await _run("内部", 270.0)
	await _run("内部偏上", 240.0)
	quit(0)
