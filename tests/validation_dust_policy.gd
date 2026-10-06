extends SceneTree
## 灰尘策略闸门：轻碎片不许拖慢全世界，且清理的边界必须精确。
##
## ⚠️ 为什么需要它（实测 tests/diag_dust_substep.gd）：子步数取的是**全世界最快**的
##    那个刚体，所以**一个** 2x2 的碎片就能拖慢全世界 —— 240 个碎片的场景里，
##    一个 2x2 碎片以 40000 px/s 飞行：子步 3 -> **334**，那一帧 **3.2 ms -> 346 ms**。
##    而它的质量只有 4（Δv = J/m：同样的冲量，轻 100 倍就快 100 倍）。
##
## 判据全是**外部可观测量**：last_substeps / bodies 里的成员 / 原生刚体数。
const PWorld := preload("res://src/physics/pworld.gd")
const PBody := preload("res://src/physics/pbody.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

var _pass := 0
var _fail := 0
func _c(n: String, ok: bool, d: String = "") -> void:
	if ok: _pass += 1; print("  PASS  ", n, "  ", d)
	else: _fail += 1; print("  FAIL  ", n, "  ", d)

func _shape(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, w, h), 1)
	return s

## 240 个落定的小碎片（让"全世界"有正常的工作量）+ 可选的灰尘。
func _world() -> PWorld:
	var w := PWorld.new()
	w.gravity = Vector2(0, 300)
	var g := PBody.new()
	g.make_static()
	w.add_body(g, [_shape(2000, 40)])
	for i in 240:
		var b := PBody.new()
		b.position = Vector2(20 + (i % 50) * 12, 100 + (i / 50) * 12)
		w.add_body(b, [_shape(6, 6)])
	for k in 60:
		w.step(1.0 / 60.0)
	return w

func _dust(w: PWorld, speed: float, size := 2) -> PBody:
	var d := PBody.new()
	d.position = Vector2(1000, 100)
	w.add_body(d, [_shape(size, size)])
	d.linear_velocity = Vector2(speed, 0)
	d.awake = true
	return d

func _initialize() -> void:
	print("=== 灰尘策略（轻碎片不许拖慢全世界）===")

	# ---- 1. 默认关：什么都不删，灰尘照样把子步顶满（这是"关"的基线）----
	var w0 := _world()
	var d0 := _dust(w0, 30000.0)
	w0.step(1.0 / 60.0)
	_c("默认关：灰尘没被删", w0.bodies.has(d0), "last_debris_removed=%d" % w0.last_debris_removed)
	_c("默认关：子步被顶到 250（= ceil(30000/60/2)）", w0.last_substeps == 250, "子步=%d" % w0.last_substeps)

	# ---- 2. 只开"清理"：同一帧就删掉，子步立刻回落 ----
	var w1 := _world()
	w1.debris_max_mass = 16.0
	w1.debris_min_speed = 2000.0
	var d1 := _dust(w1, 30000.0)
	# ⚠️ 先步一次让它**拿到 Rapier 身份**：add_body 只进 GDScript，原生刚体是
	#    第一次 step 里 _rp_create_missing 才建的。刚建出来就被删的话，op 4 根本没得发
	#    （那是理想情况，但测不到"两边一起删"这条路径）。
	w1.debris_max_mass = 0.0          # 这一步先别删，让它拿到身份
	w1.step(1.0 / 60.0)
	w1.debris_max_mass = 16.0
	var rp_before: int = w1.rp_body_count()
	_c("灰尘已经拿到原生身份", rp_before > 0, "原生=%d" % rp_before)
	w1.step(1.0 / 60.0)
	_c("清理：灰尘被删了", not w1.bodies.has(d1) and w1.last_debris_removed == 1,
		"removed=%d" % w1.last_debris_removed)
	_c("清理：**那一帧的子步就回落了**（不是下一帧）", w1.last_substeps <= 4,
		"子步=%d" % w1.last_substeps)
	_c("清理：原生侧也同步删了", w1.rp_body_count() == rp_before - 1,
		"%d -> %d" % [rp_before, w1.rp_body_count()])

	# ---- 3. 边界：三个条件必须**同时**满足才删 ----
	var w2 := _world()
	w2.debris_max_mass = 16.0
	w2.debris_min_speed = 2000.0
	var heavy := _dust(w2, 30000.0, 32)          # 32x32 = 1024 像素 -> 质量 1024，太重
	var slow := _dust(w2, 500.0)                 # 2x2 但很慢 -> 只要 5 子步，无害
	w2.step(1.0 / 60.0)
	_c("重的（质量 1024 > 16）不删", w2.bodies.has(heavy), "mass=%.0f" % heavy.mass)
	_c("慢的（500 px/s < 2000）不删", w2.bodies.has(slow), "v=%.0f" % slow.linear_velocity.length())
	_c("边界：这两个都不该删", w2.last_debris_removed == 0,
		"removed=%d" % w2.last_debris_removed)

	# ---- 3b. 自转的轻碎片也要算"高速"（判据是 _motion_of，不是线速度）----
	# ⚠️ 角速度正是**质量放大**的那个通道：Δω = J·r/I，而 I ∝ m ——
	#    同一个力矩，轻 100 倍的碎片角速度大 100 倍，而子步估计里有一项 |ω| x 半径。
	var w2b := _world()
	w2b.debris_max_mass = 16.0
	w2b.debris_min_speed = 2000.0
	var spinner := _dust(w2b, 0.0)
	spinner.angular_velocity = 5000.0
	w2b.step(1.0 / 60.0)
	_c("自转的轻碎片（线速度 0）也要被删", not w2b.bodies.has(spinner) and w2b.last_debris_removed == 1,
		"|w|=5000 -> 表面速度 %.0f" % (5000.0 * spinner.bounding_radius()))

	# ---- 4. 抓着的 / 挂关节的 / 冻着的**永不删** ----
	var w3 := _world()
	w3.debris_max_mass = 16.0
	w3.debris_min_speed = 2000.0
	var held := _dust(w3, 30000.0)
	w3.grab(held, held.position)
	var anchored := _dust(w3, 30000.0)
	var anchor := _dust(w3, 0.0, 20)
	w3.add_weld(anchored, anchor, anchored.position)
	var parked := _dust(w3, 30000.0)
	w3.freeze(parked)
	w3.step(1.0 / 60.0)
	_c("抓着的没被删", w3.bodies.has(held))
	_c("挂着关节的没被删", w3.bodies.has(anchored))
	_c("冻着的没被删", w3.bodies.has(parked))

	# ---- 5. 只开"豁免"：灰尘留着（内容不丢），但子步不许被它顶起来 ----
	var w4 := _world()
	w4.ccd_ignore_mass = 16.0
	var d4 := _dust(w4, 30000.0)
	w4.step(1.0 / 60.0)
	_c("豁免：灰尘**还在**（没有内容损失）", w4.bodies.has(d4))
	_c("豁免：子步没被它顶起来", w4.last_substeps <= 4, "子步=%d" % w4.last_substeps)

	# ---- 6. 豁免**不能**顺带把重物也豁免掉（否则防穿就废了）----
	var w5 := _world()
	w5.ccd_ignore_mass = 16.0
	var heavy5 := _dust(w5, 30000.0, 32)        # 质量 1024 > 16 -> 必须照样顶子步
	w5.step(1.0 / 60.0)
	_c("重物仍然驱动子步（豁免只对小碎片）", w5.last_substeps == 250 and w5.bodies.has(heavy5),
		"子步=%d" % w5.last_substeps)

	# ---- 7. 豁免也要放过抓着的（玩家手里的小东西必须照旧防穿）----
	var w6 := _world()
	w6.ccd_ignore_mass = 16.0
	var held6 := _dust(w6, 30000.0)
	w6.grab(held6, held6.position)
	# ⚠️ 抓取**本来就有自己的子步上限**（按世界大小摊的 grab_substep_cap）——
	#    这里把它抬掉，才看得到"抓着的那个没被豁免"这件事本身。
	w6.ccd_grab_substep_cost_budget_us = 100000000
	w6.step(1.0 / 60.0)
	_c("抓着的**不豁免**（它照样顶子步）", w6.last_substeps == 250,
		"子步=%d" % w6.last_substeps)

	print("=== %d passed, %d failed ===" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)