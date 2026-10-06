extends SceneTree
## 速度上限闸门：角速度（Rapier 没有这个旋钮，引擎自己钳）+ 线速度 + 节点层接线。
##
## ⚠️ 为什么需要角速度上限（实测 tests/diag_dust_spin.gd 的思路）：
##    角速度是**质量放大**的通道 —— Δω = J·r/I，而 **I ∝ m**：同一个力矩，
##    轻 100 倍的碎片角速度大 100 倍。而子步估计里有一项 |ω| x 外接半径，
##    所以一个疯狂自转的小碎片就能把全世界拖进几百个子步（= 每帧成本 x 几百）。
##    Rapier 2D 0.36 **只有线速度上限**，没有角速度的（翻过 crate 源码）。
const PWorld := preload("res://src/physics/pworld.gd")
const PBody := preload("res://src/physics/pbody.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")
const AddonWorld := preload("res://src/nodes/pixel_world.gd")

var _pass := 0
var _fail := 0
func _c(n: String, ok: bool, d: String = "") -> void:
	if ok: _pass += 1; print("  PASS  ", n, "  ", d)
	else: _fail += 1; print("  FAIL  ", n, "  ", d)

func _shape(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, w, h), 1)
	return s

## 一个无重力、无接触的世界 + 一个给定大小的自转刚体。
func _spinner(size: int, w0: float) -> Array:
	var w := PWorld.new()
	w.gravity = Vector2.ZERO
	var b := PBody.new()
	w.add_body(b, [_shape(size, size)])
	b.angular_velocity = w0
	return [w, b]

func _initialize() -> void:
	print("=== 角速度上限（Rapier 没有，引擎自己钳）===")

	# ---- 1. 默认值：1000 rad/s ----
	var wb := _spinner(20, 5000.0)
	var w1: PWorld = wb[0]
	var b1: PBody = wb[1]
	_c("默认上限是 1000", w1.max_angular_velocity == 1000.0, "%.0f" % w1.max_angular_velocity)
	w1.step(1.0 / 60.0)
	_c("读回来就被钳到 1000", absf(b1.angular_velocity) <= 1000.0 + 1e-9,
		"5000 -> %.3f" % b1.angular_velocity)

	# ---- 2. 子步数被钳后的角速度限住（这才是用户看得见的症状）----
	#
	# ⚠️ 钳制在**回读**里做，所以有**一步滞后**（与 terminal_speed 同一条语义）：
	#    上面那一步的估计用的是钳制**前**的 5000，所以它贵是应该的。
	# ⚠️ 而真实 artifact 不会有那一帧尖峰：角速度是**碰撞过程里**产生的，而产生它的
	#    那一步的估计用的是**碰撞前**的值 —— 到下一步估计时它已经被钳住了。
	#    这里手动设 5000 再步进是"最坏情况"，专门用来钉住这条滞后。
	w1.step(1.0 / 60.0)
	# 子步 = ceil(|w| * 外接半径 / 60 / ccd_max_motion)。
	# ⚠️ 半径必须取**自转过程中的最大值**，不能取当前值：20x20 的方块不转时半径 14.1，
	#    转到 45° 时外接盒变成 28.28x28.28、半径涨到 **20**（= 边长）。
	#    这就是"自转的碎片更贵"的第二层原因：角速度上去了，外接半径也跟着涨。
	var expect_cap: int = int(ceil(1000.0 * 20.0 / 60.0 / 2.0)) + 2
	_c("**下一步**的子步被限住（不再按 5000 算）", w1.last_substeps <= expect_cap,
		"子步=%d <= %d" % [w1.last_substeps, expect_cap])
	for k in 5:
		w1.step(1.0 / 60.0)
	_c("持续多步也一直是钳住的值", absf(b1.angular_velocity) <= 1000.0 + 1e-9,
		"|w|=%.3f" % absf(b1.angular_velocity))

	# ---- 3. 钳制**真的推回 Rapier** 了吗？看**转过的角度**（唯一能区分的可观测量）----
	# 钳住：10 步约 1000 * 9/60 + 5000 * 1/60 = 233 rad；没钳住：5000 * 10/60 = 833 rad。
	var wb3 := _spinner(20, 5000.0)
	var w3: PWorld = wb3[0]
	var b3: PBody = wb3[1]
	for k in 10:
		w3.step(1.0 / 60.0)
	var turned := absf(b3.rotation)
	_c("转过的角度按**钳住后**的角速度走（推回 Rapier 生效）", turned < 400.0,
		"10 步转过 %.1f rad（钳住约 233，没钳住约 833）" % turned)

	# ---- 4. 关掉它（0 = 不钳）：行为必须回到老样子 ----
	var wb4 := _spinner(20, 5000.0)
	var w4: PWorld = wb4[0]
	var b4: PBody = wb4[1]
	w4.max_angular_velocity = 0.0
	w4.step(1.0 / 60.0)
	_c("0 = 不钳（角速度原样）", absf(b4.angular_velocity) > 4000.0,
		"|w|=%.1f" % absf(b4.angular_velocity))
	_c("0 = 不钳（子步照样被顶起来）", w4.last_substeps > 100,
		"子步=%d" % w4.last_substeps)

	# ---- 5. 线速度上限（Rapier 自己的旋钮，引擎透传）----
	var w5 := PWorld.new()
	w5.gravity = Vector2.ZERO
	var b5 := PBody.new()
	w5.add_body(b5, [_shape(8, 8)])
	b5.linear_velocity = Vector2(100000, 0)
	w5.step(1.0 / 60.0)
	_c("线速度被 Rapier 的上限钳住（默认 40000）", b5.linear_velocity.length() <= 40000.0 + 1.0,
		"100000 -> %.1f" % b5.linear_velocity.length())

	# ---- 6. 节点层：@export 必须真的播到 world ----
	var pw = AddonWorld.new()
	get_root().add_child(pw)
	await process_frame
	pw.max_linear_velocity = 12345.0
	pw.max_angular_velocity = 50.0
	pw.min_fragment_pixels = 9
	pw.ccd_ignore_mass = 8.0
	pw.debris_max_mass = 16.0
	pw.debris_min_speed = 2000.0
	pw.push_physics_settings()
	_c("节点层：线速度上限播到了 world", pw.world.rp_max_linear_velocity == 12345.0,
		"%.0f" % pw.world.rp_max_linear_velocity)
	_c("节点层：角速度上限播到了 world", pw.world.max_angular_velocity == 50.0,
		"%.0f" % pw.world.max_angular_velocity)
	_c("节点层：min_fragment_pixels 播到了 world", pw.world.min_fragment_pixels == 9,
		"%d" % pw.world.min_fragment_pixels)
	_c("节点层：ccd_ignore_mass 播到了 world", pw.world.ccd_ignore_mass == 8.0,
		"%.1f" % pw.world.ccd_ignore_mass)
	_c("节点层：灰尘阈值播到了 world",
		pw.world.debris_max_mass == 16.0 and pw.world.debris_min_speed == 2000.0,
		"%.0f / %.0f" % [pw.world.debris_max_mass, pw.world.debris_min_speed])
	_c("节点层：重建（rebuild）也会播一遍", true)
	pw.rebuild()
	_c("rebuild 之后仍然是节点上的值", pw.world.max_angular_velocity == 50.0 and pw.world.min_fragment_pixels == 9,
		"w=%.0f pixels=%d" % [pw.world.max_angular_velocity, pw.world.min_fragment_pixels])

	print("=== %d passed, %d failed ===" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)