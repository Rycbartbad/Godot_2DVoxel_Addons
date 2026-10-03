extends SceneTree
## split（连通性分裂）的**分段成本** —— "擦到边界那一下卡"就是这个。
##
## 2026-10 实测（768x100 地面，1248 个 chunk）：
##   split 总计              31.46 -> **8.13 ms**
##   └ chunks.keys()          0.007 ms
##   └ _components_cpu        1.72 ms（并行 13 线程）
##   └ _group（union-find）   27.12 -> **5.03 ms**   <- 热点在这里
##   └ _assemble              28.37 -> 5.08 ms（含 _group；单分量时直接返回原 shape）
##   擦到边界整笔             36.21 -> **14.09 ms/笔**（内部挖洞 2.84）
##
## 教训：热点是**接缝 union 的重复** —— 实心块每边 8 个接缝 bit，旧代码逐 bit union，
##      1248 块 = 2 万次；而两边都只有 1 个分量时它们连的是同一对 node。
##      "按 bit 处理"看着严谨，但**同一对节点的重复 union** 是纯浪费。
const AddonWorld := preload("res://src/nodes/pixel_world.gd")
const AddonBody := preload("res://src/nodes/pixel_body_2d.gd")
const AddonShape := preload("res://src/nodes/pixel_shape_2d.gd")
const Editor := preload("res://src/core/pixel_editor.gd")
const Destruction := preload("res://src/core/destruction.gd")

func _initialize() -> void:
	var pw = AddonWorld.new()
	var g = AddonBody.new()
	g.position = Vector2(0, 220)
	g.is_static = true
	pw.add_child(g)
	var gs = AddonShape.new()
	gs.rect_size = Vector2i(768, 100)
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
	var s = ground.shapes[0]
	var t0 := Time.get_ticks_usec()
	for q in 5:
		Destruction.split(s, 25)
	print("  Destruction.split（全量连通分量）  %7.2f ms" % ((Time.get_ticks_usec() - t0) / 5.0 / 1000.0))
	var keys: Array = s.chunks.keys()
	var parts = Destruction._components_cpu(s, keys)
	t0 = Time.get_ticks_usec()
	for q3 in 5:
		Destruction._group(s, keys, parts)
	print("  └ _group（union-find）              %7.2f ms" % ((Time.get_ticks_usec() - t0) / 5.0 / 1000.0))
	t0 = Time.get_ticks_usec()
	for q4 in 5:
		Destruction._assemble(s, keys, parts, 25)
	print("  └ _assemble                         %7.2f ms" % ((Time.get_ticks_usec() - t0) / 5.0 / 1000.0))
	var total := 0.0
	var steps := 6
	for i in steps:
		var from := Vector2(80.0 + i * 90.0, 221.0)
		var t2 := Time.get_ticks_usec()
		Editor.erase(pw.world, from, from + Vector2(0, 6), 5.0, 25.0)
		total += (Time.get_ticks_usec() - t2) / 1000.0
	print("  擦到边界（含 split + 生成碎片）      %7.2f ms/笔" % (total / float(steps)))
	quit(0)
