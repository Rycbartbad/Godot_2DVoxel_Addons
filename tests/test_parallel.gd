extends SceneTree
## 并行求解的正确性自检（补上"着色并行与串行结果一致"这条缺口）。
##
## 为什么必须有这一组：
##   · 岛并行 / 着色并行都会改变**约束的求解顺序**，而顺序冲量法是顺序相关的；
##   · 岛并行里岛之间互不相连，所以理论上应当与串行**逐位一致**——
##     这是一个可以被断言钉死的强命题，以前只靠肉眼看过一次"堆叠漂移 0.000"。
##   · 着色会改变跨色顺序，只能要求"足够接近"，不能要求逐位一致。
##
## 另外钉死一个真实踩过的 bug：_build_islands 曾经**穿过静态体做 union**，
## 于是任何带一整块地面的场景都退化成 1 个岛，岛并行名存实亡。
## 这里直接断言"地面上多个互不相连的塔必须是多个岛"。

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

## mode: 0=串行  1=岛并行  2=着色
func _make(kind: String, mode: int) -> PWorld:
	var world := PWorld.new()
	world.sleeping_enabled = false
	match mode:
		0:
			world.use_threads = false
			world.use_coloring = false
		1:
			world.use_threads = true
			world.use_coloring = false
		2:
			world.use_threads = true
			world.use_coloring = true
	# 一整块地面：故意让所有物体共用同一个静态体（bug 的触发条件）
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
		# 单岛稳定堆叠：完全沿用 validation_stack_drift 的场景
		# （16x16 面贴面、允许休眠），否则柱子会自己倒掉，
		# 断言测的就成了"场景稳不稳"而不是"并行对不对"。
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

func _run(kind: String, mode: int, steps: int) -> PWorld:
	var w := _make(kind, mode)
	# 本文件测的是"岛并行 / 着色并行"这两条**GDScript 对象路径**，
	# 而 native 求解器是第三条路（既不分组也不并行），默认已开启 —— 必须关掉它。
	w.use_native_solve = false
	for i in 60:
		w.step(1.0 / 60.0)
	for i in steps:
		w.step(1.0 / 60.0)
	return w

## ---- 1. 岛结构：静态体不得把互不相连的塔并成一个岛 ----
func _test_island_split() -> void:
	print("[岛结构] 共用一块地面不该把互不相连的塔并起来")
	var w := _make("towers", 1)
	# ⚠️ 这一组测的是**对象路径**的岛拆分。native 求解器不走岛、也不走线程，
	#    不显式关掉它，manifolds 就是空的 —— 断言会"全绿但什么都没测"。
	w.use_native_solve = false
	for i in 60:
		w.step(1.0 / 60.0)
	var islands := w._build_islands()
	var biggest := 0
	for isle: Dictionary in islands:
		biggest = maxi(biggest, (isle["manifolds"] as Array).size())
	_check("多岛被正确拆开", islands.size() >= 10,
		"岛=%d 流形=%d" % [islands.size(), w.manifolds.size()])
	_check("没有单岛吃掉大部分工作量", biggest < w.manifolds.size(),
		"最大岛=%d / 总数=%d" % [biggest, w.manifolds.size()])
	_check("确实走了并行路径", w.last_parallel_tasks >= 2,
		"并行任务数=%d" % w.last_parallel_tasks)

## ---- 2. 岛并行 == 串行（逐位一致）----
func _test_island_parallel_equals_serial() -> void:
	print("[岛并行 vs 串行] 应当逐位一致（岛间零耦合）")
	var a := _run("towers", 0, 240)
	var b := _run("towers", 1, 240)
	var d := _max_diff(_snapshot(a), _snapshot(b))
	_check("多岛场景逐位一致", d == 0.0, "最大差=%.9f" % d)

## ---- 2b. native 求解器 == 对象路径（逐位一致）----
## 求解器搬进 C++ 后，宽相输出直接喂给 C++（连 Manifold/Point 对象都不建），
## 结果必须与对象路径逐位相同。这条断言是那次移植的回归闸门 ——
## 两个根因（Vector2*real_t 的标量截断顺序、_wake_pass 漏了第三个 manifolds 消费者）
## 都是靠它抓出来的，其中后者只在**带休眠**的场景里才暴露。
func _run_native(kind: String, native: bool, steps: int) -> PWorld:
	var w := _make(kind, 1)
	w.use_native_solve = native
	for i in 60:
		w.step(1.0 / 60.0)
	for i in steps:
		w.step(1.0 / 60.0)
	return w

func _test_native_solve_equals_object() -> void:
	print("[native 求解器 vs 对象路径] 应当逐位一致")
	for kind in ["towers", "stack"]:
		var a := _run_native(kind, false, 240)
		var b := _run_native(kind, true, 240)
		var d := _max_diff(_snapshot(a), _snapshot(b))
		_check("逐位一致 (%s，%s)" % [kind, "含休眠" if kind == "stack" else "无休眠"],
			d == 0.0, "最大差=%.9f" % d)


## ---- 3. 着色并行与串行足够接近，且"堆叠不漂移"这个已知结论仍然成立 ----
func _test_colored_matches_serial() -> void:
	print("[着色 vs 串行] 允许微小差异，但不能漂移")
	var a := _run("stack", 0, 300)
	var c := _run("stack", 2, 300)
	var d := _max_diff(_snapshot(a), _snapshot(c))
	_check("单岛堆叠与串行一致", d < 1e-6, "最大差=%.9f" % d)
	# 顶层 = 最高的那个箱子（y 最小）
	var top: PBody = null
	var top_y := 1.0e18
	for b in c.bodies:
		if b.is_static:
			continue
		if b.position.y < top_y:
			top_y = b.position.y
			top = b
	# 这是文档里 "三层堆叠 300 帧漂移 0.000" 的机器化版本：
	# 以前只有 validation_stack_drift 打印过数字，没有断言。
	_check("着色后顶层不漂移", absf(top.position.x - 100.0) < 0.05, "顶层 x=%.6f" % top.position.x)
	_check("着色后顶层不倾斜", absf(top.rotation) < 0.001, "顶层 rot=%.6f" % top.rotation)
	# 岛并行走的是另一条代码路径（整岛跑完 10 次迭代），同样要钉住
	var b3 := _run("stack", 1, 300)
	var top3: PBody = null
	var ty3 := 1.0e18
	for b4 in b3.bodies:
		if b4.is_static:
			continue
		if b4.position.y < ty3:
			ty3 = b4.position.y
			top3 = b4
	_check("岛并行后顶层不漂移", absf(top3.position.x - 100.0) < 0.05, "顶层 x=%.6f" % top3.position.x)

## ---- 4. 可复现性：同配置跑两次必须完全一样 ----
func _test_repeatable() -> void:
	print("[可复现] 同一配置跑两次结果相同")
	var a := _run("towers", 1, 120)
	var b := _run("towers", 1, 120)
	_check("岛并行可复现", _max_diff(_snapshot(a), _snapshot(b)) == 0.0)
	var c := _run("towers", 2, 120)
	var d2 := _run("towers", 2, 120)
	_check("着色可复现", _max_diff(_snapshot(c), _snapshot(d2)) == 0.0)

## ---- 5. 并行路径不发散：长时间运行后没人陷进地面，也没有 NaN ----
func _test_parallel_not_diverging() -> void:
	print("[并行不发散] 长时间运行后不陷进地面、不出 NaN")
	var w := _run("towers", 1, 600)
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
		if b.aabb.end.y > w.solver.penetration_slop + 0.5:
			sunk += 1
	_check("没有 NaN", nan == 0, "NaN %d 个" % nan)
	_check("没有箱子陷进地面", sunk == 0, "陷入 %d 个, 最深 %.3f px" % [sunk, lowest])

func _initialize() -> void:
	print("=== 并行求解自检 ===")
	_test_island_split()
	_test_island_parallel_equals_serial()
	_test_colored_matches_serial()
	_test_repeatable()
	_test_parallel_not_diverging()
	print("=== %d passed, %d failed ===" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
