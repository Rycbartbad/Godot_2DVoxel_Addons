extends RefCounted
## 物理世界：固定步长管线 + 岛屿休眠 + 破坏/分裂。
##
## 管线（与参考实现一致）：
##   IntegrateForces -> Broadphase -> Narrowphase -> Solve -> IntegrateTransform -> Sleep
## 破坏发生在窄相之前：先改拓扑，再让物理看到最新数据。

const PBody := preload("res://src/physics/pbody.gd")
const Collide := preload("res://src/physics/collide.gd")
const Solver := preload("res://src/physics/solver.gd")
const Broadphase := preload("res://src/physics/broadphase.gd")
const Destruction := preload("res://src/core/destruction.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")
const Grab := preload("res://src/physics/grab.gd")
const Sweep := preload("res://src/physics/sweep.gd")
const SolveBatch := preload("res://src/physics/solve_batch.gd")

var bodies: Array = []
var shapes_needing_coarse_proxy := 0
## 重力要按**可见尺度**定，不是按世界坐标的绝对值。
## 缩放 3 倍时可见高度只有 180 世界单位，900 的重力意味着物体 1 秒后
## 每秒下落 2.5 个屏幕高度 —— 快到看不清。600 下从静止落满一屏约 0.8 秒。
var gravity := Vector2(0.0, 600.0)
## 终端速度：只钳下落分量（不影响水平抛出和爆炸的冲量），
## 这样"掉多久"和"从多高掉"无关，手感可预测。
var terminal_speed := 650.0
var fixed_dt := 1.0 / 60.0
var max_substeps := 4
var solver := Solver.new()

var sleeping_enabled := true
var sleep_linear := 6.0
## 角速度那一半判据用**表面速度**（px/s），不是裸角速度。
## 绝对角速度阈值会把小碎块永久钉在"醒着"（见 PBody.is_slow 的实测数据）。
var sleep_surface := 6.0
var sleep_delay := 0.4

## ---- 连续碰撞（CCD）：自适应子步 ----
## 高速度下"一步跨过薄物体"是离散碰撞的固有缺陷。这里不去做复杂的扫掠，
## 而是按"本步最大位移"把这一步切成若干子步，保证任何物体每个子步
## 移动不超过 ccd_max_motion。朴素但极稳，也是 Dennis 新引擎的思路
## （sub-stepping instead of solver iterations）。
var ccd_enabled := true
var ccd_max_motion := 2.0      ## 每个子步允许的最大位移（世界单位）
var ccd_max_substeps := 16     ## 子步上限
## 子步是**全局**的：最快的那个物体会逼着所有物体陪它把整条管线重跑 N 遍。
## 所以子步数必须按物体数摊一个预算，否则一屏碎块会把帧时间直接乘 16。
## （实测 240 个高速碎块时 60 帧里有 57 帧跑满 16 子步，帧时间 500 ms。）
var ccd_substep_budget := 600
## 子步上限被顶满时，位移会被**硬钳**在这个值上。
## 代价是超高速物体变成慢动作，换来的是"绝不可能穿模"的硬保证。
var ccd_clamp_motion := true
## 自动 CCD：本**子步**位移超过 ccd_max_motion 的动态体自动做精确 OBB 扫掠。
##
## 这是修掉"≥1500 px/s 撞墙反弹"的关键（见开发日志坑 33）：
## 位移硬钳每子步推进 ccd_max_motion(2.0)，而挤出通道上限只有
## max_depenetration_speed(100 px/s) —— 每子步净**陷进去**约 1.9，
## 于是越陷越深，最后被挤出通道以极限速度顶回来。
## 扫掠让物体停在表面，压根不产生穿透，挤出通道也就不会被激活。
##
## 慢速物体零开销：进入扫掠前有一道"扫掠 AABB 不相交就跳过"的便宜早退，
## 而且它只在**需要**时才被调用。
## ⚠️ 默认 **false**：精确 sweep 的原语已验证（tests/validation_sweep.gd 14/14），
## 但接进 _integrate_transforms 后在大速度下会引入"反弹"，尚未定位完（见开发日志坑 33）。
## 在弄清楚之前不默认启用 —— 基线必须保持可比。
## ⚠️ 默认 **false**。自动触发的判定是"子步位移 > ccd_max_motion(2.0)"，
## 而子步细分的目标恰好就是"每子步位移 <= 2.0" —— 两者**正好错开**，
## 所以它在真实管线里几乎不触发（实测扫掠对默认列毫无影响）。
## 手动打开能看到它确实有用（3000 px/s 撞墙从 -137.8 改善到 48.3），
## 但会扰动基准（sleep_frag 变化），而 600~1500 的反弹另有原因（坑 34 根因 B）。
## 等根因 B 解决后，这里应当改成"按**物体自身尺寸**判定是否需要 CCD"，
## 而不是拿一个和子步阈值重合的常数。
var ccd_auto := true
var ccd_max_rotation := 0.25   ## 每个子步允许的最大转角（弧度）
## 推测接触的边际上限。
##
## ⚠️ 这个值**必须小于子步位移上限** @@ccd_max_motion(2.0)@@。1.5 对 2.0 是量出来的甜点：
##   · 边际 ≈ 每子步位移（实测 1.8/2.0）时，@@bias = -sep/dt@@ 允许物体**全速**撞上去，
##     接触出现的那一子步完全不刹车 —— 高速撞击会翻成陀螺并反弹
##     （实测 600 px/s：x 188 → 124、rot → -1.72、ω 峰值 8.45）；
##   · 边际太小（<= 1.0）时缓冲不够，落地轻微抖动 → @@sleep_box@@ 从 0/12 变 4/12 睡不着。
##
## 1.5 两边同时满足：撞墙 600/1500/3000 全部停在 188.0~188.1、rot 0；
## @@sleep_box@@ 保持 0/12 且摘要值与旧基线**逐位相同**。
## 顺带把子步数从 5/13/16 降到 1/1/1。
##
## 旧注释说"上限是为了限制接触点偏移产生的扭矩"—— 那是接触点公式错误
## （取两个支撑**角点**的中点、偏出上千单位，见坑 34）时的 workaround。
## 接触点修好之后理由换成了上面这条。
var max_speculative_margin := 1.5
var last_substeps := 1
## 形状缓存：一个 body 的 OBB 在一步里是固定的，但旧代码在**每一对**里都重建一次。
## 实测 240 个物体、只有 26 个流形时，窄相仍占掉 75% 的帧时间 —— 几乎全是重复构建。
var _obb_cache: Array = []
var _aabb_cache: Array = []
var _radius_cache: PackedFloat32Array = PackedFloat32Array()
## 窄相的 SAT 暂存：**复用同一个对象**，避免每对矩形都分配/装箱一次
## （见 collide.gd 里 Sat 的说明）。窄相是单线程的，所以复用它没有竞争问题。
var _sat_scratch := Collide.Sat.new()
## 子步被顶满时才会启用位移硬钳；正常情况靠子步本身保证精度
var _ccd_saturated := false

## ---- 多线程 ----
## WorkerThreadPool 并行度阈值：工作量太小的时候线程开销大于收益
const PARALLEL_MIN_CHUNKS := 96
const PARALLEL_MIN_PAIRS := 48
var use_threads := true
## 岛内图着色并行：实现完整、结果确定，但实测比岛并行慢（见 _solve 注释）
var use_coloring := false
## 并行任务参数（可在运行时扫描，见 tests/bench_priority.gd）。
## tasks_needed 控制把一个 group task 拆成几个并发任务；-1 = 自动。
##
## ⚠️ high_priority 默认 **false**，这是**量出来的**结论，不要随手改成 true：
##   · 低优先级通道只占线程池的约 30%（实测 4/16），看起来吃亏；
##   · 但真改成 true 之后，16 个线程并发跑求解器会让**每个任务自己的耗时涨 17 倍**
##     （实测 各任务合计 26.65 ms -> 452.66 ms），整体反而慢一倍
##     （36 塔场景整步 14.5 ms -> 35.3 ms，0.48x）。
##   原因见 tests/bench_isolation.gd：GDScript 的**对象属性读写**在 16 线程下
##   单元耗时会膨胀 93 倍（4 线程只有 4.2 倍）。求解器整条路径都是属性读写。
##   所以"线程池没给满"在这里反而是一种保护：更少的并发 = 更少的争用。
var parallel_high_priority := false
var parallel_tasks_needed := -1
## 求解器内层走 SoA（packed 数组）而不是对象属性。
##
## ⚠️ **默认关闭**，因为它在 GDScript 里无法与对象路径逐位一致：
##   Godot 的 Vector2 是 real_t = **float32**，而 GDScript 的算术是 float64。
##   对象路径每次 _apply 要舍入 3 次（构造 Vector2、乘逆质量、写回速度），
##   SoA 路径只舍入 1 次 —— 它更精确，但结果不同。
##   而 1 个 float32 ULP 的差在这套接触求解器里会被混沌放大：
##   实测单箱落地 300 步后翻倒 90°、三层堆叠从精确的 100.000 漂到 102.7。
##
## 打开它换来的是**实打实的性能**（tests/bench_batch.gd，同进程 A/B）：
##   串行 1.25~1.81x；并行天花板从 1.29x 抬到 **1.97x**（对象属性的并发争用没了）。
## 也就是说：这是一条"用数值等价性换性能"的路，要不要走是产品决定，不是技术决定。
## 想走的话，还需要在 float64 这套新数值环境里重新标定参数、重写那批
## "刀尖上的"断言（堆叠零漂移之类）。
var use_solver_batch := false
## 窄相走 GDExtension 的批量 collide。
## 实测（tests/test_gdext_collide.gd，20000 对随机 OBB）：结果与 GDScript **逐位一致**，
## 纯内核 52 ns/对 vs GDScript 4942 ns/对。端到端收益要看编码成本占多少（见坑 27）。
var use_native_collide := true
## 整个宽相走 GDExtension（含扫掠 AABB / OBB 表 / 矩形 AABB / SAP 配对 / collide）。
## 实测比"只把 collide 搬过去"省掉了 _cache_shapes 里每个矩形的对象分配。
var use_native_broadphase := true
const NATIVE_PAIR_STRIDE := 16
const NATIVE_OUT_STRIDE := 104
var _native_phys: Variant = null
var _native_out := PackedByteArray()
var _pair_bytes := PackedByteArray()
## OBB 的 flat 字节表：每个矩形 64 字节（8 个 double），_cache_shapes 里顺带写好。
## 这样批量窄相**不需要逐对编码 16 个 double** —— 每对只传 2 个字节偏移 + 1 个 margin。
## 实测：逐对编码把 60x 的内核收益吃成 1.45x，改成 flat 表后差距立刻回来。
var _obb_bytes := PackedByteArray()
var _obb_boff := PackedInt32Array()
## ---- 整个宽相搬进 GDExtension ----
## 走这条路时 **_cache_shapes 完全不建 OBB/AABB 对象**（那正是最大的一笔开销：
## 每个子步为每个矩形 new 一个 OBB = 12.5 ms / 500 体）。
## GDScript 只负责把"每体的位姿与 AABB"和"局部矩形表"铺成字节，以及最后的流形装配。
const NATIVE_BP_HEADER := 32
const NATIVE_BODY_STRIDE := 104
const NATIVE_RECT_STRIDE := 32
const NATIVE_MAN_STRIDE := 120
## 求解器也走 GDExtension：直接吃宽相的打包流形，于是**连 Manifold/Point 对象都不用建**。
## 实测那一步（把结果装成对象）占宽相+求解的大头，所以这一条是关键的。
## **默认打开**：已做到与对象路径逐位一致（dump_state 八场景全匹配）。
## 定位过程中查出两个根因（见坑 29）：
##   1. @@Vector2 * real_t@@ 是**先把标量截成 float32 再相乘**，
##      而 C++ 里写成 @@(float)((double)x * s)@@ 是"先 double 乘、最后才舍入" —— 差 1 个 ULP；
##      在 det ~ 1e-7 的病态 2x2 LCP 里会被放大成可见偏差。
##   2. @@_wake_pass@@ 也遍历 @@manifolds@@（第三个消费者）—— native 路径下它是空的，
##      于是睡眠体不再被唤醒，sleep_box 到第 227 步就少醒一个。
var use_native_solve := true
const NATIVE_SV_GRAB := 48
const NATIVE_SV_HEADER := 96
const NATIVE_SV_BODY := 96
const NATIVE_SV_OUT := 48
var _sv_phys: Variant = null
var _sv_bod := PackedByteArray()
var _sv_out := PackedByteArray()
var _bp_res := PackedByteArray()
var _bp_count := 0
var _bp_points := 0
var _bp_phys: Variant = null
var _bp_body := PackedByteArray()
var _bp_rect := PackedByteArray()
var _bp_order := PackedByteArray()
var _bp_out := PackedByteArray()
var _bp_cap := 256
## 诊断用：_broadphase 两个阶段各花多久（收集候选 vs 求解）
var bp_collect_us := 0
var bp_resolve_us := 0
var _batch := SolveBatch.new()
var max_threads := 8
var last_parallel_tasks := 0

var min_fragment_pixels := 4
# 0 = 不设上限，永远精确。
# 精确覆盖与矩形上限不可兼得，宁可多几个矩形也不要幻影碰撞体。
var max_rects_per_shape := 0
var rect_budget_overflows := 0

## ---- 剖面计数（默认关）----
## 教训：只统计**累计耗时**会漏掉"每个阶段都不慢、整帧很慢"这类问题
## （典型原因是有个乘数在放大一切，比如子步被顶满）。
## 所以剖面必须同时给出**调用次数**：SAP 配对数 / 矩形对测试数 / SAT 调用数 / 流形数。
## 热路径上只多一次局部 int 自增，不用方法调用，profile_enabled 为 false 时开销可忽略。
var profile_enabled := false
var profile_counts: Dictionary = {}

var manifolds: Array = []

## 本次子步流形走"打包数据"还是"对象数组"——**整个子步只有一个判断点**。
##
## ⚠️ 这个字段的由来是一个真实事故：最初三处消费者各自判断 @@use_native_solve@@，
## 但 @@_broadphase_native@@ 看的是它、@@_solve@@ 看的却是它**且** @@grabs.is_empty()@@。
## 结果按住拖动时：宽相跳过了对象装配（manifolds 置空），求解器却因为"有抓取"
## 退回对象路径 —— 拿到空数组、**所有接触约束消失**，表现为
## "拖动一个方块，其它方块全部掉穿地面"（只有被抓的那个还被抓取约束吊着）。
##
## 现在一律读这个字段，并且它在 @@_broadphase@@ 里**只算一次**，
## 所以同一子步内宽相 / 唤醒 / 求解 / 休眠看到的是同一个值，不可能再分叉。
var _packed_manifolds := false
## 宽相 SAP 排序用的键（每子步预抽一次，避免比较器里做属性访问）
var _bp_sort_key := PackedFloat64Array()
## 精确 OBB sweep 的工作区（复用，零分配）
var _sweeper := Sweep.Sweeper.new()
var _sweep_hit := Sweep.Hit.new()
var grabs: Array = []
var max_dynamic_bodies := 400
var last_pairs := 0
var last_contacts := 0
var _accum := 0.0
var _next_id := 1


## 材质 id -> 密度。add_body 没显式给 density_of 时用它。
##
## 默认空表 = 全部按 1.0 算，也就是**质量 == 像素数**（1 像素 1 单位质量）。
## 想让石头比木头重就 set_material_density(1, 2.5)。
var material_density := PackedFloat32Array()
var _density_fn: Callable = Callable()


## 设置某材质的密度（会自动扩容表，中间没设过的按 1.0 算）。
func set_material_density(material: int, density: float) -> void:
	if material < 0:
		return
	if material_density.size() <= material:
		material_density.resize(material + 1)
	material_density[material] = density
	_density_fn = Callable()


func density_of_material(material: int) -> float:
	if material >= 0 and material < material_density.size():
		var d := material_density[material]
		if d > 0.0:
			return d
	return 1.0


## 惰性构造一次密度函数并复用它 —— 每帧 add_body 时新建 lambda 是白烧。
func density_callable() -> Callable:
	if not _density_fn.is_valid():
		_density_fn = func(m: int) -> float: return density_of_material(m)
	return _density_fn


## 已建好的刚体在质量变了之后重算：改密度表、或者在形状上加了像素之后调用。
func refresh_mass(body: PBody, density_of: Callable = Callable()) -> void:
	body.rebuild(body.shapes, density_of if density_of.is_valid() else density_callable(),
		max_rects_per_shape)


## 方便的"按当前密度建一个动态体"。
func add_body(body: PBody, shape_list: Array, density_of: Callable = Callable()) -> PBody:
	body.id = _next_id
	_next_id += 1
	body.rebuild(shape_list, density_of if density_of.is_valid() else density_callable(),
		max_rects_per_shape)
	bodies.append(body)
	return body


func remove_body(body: PBody) -> void:
	bodies.erase(body)


func step(dt: float) -> void:
	for b in bodies:
		b.refresh_com()
	# 自适应子步：把"一步跨过薄物体"从根上消掉
	var n := _compute_substeps(dt)
	last_substeps = n
	if profile_enabled:
		# 每帧清零；帧内所有子步一律**累加**，这样 step() 结束时手里的就是"每帧总量"。
		# 混用"赋值"和"累加"会让打印出来的数字一半是每帧、一半是每子步 —— 实测踩过。
		profile_counts = {}
		profile_counts["steps"] = 1
		profile_counts["substeps"] = n
	# 关键：只有子步数被上限顶满（说明速度已经超出子步能覆盖的范围）才启用硬钳。
	# 早先无条件钳制的写法会把**所有**物体限制在每子步 2 像素 ——
	# 箱子浮在半空、拖动几乎不动、擦下来的碎块也不掉，全是这一个 bug。
	_ccd_saturated = (n >= ccd_max_substeps)
	var sub := dt / float(n)
	for i in n:
		_substep(sub)


## 本步需要切成几个子步。判据是"最快的物体一步能走多远"：
## 只要每个子步的位移都小于最薄障碍物的厚度，就不可能穿过去。
func _compute_substeps(dt: float) -> int:
	if not ccd_enabled or dt <= 0.0:
		return 1
	var fastest := 0.0
	for b: PBody in bodies:
		if b.is_static or not b.awake:
			continue
		var v := b.linear_velocity.length() + absf(b.angular_velocity) * b.bounding_radius()
		fastest = maxf(fastest, v)
	if fastest <= 0.0:
		return 1
	var motion := fastest * dt
	if motion <= ccd_max_motion:
		return 1
	# 数一下"醒着的动态体"，用它把预算摊薄
	var awake_count := 0
	for b2: PBody in bodies:
		if not b2.is_static and b2.awake:
			awake_count += 1
	var cap := clampi(int(float(ccd_substep_budget) / float(maxi(1, awake_count))),
		1, ccd_max_substeps)
	# 精度下降时退化成"慢动作"，而不是穿模 —— 位移硬钳兜住（见 _ccd_saturated）
	return clampi(int(ceil(motion / ccd_max_motion)), 1, cap)


func _substep(dt: float) -> void:
	for b0 in bodies:
		b0.clear_pseudo()
	_integrate_forces(dt)
	_broadphase(dt)
	_wake_pass()
	_solve(dt)
	_integrate_transforms(dt)
	for b in bodies:
		if not b.is_static:
			b.update_aabb()
	_update_sleep(dt)


func advance(delta: float) -> int:
	_accum += delta
	var steps := 0
	while _accum >= fixed_dt and steps < max_substeps:
		step(fixed_dt)
		_accum -= fixed_dt
		steps += 1
	if steps == max_substeps:
		_accum = 0.0
	return steps


func _integrate_forces(dt: float) -> void:
	for b: PBody in bodies:
		if b.is_static or not b.awake:
			continue
		b.linear_velocity += gravity * dt
		# 外力/外力矩（持久累加器，由调用方 clear_forces() 管理，见 PBody 的说明）。
		# 与 gravity 一样是"加速度"语义，乘 dt 后进速度。
		if b.accum_force != Vector2.ZERO:
			b.linear_velocity += b.accum_force * (b.inv_mass * dt)
		if b.accum_torque != 0.0:
			b.angular_velocity += b.accum_torque * (b.inv_inertia * dt)
		# 轻微阻尼，帮助像素碎块落定
		var damp := 1.0 / (1.0 + 0.35 * dt)
		b.linear_velocity *= damp
		if terminal_speed > 0.0 and b.linear_velocity.y > terminal_speed:
			b.linear_velocity.y = terminal_speed
		b.angular_velocity *= 1.0 / (1.0 + 0.6 * dt)


## 每个 substep 预计算一次：body 的 OBB / AABB / 包围半径。
## 这三样在一个 substep 内都不变，旧代码却把它们放在 pair 循环里现算。
func _cache_shapes() -> void:
	var n := bodies.size()
	_obb_cache.resize(n)
	_aabb_cache.resize(n)
	_radius_cache.resize(n)
	_obb_boff.resize(n)
	var flat_off := 0
	for i in n:
		var b: PBody = bodies[i]
		if b.rects.is_empty() or (b.is_static and not b.awake):
			if _obb_cache[i] == null:
				_obb_cache[i] = []
				_aabb_cache[i] = []
			else:
				(_obb_cache[i] as Array).clear()
				(_aabb_cache[i] as Array).clear()
			_radius_cache[i] = 0.0
			_obb_boff[i] = 0
			continue
		var obbs = _obb_cache[i]
		var boxes = _aabb_cache[i]
		if obbs == null:
			obbs = []
			boxes = []
			_obb_cache[i] = obbs
			_aabb_cache[i] = boxes
		var cnt: int = b.rects.size()
		while obbs.size() < cnt:
			obbs.append(null)
			boxes.append(Rect2())
		_obb_boff[i] = flat_off
		var need := flat_off + cnt * 64
		if _obb_bytes.size() < need:
			_obb_bytes.resize(need)
		for r in cnt:
			var o: Collide.OBB = Collide.obb_from_local_rect(b, b.rects[r])
			obbs[r] = o
			boxes[r] = _obb_aabb(o)
			var bo := flat_off + r * 64
			_obb_bytes.encode_double(bo, o.center.x)
			_obb_bytes.encode_double(bo + 8, o.center.y)
			_obb_bytes.encode_double(bo + 16, o.u.x)
			_obb_bytes.encode_double(bo + 24, o.u.y)
			_obb_bytes.encode_double(bo + 32, o.v.x)
			_obb_bytes.encode_double(bo + 40, o.v.y)
			_obb_bytes.encode_double(bo + 48, o.h.x)
			_obb_bytes.encode_double(bo + 56, o.h.y)
		flat_off += cnt * 64
		_radius_cache[i] = b.bounding_radius()
		if profile_enabled:
			# 这里是**分配**热点：每个 substep 都为每个矩形新建一个 OBB 对象
			profile_counts["cached_rects"] = profile_counts.get("cached_rects", 0) + cnt
	if _obb_bytes.size() > flat_off:
		_obb_bytes.resize(flat_off)   # 收缩不重分配（CowData 保留容量）


func _broadphase(dt: float) -> void:
	# ★ 唯一判断点：抓取时求解必须走对象路径（grab.solve 直接写 PBody 速度），
	#   所以那时**不能**跳过流形对象装配。
	# 扩展已原生支持抓取约束，所以这里**不再**因为 grabs 退回对象路径（那会慢 8 倍）。
	_packed_manifolds = use_native_solve and use_native_broadphase
	if use_native_broadphase:
		_broadphase_native(dt)
		return
	# 先按本步位移把 AABB 撑开，高速物体才会在移动前被配对。
	# 睡着的物体速度为 0，撑开的结果恒等于 aabb 本身，所以直接跳过
	# （_update_sleep 入睡时已经把 swept_aabb 归位到 aabb，见那里的说明）。
	for b0: PBody in bodies:
		if not b0.awake and not b0.is_static:
			continue
		b0.compute_swept_aabb(dt)
	_cache_shapes()
	var idx: Array = []
	for i in bodies.size():
		var b: PBody = bodies[i]
		if b.rects.is_empty():
			continue
		if b.is_static and not b.awake:
			continue
		idx.append(i)
	last_pairs = 0
	var pairs := Broadphase.compute_pairs(bodies, idx)
	if profile_enabled:
		profile_counts["bodies"] = profile_counts.get("bodies", 0) + bodies.size()
		profile_counts["sap_pairs"] = profile_counts.get("sap_pairs", 0) + pairs.size()
	var rect_pairs := 0
	var sat_calls := 0
	var _t_c0 := Time.get_ticks_usec()
	# ---- 阶段 1：收集候选对 ----
	# 枚举逻辑只留这一份，两条求解路径共用（否则就是坑 18 的"两份实现会分叉"）。
	var c_ia := PackedInt32Array()
	var c_ra := PackedInt32Array()
	var c_ib := PackedInt32Array()
	var c_rb := PackedInt32Array()
	var c_margin := PackedFloat64Array()
	var c_oa: Array = []
	var c_ob: Array = []
	for pr: Array in pairs:
		# 关键：把配对规范化成 id 升序。
		# 否则 SAP 的排序在前一帧与后一帧可能给出不同的 A/B 顺序，
		# 法向翻转会让 warm start 的键失配、累积冲量丢失，堆叠就会缓慢漂移。
		var ia: int = pr[0]
		var ib: int = pr[1]
		if bodies[ia].id > bodies[ib].id:
			var tmp := ia
			ia = ib
			ib = tmp
		var a: PBody = bodies[ia]
		var b: PBody = bodies[ib]
		if a.rects.is_empty() or b.rects.is_empty():
			continue
		var ra_count: int = a.rects.size()
		var rb_count: int = b.rects.size()
		# 推测接触的边际 = 这一步内两个物体可能互相接近的最大距离 + 皮肤。
		# 必须在**移动之前**就拦下来，所以边际要覆盖整个步长的相对位移。
		var rel := (b.linear_velocity - a.linear_velocity).length()
		var spin := absf(a.angular_velocity) * _radius_cache[ia] \
			+ absf(b.angular_velocity) * _radius_cache[ib]
		# 边际上限的理由见 max_speculative_margin 的声明处（与子步位移的关系）。
		var margin := minf((rel + spin) * dt + 0.5, max_speculative_margin)
		# 先用 body 级 AABB 粗筛，再逐矩形 SAT
		var obbs_a: Array = _obb_cache[ia]
		var boxes_a: Array = _aabb_cache[ia]
		var obbs_b: Array = _obb_cache[ib]
		var boxes_b: Array = _aabb_cache[ib]
		# 矩形对测试次数可以直接由矩形数相乘得到（内层循环正好遍历 ra_count x rb_count 次），
		# 这样热路径上只需要为"真正进了 SAT 的那些"各记一次，少一条内层语句。
		rect_pairs += ra_count * rb_count
		for ra in ra_count:
			var oa: Collide.OBB = obbs_a[ra]
			var box_a: Rect2 = (boxes_a[ra] as Rect2).grow(margin)
			for rb in rb_count:
				var ob: Collide.OBB = obbs_b[rb]
				var box_b: Rect2 = (boxes_b[rb] as Rect2).grow(margin)
				if not box_a.intersects(box_b, true):
					continue
				c_ia.append(ia)
				c_ra.append(ra)
				c_ib.append(ib)
				c_rb.append(rb)
				c_margin.append(margin)
				c_oa.append(oa)
				c_ob.append(ob)
	sat_calls = c_ia.size()
	var _t_c1 := Time.get_ticks_usec()
	bp_collect_us = _t_c1 - _t_c0
	# ---- 阶段 2：求解（GDScript 逐个 / 扩展批量）----
	var out: Array = []
	if use_native_collide and sat_calls > 0:
		_native_resolve(c_ia, c_ra, c_ib, c_rb, c_margin, c_oa, c_ob, out)
	else:
		for k in sat_calls:
			var res := Collide.collide(c_oa[k], c_ob[k], c_margin[k], _sat_scratch)
			_append_manifold(out, c_ia[k], c_ra[k], c_ib[k], c_rb[k], res)
	bp_resolve_us = Time.get_ticks_usec() - _t_c1
	manifolds = out
	last_contacts = 0
	for m: Solver.Manifold in manifolds:
		last_contacts += m.points.size()
	if profile_enabled:
		profile_counts["rect_pairs"] = profile_counts.get("rect_pairs", 0) + rect_pairs
		profile_counts["sat_calls"] = profile_counts.get("sat_calls", 0) + sat_calls
		profile_counts["manifolds"] = profile_counts.get("manifolds", 0) + manifolds.size()
		profile_counts["points"] = profile_counts.get("points", 0) + last_contacts


## 整个宽相走 GDExtension：扫掠 AABB -> OBB 表 -> 矩形 AABB -> SAP 配对 -> collide。
##
## ⚠️ 这里有**一处刻意留在 GDScript 的地方**：按 swept_aabb.position.x 的排序。
## 因为 Godot 的 Array.sort_custom 是不稳定排序，要在 C++ 里逐位复现它的
## 枢轴/分区顺序风险太大；而排序只涉及"物体"（几百个），代价远小于"矩形对"（上千个）。
## 排序判据与 Broadphase.compute_pairs 完全一致。
func _broadphase_native(dt: float) -> void:
	var t_full := Time.get_ticks_usec()
	for b0: PBody in bodies:
		if not b0.awake and not b0.is_static:
			continue
		b0.compute_swept_aabb(dt)
	var n := bodies.size()
	var idx: Array = []
	for i in n:
		var b: PBody = bodies[i]
		if b.rects.is_empty():
			continue
		if b.is_static and not b.awake:
			continue
		idx.append(i)
	# 排序键先抽到 packed 数组再排。比较器里直读 @@bodies[x].swept_aabb.position.x@@
	# 每次比较要做"数组索引 + 两次属性访问"，501 个物体时排序单项就是 1.59 ms；
	# 抽 key 一次只要 0.056 ms，之后比较器只读 packed 数组，排序降到 0.67 ms。
	# **省下 0.9 ms / 子步（约占整步 21%）**。
	#
	# 为什么这是安全的：比较器返回的布尔序列**完全不变**（同样的一组 < 判定），
	# 排序算法只看比较器的输出，所以执行路径相同、排列逐位不变。
	# ⚠️ 这也正是不把排序搬进 C++ 的原因：sort_custom 是不稳定排序（见下方注释），
	#    C++ 里换一个算法就会改变并列元素的相对次序。
	if _bp_sort_key.size() < n:
		_bp_sort_key.resize(n)
	for i in n:
		_bp_sort_key[i] = (bodies[i] as PBody).swept_aabb.position.x
	var order_arr: Array = idx.duplicate()
	order_arr.sort_custom(func(x: int, y: int) -> bool:
		return _bp_sort_key[x] < _bp_sort_key[y])
	var order_count: int = order_arr.size()
	var need_body := NATIVE_BP_HEADER + n * NATIVE_BODY_STRIDE
	if _bp_body.size() != need_body:
		_bp_body.resize(need_body)
	var rect_total := 0
	for i in n:
		rect_total += (bodies[i] as PBody).rects.size()
	if _bp_rect.size() < rect_total * NATIVE_RECT_STRIDE:
		_bp_rect.resize(rect_total * NATIVE_RECT_STRIDE)
	if _bp_order.size() < order_count * 4:
		_bp_order.resize(order_count * 4)
	_bp_body.encode_s32(0, n)
	_bp_body.encode_s32(4, order_count)
	_bp_body.encode_s32(12, 0)
	_bp_body.encode_double(16, dt)
	_bp_body.encode_double(24, max_speculative_margin)
	var roff := 0
	for i in n:
		var b: PBody = bodies[i]
		var cnt: int = b.rects.size()
		var o := NATIVE_BP_HEADER + i * NATIVE_BODY_STRIDE
		_bp_body.encode_double(o, b.position.x)
		_bp_body.encode_double(o + 8, b.position.y)
		_bp_body.encode_double(o + 16, b.rotation)
		_bp_body.encode_double(o + 24, b.linear_velocity.x)
		_bp_body.encode_double(o + 32, b.linear_velocity.y)
		_bp_body.encode_double(o + 40, b.angular_velocity)
		_bp_body.encode_double(o + 48, b.aabb.position.x)
		_bp_body.encode_double(o + 56, b.aabb.position.y)
		_bp_body.encode_double(o + 64, b.aabb.size.x)
		_bp_body.encode_double(o + 72, b.aabb.size.y)
		_bp_body.encode_s32(o + 80, 1 if b.is_static else 0)
		_bp_body.encode_s32(o + 84, 1 if b.awake else 0)
		_bp_body.encode_s32(o + 88, b.id)
		_bp_body.encode_s32(o + 92, roff)
		_bp_body.encode_s32(o + 96, cnt)
		for r in cnt:
			var rc: Rect2 = b.rects[r]
			var bo := (roff + r) * NATIVE_RECT_STRIDE
			_bp_rect.encode_double(bo, rc.position.x)
			_bp_rect.encode_double(bo + 8, rc.position.y)
			_bp_rect.encode_double(bo + 16, rc.size.x)
			_bp_rect.encode_double(bo + 24, rc.size.y)
		roff += cnt
	for k in order_count:
		_bp_order.encode_s32(k * 4, order_arr[k])
	if _bp_phys == null:
		if not ClassDB.class_exists("FastPhys"):
			push_warning("FastPhys 扩展不可用，宽相退回 GDScript")
			use_native_broadphase = false
			_packed_manifolds = false     # 同一子步内必须与 _solve/_wake_pass 保持一致
			_broadphase_gs_fallback(dt)
			return
		_bp_phys = ClassDB.instantiate("FastPhys")
	# 输出容量：C++ 侧被截断时会返回正好 cap 条，靠这一点检测并扩容重试
	var res := PackedByteArray()
	for attempt in 8:
		if _bp_cap < 16:
			_bp_cap = 16
		_bp_body.encode_s32(8, _bp_cap)
		var need := 8 + _bp_cap * NATIVE_MAN_STRIDE
		if _bp_out.size() != need:
			_bp_out.resize(need)
		res = _bp_phys.broadphase(_bp_body, _bp_rect, _bp_order, _bp_out)
		if res.decode_s32(0) < _bp_cap:
			break
		_bp_cap *= 2
	var total := res.decode_s32(0)
	_bp_cap = maxi(32, total * 2)
	_bp_count = total
	_bp_points = res.decode_s32(4)
	last_contacts = _bp_points
	if _packed_manifolds:
		# 求解器直接吃这份打包结果 —— 不建任何 Manifold/Point 对象
		_bp_res = res
		manifolds = []
		bp_collect_us = Time.get_ticks_usec() - t_full
		bp_resolve_us = 0
		return
	_bp_res = PackedByteArray()
	var out: Array = []
	for k in total:
		var base := 8 + k * NATIVE_MAN_STRIDE
		var ia := res.decode_s32(base)
		var ib := res.decode_s32(base + 4)
		var a: PBody = bodies[ia]
		var bb: PBody = bodies[ib]
		var m := Solver.Manifold.new()
		m.a = a
		m.b = bb
		m.normal = Vector2(res.decode_double(base + 16), res.decode_double(base + 24))
		m.key = Solver.make_key(a.id, res.decode_s32(base + 8), bb.id, res.decode_s32(base + 12))
		var cnt2 := res.decode_s32(base + 32)
		for j in cnt2:
			var po := base + 40 + j * 40
			var p := Solver.Point.new()
			p.position = Vector2(res.decode_double(po), res.decode_double(po + 8))
			p.depth = res.decode_double(po + 16)
			p.separation = res.decode_double(po + 24)
			p.feature_id = int(res.decode_double(po + 32))
			m.points.append(p)
		out.append(m)
	manifolds = out
	last_contacts = 0
	for m2: Solver.Manifold in manifolds:
		last_contacts += m2.points.size()
	bp_collect_us = Time.get_ticks_usec() - t_full
	bp_resolve_us = 0


## 扩展不可用时的退回（把扫掠 AABB 之后的标准流程走一遍）
func _broadphase_gs_fallback(dt: float) -> void:
	_cache_shapes()
	_broadphase(dt)


## 把一次 collide 的结果装成流形。两条路径共用，保证装配逻辑一致。
func _append_manifold(out: Array, ia: int, ra: int, ib: int, rb: int, res: Dictionary) -> void:
	var pts: Array = res["points"]
	if pts.is_empty():
		return
	var a: PBody = bodies[ia]
	var b: PBody = bodies[ib]
	var m := Solver.Manifold.new()
	m.a = a
	m.b = b
	m.normal = res["normal"]
	m.key = Solver.make_key(a.id, ra, b.id, rb)
	for pd: Dictionary in pts:
		var p := Solver.Point.new()
		p.position = pd["position"]
		p.depth = pd["depth"]
		p.separation = pd.get("sep", -float(pd["depth"]))
		p.feature_id = pd["feature"]
		m.points.append(p)
	out.append(m)


## 走 GDExtension 的求解器。
##
## 输入是"每体的位姿/逆质量/速度"表 + **宽相的打包流形**（不再有对象），
## 输出是每体的新速度。warm start 缓存住在扩展实例里（每个 PWorld 一个实例，
## 所以多个世界不会互相污染）。
##
## 迭代顺序是"10 轮 × 数组顺序"。这与按岛并行**逐位相同** ——
## 岛之间不共享动态体，所以全局顺序循环在每个岛内的子序列就是岛内顺序。
func _solve_native(dt: float) -> void:
	var n := bodies.size()
	var need := NATIVE_SV_HEADER + n * NATIVE_SV_BODY
	if _sv_bod.size() != need:
		_sv_bod.resize(need)
	_sv_bod.encode_s32(0, n)
	_sv_bod.encode_s32(4, _bp_count)
	_sv_bod.encode_s32(8, solver.iterations)
	_sv_bod.encode_s32(12, 1 if solver.use_block_solver else 0)
	_sv_bod.encode_double(16, dt)
	_sv_bod.encode_double(24, solver.baumgarte)
	_sv_bod.encode_double(32, solver.penetration_slop)
	_sv_bod.encode_double(40, solver.max_depenetration_speed)
	_sv_bod.encode_double(48, solver.restitution_velocity_threshold)
	_sv_bod.encode_double(56, solver.global_restitution)
	_sv_bod.encode_double(64, solver.global_friction)
	# Manifold 上的 friction / restitution 目前是固定默认值（pworld 从不改它们）。
	# 将来若要做逐材质摩擦，这两个要改成逐流形字段并一起搬过去。
	_sv_bod.encode_double(72, 0.5)
	_sv_bod.encode_double(80, 0.0)
	for i in n:
		var b: PBody = bodies[i]
		var o := NATIVE_SV_HEADER + i * NATIVE_SV_BODY
		var c := b.com_world()
		_sv_bod.encode_double(o, c.x)
		_sv_bod.encode_double(o + 8, c.y)
		_sv_bod.encode_double(o + 16, b.inv_mass)
		_sv_bod.encode_double(o + 24, b.inv_inertia)
		_sv_bod.encode_double(o + 32, b.linear_velocity.x)
		_sv_bod.encode_double(o + 40, b.linear_velocity.y)
		_sv_bod.encode_double(o + 48, b.angular_velocity)
		_sv_bod.encode_double(o + 56, b.pseudo_linear_velocity.x)
		_sv_bod.encode_double(o + 64, b.pseudo_linear_velocity.y)
		_sv_bod.encode_double(o + 72, b.pseudo_angular_velocity)
		_sv_bod.encode_s32(o + 80, 1 if b.awake else 0)
		_sv_bod.encode_s32(o + 84, 1 if b.is_static else 0)
		_sv_bod.encode_s32(o + 88, b.id)
	# ---- 抓取约束表（跟在物体表之后）----
	# 求解本身只改速度、不改位姿，所以 anchor / r / bias 在 10 次迭代里是常量，
	# 全部在这里算一次即可 —— 与 Grab.solve 的前半段逐字对应。
	#
	# ⚠️ 这里让扩展**原生支持抓取**，是为了不再因为"有抓取"整条退回对象路径：
	# 实测 49 个物体时拖动会让 step 从 1.28 ms 涨到 10.21 ms（慢 8 倍），
	# 拖动时肉眼可见地卡。扩展里做同一件事只多花几个微秒。
	var gn := grabs.size()
	var grab_off := NATIVE_SV_HEADER + n * NATIVE_SV_BODY
	var need_bod := grab_off + gn * NATIVE_SV_GRAB
	if _sv_bod.size() != need_bod:
		_sv_bod.resize(need_bod)
	for gi in gn:
		var g: Grab = grabs[gi]
		var gb: PBody = g.body
		var o2 := grab_off + gi * NATIVE_SV_GRAB
		var bi := -1
		for j in n:
			if (bodies[j] as PBody) == gb:
				bi = j
				break
		_sv_bod.encode_s32(o2, bi)
		if bi < 0 or gb == null or gb.is_static:
			_sv_bod.encode_double(o2 + 40, 0.0)     # is_static：Grab.solve 直接返回
			continue
		var anchor := g.anchor_world()
		var gr := anchor - gb.com_world()
		var err := g.target - anchor
		var omega: float = g.max_omega
		var err_len := err.length()
		if err_len > 1e-4:
			omega = minf(g.max_omega, sqrt(g.max_accel / err_len))
		var gbias := err * omega
		if gbias.length() > g.max_speed:
			gbias = gbias.normalized() * g.max_speed
		_sv_bod.encode_double(o2 + 8, gr.x)
		_sv_bod.encode_double(o2 + 16, gr.y)
		_sv_bod.encode_double(o2 + 24, gbias.x)
		_sv_bod.encode_double(o2 + 32, gbias.y)
		_sv_bod.encode_double(o2 + 40, g.max_accel * gb.mass * dt)
		# Grab.solve 里的唤醒副作用。必须放在**物体表编码之后**：
		# 对象路径里 prepare 先读到旧的 awake，抓取求解时才把它置真，顺序不能反。
		gb.awake = true
		gb.sleep_timer = 0.0
	for g2: Grab in grabs:
		g2.reset_accumulator()      # 累积冲量在扩展里是每次调用局部变量
	_sv_bod.encode_s32(88, gn)

	var need_out := 8 + n * NATIVE_SV_OUT
	if _sv_out.size() != need_out:
		_sv_out.resize(need_out)
	if _sv_phys == null:
		if not ClassDB.class_exists("FastPhys"):
			push_warning("FastPhys 扩展不可用，求解退回 GDScript")
			use_native_solve = false
			_bp_res = PackedByteArray()
			return
		_sv_phys = ClassDB.instantiate("FastPhys")
	var res: PackedByteArray = _sv_phys.solve(_sv_bod, _bp_res, _sv_out)
	if res.size() < need_out:
		return
	for i in n:
		var b: PBody = bodies[i]
		if b.is_static or not b.awake:
			continue     # 求解器本来就不写它们，与 scatter 的规则一致
		var o := 8 + i * NATIVE_SV_OUT
		b.linear_velocity = Vector2(res.decode_double(o), res.decode_double(o + 8))
		b.angular_velocity = res.decode_double(o + 16)
		b.pseudo_linear_velocity = Vector2(res.decode_double(o + 24), res.decode_double(o + 32))
		b.pseudo_angular_velocity = res.decode_double(o + 40)


## 走 GDExtension 的批量窄相。
##
## ⚠️ 这里有个必须正视的成本：**把 OBB 编码进输入缓冲**要逐值读属性、逐值写字节，
## 候选对一多，这部分可能吃掉相当一部分收益（实测见 docs/development_log.md 坑 27）。
## 根治办法是把 OBB 缓存本身换成 packed 数组（那样连拷贝都省了），
## 但那要动 _cache_shapes，先按现状接上、用数据说话。
func _native_resolve(c_ia: PackedInt32Array, c_ra: PackedInt32Array,
		c_ib: PackedInt32Array, c_rb: PackedInt32Array, c_margin: PackedFloat64Array,
		c_oa: Array, c_ob: Array, out: Array) -> void:
	var n := c_ia.size()
	if _native_phys == null:
		# 扩展缺失时**必须优雅退回**，否则一份没编 DLL 的检出直接跑不起来。
		if not ClassDB.class_exists("FastPhys"):
			push_warning("FastPhys 扩展不可用，退回 GDScript 窄相")
			use_native_collide = false
			for k in n:
				_append_manifold(out, c_ia[k], c_ra[k], c_ib[k], c_rb[k],
					Collide.collide(c_oa[k], c_ob[k], c_margin[k], _sat_scratch))
			return
		_native_phys = ClassDB.instantiate("FastPhys")
	var need := n * NATIVE_PAIR_STRIDE
	if _pair_bytes.size() != need:
		_pair_bytes.resize(need)
		_native_out.resize(n * NATIVE_OUT_STRIDE)
	for k in n:
		var bo := k * NATIVE_PAIR_STRIDE
		_pair_bytes.encode_s32(bo, _obb_boff[c_ia[k]] + c_ra[k] * 64)
		_pair_bytes.encode_s32(bo + 4, _obb_boff[c_ib[k]] + c_rb[k] * 64)
		_pair_bytes.encode_double(bo + 8, c_margin[k])
	var res_bytes: PackedByteArray = _native_phys.collide_batch(_obb_bytes, _pair_bytes, _native_out, n)
	for k2 in n:
		var base: int = k2 * NATIVE_OUT_STRIDE
		var cnt := res_bytes.decode_s32(base + 16)
		if cnt <= 0:
			continue
		var m := Solver.Manifold.new()
		var a2: PBody = bodies[c_ia[k2]]
		m.a = a2
		m.b = bodies[c_ib[k2]]
		m.normal = Vector2(res_bytes.decode_double(base), res_bytes.decode_double(base + 8))
		m.key = Solver.make_key(a2.id, c_ra[k2], bodies[c_ib[k2]].id, c_rb[k2])
		for j in cnt:
			var po: int = base + 24 + j * 40
			var p := Solver.Point.new()
			p.position = Vector2(res_bytes.decode_double(po), res_bytes.decode_double(po + 8))
			p.depth = res_bytes.decode_double(po + 16)
			p.separation = res_bytes.decode_double(po + 24)
			p.feature_id = int(res_bytes.decode_double(po + 32))
			m.points.append(p)
		out.append(m)


func _obb_aabb(o: Collide.OBB) -> Rect2:
	var ex := absf(o.u.x) * o.h.x + absf(o.v.x) * o.h.y
	var ey := absf(o.u.y) * o.h.x + absf(o.v.y) * o.h.y
	return Rect2(o.center - Vector2(ex, ey), Vector2(ex, ey) * 2.0)


static func _obb_aabb_static(o) -> Rect2:
	var ex: float = absf(o.u.x) * o.h.x + absf(o.v.x) * o.h.y
	var ey: float = absf(o.u.y) * o.h.x + absf(o.v.y) * o.h.y
	return Rect2(o.center - Vector2(ex, ey), Vector2(ex, ey) * 2.0)


func _wake_pass() -> void:
	## 有清醒且仍在运动的物体碰到睡眠体时唤醒它。
	##
	## ⚠️ 这是**第三个**消费 manifolds 的地方（另外两个是 _solve 和 _update_sleep）。
	## 走扩展求解时 manifolds 是空的，如果这里不改就会"睡得太好"——
	## 实测 sleep_box 到第 227 步就有 1 个物体提前睡着（awake 10 vs 11）。
	## 成对逻辑抽成 _wake_pair 一处，两条路径共用，避免两份实现分叉（坑 18）。
	if _packed_manifolds:
		for k in _bp_count:
			var base := 8 + k * NATIVE_MAN_STRIDE
			var a0: PBody = bodies[_bp_res.decode_s32(base)]
			var b0: PBody = bodies[_bp_res.decode_s32(base + 4)]
			# 早退条件放在这里（原本是 _wake_pair 的第一行）：
			# 绝大多数配对的睡眠状态一致，省掉一次 GDScript 函数调用。
			# 判定逻辑仍然只在 _wake_pair 一处，不会分叉。
			if a0.awake != b0.awake:
				_wake_pair(a0, b0)
		return
	for m: Solver.Manifold in manifolds:
		_wake_pair(m.a, m.b)


func _wake_pair(a: PBody, b: PBody) -> void:
	if a.awake == b.awake:
		return
	var sleeper: PBody = a if not a.awake else b
	var mover: PBody = b if not a.awake else a
	if sleeper.is_static:
		return
	if mover.is_static or not mover.is_slow(sleep_linear * 2.0, sleep_surface * 2.0):
		sleeper.awake = true
		sleeper.sleep_timer = 0.0


## ---------- 求解 ----------
## 多线程的关键在于**按岛分组**：约束图里互不相连的岛之间没有任何耦合，
## 各自跑完整套迭代拿到的结果与串行完全一致（不是近似，是可复现的相同结果）。
## 所以这是"既安全又确定"的并行方式，不需要锁、也不需要归约。
func _solve(dt: float) -> void:
	# 整条求解链走 GDExtension（宽相输出 -> 求解器）。抓取约束仍然走对象路径。
	if _packed_manifolds:
		_solve_native(dt)
		return
	solver.prepare(manifolds, dt)
	for g in grabs:
		g.reset_accumulator()
	# 实测结论（tests/bench_parallel.gd，交叉重复取最小值）：
	#   **岛并行稳定优于着色并行**：岛并行 1.20~1.39x，全局着色只有 0.37~0.99x。
	# 原因有两层：
	#   1. 岛并行里每个岛自己跑完整个迭代循环，**岛之间零同步**；
	#      着色每种颜色都要一次 barrier，一次迭代就是"色数"次同步。
	#   2. 更根本的是 GDScript 的对象属性读写在多线程下会剧烈膨胀
	#      （16 线程时单元耗时涨 93 倍，见 tests/bench_isolation.gd），
	#      而着色把并发任务数推得更高，正好踩在这个坑上。
	# 所以着色默认关闭；只有在"单个岛吃掉几乎全部工作量"时才值得一试。
	#
	# ⚠️ 两层混合并行（只在最重的岛内部着色 + 其余岛走岛并行）**已经评估过，不要做**：
	#   · 嵌套 group task 会死锁（外层任务数 >= 池线程数时，子任务永远排不上，
	#     见 tests/probe_nested_tasks.gd，实测挂死）；
	#   · 退而求其次的"分波"写法也救不回来：在 pile:8:6 这个"最大岛占 92%"的
	#     最有利场景里，给这个大岛着色仍然是 0.95x（比串行还慢）。
	#   结论：瓶颈不是"岛并行拿不到并行度"，而是"并发本身在这个 VM 上不划算"。
	# ---- SoA 路径（默认）----
	# 抓取约束仍然走对象路径：grab.solve() 直接写 PBody 的速度，
	# 而 SoA 求解器是在 packed 数组上算完再 scatter 回去的 —— 两者会互相覆盖。
	# 抓取时物体通常很少，走对象路径本来就够快。
	if use_solver_batch and grabs.is_empty():
		_solve_batched(dt)
		return
	var islands := _build_islands()
	if profile_enabled:
		profile_counts["islands"] = profile_counts.get("islands", 0) + islands.size()
	if use_coloring and manifolds.size() >= PARALLEL_MIN_PAIRS:
		var groups := Solver.color_manifolds(manifolds)
		solver.solve_colored(groups, dt, grabs)
		last_parallel_tasks = groups.size()
	elif use_threads and islands.size() >= 2 and manifolds.size() >= PARALLEL_MIN_PAIRS:
		_parallel_solve(islands, dt)
		last_parallel_tasks = islands.size()
	else:
		solver.solve(manifolds, dt, grabs)
		last_parallel_tasks = 1
	solver.store_warm(manifolds)


## SoA 求解：gather -> 迭代 -> scatter。
##
## 岛的划分仍然是并查集，但输出改成"流形下标的排列 + 每岛一段区间"，
## 于是并行任务只需要两个整数（lo, hi），内层循环完全不碰对象。
## 岛内**保持原数组顺序**，所以与对象路径逐位一致（tests/dump_state.gd 卡住）。
func _solve_batched(dt: float) -> void:
	_batch.sync_params(solver)
	var islands := _build_islands()
	if profile_enabled:
		profile_counts["islands"] = profile_counts.get("islands", 0) + islands.size()
	var perm := PackedInt32Array()
	var ranges: Array = []
	for isle: Dictionary in islands:
		var idx: Array = isle["idx"]
		if idx.is_empty():
			continue
		ranges.append([perm.size(), perm.size() + idx.size()])
		for k: int in idx:
			perm.append(k)
	# 理论上流形都会被某个岛收走；万一有遗漏就追加到末尾（顺序仍然保持一致）
	if perm.size() < manifolds.size():
		var covered := {}
		for k2: int in perm:
			covered[k2] = true
		var tail_lo := perm.size()
		for i in manifolds.size():
			if not covered.has(i):
				perm.append(i)
		if perm.size() > tail_lo:
			ranges.append([tail_lo, perm.size()])
	_batch.gather_bodies(bodies)
	_batch.build(manifolds, perm, dt, solver._warm, bodies)
	if use_threads and ranges.size() >= 2 and manifolds.size() >= PARALLEL_MIN_PAIRS:
		var worker := func(t: int) -> void:
			var rg: Array = ranges[t]
			_batch.solve_range(rg[0], rg[1], dt)
		var gid := WorkerThreadPool.add_group_task(worker, ranges.size(), parallel_tasks_needed,
			parallel_high_priority, "solve_batch")
		WorkerThreadPool.wait_for_group_task_completion(gid)
		last_parallel_tasks = ranges.size()
	else:
		_batch.solve_all(dt)
		last_parallel_tasks = 1
	_batch.scatter_bodies(bodies)
	_batch.store_warm(solver._warm, manifolds, perm)


## 按接触关系把流形和抓取约束分到互不相连的岛里
func _build_islands() -> Array:
	var n := bodies.size()
	if n == 0:
		return []
	var index_of := {}
	for i in n:
		index_of[bodies[i].id] = i
	var parent: Array = []
	parent.resize(n)
	for i in n:
		parent[i] = i
	for m: Solver.Manifold in manifolds:
		# 静态体**不连接岛**：它永远不会被求解器写入（_apply 里 is_static 直接跳过），
		# 所以"两个动态体都压在同一个地面上"根本不构成耦合，可以分到两个岛里并行解。
		# 旧代码在这里无条件 union，于是**任何带一整块地面的场景都被并成一个岛** ——
		# 岛并行退化成"1 个岛"，实测比串行还慢（0.90x）：这是岛并行上限的真正来源。
		# （_update_sleep 早就用同样的规则跳过静态体，两边现在一致了。）
		if m.a.is_static or m.b.is_static:
			continue
		var ia: int = index_of.get(m.a.id, -1)
		var ib: int = index_of.get(m.b.id, -1)
		if ia >= 0 and ib >= 0:
			_union(parent, ia, ib)
	for g in grabs:
		if g.body != null and index_of.has(g.body.id):
			pass   # 抓取约束不连接两个物体，跟着它自己的岛走即可
	var groups := {}
	var groups_idx := {}
	for i2 in n:
		var root0 := _find(parent, i2)
		groups[root0] = []
		groups_idx[root0] = []
	for mi in manifolds.size():
		var m2: Solver.Manifold = manifolds[mi]
		# 流形归到**动态体**所在的那个岛。
		# 旧代码固定用 m.a：而静态地面通常 id 最小（最先 add_body），
		# 于是"所有物体与地面的接触"全部落进地面那一个岛 —— 地面岛变成
		# 串行瓶颈，其余岛再并行也白搭（这正是"一屏碎块压在一块地板上"的常见形状）。
		# 静态体不会被写入，所以它的接触跟着动态体走完全安全。
		var ia2: int = index_of.get(m2.a.id, -1)
		var ib2: int = index_of.get(m2.b.id, -1)
		var root := -1
		if not m2.a.is_static and ia2 >= 0:
			root = _find(parent, ia2)
		elif not m2.b.is_static and ib2 >= 0:
			root = _find(parent, ib2)
		elif ia2 >= 0:
			root = _find(parent, ia2)
		else:
			continue
		groups[root].append(m2)
		# 同时记下**流形在原数组里的下标**：SoA 求解器要按岛拿到连续区间
		(groups_idx[root] as Array).append(mi)
	var out: Array = []
	for root2: int in groups:
		var ms: Array = groups[root2]
		var gs: Array = []
		for g2 in grabs:
			if g2.body != null and index_of.has(g2.body.id) and _find(parent, index_of[g2.body.id]) == root2:
				gs.append(g2)
		if ms.is_empty() and gs.is_empty():
			continue
		out.append({"manifolds": ms, "grabs": gs, "idx": groups_idx[root2]})
	return out


## 诊断用：记录每个岛任务跑在哪个线程、时间区间、以及解了多少条流形。
## 打开后会写一个小数组（Mutex 保护），只在基准里用。
var trace_enabled := false
var parallel_trace: Array = []

func _parallel_solve(islands: Array, dt: float) -> void:
	if trace_enabled:
		parallel_trace = []
		parallel_trace.resize(islands.size())
	var trace_mtx := Mutex.new()
	# 每个岛只碰自己的流形和自己的物体，天然无竞争；也不需要回写结果。
	var worker := func(t: int) -> void:
		var isle: Dictionary = islands[t]
		if trace_enabled:
			var s0 := Time.get_ticks_usec()
			solver.solve(isle["manifolds"], dt, isle["grabs"])
			var e0 := Time.get_ticks_usec()
			trace_mtx.lock()
			parallel_trace[t] = [OS.get_thread_caller_id(), s0, e0,
				(isle["manifolds"] as Array).size()]
			trace_mtx.unlock()
			return
		solver.solve(isle["manifolds"], dt, isle["grabs"])
	# high_priority = true 是**必须**的，不是调优：
	# WorkerThreadPool 把线程分成高/低优先级两组，低优先级那组只占
	# threading/worker_pool/low_priority_thread_ratio（默认 0.3）。
	# 传 false 时实测只有 **4 个线程**在跑，传 true 是 **16 个**（并行度 3.9x -> 15.0x）。
	# 物理求解在帧的关键路径上，本来就该走高优先级。
	var gid := WorkerThreadPool.add_group_task(worker, islands.size(), parallel_tasks_needed,
		parallel_high_priority, "solve_islands")
	WorkerThreadPool.wait_for_group_task_completion(gid)


func _integrate_transforms(dt: float) -> void:
	for b: PBody in bodies:
		if b.is_static or not b.awake:
			continue
		# 真实速度 + 位置修正伪速度一起积分（伪速度只影响位置，不影响动能）
		var vl := b.linear_velocity + b.pseudo_linear_velocity
		var va := b.angular_velocity + b.pseudo_angular_velocity
		if vl.length_squared() < 0.0000001 and absf(va) < 0.0000001:
			continue
		var disp := vl * dt
		var drot := va * dt
		if ccd_enabled:
			# 扫掠 CCD 只截断位移、不改变速度。b.ccd 是"强制常开"的手动开关。
			var need_ccd := b.ccd
			if not need_ccd and ccd_auto:
				# ⚠️ 判据必须**按物体自身尺寸**，不能用一个常数。
				# 要防的隧穿是"这一步会不会一步跨过比自身还薄的东西"，
				# 所以门槛取"自身最小边的一半"。
				# 早期写成 |disp| > ccd_max_motion 是错的：子步细分的目标
				# 恰好就是"每子步位移 <= ccd_max_motion"，两者正好错开 ——
				# 实测位移正好等于 2.0、判定又是严格 >，判据永远不成立。
				var sz := b.aabb.size
				var thin := 0.5 * minf(sz.x, sz.y)
				need_ccd = disp.length_squared() > thin * thin
			# 子步已经顶满：细分不再能保证"位移小于最薄障碍"，一律扫掠。
			# 这也正是位移硬钳唯一会出问题的场景（坑 34 根因 A，每子步净陷进去），
			# 扫掠在这里接管正好把它顶掉。
			if not need_ccd and ccd_auto and _ccd_saturated:
				need_ccd = true
			if need_ccd:
				disp = _sweep_clamp(b, disp, dt)
			if _ccd_saturated:
				# 子步顶满时的转角上限（位移交给上面的扫掠/硬钳）
				if absf(drot) > ccd_max_rotation:
					drot = signf(drot) * ccd_max_rotation
				# ⚠️ 硬钳**只在 sweep 没接管时**才用（坑 34 根因 A）：
				# 它每子步推进 ccd_max_motion(2.0)，而挤出通道上限只有
				# max_depenetration_speed(100 px/s ≈ 每子步 0.1) —— 两者不匹配，
				# 每子步净**陷进去**约 1.9，越陷越深后被挤出通道以极限速度顶回来
				# （实测 3000 px/s 撞墙从 188 反弹到 -137）。
				# 精确 sweep 把位移钳在**真实表面**之前，不产生穿透，也就没有这个问题。
				if not need_ccd and ccd_clamp_motion \
						and disp.length_squared() > ccd_max_motion * ccd_max_motion:
					disp = disp.normalized() * ccd_max_motion
		# 刚体绕**质心**旋转，不是绕 Body 原点。
		# position 只是形状数据的参考原点，质心偏离它时（画笔绘制的物体尤其明显）
		# 直接 position += v*dt 会让物体绕着一个虚空中的点打转。
		var com_before := b.com_world()
		var new_com := com_before + disp
		b.rotation += drot
		b.position = new_com - b.local_com.rotated(b.rotation)
		b.refresh_com()


## 扫掠 CCD：把移动体的 AABB 收成一个点、把障碍 AABB 按半尺寸膨胀
## （Minkowski 和），然后做一次射线-矩形平板测试，取最早命中。
## 命中就把位移截断在表面，并消掉法向速度。
func _sweep_clamp(b: PBody, disp: Vector2, dt: float) -> Vector2:
	if disp.length_squared() < 0.000001:
		return disp
	var best_t := 1.0
	var hit_normal := Vector2.ZERO
	var swept := b.swept_aabb
	for other: PBody in bodies:
		if other == b or other.rects.is_empty():
			continue
		# 便宜的早退：两个扫掠 AABB 不相交就不可能碰上（真正判定交给精确 sweep）
		if not swept.intersects(other.swept_aabb):
			continue
		_sweeper.sweep_bodies(b, other, dt, _sweep_hit)
		if _sweep_hit.hit and _sweep_hit.t < best_t:
			best_t = _sweep_hit.t
			hit_normal = _sweep_hit.normal
	if best_t >= 1.0:
		return disp
	if best_t <= 0.001:
		# 出发时**已经重叠或贴住**（初始嵌入、或被挤进去）。
		#
		# ⚠️ 这里既不能把位移钳成 0，也不能放行全程 —— 两个错误都踩过：
		#   · 钳成 0：物体会被**永久冻结**（实测"初始嵌入 8px 后往外拖"纹丝不动）；
		#   · 放行全程：贴住表面的物体每子步又推进去一整个 disp，越陷越深
		#     （实测高速撞墙反而比不开 CCD 更糟）。
		# 正确语义是"**不允许继续深入，但放行切向与往外走的分量**"：
		# 把指向对方的分量扣掉，剩下的照样走 —— 深嵌物体能被拉出来、
		# 也能沿表面滑动（挤出通道负责把它推出来）。
		if hit_normal != Vector2.ZERO:
			var along := disp.dot(hit_normal)
			if along > 0.0:
				disp -= hit_normal * along
		return disp
	# 停在表面前留一点皮，避免下一帧以"已重叠"的状态开局
	var travel := disp * maxf(0.0, best_t - 0.001)
	if hit_normal != Vector2.ZERO:
		# ⚠️ 法向是**由 b 指向 other**（sweep 沿用 SAT 的约定）。
		# 所以"正在朝对方去"是 vn > 0，不是 vn < 0 ——
		# 旧实现用的是射线命中法向（由障碍指向移动体），方向相反，
		# 照抄过来会变成"接近时不消速度、分离时反而消"。
		var vn := b.linear_velocity.dot(hit_normal)
		if vn > 0.0:
			b.linear_velocity -= hit_normal * vn
	return travel


## 射线 vs AABB 平板测试。返回 [命中t(-1 表示未命中), 法向]
func _ray_box(origin: Vector2, dir: Vector2, lo: Vector2, hi: Vector2) -> Array:
	var t_near := 0.0
	var t_far := 1.0
	var normal := Vector2.ZERO
	for axis in 2:
		var o := origin[axis]
		var d := dir[axis]
		var l := lo[axis]
		var h := hi[axis]
		if absf(d) < 1e-9:
			if o < l or o > h:
				return [-1.0, Vector2.ZERO]
			continue
		var t1 := (l - o) / d
		var t2 := (h - o) / d
		var sign := -1.0
		if t1 > t2:
			var tmp := t1
			t1 = t2
			t2 = tmp
			sign = 1.0
		if t1 > t_near:
			t_near = t1
			normal = Vector2.ZERO
			normal[axis] = sign
		t_far = minf(t_far, t2)
		if t_near > t_far:
			return [-1.0, Vector2.ZERO]
	return [t_near, normal]


## 掉出世界之外的动态体直接回收。
## 不回收的话它们会永远加速下落 —— 于是 _compute_substeps 永久饱和在 16，
## 整个物理每帧跑 16 遍，即使屏幕上什么都看不见。这是掉帧的头号原因。
func cull_outside(bounds: Rect2) -> int:
	var removed := 0
	for i in range(bodies.size() - 1, -1, -1):
		var b: PBody = bodies[i]
		if b.is_static:
			continue
		if not bounds.intersects(b.aabb):
			bodies.remove_at(i)
			removed += 1
	return removed


func _update_sleep(dt: float) -> void:
	if not sleeping_enabled:
		return
	# 被抓着的物体永不入睡
	var held := {}
	for g in grabs:
		if g.body != null:
			held[g.body.id] = true
	# 用并查集按接触关系分岛；同岛必须一起睡，否则会出现"悬空支撑"
	var n := bodies.size()
	var parent: Array = []
	parent.resize(n)
	for i in n:
		parent[i] = i
	# 用 id -> 下标建索引，别用 bodies.find()。
	# find() 是**线性查找**，每个流形要查两次：240 物体 + 数百流形时，
	# 每子步就是几万次比较，纯属白烧（这个函数每子步都跑一遍）。
	var index_of := {}
	for i in n:
		index_of[bodies[i].id] = i
	if _packed_manifolds:
		# 打包路径：流形记录里直接就是物体**下标**，连 id->index 都不用查
		for k in _bp_count:
			var base := 8 + k * NATIVE_MAN_STRIDE
			var ia0 := _bp_res.decode_s32(base)
			var ib0 := _bp_res.decode_s32(base + 4)
			if bodies[ia0].is_static or bodies[ib0].is_static:
				continue
			_union(parent, ia0, ib0)
	else:
		for m: Solver.Manifold in manifolds:
			if m.a.is_static or m.b.is_static:
				continue
			var ia: int = index_of.get(m.a.id, -1)
			var ib: int = index_of.get(m.b.id, -1)
			if ia < 0 or ib < 0:
				continue
			_union(parent, ia, ib)
	for i in n:
		var b: PBody = bodies[i]
		if b.is_static:
			continue
		# ⚠️ 被**外力驱动**的刚体不累积睡眠时间。
		# 少了这一条会出很隐蔽的陷阱：给一个静止物体加法向力，它一开始速度很小
		# 就被判为"慢"、随即睡着，之后外力**再也施加不上**（实测速度恒为 0）。
		# 语义上也对：持续外力 == 有东西在驱动它，不该被判定为静止。
		var driven := b.accum_force != Vector2.ZERO or b.accum_torque != 0.0
		if b.awake and not driven and b.is_slow(sleep_linear, sleep_surface):
			b.sleep_timer += dt
		elif b.awake:
			b.sleep_timer = 0.0
	# ---- 岛屿级唤醒 ----
	#
	# ⚠️ 只靠逐对唤醒（_wake_pass）会死锁：A 被抓着、想推开睡着的 B，
	# 但 A 因为被 B 挡住所以速度很低 —— 于是
	#     "A 太慢" ⇒ 不唤醒 B ⇒ B 当作静态（无限质量）⇒ A 更动不了
	# 实测以 20 px/s 拖动时邻居**永不苏醒**，物体 2 秒只挪了 1.2 像素。
	#
	# 判据必须与"被挡住物体的**速度**"无关。唯一的信号是"有东西在**驱动**这个岛"：
	#   · 被抓着  —— 游戏逻辑正在操控它
	#   · 有外力  —— 同上
	#
	# ⚠️ 不要把"岛里有成员在运动"也算进来。看着合理，实测**灾难性**：
	#    它把 sleep_box 从 0/12 变成 8/12 清醒 —— 因为该判据用的是双倍阈值
	#    （12 px/s），比休眠阈值（6）宽松，于是 6~12 之间的缓慢蠕动
	#    会让整个岛永远醒着。而这一条本来也是多余的：
	#    下面 island_min 取的是岛内 awake 成员 sleep_timer 的最小值，
	#    只要有人不"慢"，它的计时就是 0，岛自然不会睡。
	var island_drive := {}
	for i in n:
		var bd: PBody = bodies[i]
		if bd.is_static:
			continue
		if held.has(bd.id) or bd.accum_force != Vector2.ZERO or bd.accum_torque != 0.0:
			island_drive[_find(parent, i)] = true
	if not island_drive.is_empty():
		for i in n:
			var bw: PBody = bodies[i]
			if bw.is_static:
				continue
			if island_drive.has(_find(parent, i)):
				bw.awake = true
				bw.sleep_timer = 0.0
	# 每个岛取最小的 sleep_timer 作为岛的计时
	var island_min: Dictionary = {}
	for i in n:
		var b2: PBody = bodies[i]
		if b2.is_static or held.has(b2.id):
			continue
		var root := _find(parent, i)
		var prev: float = island_min.get(root, INF)
		island_min[root] = minf(prev, b2.sleep_timer if b2.awake else INF)
	for i in n:
		var b3: PBody = bodies[i]
		if b3.is_static or held.has(b3.id):
			continue
		var root2 := _find(parent, i)
		var t: float = island_min.get(root2, 0.0)
		if t >= sleep_delay:
			b3.awake = false
			b3.linear_velocity = Vector2.ZERO
			b3.angular_velocity = 0.0
			# 入睡时把"扫过范围"归位到 aabb：醒来之前 aabb 不会变，
			# 于是宽相可以整体跳过它（不归位的话它会留着入睡前一帧的膨胀量，
			# 跳过就不再等价了）。
			b3.swept_aabb = b3.aabb


static func _find(parent: Array, i: int) -> int:
	var root := i
	while parent[root] != root:
		root = parent[root]
	while parent[i] != root:
		var next: int = parent[i]
		parent[i] = root
		i = next
	return root


static func _union(parent: Array, a: int, b: int) -> void:
	var ra := _find(parent, a)
	var rb := _find(parent, b)
	if ra != rb:
		parent[rb] = ra


## ---------- 程序化破坏（世界坐标）----------
##
## fracture() 是**底层**接口：作用于一个 Body、坐标在**该 Body 的 Shape 局部像素空间**。
## 下面这一组才是给游戏逻辑用的 —— 给世界坐标，自动找出受影响的 Body 并换算过去，
## 并且**处理"破坏会改变 bodies 数组"这件事**（fracture 会增删刚体）。
##
## 全部返回新生成的碎片 Body 数组（与 fracture 一致）。
## material_delta：>0 把破坏边缘的像素换成该材质（烧焦/结冰/腐蚀），0 = 不改。
## burst_speed：碎片获得的初速度大小。

func damage_circle(world_center: Vector2, radius: float,
		material_delta: int = 0, burst_speed: float = 40.0) -> Array:
	var bounds := Rect2(world_center - Vector2(radius, radius), Vector2(radius, radius) * 2.0)
	return _damage_world(bounds, material_delta, burst_speed,
		func(b: PBody) -> Variant: return Destruction.Damage.circle(b.to_local(world_center), radius))


func damage_rect(world_center: Vector2, half_size: Vector2,
		material_delta: int = 0, burst_speed: float = 40.0) -> Array:
	var bounds := Rect2(world_center - half_size, half_size * 2.0)
	return _damage_world(bounds, material_delta, burst_speed,
		func(b: PBody) -> Variant: return Destruction.Damage.rect(b.to_local(world_center), half_size))


## 沿一条世界坐标线段挖一条半径 radius 的沟（"激光切割"）。
func damage_segment(world_from: Vector2, world_to: Vector2, radius: float,
		material_delta: int = 0, burst_speed: float = 40.0) -> Array:
	var pad := Vector2(radius, radius)
	var lo := Vector2(minf(world_from.x, world_to.x), minf(world_from.y, world_to.y)) - pad
	var hi := Vector2(maxf(world_from.x, world_to.x), maxf(world_from.y, world_to.y)) + pad
	var bounds := Rect2(lo, hi - lo)
	return _damage_world(bounds, material_delta, burst_speed,
		func(b: PBody) -> Variant:
			return Destruction.Damage.segment(b.to_local(world_from), b.to_local(world_to), radius))


## 爆炸：半径内先按距离衰减施加**径向冲量**，再做一次圆形破坏。
##
## power 是**速度增量**语义（紧贴爆心的物体大约获得 power 的速度），
## 与物体质量无关 —— 内部按 impulse *= mass 抵消掉质量项。
func explode(world_center: Vector2, radius: float, power: float,
		material_delta: int = 0, burst_speed: float = 40.0) -> Array:
	var r2 := radius * radius
	for b: PBody in bodies:
		if b.is_static or not b.awake:
			continue
		var d := b.com_world() - world_center
		var dsq := d.length_squared()
		if dsq > r2:
			continue
		var dist := sqrt(dsq)
		var falloff := 1.0 - dist / radius
		var dir := Vector2.UP if dist < 1e-4 else d / dist
		b.apply_central_impulse(dir * (power * falloff * b.mass))
	return damage_circle(world_center, radius, material_delta, burst_speed)


## 世界坐标的"涂色"：把半径内的像素材质改成 material（**不破坏、不分裂**）。
## 返回改动的像素数。
##
## ⚠️ 只接受非 0 材质。擦除会把 Shape 挖成不连通（违反引擎不变量），
##    需要挖洞请用 damage_circle（它带连通性分裂）。
func paint_circle(world_center: Vector2, radius: float, material: int) -> int:
	if material <= 0:
		push_error("paint_circle 的 material 必须 > 0；挖洞请用 damage_circle")
		return 0
	var total := 0
	var bounds := Rect2(world_center - Vector2(radius, radius), Vector2(radius, radius) * 2.0)
	var touched: Array = []
	for b: PBody in bodies:
		if b.rects.is_empty() or not bounds.intersects(b.aabb):
			continue
		var local_center := b.to_local(world_center)
		var n := 0
		for s in b.shapes:
			n += _paint_shape_circle(s, local_center, radius, material)
		if n > 0:
			total += n
			touched.append(b)
	# 材质变了 -> 密度可能变 -> 只对**真的被改到**的刚体重算质量/惯量
	for b2: PBody in touched:
		if not b2.is_static:
			refresh_mass(b2)
	return total


func _paint_shape_circle(shape, local_center: Vector2, radius: float, material: int) -> int:
	var n := 0
	var r2 := radius * radius
	var lo := Vector2i(int(floor(local_center.x - radius)), int(floor(local_center.y - radius)))
	var hi := Vector2i(int(ceil(local_center.x + radius)), int(ceil(local_center.y + radius)))
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			var dx := float(x) + 0.5 - local_center.x
			var dy := float(y) + 0.5 - local_center.y
			if dx * dx + dy * dy > r2:
				continue
			if shape.get_pixel(x, y) == 0:
				continue
			shape.set_pixel(x, y, material)
			n += 1
	return n


func _damage_world(bounds: Rect2, material_delta: int, burst_speed: float,
		make_damage: Callable) -> Array:
	var out: Array = []
	# ⚠️ fracture 会增删 bodies —— 必须先拷一份再遍历，否则会漏掉/重复处理
	for b: PBody in bodies.duplicate():
		if b.rects.is_empty() or not bounds.intersects(b.aabb):
			continue
		var d = make_damage.call(b)
		d.material_delta = material_delta
		for p in fracture(b, d, burst_speed):
			out.append(p)
	return out


## ---------- 破坏（底层）----------

## 在 body 局部像素空间施加破坏，并做连通性分裂。
## 返回新生成的碎片 Body（原 Body 保留最大的那一块）。
func fracture(body: PBody, damage, burst_speed: float = 40.0) -> Array:
	var removed := 0
	var parts: Array = []
	for s in body.shapes:
		# 优先走 GPU：一次 dispatch 同时完成破坏 + 分量标注
		var accel: Dictionary = Destruction.apply_damage_and_split_gpu(s, damage, min_fragment_pixels)
		if not accel.is_empty():
			removed += int(accel["removed"])
			for p in accel["parts"]:
				parts.append(p)
			continue
		# CPU 回退路径
		removed += Destruction.apply_damage(s, damage)
		for p in Destruction.split(s, min_fragment_pixels):
			parts.append(p)
	if removed == 0:
		return []
	if parts.is_empty():
		remove_body(body)
		return []

	# 最大的那块留在原 Body
	var best := 0
	var best_n := -1
	for i in parts.size():
		var cnt: int = parts[i].pixel_count()
		if cnt > best_n:
			best_n = cnt
			best = i

	var parent_vel := body.linear_velocity
	var parent_ang := body.angular_velocity
	body.rebuild([parts[best]], Callable(), max_rects_per_shape)
	body.awake = true
	body.sleep_timer = 0.0
	body.update_aabb()

	var spawned: Array = []
	for i in parts.size():
		if i == best:
			continue
		var frag := PBody.new()
		frag.position = body.position
		frag.rotation = body.rotation
		# 继承母体速度，并给一点向外飞散的冲量
		var dir: Vector2 = parts[i].local_aabb().get_center() - parts[best].local_aabb().get_center()
		if dir.length_squared() < 0.0001:
			dir = Vector2(0, -1)
		frag.linear_velocity = parent_vel + dir.normalized() * burst_speed
		frag.angular_velocity = parent_ang
		frag.awake = true
		add_body(frag, [parts[i]])
		spawned.append(frag)
	if not spawned.is_empty():
		solver.clear_warm()
	return spawned


## ---------- 抓取 ----------

func grab(b: PBody, world_point: Vector2, accel: float = 2500.0) -> Grab:
	## 同一个物体只允许一个抓取点；抓取会立刻唤醒它。
	release_grab()
	if b == null or b.is_static:
		return null
	var g := Grab.new()
	g.body = b
	g.local_anchor = b.to_local(world_point)
	g.target = world_point
	g.max_accel = accel
	grabs.append(g)
	b.awake = true
	b.sleep_timer = 0.0
	return g


func set_grab_target(world_point: Vector2) -> void:
	for g in grabs:
		g.target = world_point


func release_grab() -> void:
	grabs.clear()


func is_grabbing() -> bool:
	return not grabs.is_empty()


## 碎块数量上限：超出时淘汰最小、且已休眠、且没被抓的碎片。
## 没有这道闸门，连续擦除地形几分钟就会积累上千个刚体。
func enforce_body_budget() -> int:
	var count := 0
	for b in bodies:
		if not b.is_static:
			count += 1
	if count <= max_dynamic_bodies:
		return 0
	var held := {}
	for g in grabs:
		if g.body != null:
			held[g.body.id] = true
	var candidates: Array = []
	for b2 in bodies:
		if b2.is_static or b2.awake or held.has(b2.id):
			continue
		candidates.append(b2)
	candidates.sort_custom(func(x: PBody, y: PBody) -> bool:
		return x.mass < y.mass)
	var removed := 0
	for b3: PBody in candidates:
		if count - removed <= max_dynamic_bodies:
			break
		remove_body(b3)
		removed += 1
	return removed
