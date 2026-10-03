extends SceneTree
## 关节自检：五种类型、限位、马达、断裂、静态锚定、刚体删除时的清理。
##
## 为什么要单独一个脚本：关节是**跨三层**的（GDScript 参数 -> 命令流 -> Rust/Rapier），
## 任何一层写错都不会报错，只会"看起来没连上"或者"连上了但位置慢慢漂"。

const PBody := preload("res://src/physics/pbody.gd")
const Grab := preload("res://src/physics/grab.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")
const PJoint := preload("res://src/physics/joint.gd")

var _pass := 0
var _fail := 0

func _check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		_pass += 1
		print("  PASS  ", name, "  ", detail)
	else:
		_fail += 1
		print("  FAIL  ", name, "  ", detail)

func _box_shape(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	for y in h:
		for x in w:
			s.set_pixel(x, y, 1)
	return s

func _make_world() -> PWorld:
	return PWorld.new()

func _static_box(world: PWorld, pos: Vector2, rot := 0.0) -> PBody:
	var b := PBody.new()
	b.position = pos
	b.rotation = rot
	b.make_static()
	world.add_body(b, [_box_shape(16, 16)])
	return b

func _dynamic_box(world: PWorld, pos: Vector2, rot := 0.0) -> PBody:
	var b := PBody.new()
	b.position = pos
	b.rotation = rot
	world.add_body(b, [_box_shape(16, 16)])
	return b

func _initialize() -> void:
	print("=== joint self-test ===")
	_test_hinge_pendulum()
	_test_hinge_limits()
	_test_hinge_motor()
	_test_slider()
	_test_weld()
	_test_overlap_no_contacts()
	_test_grab_angular_damping()
	_test_grab_welded()
	_test_rope()
	_test_spring()
	_test_remove_and_body_delete()
	_test_break()
	_test_is_jointed_to_static()
	print("=== %d passed, %d failed ===" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _test_hinge_pendulum() -> void:
	print("[hinge: 摆]")
	var world := _make_world()
	# 支点取刚体原点（左上角），质心在右下 -> 重力有力矩，摆得起来。
	var b := _dynamic_box(world, Vector2(100, 100))
	var pivot := Vector2(100, 100)
	# ⚠️ 量的是**质心**位移：支点就取在刚体原点上，所以原点（position）本来就不动 ——
	#    第一版量 position，于是"摆起来了"永远测成 0.00（物理是对的，判据是错的）。
	var com0 := b.com_world()
	var j: PJoint = world.add_hinge(b, null, pivot)
	_check("hinge 建出来了", j != null and j.rapier_id == 0, "等第一子步分配 id")
	world.step(1.0 / 60.0)
	_check("hinge 有 rapier_id", j.rapier_id > 0, "id=%d" % j.rapier_id)
	for i in 180:
		world.step(1.0 / 60.0)
	var anchor := j.anchor_a_world()
	_check("支点没跑", anchor.distance_to(pivot) < 1.0, "anchor=%s 期望=%s" % [anchor, pivot])
	_check("确实摆起来了", b.com_world().distance_to(com0) > 2.0, "质心位移=%.2f" % b.com_world().distance_to(com0))
	_check("角度在动", absf(j.movement()) > 0.05, "movement=%.4f" % j.movement())


func _test_hinge_limits() -> void:
	print("[hinge: 限位]")
	var world := _make_world()
	var b := _dynamic_box(world, Vector2(100, 100))
	var j: PJoint = world.add_hinge(b, null, Vector2(100, 100))
	j.set_limits(-0.2, 0.2)
	for i in 300:
		world.step(1.0 / 60.0)
	_check("限位把摆角压住了", absf(j.movement()) < 0.25, "movement=%.4f" % j.movement())
	_check("限位确实被用上了（不是没动）", absf(j.movement()) > 0.15, "movement=%.4f" % j.movement())
	# 对照：不设限位时同一个场景会荡得更远
	var world2 := _make_world()
	var b2 := _dynamic_box(world2, Vector2(100, 100))
	var j2: PJoint = world2.add_hinge(b2, null, Vector2(100, 100))
	var max_ang := 0.0
	for i in 300:
		world2.step(1.0 / 60.0)
		max_ang = maxf(max_ang, absf(j2.movement()))
	_check("不设限位时摆得更远（对照）", max_ang > 0.3, "max=%.4f" % max_ang)


func _test_hinge_motor() -> void:
	print("[hinge: 马达]")
	var world := _make_world()
	world.gravity = Vector2.ZERO
	# ⚠️ 世界默认给每个刚体 0.6 的角阻尼（见 PWorld.rp_angular_damping）。
	#    不关掉的话，测到的是"马达推力 vs 阻尼"的平衡点（实测 2.5 而不是 3.0）——
	#    那是**对的物理**，但这条测的是马达本身。
	world.rp_angular_damping = 0.0
	var b := _dynamic_box(world, Vector2(100, 100))
	var j: PJoint = world.add_hinge(b, null, Vector2(100, 100))
	j.set_motor_velocity(3.0, 1.0e7)
	for i in 90:
		world.step(1.0 / 60.0)
	# Rapier 的马达是软约束：damp=100 时稳态差 ~1%（实测 2.97/3.0），所以容差取 0.1。
	_check("速度马达跑到目标角速度", absf(j.speed() - 3.0) < 0.1, "speed=%.3f" % j.speed())
	j.set_motor_target(1.0, 1.0e7)
	for i in 240:
		world.step(1.0 / 60.0)
	_check("位置伺服停在目标角", absf(j.movement() - 1.0) < 0.1, "movement=%.3f" % j.movement())
	j.motor_off()
	_check("马达关掉后模式是 OFF", j.motor_mode == PJoint.MOTOR_OFF)


func _test_slider() -> void:
	print("[slider: 滑轨]")
	var world := _make_world()
	var b := _dynamic_box(world, Vector2(100, 100))
	var j: PJoint = world.add_slider(b, null, Vector2(100, 100), Vector2.RIGHT)
	for i in 120:
		world.step(1.0 / 60.0)
	_check("垂直方向被锁住", absf(b.position.y - 100.0) < 0.5, "y=%.3f" % b.position.y)
	_check("没有外力时不动", absf(j.movement()) < 1.0, "movement=%.3f" % j.movement())
	b.apply_central_impulse(Vector2(6000, 0))
	for i in 60:
		world.step(1.0 / 60.0)
	_check("沿轴滑出去了", j.movement() > 5.0, "movement=%.3f" % j.movement())
	_check("滑轨的 speed 是沿轴的", j.speed() > 1.0, "speed=%.3f" % j.speed())
	# 限位
	j.set_limits(-4.0, 4.0)
	b.apply_central_impulse(Vector2(60000, 0))
	for i in 240:
		world.step(1.0 / 60.0)
	_check("限位挡住了滑动", j.movement() < 4.5, "movement=%.3f" % j.movement())


## 重合体素 + 关节：默认**不生成接触**，否则接触求解器和关节会一直打架（抽搐）。
##
## ⚠️ 判据不能用"求解后的速度" —— 两股冲量在同一子步里互相抵消，速度看着是 0，
##    而位置在一步步来回弹。要量**逐帧位移跳变**（见 diag_joint_overlap 的实测：
##    互碰时 0.785 px/步、关节冲量 121280；不碰时 0.0000、冲量 0）。
func _overlap_jump(contacts: bool) -> Array:
	var world := _make_world()
	world.gravity = Vector2.ZERO
	var a := PBody.new()
	a.position = Vector2(100, 100)
	world.add_body(a, [_box_shape(16, 16)])
	var b := PBody.new()
	b.position = Vector2(108, 100)      # 与 a 重合 8 像素
	world.add_body(b, [_box_shape(16, 16)])
	var j: PJoint = world.add_weld(a, b, Vector2(108, 108))
	j.contacts_enabled = contacts
	var max_jump := 0.0
	var max_contacts := 0
	var pa := a.position
	var pb := b.position
	for i in 240:
		world.step(1.0 / 60.0)
		max_jump = maxf(max_jump, a.position.distance_to(pa) + b.position.distance_to(pb))
		pa = a.position
		pb = b.position
		max_contacts = maxi(max_contacts, world.last_contacts)
	return [max_jump, max_contacts]


## 拖**焊接组件**：力控 + 正确的支点/惯量。
##
## ⚠️⚠️ 这条测试**曾经断言"组件不转"** —— 那是"按质心分配冲量、力矩为 0"的错误实现。
##    甲方明确指出「转动的支点/惯量不太对」：抓一个点，物体本来就该**绕那个点**转。
##    现在断言三件事：
##      1. 焊接不被拉变形（中心距恒定）；
##      2. 抓点跟得上（力控允许滞后，但必须有界 —— 不能"抓丢了"）；
##      3. **重力力矩生效**：抓点偏在一侧时，组件必须转下去（钟摆）。
func _grab_welded(grab_b: bool, offset: Vector2, steps: int) -> Array:
	var world := _make_world()
	var a := PBody.new()
	a.position = Vector2(100, 240)
	world.add_body(a, [_box_shape(16, 16)])
	var b := PBody.new()
	b.position = Vector2(120, 240)
	world.add_body(b, [_box_shape(16, 16)])
	world.add_weld(a, b, Vector2(116, 248))
	var target: PBody = b if grab_b else a
	var start: Vector2 = target.position + Vector2(8, 8) + offset
	world.grab(target, start)
	var ja := 0.0
	var jb := 0.0
	var max_d := 0.0
	var min_d := 999.0
	var max_err := 0.0
	var ang0: float = a.position.angle_to_point(b.position)
	var ang := 0.0
	var pa: Vector2 = a.position
	var pb: Vector2 = b.position
	var drag := offset == Vector2.ZERO      # offset=0 时才是"拖动"，否则是"挂着看它垂"
	for i in steps:
		if drag:
			world.set_grab_target(start + Vector2(2.0 * i, 0))     # 120 px/s
		world.step(1.0 / 60.0)
		ja = maxf(ja, a.position.distance_to(pa))
		jb = maxf(jb, b.position.distance_to(pb))
		var d: float = a.position.distance_to(b.position)
		max_d = maxf(max_d, d)
		min_d = minf(min_d, d)
		var g0 = world.grabs[0]
		max_err = maxf(max_err, g0.target.distance_to(g0.anchor_world()))
		ang = rad_to_deg(absf(angle_difference(a.position.angle_to_point(b.position), ang0)))
		pa = a.position
		pb = b.position
	return [ja, jb, max_d - min_d, max_err, ang]
func _test_grab_welded() -> void:
	print("[拖动焊接组件：力控 / 支点 / 重力力矩]")
	for grab_b in [false, true]:
		var r: Array = _grab_welded(grab_b, Vector2.ZERO, 300)
		var who := "抓右边" if grab_b else "抓左边"
		_check("%s：焊接处没被拉开" % who, r[2] < 0.01, "中心距波动 %.4f" % r[2])
		# 力控允许滞后（这正是"重物要滞后"的手感），但不能抓丢。
		_check("%s：抓点跟得上（滞后有界）" % who, r[3] < 60.0, "最大滞后 %.1f px" % r[3])
	# 钟摆：抓点在组件左上方 40px -> 组件质心必须转下去（重力力矩生效）。
	var p: Array = _grab_welded(false, Vector2(-40, -20), 480)
	_check("重力力矩生效（挂起来会垂下去）", p[4] > 20.0, "转角 %.1f 度" % p[4])


## 抓取的**角阻尼必须真的作用到物理**。
##
## ⚠️ 桥接函数 `rb_body_add_force(id, fx, fy, torque)` 曾经**把 torque 参数丢掉**
## （函数体里只有 add_force）—— 整个项目的力矩静默失效：抓取的角阻尼、`accum_torque`、
## 任何靠力矩转起来的玩法全都不动。表现是"摆动怎么调都不衰减"
## （实测摆幅 12 秒恒在 150~180 度，阻尼 0 -> 20 毫无变化）。
## 这条断言把它钉死：转起来的焊接组件被抓着，角速度必须明显衰减。
func _test_grab_angular_damping() -> void:
	print("[抓取角阻尼：力矩真的生效]")
	var world := _make_world()
	world.gravity = Vector2.ZERO
	var a := PBody.new()
	a.position = Vector2(100, 100)
	world.add_body(a, [_box_shape(16, 16)])
	var b := PBody.new()
	b.position = Vector2(120, 100)
	world.add_body(b, [_box_shape(16, 16)])
	world.add_weld(a, b, Vector2(116, 108))
	a.angular_velocity = 5.0
	b.angular_velocity = 5.0
	var g: Grab = world.grab(a, a.position + Vector2(8, 8))
	g.ang_damp = 8.0
	for i in 120:
		world.set_grab_target(a.position + Vector2(8, 8))
		world.step(1.0 / 60.0)
	# 阈值 4.4（衰减 > 12%）：修之前这里**不但不衰减，还会涨到 15+**
	# （角速度阻尼力矩被桥接丢掉，抓取的泵能量没有对手）。
	_check("角阻尼把自转刹住", absf(a.angular_velocity) < 4.4,
		"2 秒后角速度 %.3f（初始 5.0）" % a.angular_velocity)


func _test_overlap_no_contacts() -> void:
	print("[重合体素：关节默认不生成接触]")
	_check("默认就是关（Box2D 的 collideConnected=false 同款默认）",
		not PJoint.new().contacts_enabled)
	var off: Array = _overlap_jump(false)
	_check("不碰：不抖", off[0] < 0.01, "逐帧跳变=%.4f" % off[0])
	_check("不碰：真的没有接触", off[1] == 0, "接触数=%d" % off[1])
	var on: Array = _overlap_jump(true)
	_check("打开后会打架（对照，证明判据抓得到）", on[0] > 0.1,
		"逐帧跳变=%.4f 接触数=%d" % [on[0], on[1]])


func _test_weld() -> void:
	print("[weld: 焊接]")
	var world := _make_world()
	# ⚠️ 两个刚体**各自转过不同角度** —— 这正是第一版会出错的地方：
	#    Rapier 的关节帧默认单位旋转，焊接会把它俩硬拧到同一个朝向。
	var a := _static_box(world, Vector2(100, 100), 0.5)
	var b := _dynamic_box(world, Vector2(140, 100), -0.3)
	var rel0 := b.rotation - a.rotation
	var j: PJoint = world.add_weld(a, b, Vector2(120, 105))
	world.step(1.0 / 60.0)
	for i in 240:
		world.step(1.0 / 60.0)
	var rel1 := wrapf(b.rotation - a.rotation, -PI, PI)
	_check("焊接保持相对朝向（不会被拧正）", absf(rel1 - rel0) < 0.05, "rel0=%.3f rel1=%.3f" % [rel0, rel1])
	_check("焊接点没散开", j.anchor_a_world().distance_to(j.anchor_b_world()) < 1.0,
		"距离=%.3f" % j.anchor_a_world().distance_to(j.anchor_b_world()))
	# ⚠️ 建关节时的"零位"必须用**刚体当前**的位姿（而不是 Rapier 那边的旧值）。
	#    这条是加 demo 演示时踩出来的：add_body 之后改 rotation 再建焊接，
	#    关节零位会错位（表现是"焊完自己转一下才停"）。
	var world3 := _make_world()
	var wa := _static_box(world3, Vector2(100, 100), 0.0)
	var wb := PBody.new()
	wb.position = Vector2(140, 100)
	world3.add_body(wb, [_box_shape(16, 16)])
	world3.step(1.0 / 60.0)    # 先跑一步：它有了 rapier_id，位姿也已经同步过
	wb.rotation = 0.7          # 现在才转 —— 这一改动**还没**推给 Rapier
	# （⚠️ 必须先跑一步：如果刚体是在同一子步里建的，_rp_create_missing 会带着
	#   当前旋转建体，那条路本来就不会错 —— 测不到这个坑。第一版就是这么写的，
	#   探针去掉修复后仍然全绿，等于白测。）
	var j3: PJoint = world3.add_weld(wa, wb, Vector2(120, 105))
	for i in 120:
		world3.step(1.0 / 60.0)
	_check("建关节时用的是当前位姿（不会被拧回 0）", absf(wrapf(wb.rotation - 0.7, -PI, PI)) < 0.05,
		"rot=%.3f" % wb.rotation)


func _test_rope() -> void:
	print("[rope: 绳]")
	var world := _make_world()
	var b := _dynamic_box(world, Vector2(100, 100))
	var j: PJoint = world.add_rope(b, null, Vector2(100, 100), Vector2(100, 100), 50.0)
	for i in 240:
		world.step(1.0 / 60.0)
	var d := j.anchor_a_world().distance_to(j.anchor_b_world())
	_check("绳长没超过上限", d <= 51.0, "距离=%.3f 上限=50" % d)
	_check("确实被绳吊住了（不是没掉）", d > 40.0, "距离=%.3f" % d)


func _test_spring() -> void:
	print("[spring: 弹簧]")
	var world := _make_world()
	world.gravity = Vector2.ZERO
	var b := _dynamic_box(world, Vector2(100, 150))
	var j: PJoint = world.add_spring(b, null, Vector2(100, 100), Vector2(100, 150), 20.0, 200.0, 20.0)
	for i in 600:
		world.step(1.0 / 60.0)
	var d := j.anchor_a_world().distance_to(j.anchor_b_world())
	_check("弹簧收敛到静止长度", absf(d - 20.0) < 2.0, "距离=%.3f 期望=20" % d)
	_check("movement 报的是距离", absf(j.movement() - d) < 0.001, "movement=%.3f" % j.movement())


func _test_remove_and_body_delete() -> void:
	print("[移除 / 刚体删除]")
	var world := _make_world()
	# ⚠️ 这里**不能**在下面放静态块：第一版把支点刚体放在 (100,100)，
	#    于是断开后物体只掉 4 px 就落在它上面了（y=84），判据却写的是"掉到 110 以下"。
	var b := _dynamic_box(world, Vector2(100, 80))
	var j: PJoint = world.add_hinge(b, null, Vector2(108, 88))
	world.step(1.0 / 60.0)
	_check("关节在 Rapier 里存在", world.rp_joint_count() == 1, "count=%d" % world.rp_joint_count())
	world.remove_joint(j)
	_check("移除后关节表空了", world.joints.is_empty() and not j.is_active())
	_check("Rapier 侧也删了", world.rp_joint_count() == 0, "count=%d" % world.rp_joint_count())
	for i in 90:
		world.step(1.0 / 60.0)
	_check("关节断开后物体掉下来", b.position.y > 110.0, "y=%.3f" % b.position.y)
	# 刚体被删 -> 挂在它上面的关节跟着清（Rapier 侧是自动删的，GDScript 侧要跟着）
	var a2 := _dynamic_box(world, Vector2(300, 100))
	var b2 := _dynamic_box(world, Vector2(320, 100))
	var j2: PJoint = world.add_hinge(a2, b2, Vector2(310, 100))
	world.step(1.0 / 60.0)
	_check("第二个关节建出来了", j2.rapier_id > 0, "id=%d" % j2.rapier_id)
	_check("第二个关节在 Rapier 里", world.rp_joint_count() == 1, "count=%d" % world.rp_joint_count())
	world.remove_body(b2)
	_check("刚体删除后关节被清掉", world.joints.is_empty() and not j2.is_active())
	_check("Rapier 侧没泄漏", world.rp_joint_count() == 0, "count=%d" % world.rp_joint_count())


func _test_break() -> void:
	print("[断裂]")
	var world := _make_world()
	var b := _dynamic_box(world, Vector2(100, 100))
	var j: PJoint = world.add_hinge(b, null, Vector2(100, 100))
	j.break_impulse = 1.0     # 极小 -> 重力载荷一定超
	for i in 120:
		world.step(1.0 / 60.0)
	_check("冲量超阈值 -> 断", j.is_broken(), "impulse=%.1f" % j.last_impulse)
	_check("断掉的关节记进了 broken_joints", world.broken_joints.size() == 1)
	_check("断掉后不在活动表里", world.joints.is_empty())
	for i in 90:
		world.step(1.0 / 60.0)
	_check("断掉后物体掉下来", b.position.y > 120.0, "y=%.3f" % b.position.y)
	# 阈值很大 -> 不断
	var world2 := _make_world()
	var b2 := _dynamic_box(world2, Vector2(100, 100))
	var j2: PJoint = world2.add_hinge(b2, null, Vector2(100, 100))
	j2.break_impulse = 1.0e9
	for i in 180:
		world2.step(1.0 / 60.0)
	_check("阈值大时不断", not j2.is_broken(), "impulse=%.1f" % j2.last_impulse)
	_check("阈值大时关节还在", world2.joints.size() == 1)


func _test_is_jointed_to_static() -> void:
	print("[静态锚定判定]")
	var world := _make_world()
	var a := _dynamic_box(world, Vector2(100, 100))
	var b := _dynamic_box(world, Vector2(140, 100))
	var c := _dynamic_box(world, Vector2(180, 100))
	var d := _dynamic_box(world, Vector2(220, 100))
	world.add_hinge(a, null, Vector2(100, 100))
	world.add_hinge(a, b, Vector2(120, 100))
	world.add_rope(b, c, Vector2(150, 100), Vector2(190, 100), 60.0)
	world.step(1.0 / 60.0)
	_check("直接锚定", world.is_jointed_to_static(a))
	_check("经一个关节锚定", world.is_jointed_to_static(b))
	_check("经两个关节锚定（传递）", world.is_jointed_to_static(c))
	_check("没连上的不算", not world.is_jointed_to_static(d))
	_check("joints_of 只返回自己那一端", world.joints_of(c).size() == 1)
