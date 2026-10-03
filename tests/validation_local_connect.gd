extends SceneTree
## 局部连通判据（Destruction.local_connectivity）的**安全性闸门**。
##
## ⚠️⚠️ 这个判据是"破坏后仍然连通"的**充分**条件，判错的方向只有一个：
##    说了"连通"但其实裂开了 -> 形状数据断了而 rects 没重算 ->
##    **画出来的形状和碰撞体不一致**（用户报过两次）。
##    所以参照物必须是**全量连通分量标注**（Destruction.split），
##    而判据的每一次"连通"结论都要被它验证。
##
## 反过来不要求："判不出来"永远允许（退回全量，只是慢）。
##
## ⚠️ 多岛屿形状这一例：定理的前提是"破坏前连通"，多岛屿不满足 ——
##    判据会说"连通"。
##    这个前提现在由**建造时保证**兜住了：PWorld.add_body 会把多岛屿 shape
##    就地拆成独立刚体（见 ensure_connected / validation_connected_body.gd），
##    所以进入世界的 body 一定满足前提。
##    这里保留这一例，是为了钉住**低层函数本身**的边界（它被直接调用时会发生什么），
##    而不是依赖调用方守规矩。
##    ⚠️ 它不是数据一致性问题：判据说"连通"时**不会改动形状**，
##    形状与 rects 仍然一致。

const PixelShape := preload("res://src/core/pixel_shape.gd")
const Destruction := preload("res://src/core/destruction.gd")

var passed := 0
var failed := 0
var applied := 0
var total := 0
var diff_ok := 0

func _assert(cond: bool, msg: String) -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		if failed <= 10:
			print("  [失败] " + msg)

func _rect(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	for y in h:
		for x in w:
			s.set_pixel(x, y, 1)
	return s

func _box_of(d) -> Rect2i:
	var b: Rect2 = d.bounds()
	return Rect2i(floori(b.position.x), floori(b.position.y), ceili(b.size.x) + 1, ceili(b.size.y) + 1)

## 在 shape 的副本上施加伤害，然后比对判据与全量标注
func _case(src: PixelShape, dmg, label: String, min_px: int = 25) -> void:
	var s := PixelShape.new()
	for k in src.chunks:
		var c = src.chunks[k]
		s.chunks[k] = c.clone()
	var removed := Destruction.apply_damage(s, dmg)
	var box := _box_of(dmg)
	var lc := Destruction.local_connectivity(s, box, min_px)
	var parts := Destruction.split(s, min_px)
	total += 1
	if lc == Destruction.LOCAL_UNKNOWN:
		return
	applied += 1
	if lc == Destruction.LOCAL_CONNECTED:
		if label.begins_with("多岛屿"):
			# 已知差异：前提（破坏前连通）不成立，所以这里**预期**与全量标注不同。
			_assert(parts.size() == 2, "%s：多岛屿的已知差异变了（全量标注给了 %d 块，预期 2）" % [label, parts.size()])
			diff_ok += 1
		else:
			_assert(parts.size() == 1, "%s：判据说连通，全量标注却是 %d 块（removed=%d）" % [label, parts.size(), removed])
	elif lc == Destruction.LOCAL_DROPPED:
		_assert(parts.is_empty(), "%s：判据说丢弃，全量标注却给了 %d 块" % [label, parts.size()])

func _initialize() -> void:
	print("=== 局部连通判据 vs 全量标注 ===")
	var big := _rect(768, 100)
	# 贴边界的小洞（用户报的场景）
	for i in 8:
		_case(big, Destruction.Damage.circle(Vector2(60.0 + i * 90.0, 1.0), 4.0), "大物体-上边界小洞#%d" % i)
		_case(big, Destruction.Damage.circle(Vector2(60.0 + i * 90.0, 99.0), 5.0), "大物体-下边界小洞#%d" % i)
	# 四个角
	for c in [Vector2(1, 1), Vector2(766, 1), Vector2(1, 98), Vector2(766, 98)]:
		_case(big, Destruction.Damage.circle(c, 6.0), "大物体-角 %s" % str(c))
	# 大半径（切得开，也超过探测框上限）
	_case(big, Destruction.Damage.circle(Vector2(384.0, 50.0), 60.0), "大物体-大半径 60")
	# 竖着切一刀（真的裂开）
	_case(big, Destruction.Damage.segment(Vector2(400.0, 0.0), Vector2(400.0, 99.0), 4.0), "大物体-竖切一刀")
	# 细杆：R 横跨杆宽 -> 必须退回全量
	var bar := _rect(200, 4)
	for i in 6:
		_case(bar, Destruction.Damage.circle(Vector2(30.0 + i * 25.0, 2.0), 4.0), "细杆-切断#%d" % i, 1)
	# 细杆但伤害没打穿
	_case(bar, Destruction.Damage.circle(Vector2(30.0, 2.0), 1.5), "细杆-小坑", 1)
	# 梳子 / 阶梯 / 环
	var comb := PixelShape.new()
	for y in 30:
		for x in 60:
			if (x / 10) % 2 == 0 or y < 4:
				comb.set_pixel(x, y, 1)
	_case(comb, Destruction.Damage.circle(Vector2(5.0, 29.0), 4.0), "梳子-齿根")
	_case(comb, Destruction.Damage.circle(Vector2(5.0, 1.0), 3.0), "梳子-横梁")
	var ring := PixelShape.new()
	for y in 40:
		for x in 40:
			var dx: int = mini(x, 39 - x)
			var dy: int = mini(y, 39 - y)
			if mini(dx, dy) <= 3:
				ring.set_pixel(x, y, 1)
	_case(ring, Destruction.Damage.circle(Vector2(1.0, 20.0), 5.0), "环-侧边")
	_case(ring, Destruction.Damage.circle(Vector2(0.0, 20.0), 8.0), "环-侧边大洞")
	# 多岛屿（引擎不变量不成立的情形）：判据可以跳过分裂，但不能给出错误结论
	var two := PixelShape.new()
	for y in 20:
		for x in 20:
			if x < 8 or x >= 12:
				two.set_pixel(x, y, 1)
	_case(two, Destruction.Damage.circle(Vector2(2.0, 10.0), 4.0), "多岛屿-左块边界")
	print("---")
	print("  判据生效 %d / %d 例（其余退回全量标注）；已知差异（多岛屿）%d 例" % [applied, total, diff_ok])
	if failed == 0:
		print("全部通过：%d 项断言" % passed)
	else:
		print("失败 %d / %d 项" % [failed, passed + failed])
	quit(0 if failed == 0 else 1)
