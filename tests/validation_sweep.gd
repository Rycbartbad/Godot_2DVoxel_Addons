extends SceneTree
## 精确 OBB sweep 的验证：与**暴力细分参考解**对照。
##
## 参考解：把这段运动切成 N 份，逐份算有符号分离量，取第一个 sep<=0 的时刻。
## 它慢但直白，且不含任何"保守"假设 —— 正好用来检验扫掠是不是
##   1) **保守**：t_sweep <= t_ref（绝不会跨过真 TOI）
##   2) 不太早：t_sweep 与 t_ref 的差距在有界范围内（收敛了，不是随便给个数）
##
## ⚠️ 用例的几何要自己算：dt=1/60，3000 单位/秒只有 50 单位行程 ——
## 靶子放在 200 单位外的话两边都"不碰"，测试会变成假绿。

const Collide := preload("res://src/physics/collide.gd")
const Sweep := preload("res://src/physics/sweep.gd")

var _pass := 0
var _fail := 0

func _check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		_pass += 1
		print("  PASS  ", name, "  ", detail)
	else:
		_fail += 1
		print("  FAIL  ", name, "  ", detail)

func _obb(cx: float, cy: float, hw: float, hh: float, ang: float) -> Collide.OBB:
	var o := Collide.OBB.new()
	o.u = Vector2(cos(ang), sin(ang))
	o.v = Vector2(-o.u.y, o.u.x)
	o.h = Vector2(hw, hh)
	o.center = Vector2(cx, cy)
	return o

func _at(o: Collide.OBB, com: Vector2, v: Vector2, w: float, t: float, dt: float) -> Collide.OBB:
	var dst := Collide.OBB.new()
	Sweep.Sweeper._place(o, com, v, w, t, dt, dst)
	return dst

func _ref_t(oa: Collide.OBB, com_a: Vector2, va: Vector2, wa: float,
		ob: Collide.OBB, com_b: Vector2, vb: Vector2, wb: float, dt: float, n: int) -> float:
	var sat := Collide.Sat.new()
	for k in n + 1:
		var t := float(k) / float(n)
		Collide.sat_signed_into(_at(oa, com_a, va, wa, t, dt), _at(ob, com_b, vb, wb, t, dt), sat)
		if sat.sep <= 0.0:
			return t
	return 2.0

func _case(name: String, oa: Collide.OBB, com_a: Vector2, va: Vector2, wa: float,
		ob: Collide.OBB, com_b: Vector2, vb: Vector2, wb: float, dt: float,
		expect_hit: bool) -> void:
	var sw := Sweep.Sweeper.new()
	var out := Sweep.Hit.new()
	var ra := (oa.center - com_a).length() + sqrt(oa.h.x * oa.h.x + oa.h.y * oa.h.y)
	var rb := (ob.center - com_b).length() + sqrt(ob.h.x * ob.h.x + ob.h.y * ob.h.y)
	sw.sweep(oa, com_a, va, wa, ra, ob, com_b, vb, wb, rb, dt, out)
	var t_ref := _ref_t(oa, com_a, va, wa, ob, com_b, vb, wb, dt, 4000)
	if expect_hit:
		_check("%s：保守" % name, out.hit and out.t <= t_ref + 1e-9,
			"t_sweep=%.6f t_ref=%.6f" % [out.t, t_ref])
		_check("%s：收敛" % name, out.hit and (t_ref - out.t) <= 0.01,
			"落后 %.6f" % (t_ref - out.t))
	else:
		_check("%s：正确地判定不碰" % name, not out.hit,
			"t_ref=%.6f t_sweep=%.6f" % [t_ref, out.t])

func _initialize() -> void:
	var dt := 1.0 / 60.0
	var zero := Vector2.ZERO
	print("[精确 OBB sweep 验证] 与 4000 份暴力细分参考解对照")

	# 1. 平动正面：3000/s * 1/60 = 50 单位行程，靶子放 30 处（间隙 20）
	_case("平动正面", _obb(0.0, 0.0, 5.0, 5.0, 0.0), zero, Vector2(3000.0, 0.0), 0.0,
		_obb(30.0, 0.0, 5.0, 5.0, 0.0), zero, zero, 0.0, dt, true)

	# 2. 平动擦边（dy=9.5 < 10，刚好蹭到）
	_case("平动擦边", _obb(0.0, 0.0, 5.0, 5.0, 0.0), zero, Vector2(3000.0, 0.0), 0.0,
		_obb(30.0, 9.5, 5.0, 5.0, 0.0), zero, zero, 0.0, dt, true)

	# 3. 将将错过（dy=10.3 > 10）
	_case("平动将将错过", _obb(0.0, 0.0, 5.0, 5.0, 0.0), zero, Vector2(3000.0, 0.0), 0.0,
		_obb(30.0, 10.3, 5.0, 5.0, 0.0), zero, zero, 0.0, dt, false)

	# 4. ★ 纯转动扫入：长杆原地旋转 1 弧度，靶子放在**杆端扫过的弧**上
	#    这是旧 AABB 实现必然漏掉的场景（AABB 完全不动 -> 永远不相交）
	var arc_r := 60.0
	var arc_a := 0.5
	_case("纯转动扫入", _obb(0.0, 0.0, 60.0, 3.0, 0.0), zero, zero, 60.0,
		_obb(arc_r * cos(arc_a), arc_r * sin(arc_a), 4.0, 4.0, 0.0), zero, zero, 0.0, dt, true)

	# 5. 双向迎头：各 2000，合 4000/s = 66.7 单位/步，相距 40
	_case("双向迎头", _obb(0.0, 0.0, 5.0, 5.0, 0.0), zero, Vector2(2000.0, 0.0), 0.0,
		_obb(40.0, 0.0, 5.0, 5.0, 0.0), zero, Vector2(-2000.0, 0.0), 0.0, dt, true)

	# 6. 质心偏离盒子中心：质心在 (-40,0)，盒子中心绕它画半径 40 的圆
	var orb_r := 40.0
	var orb_a := 0.5
	_case("质心偏离+绕质心转动", _obb(0.0, 0.0, 8.0, 8.0, 0.0), Vector2(-40.0, 0.0), zero, 60.0,
		_obb(-40.0 + orb_r * cos(orb_a), orb_r * sin(orb_a), 3.0, 3.0, 0.0), zero, zero, 0.0, dt, true)

	# 7. 高速穿薄板：9000/s = 150 单位/步，薄板厚 3，放在 150 处
	_case("高速穿薄板", _obb(0.0, 0.0, 1.0, 1.0, 0.0), zero, Vector2(9000.0, 0.0), 0.0,
		_obb(150.0, 0.0, 1.5, 60.0, 0.0), zero, zero, 0.0, dt, true)

	# 8. 已经分离且正在远离
	_case("分离且远离", _obb(0.0, 0.0, 5.0, 5.0, 0.0), zero, Vector2(-3000.0, 0.0), 0.0,
		_obb(30.0, 0.0, 5.0, 5.0, 0.0), zero, zero, 0.0, dt, false)

	print("=== %d passed, %d failed ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
