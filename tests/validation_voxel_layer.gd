extends SceneTree
## 第 1 层验证：aux 逐体素辅助表 + 脏区域跟踪
## 并隔离测量脏标记的开销（直接改 chunk vs 走 set_pixel）
const PixelShape := preload("res://src/core/pixel_shape.gd")
const PixelChunk := preload("res://src/core/pixel_chunk.gd")
const Destruction := preload("res://src/core/destruction.gd")

var _pass := 0
var _fail := 0
func _c(n: String, ok: bool, d: String = "") -> void:
	if ok:
		_pass += 1
		print("  PASS  ", n, "  ", d)
	else:
		_fail += 1
		print("  FAIL  ", n, "  ", d)

func _initialize() -> void:
	print("=== aux 辅助表 ===")
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, 16, 16), 1)
	_c("初始 aux 全 0", s.get_aux(3, 3) == 0)
	s.set_aux(3, 3, 200)
	_c("set_aux / get_aux", s.get_aux(3, 3) == 200)
	s.set_pixel(3, 3, 2)
	_c("改材质不动 aux（损伤要保留）", s.get_aux(3, 3) == 200, "%d" % s.get_aux(3, 3))
	s.clear_pixel(3, 3)
	_c("清像素会把 aux 归零", s.get_aux(3, 3) == 0)

	# clone 保留 aux
	var c: PixelChunk = s.chunk_at(0, 0)
	c.aux[0] = 77
	var c2 = c.clone()
	_c("clone 带 aux", c2.aux[0] == 77)

	# 切分保留 aux
	var s2 := PixelShape.new()
	s2.fill_rect(Rect2i(0, 0, 20, 4), 1)
	s2.fill_rect(Rect2i(0, 8, 20, 4), 1)
	s2.set_aux(5, 1, 123)
	s2.set_aux(5, 9, 45)
	var parts: Array = Destruction.split(s2, 1)
	# ⚠️ 分量顺序不保证（_components_cpu 返回的是 Dictionary），
	# 所以要**在所有块里找**哪一个含 (5,9)，不能假定 parts[0]
	var found := -1
	for p in parts:
		if (p as PixelShape).get_aux(5, 9) == 45:
			found = 45
	_c("切分后 aux 跟着走", found == 45, "在主形状 %d / 在分块 %d" % [s2.get_aux(5, 9), found])

	# 删除像素时 aux 清掉
	var s3 := PixelShape.new()
	s3.fill_rect(Rect2i(0, 0, 8, 8), 1)
	s3.set_aux(2, 2, 99)
	var d := Destruction.Damage.circle(Vector2(2.0, 2.0), 1.0)
	Destruction.apply_damage(s3, d)
	_c("破坏掉的像素 aux 归零", s3.get_aux(2, 2) == 0)

	print("=== 脏区域跟踪 ===")
	var s4 := PixelShape.new()
	s4.clear_dirty()
	_c("初始无脏块", not s4.has_dirty())
	s4.set_pixel(0, 0, 1)
	s4.set_pixel(1, 0, 1)
	_c("同 chunk 多次写只记一次", s4.dirty_chunks().size() == 1,
		"%d 个脏块" % s4.dirty_chunks().size())
	s4.set_pixel(100, 100, 1)
	_c("跨 chunk 会各记一次", s4.dirty_chunks().size() == 2, "%d 个脏块" % s4.dirty_chunks().size())
	s4.clear_dirty()
	_c("clear_dirty 生效", not s4.has_dirty())
	s4.set_aux(0, 0, 5)
	_c("set_aux 也会标脏", s4.has_dirty())
	s4.clear_dirty()
	s4.clear_pixel(0, 0)
	_c("clear_pixel 也会标脏", s4.has_dirty())
	# 批量直写不会自动标脏（文档里写明了）
	s4.clear_dirty()
	var ch: PixelChunk = s4.chunk_at(0, 0)
	ch.mat[0] = 9
	_c("直改 chunk.mat 不自动标脏（需手动 mark_dirty）", not s4.has_dirty())
	s4.mark_dirty(0, 0)
	_c("手动 mark_dirty 生效", s4.has_dirty())

	print("=== 脏标记的开销（隔离测量）===")
	var N := 200000
	var a := PixelShape.new()
	var t0 := Time.get_ticks_usec()
	for i in N:
		a.set_pixel(i & 255, (i >> 8) & 255, 1)
	var t1 := Time.get_ticks_usec()
	var b := PixelShape.new()
	# 预热，保证 chunk 都在
	b.fill_rect(Rect2i(0, 0, 256, 256), 1)
	var t2 := Time.get_ticks_usec()
	for i in N:
		var cx := (i & 255) >> 3
		var cy := ((i >> 8) & 255) >> 3
		var ck: PixelChunk = b.chunk_at(cx, cy)
		ck.mat[((i >> 8) & 255 & 7) * 8 + (i & 7)] = 1
	var t3 := Time.get_ticks_usec()
	print("  set_pixel（含 chunk 查找+创建+标脏） %9.1f us  -> %6.1f ns/像素" % [t1 - t0, float(t1 - t0) * 1000.0 / N])
	print("  直改 chunk.mat（批量路径）          %9.1f us  -> %6.1f ns/像素" % [t3 - t2, float(t3 - t2) * 1000.0 / N])
	# 单独隔离 mark_dirty：上面两条都被 GDScript 的调用开销主导，看不出标脏本身多贵
	var t4 := Time.get_ticks_usec()
	for i in N:
		a.mark_dirty((i & 255) >> 3, ((i >> 8) & 255) >> 3)
	var t5 := Time.get_ticks_usec()
	print("  单独 mark_dirty（已脏时早退）       %9.1f us  -> %6.1f ns/次" % [t5 - t4, float(t5 - t4) * 1000.0 / N])
	print("  => 标脏本身很便宜（一次查表）；set_pixel 慢在多层函数调用。")
	print("     元胞自动机请走**批量路径**（直改 chunk.mat/aux + 每个 chunk 手动 mark_dirty 一次）")

	print("=== %d passed, %d failed ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
