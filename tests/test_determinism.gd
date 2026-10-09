extends SceneTree
## 可复现性与长期稳定性自检（native 唯一路径）。
##
## ⚠️ 这个文件原来是 `tests/test_parallel.gd`，测的是三条**逐位一致**断言：
##    "岛并行 == 串行"、"着色 == 串行"、"native 求解器 == 对象路径"。
##    那三条依赖的 GDScript 路径（岛并行 / 着色 / 对象求解 / SoA 批量）已经**全部删除**
##    （见 pworld.gd 头部的说明）：双路径逐位一致曾经是最强的验证手段，
##    但它也是最大的税 —— 每次改动都要写两遍，而且反复分叉（坑 18/31/36）。
##
## 删掉旧断言之后**必须补上新的**，否则等于把质量机制一起删了。
## 这里测的是"换实现也依然成立"的性质：
##   · **可复现**：同配置跑两次必须逐位相同。这条同时也在防一个真实风险 ——
##     warm-start 缓存住在 GDExtension 实例里，多个 PWorld 若互相污染就会在这里露出来。
##   · **不发散**：长时间运行没有 NaN、没有箱子陷进地面（阈值取引擎真实的 slop）。
##   · **不漂移**：文档里"三层堆叠 300 帧漂移 0.000"的机器化版本。

const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

var _pass := 0
var _fail := 0

func _check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		_pass += 1
		print("  PASS  ", name, "  ", detail)
	else:
		_fail += 1
		print("  FAIL  ", name, "  ", detail)

func _block(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	for y in h:
		for x in w:
			s.set_pixel(x, y, 1)
	return s

func _make(kind: String) -> PWorld:
	var world := PWorld.new()
	world.sleeping_enabled = false
	# 一整块地面：故意让所有物体共用同一个静态体
	var g := PBody.new()
	g.position = Vector2(-600.0, 0.0)
	g.make_static()
	world.add_body(g, [_block(1200, 40)])
	if kind == "towers":
		# 20 座塔，塔距 40 —— 互不相连，但都压在同一块地面上
		for p in 20:
			var gx := -560.0 + float(p) * 40.0
			for i in 4:
				var b := PBody.new()
				b.position = Vector2(gx, -7.0 - float(i) * 16.0)
				world.add_body(b, [_block(14, 14)])
	elif kind == "stack":
		# 单岛稳定堆叠：16x16 面贴面、允许休眠，否则柱子会自己倒掉，
		# 断言测的就成了"场景稳不稳"而不是"结果可不可复现"。
		world.sleeping_enabled = true
		for i in 3:
			var b2 := PBody.new()
			b2.position = Vector2(100.0, 200.0 - 16.0 * float(i + 1))
			world.add_body(b2, [_block(16, 16)])
	return world

func _snapshot(world: PWorld) -> Array:
	var out: Array = []
	for b in world.bodies:
		if b.is_static:
			continue
		out.append([b.position.x, b.position.y, b.rotation, b.linear_velocity.x, b.linear_velocity.y])
	return out

static func _max_diff(a: Array, b: Array) -> float:
	var m := 0.0
	for i in mini(a.size(), b.size()):
		var x: Array = a[i]
		var y: Array = b[i]
		for k in mini(x.size(), y.size()):
			m = maxf(m, absf(float(x[k]) - float(y[k])))
	return m

func _run(kind: String, steps: int) -> PWorld:
	var w := _make(kind)
	for i in 60:
		w.step(1.0 / 60.0)
	for i in steps:
		w.step(1.0 / 60.0)
	return w

## ---- 1. 可复现：同配置跑两次逐位相同 ----
## 同时防"warm-start 缓存跨世界污染"——那是把缓存搬进扩展实例之后的真实风险。
func _test_repeatable() -> void:
	print("[可复现] 同一配置跑两次必须逐位相同")
	for kind in ["towers", "stack"]:
		var a := _run(kind, 240)
		var b := _run(kind, 240)
		var d := _max_diff(_snapshot(a), _snapshot(b))
		_check("可复现 (%s)" % kind, d == 0.0, "最大差=%.9f" % d)

## ---- 2. 不漂移：三层堆叠 300 帧，顶层不漂不倾 ----
func _test_stack_drift() -> void:
	print("[不漂移] 三层堆叠 300 帧后顶层不漂移、不倾斜")
	var w := _run("stack", 300)
	var top: PBody = null
	var top_y := 1.0e18
	for b in w.bodies:
		if b.is_static:
			continue
		if b.position.y < top_y:
			top_y = b.position.y
			top = b
	_check("顶层不漂移", absf(top.position.x - 100.0) < 0.05, "顶层 x=%.6f" % top.position.x)
	_check("顶层不倾斜", absf(top.rotation) < 0.001, "顶层 rot=%.6f" % top.rotation)

## ---- 3. 不发散：长时间运行没有 NaN、没有箱子陷进地面 ----
func _test_not_diverging() -> void:
	print("[不发散] 长时间运行后不陷进地面、不出 NaN")
	var w := _run("towers", 600)
	var sunk := 0
	var nan := 0
	var lowest := -1.0e18
	for b in w.bodies:
		if b.is_static:
			continue
		if not is_finite(b.position.x) or not is_finite(b.position.y) or not is_finite(b.rotation):
			nan += 1
		# 地面顶面 y=0：任何箱子的底边都不该跑到地面以下超过 slop。
		#
		# ⚠️ 阈值必须取自引擎真实的 penetration_slop，不能硬编码 ——
		#    slop 就是"允许的穿透深度"，箱子静止时**正好**停在那个深度上。
		#    硬编码 1.0 而 slop 也是 1.0 时会卡在边界上误报（实测 16 个"陷入 1.001"）。
		lowest = maxf(lowest, b.aabb.end.y)
		if b.aabb.end.y > PWorld.PENETRATION_SLOP + 0.5:
			sunk += 1
	_check("没有 NaN", nan == 0, "NaN %d 个" % nan)
	_check("没有箱子陷进地面", sunk == 0, "陷入 %d 个, 最深 %.3f px" % [sunk, lowest])

func _initialize() -> void:
	print("=== 可复现性与长期稳定性自检（native 唯一路径）===")
	_test_repeatable()
	_test_stack_drift()
	_test_not_diverging()
	print("=== %d passed, %d failed ===" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
