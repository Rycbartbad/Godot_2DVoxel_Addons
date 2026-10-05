extends SceneTree
## **关节感知的 CCD 子步**闸门（表 ③）。
##
## 守五件事：
##   1. **关着的时候就是老行为**（逐刚体取最快）—— 逐位对得上独立算出来的老公式；
##   2. 开着时，焊接组里**轻质件的瞬态速度**不再顶起全世界的子步数；
##   3. 但**真运动**照旧（整组都在飞 -> 子步数不变）—— 别把防穿一起优化掉；
##   4. **断得开的焊接不摊平**（安全阀：焊接可能在这一步断掉，那时刚体是真在飞）；
##   5. **薄壁防穿**：焊在静态世界上的瞬态、以及整组高速撞 2 像素薄墙，都不能穿过去。
##
## ⚠️ 判据是**独立算出来的**：老公式在测试里自己写一遍（速度 + 角速度 x 外接半径 ->
##    ceil(位移 / ccd_max_motion)），不拿引擎的中间量当预期值。
const PWorld := preload("res://src/physics/pworld.gd")
const PBody := preload("res://src/physics/pbody.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

var _pass := 0
var _fail := 0
func _c(n: String, ok: bool, d: String = "") -> void:
	if ok:
		_pass += 1
		print("  PASS  ", n, "  ", d)
	else:
		_fail += 1
		print("  FAIL  ", n, "  ", d)


func _box(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, w, h), 1)
	return s


## 老公式（逐刚体取最快）的**独立**实现 —— 用来证明"关着时行为没变"。
func _plain_expect(w, dt: float) -> int:
	var fastest := 0.0
	for b in w.bodies:
		if b.is_static or not b.awake:
			continue
		fastest = maxf(fastest, b.linear_velocity.length() + absf(b.angular_velocity) * b.bounding_radius())
	var need := 1
	if fastest > 0.0:
		var motion: float = fastest * dt
		if motion > w.ccd_max_motion:
			need = clampi(int(ceil(motion / w.ccd_max_motion)), 1, w.ccd_substep_budget)
	return need


func _world() -> PWorld:
	var w := PWorld.new()
	w.gravity = Vector2.ZERO
	return w


## 重 100x100（质量 1e4）+ 轻 4x4（质量 16），焊在一起。
func _heavy_light() -> Array:
	var w := _world()
	var heavy := PBody.new()
	heavy.position = Vector2(0, 0)
	w.add_body(heavy, [_box(100, 100)])
	var light := PBody.new()
	light.position = Vector2(120, 0)
	w.add_body(light, [_box(4, 4)])
	var j = w.add_weld(heavy, light)
	return [w, heavy, light, j]


func _initialize() -> void:
	print("=== 关节感知的 CCD 子步（表 ③）===")
	var dt := 1.0 / 60.0

	# ---- 1. 关着 = 老行为 ----
	var hl := _heavy_light()
	var w1: PWorld = hl[0]
	var light1: PBody = hl[2]
	light1.linear_velocity = Vector2(3000, 0)
	w1.ccd_joint_aware = false
	var off_val: int = w1._compute_substeps(dt)
	var expect: int = _plain_expect(w1, dt)
	_c("关着时 = 老公式（独立算的）", off_val == expect, "%d vs %d" % [off_val, expect])

	# ---- 2. 开着：轻质件的瞬态被质量加权摊平 ----
	w1.ccd_joint_aware = true
	var on_val: int = w1._compute_substeps(dt)
	_c("开着时轻质瞬态不再顶起子步数", on_val < off_val,
		"%d -> %d（重 10000 vs 轻 16）" % [off_val, on_val])
	_c("开着时降到 1（组整体几乎不动）", on_val == 1, "%d" % on_val)

	# ---- 3. 真运动照旧 ----
	var hl2 := _heavy_light()
	var w2: PWorld = hl2[0]
	(hl2[1] as PBody).linear_velocity = Vector2(3000, 0)
	(hl2[2] as PBody).linear_velocity = Vector2(3000, 0)
	w2.ccd_joint_aware = true
	var both_on: int = w2._compute_substeps(dt)
	w2.ccd_joint_aware = false
	var both_off: int = w2._compute_substeps(dt)
	_c("整组真在飞：子步数不变（防穿没被优化掉）", both_on == both_off,
		"%d vs %d" % [both_on, both_off])

	# ---- 4. 焊在静态世界上：整体动不了 -> 记 0；而且它真的不会跑掉 ----
	var w3 := _world()
	var hand := PBody.new()
	hand.position = Vector2(0, 0)
	w3.add_body(hand, [_box(20, 20)])
	w3.add_weld(null, hand, Vector2(10, 10))          # 焊在世界锚点上
	hand.linear_velocity = Vector2(3000, 0)
	w3.ccd_joint_aware = false
	var anc_off: int = w3._compute_substeps(dt)
	w3.ccd_joint_aware = true
	var anc_on: int = w3._compute_substeps(dt)
	_c("焊在静态世界：老公式会顶起子步数", anc_off > 1, "%d" % anc_off)
	_c("焊在静态世界：关节感知记 0 -> 1 子步", anc_on == 1, "%d" % anc_on)
	var p0 := hand.position
	for i in 30:
		w3.step(dt)
		hand.linear_velocity = Vector2(3000, 0)        # 每步都给它一个"瞬态"（模拟持续施力）
	_c("约束稳定：30 步之后它没被瞬态带走", hand.position.distance_to(p0) < 1.0,
		"位移 %.4f px" % hand.position.distance_to(p0))

	# ---- 5. 断得开的焊接：不摊平（保守） ----
	var w4 := _world()
	var b4 := PBody.new()
	b4.position = Vector2(0, 0)
	w4.add_body(b4, [_box(20, 20)])
	var j4 = w4.add_weld(null, b4, Vector2(10, 10))
	j4.break_impulse = 1000.0                          # 这一步可能断 -> 不能摊平
	b4.linear_velocity = Vector2(3000, 0)
	w4.ccd_joint_aware = true
	var brk_on: int = w4._compute_substeps(dt)
	_c("断得开的焊接：仍然按自己的速度算子步（安全阀）", brk_on == _plain_expect(w4, dt),
		"%d vs 老公式 %d" % [brk_on, _plain_expect(w4, dt)])

	# ---- 6. 防穿：焊在静态世界 + 瞬态冲向 2 像素薄墙 ----
	var w5 := _world()
	var wall := PBody.new()
	wall.position = Vector2(60, -40)
	wall.make_static()
	w5.add_body(wall, [_box(2, 80)])
	var probe := PBody.new()
	probe.position = Vector2(0, 0)
	w5.add_body(probe, [_box(8, 8)])
	w5.add_weld(null, probe, Vector2(4, 4))
	w5.ccd_joint_aware = true
	var tunneled := false
	for i in 60:
		probe.linear_velocity = Vector2(3000, 0)       # 持续瞬态，直冲薄墙
		w5.step(dt)
		if probe.position.x > 62.0:                    # 越过墙的远端 = 穿了
			tunneled = true
	_c("焊在静态世界 + 瞬态冲向 2 像素薄墙：没穿过去", not tunneled,
		"最终 x=%.2f（墙在 60..62）" % probe.position.x)

	# ---- 7. 整组高速撞薄墙（真运动，不许穿） ----
	var w6 := _world()
	var wall2 := PBody.new()
	wall2.position = Vector2(200, -40)
	wall2.make_static()
	w6.add_body(wall2, [_box(2, 80)])
	var g_heavy := PBody.new()
	g_heavy.position = Vector2(100, 0)
	w6.add_body(g_heavy, [_box(40, 40)])
	var g_light := PBody.new()
	g_light.position = Vector2(150, 0)
	w6.add_body(g_light, [_box(4, 4)])
	w6.add_weld(g_heavy, g_light)
	w6.ccd_joint_aware = true
	var sub_max := 0
	for i in 60:
		g_heavy.linear_velocity = Vector2(1200, 0)
		g_light.linear_velocity = Vector2(1200, 0)
		w6.step(dt)
		sub_max = maxi(sub_max, w6.last_substeps)
	var passed := g_heavy.position.x > 202.0
	_c("整组高速撞薄墙：子步数确实顶上去了", sub_max > 5, "峰值 %d 子步" % sub_max)
	_c("整组高速撞薄墙：没穿过去", not passed, "最终 x=%.2f（墙在 200..202）" % g_heavy.position.x)

	# ---- 8. 没有关节时开关无影响 ----
	var w7 := _world()
	var lone := PBody.new()
	lone.position = Vector2(0, 0)
	w7.add_body(lone, [_box(8, 8)])
	lone.linear_velocity = Vector2(3000, 0)
	w7.ccd_joint_aware = false
	var lone_off: int = w7._compute_substeps(dt)
	w7.ccd_joint_aware = true
	var lone_on: int = w7._compute_substeps(dt)
	_c("没有关节：开关无影响（逐位相同）", lone_off == lone_on, "%d vs %d" % [lone_off, lone_on])

	print("---")
	if _fail == 0:
		print("全部通过：%d 项断言" % _pass)
	else:
		print("失败 %d / %d 项" % [_fail, _pass + _fail])
	quit(0 if _fail == 0 else 1)
