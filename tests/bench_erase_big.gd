extends SceneTree
## **大物体**擦除基准：网格构建的代价随物体尺寸走，而一笔擦除只动一小块。
##
## ⚠️ 为什么要单独一条：tests/bench_erase_interior.gd 用的是 768x100 地面，
##    那个尺寸下 build_grid 只占擦除的 ~35%；物体一大它就成了绝对大头 ——
##    2048x128 实测 build_grid 17.4 ms / 整笔 39.0 ms（45%），而它跟
##    "这一笔改了哪里"完全无关。
##
## 判据（自校验增量网格，见 GreedyRects._build_grid）：
##    build_grid 2048x128: 17.35 -> 3.44 ms（5.0 倍）
##    整笔擦除            2048x128: 39.03 -> 28.02 ms/笔（-28%）
##    8 条基准逐位不变（矩形集合没变）。
const AddonWorld := preload("res://src/nodes/pixel_world.gd")
const AddonBody := preload("res://src/nodes/pixel_body_2d.gd")
const AddonShape := preload("res://src/nodes/pixel_shape_2d.gd")
const Editor := preload("res://src/core/pixel_editor.gd")
const GreedyRects := preload("res://src/core/greedy_rects.gd")

func _run(w: int, h: int) -> void:
	var pw = AddonWorld.new()
	var g = AddonBody.new()
	g.position = Vector2(0, 400)
	g.is_static = true
	pw.add_child(g)
	var gs = AddonShape.new()
	gs.rect_size = Vector2i(w, h)
	g.add_child(gs)
	get_root().add_child(pw)
	await process_frame
	await process_frame
	pw.rebuild()
	var ground = null
	for b in pw.world.bodies:
		if b.is_static:
			ground = b
			break
	pw.renderer.sync(ground)
	var s = ground.shapes[0]
	var t0 := Time.get_ticks_usec()
	var gg = GreedyRects._build_grid(s)
	var t_grid := (Time.get_ticks_usec() - t0) / 1000.0
	t0 = Time.get_ticks_usec()
	var rects = GreedyRects._greedy(gg.words.duplicate(), gg.wq, gg.w, gg.h, true)
	var t_g := (Time.get_ticks_usec() - t0) / 1000.0
	print("%5dx%-4d chunk %5d | build_grid %6.2f ms | greedy_h %6.2f ms | 初始矩形 %d" % [w, h, s.chunks.size(), t_grid, t_g, rects.size()])
	var steps := 10
	var total := 0.0
	var wy := float(400 + h / 2)
	for i in steps:
		var from := Vector2(60.0 + i * 40.0, wy)
		var t1 := Time.get_ticks_usec()
		Editor.erase(pw.world, from, from + Vector2(0, 1), 6.0, 25.0)
		pw.renderer.sync(ground)
		total += (Time.get_ticks_usec() - t1) / 1000.0
	var r2 = GreedyRects.decompose(s, 64)
	print("        内部擦除 %6.2f ms/笔   擦完矩形 %d" % [total / float(steps), r2.rects.size()])
	pw.free()

func _initialize() -> void:
	await _run(768, 100)
	await _run(2048, 128)
	await _run(4096, 64)
	quit(0)
