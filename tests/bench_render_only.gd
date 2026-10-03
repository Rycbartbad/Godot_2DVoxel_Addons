extends SceneTree
## 纯渲染成本 —— 走**真实路径**（Editor.erase 会标脏块）。
##
## 对照：
##   分块之前            ~44 ms/笔（整张 768x100 重建 + 上传）
##   分块后但每块扫全局   821 ms/笔（每块遍历全部 1248 个 chunk）
##   现在                ?
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

	var STEPS := 10
	var total := 0.0
	var rebuilt := 0
	for i in STEPS:
		var wx := 60.0 + i * 60.0
		Editor.erase(pw.world, Vector2(wx, world_y), Vector2(wx, world_y + 1.0), 6.0, 25.0)
		var t := Time.get_ticks_usec()
		pw.renderer.sync(ground)
		total += (Time.get_ticks_usec() - t) / 1000.0
		rebuilt += pw.renderer.last_tiles_rebuilt
	print("  %-8s 每笔 sync %6.2f ms（平均重建 %.1f/24 块）" % [
		label, total / float(STEPS), float(rebuilt) / float(STEPS)])

func _initialize() -> void:
	print("=== 纯渲染成本（真实擦除路径）===")
	await _run("内部", 270.0)
	await _run("边缘", 205.0)
	quit(0)
