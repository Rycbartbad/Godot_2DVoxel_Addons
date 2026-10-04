extends SceneTree
## **每帧 sync 到底在干什么** —— 用渲染器自带的诊断字段（last_debug / last_tiles_rebuilt）直接回答。
##
## ⚠️⚠️ 这个探针的存在理由是一次**测量假象**：早先的 diag_frame_cost 把 20 帧**平均**，
##    而第 0 帧要把整张形状的块全部建出来（1000 矩形 / 128 块 = **137 ms**），
##    被摊进去之后得到 6.5 ms/帧，于是被当成"每帧 sync 6.5 ms（= 6.5 us/矩形）"写进了报告。
##    逐帧看真相完全不同：
##      第 0 帧（首次）      137.3 ms   重建 128/128 块   <- 建块，一次性
##      第 1 帧起（无变化）  0.007~0.031 ms              <- 查 revision 就早退
##
##    教训：**热路径的性能数字必须逐帧看**，平均值会把一次性的初始化成本摊成"每帧成本"，
##    从而把优化方向指错（我据此差点去优化一个 0.01 ms 的路径）。
##
## 同时它量出一个真成本：**首次建块 ≈ 1 ms / 64px 块** —— 生成碎片那一下里，
## 渲染侧的这一份是 ~12 ms（12 块）。那是 GDScript 逐像素填充的地板
## （~0.25 us/像素），要再快只能走原生或复用母体已有的块图。
const AddonWorld := preload("res://src/nodes/pixel_world.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")
const PBody := preload("res://src/physics/pbody.gd")

func _initialize() -> void:
	var pw = AddonWorld.new()
	get_root().add_child(pw)
	await process_frame
	var w = pw.world
	var r = pw.renderer
	var s := PixelShape.new()
	for j in 1000:
		s.fill_rect(Rect2i(0, j * 2, 200, 1), 1)
	var b := PBody.new()
	w.add_body(b, [s], Callable(), true)
	print("矩形 %d，chunk %d，形状 revision %d / range %d" % [b.rects.size(), s.chunks.size(), s.revision, s.range_revision])
	for i in 6:
		var t0 := Time.get_ticks_usec()
		r.sync(b)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		print("帧%d sync %7.3f ms | 重建块 %d/%d | %s" % [i, ms, r.last_tiles_rebuilt, r.last_tiles_total, r.last_debug])
		b.position.y += 1.0        # 模拟"在动"
	print("--- 静止不再动 ---")
	for i in 3:
		var t0 := Time.get_ticks_usec()
		r.sync(b)
		print("帧%d sync %7.3f ms | 重建块 %d/%d | %s" % [i, (Time.get_ticks_usec() - t0) / 1000.0, r.last_tiles_rebuilt, r.last_tiles_total, r.last_debug])
	quit(0)
