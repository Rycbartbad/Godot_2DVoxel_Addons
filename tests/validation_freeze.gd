extends SceneTree
## **冻结 / 恢复**（可逆地"关掉物理"）闸门。
##
## 守八件事：
##   1. 冻住 = 真的不动（重力、速度都推不动），解冻后接着跑；
##   2. 速度**留着**（解冻后原样交回），位置连续（不瞬移）；
##   3. 碰撞体**还在**：醒着的东西照样被它挡住；
##   4. 解冻后**质量**在 Rapier 侧也是对的 —— 用**冲量反推** dv = j/m（不看引擎字段，
##      因为字段本来就没被冻过：这条专抓"Rapier 换刚体类型把质量重算成默认值"）；
##   5. 关节组件是**原子**的：半冻会把醒着那头钉住；
##   6. keep（玩家）所在的**整个关节组件**保持计算；
##   7. 抓着的刚体永不冻；冻着的刚体不被 cull_outside 移除、不被碎片预算淘汰；
##   8. 冻着的刚体不参与子步估计（它不积分，拿它算子步是白算）。
##
## ⚠️ 判据都是**外部可观测量**：位置、速度、被挡住的位置、冲量反推的 dv ——
##    不拿引擎自己的中间状态当预期值。
const PWorld := preload("res://src/physics/pworld.gd")
const PBody := preload("res://src/physics/pbody.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

const DT := 1.0 / 60.0

var _pass := 0
var _fail := 0
func _c(n: String, ok: bool, d: String = "") -> void:
	if ok:
		_pass += 1
		print("  PASS  ", n, "  ", d)
	else:
		_fail += 1
		print("  FAIL  ", n, "  ", d)


func _box(w: int, h: int, mat: int = 1) -> PixelShape:
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, w, h), mat)
	return s


func _world(g: Vector2 = Vector2.ZERO) -> PWorld:
	var w := PWorld.new()
	w.gravity = g
	return w


func _body(w: PWorld, pos: Vector2, size: Vector2i, mat: int = 1) -> PBody:
	var b := PBody.new()
	b.position = pos
	w.add_body(b, [_box(size.x, size.y, mat)])
	return b


func _initialize() -> void:
	print("=== 冻结 / 恢复（可逆的关掉物理）===")

	# ---- 1. 冻住 = 真的不动（有重力也纹丝不动） ----
	var w1 := _world(Vector2(0, 500))
	var b1 := _body(w1, Vector2(0, 0), Vector2i(10, 10))
	w1.freeze(b1)
	var p1 := b1.position
	for i in 60:
		w1.step(DT)
	_c("冻住：60 步（有重力）位置纹丝不动", b1.position.distance_to(p1) < 1e-4,
		"位移 %.6f px" % b1.position.distance_to(p1))
	w1.unfreeze(b1)
	for i in 60:
		w1.step(DT)
	_c("解冻：接着往下掉", b1.position.y > p1.y + 10.0, "y=%.2f" % b1.position.y)

	# ---- 2. 速度留着 + 位置连续（不瞬移） ----
	var w2 := _world()
	var b2 := _body(w2, Vector2(0, 0), Vector2i(10, 10))
	b2.linear_velocity = Vector2(300, 0)
	for i in 10:
		w2.step(DT)
	var before_freeze := b2.position
	w2.freeze(b2)
	var v_at_freeze := b2.linear_velocity
	for i in 30:
		w2.step(DT)
	_c("冻住期间位置不动", b2.position.distance_to(before_freeze) < 1e-4,
		"位移 %.6f" % b2.position.distance_to(before_freeze))
	w2.unfreeze(b2)
	_c("解冻后速度原样交回", absf(b2.linear_velocity.x - v_at_freeze.x) < 1.0,
		"%.2f -> %.2f" % [v_at_freeze.x, b2.linear_velocity.x])
	_c("解冻后位置连续（没瞬移）", b2.position.distance_to(before_freeze) < 1.0,
		"%.4f px" % b2.position.distance_to(before_freeze))
	for i in 30:
		w2.step(DT)
	_c("解冻后接着跑", b2.position.x > before_freeze.x + 50.0, "x=%.2f" % b2.position.x)

	# ---- 3. 碰撞体还在：醒着的东西被冻住的挡下来 ----
	var w3 := _world()
	var blocker := _body(w3, Vector2(50, -5), Vector2i(10, 10))
	w3.freeze(blocker)
	var mover := _body(w3, Vector2(0, 0), Vector2i(6, 6))
	mover.linear_velocity = Vector2(400, 0)
	for i in 60:
		w3.step(DT)
	_c("冻住的刚体照样挡人", mover.position.x < 50.0 and mover.position.x > 40.0,
		"冲过来的停在 x=%.2f（冻块在 50）" % mover.position.x)

	# ---- 4. 解冻后质量在 Rapier 侧也是对的（冲量反推） ----
	# 参照：全新刚体，密度 2.5 -> 1600 像素 x 2.5 = 4000
	var w4 := _world()
	w4.set_material_density(1, 2.5)
	var fresh := _body(w4, Vector2(0, 0), Vector2i(40, 40))
	var frozen_one := _body(w4, Vector2(200, 0), Vector2i(40, 40))
	w4.freeze(frozen_one)
	w4.step(DT)
	w4.unfreeze(frozen_one)
	w4.step(DT)
	_c("参照刚体质量 = 1600 x 2.5", absf(fresh.mass - 4000.0) < 0.01, "%.1f" % fresh.mass)
	var j := Vector2(1000, 0)
	fresh.apply_central_impulse(j)
	frozen_one.apply_central_impulse(j)
	w4.step(DT)
	var dv_fresh: float = fresh.linear_velocity.x
	var dv_thawed: float = frozen_one.linear_velocity.x
	_c("解冻后质量没被重算成默认值（冲量反推 dv 一致）",
		absf(dv_fresh - dv_thawed) < 0.001 and dv_fresh > 0.0,
		"dv 参照 %.4f vs 解冻 %.4f（若密度没重推会是 %.4f）" % [dv_fresh, dv_thawed, 1000.0 / 1600.0])

	# ---- 5. 关节组件是原子的 ----
	var w5 := _world()
	var heavy := _body(w5, Vector2(0, 0), Vector2i(40, 40))
	var light := _body(w5, Vector2(100, 0), Vector2i(4, 4))
	w5.add_weld(heavy, light)
	# 只框住轻的那个：组件里还有一个在范围内 -> 整组都不冻
	var r5 := Rect2(95, -10, 20, 20)
	var res5: Dictionary = w5.cull_freeze(r5)
	_c("组件原子：只框住一半 -> 整组都不冻", res5["frozen"] == 0 and not heavy.frozen and not light.frozen,
		"frozen=%d" % res5["frozen"])
	# 两个都在范围外 -> 整组都冻（⚠️ 不能用"把两个都框住"的矩形：那个语义是
	# "在范围内 -> 保持计算"，框住 = 都不冻 —— 我第一版就是这么写错的）
	var r5b := Rect2(1000, 1000, 50, 50)
	var res5b: Dictionary = w5.cull_freeze(r5b)
	_c("组件原子：全框住 -> 整组都冻", res5b["frozen"] == 2 and heavy.frozen and light.frozen,
		"frozen=%d" % res5b["frozen"])

	# ---- 6. keep（玩家）的整个关节组件保持计算 ----
	var w6 := _world()
	var player := _body(w6, Vector2(0, 0), Vector2i(8, 8))
	var arm := _body(w6, Vector2(200, 0), Vector2i(8, 8))
	w6.add_hinge(player, arm, Vector2(100, 0))
	var far := Rect2(1000, 1000, 50, 50)          # 玩家和手臂都在范围外
	var res6: Dictionary = w6.cull_freeze(far, [player])
	_c("keep：与玩家关节连接的保持计算", res6["frozen"] == 0 and not player.frozen and not arm.frozen,
		"frozen=%d kept=%d" % [res6["frozen"], res6["kept"]])
	# 不给 keep 就都冻上
	var res6b: Dictionary = w6.cull_freeze(far)
	_c("不给 keep：同一组就被冻上", res6b["frozen"] == 2 and player.frozen and arm.frozen,
		"frozen=%d" % res6b["frozen"])

	# ---- 7a. 抓着的永不冻 ----
	var w7 := _world()
	var held := _body(w7, Vector2(0, 0), Vector2i(8, 8))
	w7.grab(held, Vector2(4, 4))
	var res7: Dictionary = w7.cull_freeze(Rect2(1000, 1000, 10, 10))
	_c("抓着的刚体永不冻", not held.frozen, "frozen=%d" % res7["frozen"])
	# ---- 7b. 冻着的不被 cull_outside 移除 ----
	var w7b := _world()
	var parked := _body(w7b, Vector2(500, 0), Vector2i(8, 8))
	w7b.freeze(parked)
	var removed: int = w7b.cull_outside(Rect2(0, 0, 100, 100))
	_c("冻着的不被 cull_outside 移除", removed == 0 and w7b.bodies.has(parked),
		"移除 %d 个，刚体数 %d" % [removed, w7b.bodies.size()])
	# ---- 7c. 冻着的不被碎片预算淘汰 ----
	var w7c := _world()
	w7c.max_dynamic_bodies = 1
	var park2 := _body(w7c, Vector2(0, 0), Vector2i(8, 8))
	w7c.freeze(park2)
	var extra := _body(w7c, Vector2(0, 100), Vector2i(8, 8))
	w7c.enforce_body_budget()
	_c("冻着的不被碎片预算淘汰", w7c.bodies.has(park2), "刚体数 %d" % w7c.bodies.size())

	# ---- 8. 冻着的不参与子步估计 ----
	var w8 := _world()
	var fast := _body(w8, Vector2(0, 0), Vector2i(8, 8))
	fast.linear_velocity = Vector2(3000, 0)
	var sub_before: int = w8._compute_substeps(DT)
	w8.freeze(fast)
	var sub_after: int = w8._compute_substeps(DT)
	_c("冻着的刚体不顶子步数", sub_before > 1 and sub_after == 1,
		"%d -> %d" % [sub_before, sub_after])

	# ---- 9. 幂等 + 静态刚体返回 false ----
	var w9 := _world()
	var b9 := _body(w9, Vector2(0, 0), Vector2i(8, 8))
	var r9a: Dictionary = w9.cull_freeze(Rect2(1000, 1000, 10, 10))
	var r9b: Dictionary = w9.cull_freeze(Rect2(1000, 1000, 10, 10))
	_c("幂等：第二次没有变化", r9a["frozen"] == 1 and r9b["frozen"] == 0 and r9b["unfrozen"] == 0,
		"第一次 frozen=%d，第二次 frozen=%d unfrozen=%d" % [r9a["frozen"], r9b["frozen"], r9b["unfrozen"]])
	var st := PBody.new()
	st.make_static()
	w9.add_body(st, [_box(8, 8)])
	_c("静态刚体 freeze() 返回 false", w9.freeze(st) == false and not st.frozen)

	print("---")
	if _fail == 0:
		print("全部通过：%d 项断言" % _pass)
	else:
		print("失败 %d / %d 项" % [_fail, _pass + _fail])
	quit(0 if _fail == 0 else 1)
