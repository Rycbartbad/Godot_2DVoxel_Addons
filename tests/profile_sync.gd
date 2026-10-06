extends SceneTree
## renderer.sync 的**分段成本** —— 下一个渲染优化的入口。
##
## 2026-10 实测（768x100 地面，10 笔内部擦除）：
##   _local_bounds            0.000 ms（AABB 缓存后已免费）
##   _content_revision        0.000 ms
##   _build_region_image 64x64 实心块  **2.41 ms**  <- 逐像素循环，sync 的几乎全部成本
##   _take_dirty_rect         0.014 ms（一笔擦除的脏矩形只有 24x24）
##   sync 总（改前）           3.04 ms/笔
##   sync 总（改后）           0.36 ms/笔  <- 只画"脏矩形 ∩ 本块"再 blit 进持久图
##
## 教训：脏矩形 24x24 = 576 像素，而整块 64x64 = 4096 像素 —— **7 倍浪费**。
##      "按块重建"如果块粒度远大于改动粒度，省下的只是"别的块"。
const AddonWorld := preload("res://src/nodes/pixel_world.gd")
const AddonBody := preload("res://src/nodes/pixel_body_2d.gd")
const AddonShape := preload("res://src/nodes/pixel_shape_2d.gd")
const Editor := preload("res://src/core/pixel_editor.gd")

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
	var r = pw.renderer
	r.sync(ground)
	var aabb = r._local_bounds(ground)
	var t0 := Time.get_ticks_usec()
	for i in 20:
		r._local_bounds(ground)
	print("  _local_bounds              %7.3f ms" % ((Time.get_ticks_usec() - t0) / 20.0 / 1000.0))
	t0 = Time.get_ticks_usec()
	for i in 20:
		r._content_revision(ground)
	print("  _content_revision          %7.3f ms" % ((Time.get_ticks_usec() - t0) / 20.0 / 1000.0))
	var tr := Rect2i(0, 0, 64, 64)
	t0 = Time.get_ticks_usec()
	for i in 20:
		r._build_region_image(ground.shapes, aabb, tr)
	print("  _build_region_image 64x64  %7.3f ms  <- 分发入口（现在是原生）" % ((Time.get_ticks_usec() - t0) / 20.0 / 1000.0))
	t0 = Time.get_ticks_usec()
	for i in 20:
		r._build_region_image_gd(ground.shapes, aabb, tr)
	print("  同上（GDScript 参照实现）   %7.3f ms  <- 0.65 us/像素，只在缺扩展/shading 时走" % ((Time.get_ticks_usec() - t0) / 20.0 / 1000.0))
	Editor.erase(pw.world, Vector2(300.0, 270.0), Vector2(300.0, 271.0), 6.0, 25.0)
	t0 = Time.get_ticks_usec()
	var dr = r._take_dirty_rect(ground, aabb)
	print("  _take_dirty_rect           %7.3f ms  -> %s" % [(Time.get_ticks_usec() - t0) / 1000.0, str(dr)])
	var steps := 10
	var total := 0.0
	var rebuilt := 0
	for i in steps:
		Editor.erase(pw.world, Vector2(60.0 + i * 40.0, 270.0), Vector2(60.0 + i * 40.0, 271.0), 6.0, 25.0)
		t0 = Time.get_ticks_usec()
		r.sync(ground)
		total += (Time.get_ticks_usec() - t0) / 1000.0
		rebuilt += r.last_tiles_rebuilt
	print("  sync 总                    %7.3f ms/笔（平均重建 %.1f 块）" % [total / float(steps), float(rebuilt) / float(steps)])
	quit(0)
