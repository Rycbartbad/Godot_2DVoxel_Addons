extends SceneTree
## 物理自检：落地、堆叠稳定性、休眠、破坏分裂

const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")
const Destruction := preload("res://src/core/destruction.gd")

var _pass := 0
var _fail := 0

func _check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		_pass += 1
		print("  PASS  ", name, "  ", detail)
	else:
		_fail += 1
		print("  FAIL  ", name, "  ", detail)

func _box_shape(w: int, h: int, ox: int = 0, oy: int = 0) -> PixelShape:
	var s := PixelShape.new()
	for y in h:
		for x in w:
			s.set_pixel(ox + x, oy + y, 1)
	return s

func _initialize() -> void:
	print("=== 2D physics self-test ===")
	_test_single_drop()
	_test_stack()
	_test_sleep()
	_test_torque_reaches_engine()
	_test_fracture()
	_test_offset_origin_rotation()
	_test_advance()
	print("=== %d passed, %d failed ===" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

func _make_world() -> PWorld:
	var w := PWorld.new()
	return w

func _add_ground(world: PWorld, y: float) -> PBody:
	var g := PBody.new()
	g.position = Vector2(0, y)
	g.make_static()
	world.add_body(g, [_box_shape(240, 16)])
	return g

func _test_single_drop() -> void:
	print("[single drop]")
	var world := _make_world()
	_add_ground(world, 200.0)
	var b := PBody.new()
	b.position = Vector2(100, 40)
	world.add_body(b, [_box_shape(16, 16)])
	for i in 400:
		world.step(1.0 / 60.0)
	var bottom: float = b.aabb.end.y
	_check("rests on ground", absf(bottom - 200.0) < 1.0, "bottom=%.3f" % bottom)
	_check("settled", b.linear_velocity.length() < 1.0, "v=%.3f" % b.linear_velocity.length())
	_check("no sideways drift", absf(b.position.x - 100.0) < 0.5, "x=%.3f" % b.position.x)

func _test_stack() -> void:
	print("[stack of 3]")
	var world := _make_world()
	_add_ground(world, 200.0)
	var boxes: Array = []
	for i in 3:
		var b := PBody.new()
		b.position = Vector2(100, 184.0 - 16.0 * (i + 1) + 16.0)
		b.position.y = 200.0 - 16.0 * (i + 1)
		world.add_body(b, [_box_shape(16, 16)])
		boxes.append(b)
	for i in 900:
		world.step(1.0 / 60.0)
	for i in 3:
		var b2: PBody = boxes[i]
		# 每个接触面允许 penetration_slop 以内的下陷，所以要按"相对下方支撑面"判定，
		# 而不是绝对高度（误差会沿堆叠累积）。
		var support_top := 200.0 if i == 0 else (boxes[i - 1] as PBody).aabb.position.y
		_check("box %d rests" % i, absf(b2.aabb.end.y - support_top) < 0.6,
			"bottom=%.3f support=%.3f sink=%.3f" % [b2.aabb.end.y, support_top, b2.aabb.end.y - support_top])
		_check("box %d no drift" % i, absf(b2.position.x - 100.0) < 0.05,
			"x=%.5f" % b2.position.x)
		_check("box %d no tilt" % i, absf(b2.rotation) < 0.001,
			"rot=%.6f" % b2.rotation)
		_check("box %d sleeping" % i, not b2.awake, "awake=%s" % b2.awake)

## ⚠️⚠️ 力矩必须真的传到物理内核。
##
## 病灶（2026 年这轮才发现）：桥接函数 `rb_body_add_force(id, fx, fy, torque)` 的
## **torque 参数接了但没用** —— 函数体里只有 `add_force`，没有 `add_torque`。
## 后果是整个项目的力矩**静默失效**：`accum_torque`、抓取的角阻尼、任何靠力矩
## 转起来的玩法全都不动。表现是"摆动怎么调都不衰减"（实测摆幅 12 秒恒在 150~180 度，
## 阻尼从 0 调到 20 毫无变化）—— 甲方原话"摆动的方式不对"。
##
## 这条断言把"力矩生效"钉死：无重力、无力，只给力矩 -> 角速度必须涨。
func _test_torque_reaches_engine() -> void:
	print("[力矩真的生效]")
	var world := PWorld.new()
	world.gravity = Vector2.ZERO
	var b := PBody.new()
	b.position = Vector2(100, 100)
	world.add_body(b, [_box_shape(16, 16)])
	b.accum_torque = 200000.0                 # 持续力矩（每子步推一次）
	for i in 30:
		world.step(1.0 / 60.0)
	_check("持续力矩把物体转起来", b.angular_velocity > 1.0,
		"30 步后角速度 %.3f rad/s" % b.angular_velocity)


func _test_sleep() -> void:
	print("[sleep]")
	var world := _make_world()
	_add_ground(world, 200.0)
	var b := PBody.new()
	b.position = Vector2(100, 150)
	world.add_body(b, [_box_shape(16, 16)])
	for i in 600:
		world.step(1.0 / 60.0)
	_check("body fell asleep", not b.awake, "awake=%s timer=%.2f" % [b.awake, b.sleep_timer])

func _test_fracture() -> void:
	print("[fracture]")
	var world := _make_world()
	world.gravity = Vector2.ZERO
	var bar := PBody.new()
	bar.position = Vector2(0, 0)
	world.add_body(bar, [_box_shape(64, 8)])
	var before: int = bar.shapes[0].pixel_count()
	_check("bar pixels", before == 512, str(before))
	var frags := world.fracture(bar, Destruction.Damage.rect(Vector2(32.5, 4.0), Vector2(2.0, 4.0)))
	_check("fractured into 1 fragment", frags.size() == 1, str(frags.size()))
	var total: int = bar.shapes[0].pixel_count()
	for f: PBody in frags:
		total += f.shapes[0].pixel_count()
	_check("mass conserved", total == 512 - 40, "%d (want %d)" % [total, 512 - 40])
	_check("original keeps 240", bar.shapes[0].pixel_count() == 240, str(bar.shapes[0].pixel_count()))
	if frags.size() == 1:
		var f2: PBody = frags[0]
		_check("fragment has 232", f2.shapes[0].pixel_count() == 232, str(f2.shapes[0].pixel_count()))
		_check("fragment inherited velocity", f2.linear_velocity.length() > 0.0, str(f2.linear_velocity))
		# 碎片应该已经有质量与碰撞形状
		_check("fragment mass", is_equal_approx(f2.mass, 232.0), str(f2.mass))
		_check("fragment rects", f2.rects.size() >= 1, str(f2.rects.size()))

func _test_offset_origin_rotation() -> void:
	print("[offset origin rotation]")
	# 形状离 Body 原点很远（画笔绘制出来的物体就是这样）。
	# 旋转时必须绕质心，质心在无外力时不应移动。
	var world := PWorld.new()
	world.gravity = Vector2.ZERO
	var b := PBody.new()
	b.position = Vector2.ZERO
	var s := PixelShape.new()
	for y in 8:
		for x in 8:
			s.set_pixel(500 + x, 300 + y, 1)
	world.add_body(b, [s])
	var com0 := b.com_world()
	_check("com is at blob centre", com0.is_equal_approx(Vector2(504.0, 304.0)), str(com0))
	b.angular_velocity = 3.0
	for i in 60:
		world.step(1.0 / 60.0)
	var com1 := b.com_world()
	_check("com did not move", com0.distance_to(com1) < 0.01, "%.5f" % com0.distance_to(com1))
	_check("body did rotate", absf(b.rotation) > 1.0, "rot=%.3f" % b.rotation)


## ⚠️ 这一条是被**真实事故**逼出来的：删 pworld 里相邻的几个函数时误伤了 advance()，
##    而当时没有任何测试覆盖它 —— 直到 demo 跑起来才炸
##    （game.gd: "Nonexistent function 'advance' in base 'RefCounted (pworld.gd)'"）。
##    公共 API 里"只被 demo 用"的那几个，正是最容易被静默删掉的。
func _test_advance() -> void:
	print("[advance]")
	var world := _make_world()
	_add_ground(world, 200.0)
	var b := PBody.new()
	b.position = Vector2(100, 100)
	world.add_body(b, [_box_shape(16, 16)])
	var y0: float = b.position.y
	# fixed_dt 是 1/60；喂 0.05 秒应当正好走 3 步
	var n: int = world.advance(0.05)
	_check("advance 返回整数步数", n == 3, str(n))
	_check("advance 之后物体确实动了", b.position.y > y0, "%.3f -> %.3f" % [y0, b.position.y])
	# 不足一步的余量必须留着 —— 吞掉的话慢帧率下物理会越来越慢
	var n2: int = world.advance(0.001)
	_check("不足一步时不推进、余量保留", n2 == 0, str(n2))
	var n3: int = world.advance(0.02)
	_check("余量攒够后补上一步", n3 == 1, str(n3))
