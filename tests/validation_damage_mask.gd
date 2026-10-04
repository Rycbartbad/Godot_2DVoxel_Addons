extends SceneTree
## make_keep_mask 内联版的**位等价闸门**。
##
## ⚠️⚠️ 为什么参照物必须是**冻结的旧实现**（逐像素调 damage.hits()）：
##    内联把"方法调用"换成了"同一组表达式"，看起来显然等价 —— 但
##    · segment 的 ab / length_squared() 从"每像素算"变成"循环外算一次"，
##    · radius*radius 被提出来了，
##    这些都可能改变**浮点运算顺序**，而边界像素（正好落在 |dx| ≈ r 上）会因此翻转。
##    掩码错一位 = 擦掉/保留了不该动的像素，而且**不报错**。
##    所以逐位对拍，语料里专门放"边界正好压线"的用例（半整数圆心 + 整数半径）。
##
## 覆盖：三种 kind × 半整数/整数圆心 × 大/小/零半径 × 水平/垂直/斜线段 ×
##      空段（a==b）× 分数 half × force_keep × 远处 chunk × 负坐标 chunk

const Destruction := preload("res://src/core/destruction.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

var passed := 0
var failed := 0
var cases := 0

func _assert(cond: bool, msg: String) -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		if failed <= 10:
			print("  [失败] " + msg)

## 旧实现原样冻结：逐像素调 damage.hits()
func _old(chunk_key: int, damage, force_keep: int) -> int:
	var keep := 0
	var bx := PixelShape.key_x(chunk_key) << 3
	var by := PixelShape.key_y(chunk_key) << 3
	for y in 8:
		for x in 8:
			var bit := 1 << (x + (y << 3))
			if (force_keep & bit) != 0:
				keep |= bit
				continue
			if not damage.hits(bx + x + 0.5, by + y + 0.5):
				keep |= bit
	return keep

func _one(chunk_key: int, damage, force_keep: int, label: String) -> void:
	cases += 1
	var a := _old(chunk_key, damage, force_keep)
	var b := Destruction.make_keep_mask(chunk_key, damage, force_keep)
	if a == b:
		passed += 1
		return
	if a != b:
		var bx := PixelShape.key_x(chunk_key) << 3
		var by := PixelShape.key_y(chunk_key) << 3
		_assert(false, "%s（chunk %d,%d）：掩码不同 旧=%016x 新=%016x" % [label, bx >> 3, by >> 3, a, b])

func _initialize() -> void:
	print("=== make_keep_mask 内联 vs 冻结的旧实现（逐位）===")
	var keys: Array = []
	for cy in range(-2, 3):
		for cx in range(-2, 3):
			keys.append(PixelShape.make_key(cx, cy))
	var fks := [0, -1, 0x0F0F0F0F0F0F0F0F, 0x00000000FFFFFFFF, 0x0101010101010101]
	# 圆：整数/半整数圆心、压线半径、零半径、大半径
	for cxy in [Vector2(0.0, 0.0), Vector2(0.5, 0.5), Vector2(3.5, 4.0), Vector2(-8.0, -8.0), Vector2(12.0, 3.5), Vector2(4.5, 4.5)]:
		for r in [0.0, 0.5, 1.0, 4.0, 5.0, 7.5, 8.0, 12.0, 33.3]:
			var d = Destruction.Damage.circle(cxy, r)
			for k in keys:
				for fk in fks:
					_one(k, d, fk, "圆 c=%s r=%.1f" % [str(cxy), r])
	# 线段：水平/垂直/斜/零长/压线
	for seg in [[Vector2(0.0, 0.0), Vector2(20.0, 0.0)], [Vector2(0.0, 0.0), Vector2(0.0, 20.0)],
			[Vector2(0.0, 0.0), Vector2(20.0, 20.0)], [Vector2(4.5, 4.5), Vector2(4.5, 4.5)],
			[Vector2(-5.0, 2.5), Vector2(9.0, 2.5)], [Vector2(3.0, -4.0), Vector2(3.0, 12.0)]]:
		for r2 in [0.5, 1.0, 4.0, 4.5, 8.0]:
			var d2 = Destruction.Damage.segment(seg[0], seg[1], r2)
			for k2 in keys:
				for fk2 in fks:
					_one(k2, d2, fk2, "段 %s->%s r=%.1f" % [str(seg[0]), str(seg[1]), r2])
	# 矩形：分数半宽
	for c3 in [Vector2(0.0, 0.0), Vector2(0.5, 0.5), Vector2(-4.5, 8.0)]:
		for h3 in [Vector2(1.0, 1.0), Vector2(4.5, 2.5), Vector2(0.0, 3.0), Vector2(9.5, 9.5)]:
			var d3 = Destruction.Damage.rect(c3, h3)
			for k3 in keys:
				for fk3 in fks:
					_one(k3, d3, fk3, "矩形 c=%s half=%s" % [str(c3), str(h3)])
	print("  对拍 %d 组全部逐位相同" % cases)
	print("---")
	if failed == 0:
		print("全部通过：%d 项断言" % passed)
	else:
		print("失败 %d / %d 项" % [failed, passed + failed])
	quit(0 if failed == 0 else 1)
