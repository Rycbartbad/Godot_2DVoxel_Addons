extends SceneTree
## 位网格缓存的闸门：**带缓存建出来的网格必须与全量重建逐位相同**。
##
## ⚠️ 为什么这条是硬的：网格逐位相同 => 贪心结果相同 => 矩形集合相同 =>
##    8 条基准逐位不变。反过来，网格错了是**不报错**的 ——
##    只会让形状与碰撞箱静默错位（用户报过两次）。
##
## 覆盖：
##   1. 每一条写入路径（set_pixel / clear_pixel / add_pixel / fill_rect /
##      apply_damage / mark_dirty_range / touch / translate_pixels）
##   2. **直接改 chunk.occ** —— 模拟原生破坏那条不经过任何标记的路
##   3. AABB 变化（擦到边界 / 补回来）—— 布局跟着 AABB 走，必须整块重建且仍然正确
##   4. 内联的键运算 vs PixelShape 的助手（含**负坐标**；负坐标上"加法写法"会进位）

const GreedyRects := preload("res://src/core/greedy_rects.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")
const PixelChunk := preload("res://src/core/pixel_chunk.gd")
const Bits := preload("res://src/core/pixel_bits.gd")
const Destruction := preload("res://src/core/destruction.gd")

const W := 256
const H := 96

var passed := 0
var failed := 0

func _assert(cond: bool, msg: String) -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		if failed <= 8:
			print("  [失败] " + msg)

func _same(a: PackedInt64Array, b: PackedInt64Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if a[i] != b[i]:
			return false
	return true

## 冷网格：把缓存整个丢掉，_build_grid 会走全量重建 —— 这就是参照实现。
func _cold(s: PixelShape) -> PackedInt64Array:
	s._grid_ready = false
	s._grid_sigs.clear()
	s._grid_keys.clear()
	return GreedyRects._build_grid(s).words

func _check(s: PixelShape, label: String) -> void:
	var warm := GreedyRects._build_grid(s).words
	var cold := _cold(s)
	_assert(_same(warm, cold), "%s：带缓存的网格与全量重建不一致（%d vs %d 个 word）" % [label, warm.size(), cold.size()])
	var warm2 := GreedyRects._build_grid(s).words
	_assert(_same(warm, warm2), "%s：连续两次建网格结果不同" % label)

func _solid(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	for y in h:
		for x in w:
			s.set_pixel(x, y, 1)
	return s

func _initialize() -> void:
	print("=== 位网格缓存：带缓存 vs 全量重建 ===")
	# 4) 键运算等价性（先查公式，再查网格）
	var key_bad := 0
	for cx in [-9, -8, -1, 0, 1, 7, 8, 63, 64, 100, -100]:
		for cy in [-9, -8, -1, 0, 5, 8, -8]:
			var k := PixelShape.make_key(cx, cy)
			var inline_bk := ((k >> 35) << 32) | (((k << 32) >> 35) & 0xFFFFFFFF)
			if inline_bk != PixelShape.make_key(cx >> 3, cy >> 3):
				key_bad += 1
			var inlined_chunk: int = ((cx << 3) << 32) | ((cy << 3) & 0xFFFFFFFF)
			if inlined_chunk != PixelShape.make_key(cx << 3, cy << 3):
				key_bad += 1
	_assert(key_bad == 0, "内联键运算与助手不一致（%d 处，负坐标最容易错）" % key_bad)

	var rng := RandomNumberGenerator.new()
	rng.seed = 20261005
	var s := _solid(W, H)
	_check(s, "初始实心")
	s.clear_pixel(10, 10)
	_check(s, "clear_pixel")
	s.set_pixel(10, 10, 1)
	_check(s, "set_pixel 补回")
	s.add_pixel(3, 3, 1)
	_check(s, "add_pixel（已存在）")
	s.fill_rect(Rect2i(20, 20, 9, 5), 0)
	_check(s, "fill_rect 挖洞")
	s.fill_rect(Rect2i(20, 20, 9, 5), 1)
	_check(s, "fill_rect 补回")
	Destruction.apply_damage(s, Destruction.Damage.circle(Vector2(60.0, 30.0), 7.0))
	_check(s, "apply_damage（原生路径）")
	s.mark_dirty_range(Rect2i(0, 0, W, H))
	_check(s, "mark_dirty_range（只标脏）")
	s.touch()
	_check(s, "touch")
	# 直接改块位图：绕过所有标记
	var c0 := s.chunk_at(2, 2)
	c0.occ &= ~Bits.row_mask(3)
	_check(s, "直接改 chunk.occ（绕过所有标记）")
	# 整块清空 + 整块重建（chunk 被 erase / 新建）
	var c1 := s.chunk_at(1, 1)
	c1.occ = 0
	s.chunks.erase(PixelShape.make_key(1, 1))
	_check(s, "整块清空（chunk 被 erase）")
	s.fill_rect(Rect2i(8, 8, 8, 8), 1)
	_check(s, "整块重建（新 chunk）")
	# 随机变异
	for it in 40:
		var op := rng.randi_range(0, 6)
		match op:
			0:
				s.fill_rect(Rect2i(rng.randi_range(0, W - 1), rng.randi_range(0, H - 1), rng.randi_range(1, 14), rng.randi_range(1, 14)), 0)
			1:
				s.fill_rect(Rect2i(rng.randi_range(0, W - 1), rng.randi_range(0, H - 1), rng.randi_range(1, 14), rng.randi_range(1, 14)), 1)
			2:
				Destruction.apply_damage(s, Destruction.Damage.circle(Vector2(rng.randi_range(0, W), rng.randi_range(0, H)), rng.randf_range(2.0, 10.0)))
			3:
				s.clear_pixel(rng.randi_range(0, W - 1), rng.randi_range(0, H - 1))
			4:
				s.set_pixel(rng.randi_range(0, W - 1), rng.randi_range(0, H - 1), 1)
			5:
				var cc := s.chunk_or_create(rng.randi_range(0, (W >> 3) - 1), rng.randi_range(0, (H >> 3) - 1))
				cc.occ &= ~(1 << rng.randi_range(0, 63))
			6:
				s.touch()
		_check(s, "随机 #%d op=%d" % [it, op])
	# 3) AABB 变化：擦掉整条上边 -> AABB 必须缩，且网格仍然正确
	for i in 40:
		Destruction.apply_damage(s, Destruction.Damage.circle(Vector2(float(i * 6 + 2), 0.0), 5.0))
	_check(s, "擦掉上边界（AABB 缩）")
	s.fill_rect(Rect2i(0, 0, W, 4), 1)
	_check(s, "补回上边界（AABB 涨）")
	# 负坐标：整个形状平移到负区
	s.translate_pixels(-30, -20)
	_check(s, "translate_pixels（负坐标）")
	print("---")
	var g := GreedyRects._build_grid(s)
	print("网格 %dx%d（wq=%d，%d 个 word），块 %d 个" % [g.w, g.h, g.wq, g.words.size(), s._grid_keys.size()])
	if failed == 0:
		print("全部通过：%d 项断言" % passed)
	else:
		print("失败 %d / %d 项" % [failed, passed + failed])
	quit(0 if failed == 0 else 1)
