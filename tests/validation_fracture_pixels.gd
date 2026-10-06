extends SceneTree
## fracture_pixels 的闸门 —— 逐条对应接口请求里的验证清单：
##   ① 不规则跨 chunk 掩码删除准确
##   ② 多 shape 不串删
##   ③ 断杆只分裂一次（fragments 恰好 1 个）
##   ④ 最大块保留原 body
##   ⑤ 旋转体分裂继承局部速度场（v_new = v_old + omega x r）
##   ⑥ 钉子决定 static，钉子破坏后解除 static
const PWorld := preload("res://src/physics/pworld.gd")
const PBody := preload("res://src/physics/pbody.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

var passed := 0
var failed := 0

func _assert(cond: bool, msg: String) -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		print("  [失败] " + msg)


func _shape(w: int, h: int, ox: int = 0, oy: int = 0) -> PixelShape:
	var s := PixelShape.new()
	s.fill_rect(Rect2i(ox, oy, w, h), 1)
	return s


func _initialize() -> void:
	print("=== fracture_pixels ===")

	# ① 不规则跨 chunk 掩码（一条斜线，故意跨 8 像素的 chunk 边界）
	var w1 := PWorld.new()
	var b1 := PBody.new()
	var s1 := _shape(32, 32)
	w1.add_body(b1, [s1], Callable(), true)
	var before1: int = s1.pixel_count()
	var mask1 := {}
	for i in 24:
		mask1[Vector2i(i, i)] = true          # 跨 chunk 的斜线
	var res1: Dictionary = w1.fracture_pixels(b1, {s1: mask1})
	var after1: int = b1.shapes[0].pixel_count() if b1.shapes.size() > 0 else 0
	print("① 斜线掩码：removed=%d（期望 24），像素 %d -> %d" % [res1["removed"], before1, after1])
	_assert(res1["removed"] == 24, "removed 应为 24，实际 %d" % res1["removed"])
	_assert(after1 == before1 - 24, "剩余像素应为 %d，实际 %d" % [before1 - 24, after1])
	_assert(res1["body_alive"], "内部斜线不该让原体消失")

	# ② 多 shape 不串删：只删第一个
	var w2 := PWorld.new()
	var b2 := PBody.new()
	var sa := _shape(16, 16)
	var sb := _shape(16, 16, 40, 0)            # 分开放，互不相连
	w2.add_body(b2, [sa, sb], Callable(), true)
	var n_before: int = sb.pixel_count()
	var m2 := {Vector2i(3, 3): true, Vector2i(4, 4): true}
	var res2: Dictionary = w2.fracture_pixels(b2, {sa: m2})
	print("② 多 shape：removed=%d，第二个 shape %d -> %d" % [res2["removed"], n_before, sb.pixel_count()])
	_assert(res2["removed"] == 2, "removed 应为 2，实际 %d" % res2["removed"])
	_assert(sb.pixel_count() == n_before, "未被列出的 shape 不该被删（%d -> %d）" % [n_before, sb.pixel_count()])

	# ③ 断杆只分裂一次：细杆中间删一列
	var w3 := PWorld.new()
	var b3 := PBody.new()
	var s3 := _shape(40, 4)
	w3.add_body(b3, [s3], Callable(), true)
	var m3 := {}
	for y in 4:
		m3[Vector2i(20, y)] = true
	var res3: Dictionary = w3.fracture_pixels(b3, {s3: m3})
	print("③ 断杆：removed=%d，fragments=%d，body_alive=%s" % [
		res3["removed"], (res3["fragments"] as Array).size(), str(res3["body_alive"])])
	_assert(res3["removed"] == 4, "removed 应为 4，实际 %d" % res3["removed"])
	_assert((res3["fragments"] as Array).size() == 1, "断杆应恰好产生 1 个碎片，实际 %d" % (res3["fragments"] as Array).size())
	_assert(res3["body_alive"], "断杆后原体应存活")

	# ④ 最大块保留原 body：删掉一侧 1/4
	var w4 := PWorld.new()
	var b4 := PBody.new()
	var s4 := _shape(40, 10)
	w4.add_body(b4, [s4], Callable(), true)
	var m4 := {}
	for y in 10:
		for x in range(0, 10):
			m4[Vector2i(x, y)] = true          # 左边 1/4
	var res4: Dictionary = w4.fracture_pixels(b4, {s4: m4})
	var kept_n: int = b4.shapes[0].pixel_count() if b4.shapes.size() > 0 else 0
	print("④ 删左侧 1/4：removed=%d，原 body 剩 %d（期望 300），fragments=%d" % [
		res4["removed"], kept_n, (res4["fragments"] as Array).size()])
	_assert(kept_n == 300, "最大块应留在原 body（期望 300，实际 %d）" % kept_n)
	# ⚠️ 这里**不该**有碎片：fracture_pixels 的契约是"删掉掩码里的像素"（与 fracture 一致），
	#    被删的部分**不会**变成碎片（那是 detach 的行为）。剩下的 300 像素是一整块。
	#    我第一版把期望写成 1，是错的 —— 测试写错和代码写错一样要当场改掉。
	_assert((res4["fragments"] as Array).size() == 0, "删掉一侧后不该有碎片，实际 %d" % (res4["fragments"] as Array).size())

	# ⑤ 速度场继承：给原体一个角速度，碎片的速度应含 omega x r
	var w5 := PWorld.new()
	var b5 := PBody.new()
	var s5 := _shape(40, 4)
	w5.add_body(b5, [s5], Callable(), true)
	b5.linear_velocity = Vector2(100, 0)
	b5.angular_velocity = 2.0
	var m5 := {}
	for y in 4:
		m5[Vector2i(20, y)] = true
	var res5: Dictionary = w5.fracture_pixels(b5, {s5: m5})
	var frags5: Array = res5["fragments"]
	var v_frag: Vector2 = frags5[0].linear_velocity if frags5.size() > 0 else Vector2.ZERO
	var w_frag: float = frags5[0].angular_velocity if frags5.size() > 0 else 0.0
	print("⑤ 速度继承：v_old=(100,0) w_old=2.0 -> 碎片 v=%s w=%.3f（应含 omega x r 的横向分量）" % [
		str(v_frag), w_frag])
	_assert(absf(w_frag - 2.0) < 1e-6, "碎片角速度应继承 2.0，实际 %.4f" % w_frag)
	_assert(absf(v_frag.y) > 1.0, "碎片线速度应含 omega x r 的横向分量，实际 v=%s" % str(v_frag))

	# 材质由重建统一计算；游戏不应为了补摩擦再重建整块。
	var w6 := PWorld.new()
	w6.set_material_friction(1, 0.8)
	w6.set_material_restitution(1, 0.15)
	var b6 := PBody.new()
	b6.is_static = true
	b6.collision_layer = 4
	b6.collision_mask = 8
	b6.gravity_scale = 0.5
	var s6 := _shape(40, 4)
	w6.add_body(b6, [s6], Callable(), true)
	var res6: Dictionary = w6.fracture_pixels(b6, {s6: m3}, 0.0, true)
	var fragment = res6.fragments[0]
	_assert(b6.is_static and not fragment.is_static, "地形保留静态，脱落碎片转为动态")
	_assert(fragment.collision_layer == 4 and fragment.collision_mask == 8, "碎片继承碰撞过滤")
	_assert(fragment.gravity_scale == 0.5, "碎片继承重力倍率")
	_assert(is_equal_approx(b6.friction, 0.8) and is_equal_approx(fragment.friction, 0.8), "原体与碎片保留材料摩擦")
	_assert(is_equal_approx(b6.restitution, 0.15) and is_equal_approx(fragment.restitution, 0.15), "原体与碎片保留材料恢复系数")

	# ⑥ 钉子在较小的左块：左块继承原 body 且保持 static，较大的右块必须掉落。
	var w7 := PWorld.new()
	var b7 := PBody.new()
	b7.is_static = true
	var s7 := _shape(40, 4)
	w7.add_body(b7, [s7], Callable(), true)
	var cut7 := {}
	for y in 4:
		cut7[Vector2i(10, y)] = true
	var nail := Vector2i(5, 1)
	var res7: Dictionary = w7.fracture_pixels(b7, {s7: cut7}, 0.0, true,
		{s7: {nail: true}})
	_assert(b7.is_static and b7.shapes[0].pixel_count() == 40,
		"含钉子的较小分量应保持原 static body")
	_assert(res7.fragments.size() == 1 and not res7.fragments[0].is_static
		and res7.fragments[0].shapes[0].pixel_count() == 116,
		"不含钉子的较大分量应成为动态碎片")
	var anchored_shape = b7.shapes[0]
	w7.fracture_pixels(b7, {anchored_shape: {nail: true}}, 0.0, true,
		{anchored_shape: {nail: true}})
	_assert(not b7.is_static and b7.mass > 0.0 and b7.inv_mass > 0.0,
		"钉子像素破坏后原体应一次重建为动态体")

	for world in [w1, w2, w3, w4, w5, w6, w7]:
		for body in world.bodies.duplicate():
			for shape in body.shapes:
				shape.owner_body = null
			world.remove_body(body)
			body.shapes.clear()
		world._rp = null
	print("---")
	if failed == 0:
		print("全部通过：%d 项断言" % passed)
	else:
		print("失败 %d / %d 项" % [failed, passed + failed])
	quit(0 if failed == 0 else 1)
