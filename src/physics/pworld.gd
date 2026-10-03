extends RefCounted
## 物理世界：固定步长管线 + 岛屿休眠 + 破坏/分裂。
##
## 管线（与参考实现一致）：
##   IntegrateForces -> Broadphase -> Narrowphase -> Solve -> IntegrateTransform -> Sleep
## 破坏发生在窄相之前：先改拓扑，再让物理看到最新数据。

const PBody := preload("res://src/physics/pbody.gd")
const Collide := preload("res://src/physics/collide.gd")
const Solver := preload("res://src/physics/solver.gd")

const Destruction := preload("res://src/core/destruction.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")
const Grab := preload("res://src/physics/grab.gd")
const Sweep := preload("res://src/physics/sweep.gd")

const Query := preload("res://src/physics/query.gd")

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
## 睡眠的**表面速度**容差：|ω| * bounding_radius() 要小于它才算「慢」。
## 休眠的表面速度阈值：接触点处速度 = 线速度 + 角速度 × 力臂。
##
## ⚠️ 这个值曾经**和接触点公式绑死**，现在解开了 —— 现在的 6.0 是接触点修好
## 之后重新量出来的（数值和最初那个 6.0 相同，但理由完全不同，别再混为一谈）。
##
## 历史：接触点公式错误时（合成点落在窄物体的形心上），推测接触实际是死的，
## 静止堆叠会残留 0.43~0.48 rad/s 的角速度；20x20 方块的对角半径约 14，
## 表面速度 ≈ 6.7 刚好压过 6.0 —— 于是"几乎不动"的箱子永远醒着。
## 当时把阈值提到 12.0 把它盖住了 —— **那是在盖症状，不是修问题**。
##
## 接触点改回真实几何（见 collide.gd 的墓碑注释）之后重新扫过：
##   · 单场景扫描（sleep_box / sleep_frag，各扫 4/6/8/10/12）：
##       surf=4.0  → sleep_box 12/12 清醒（最大表面速度 7.624）
##       surf>=6.0 → 两个场景全部入睡，最大表面速度 0.000
##   · 当初促成 12.0 的那条诊断（tests/diag_sleep_surface.gd，gap=4/8 的三层
##     堆叠）在 6.0 下**全部入睡**（vmax / wmax 都是 0）
## 所以 6.0 已经够用，12.0 偏松（会让真正在慢慢转的堆叠也睡着）。已改回 6.0。
##
## ⚠️ 改这个值会动两条休眠基准。**当前基准（6.0）**：
##     sleep_box  -4.465181229425  (0/12)
##     sleep_frag -39.158215979656 (0/120)
## 参考：12.0 时是 -4.415035308716 / -39.175550847507（已废弃）。
## 另外四条非休眠基准不受影响（那些场景 sleeping_enabled = false）。
##
## ⚠️ 它还和 _wake_pair 耦合：那里用 sleep_surface * 2.0 判"邻居算不算在动"，
##    所以这个值一变，"睡着的物体被谁唤醒"也跟着变（6.0 → 唤醒门槛 12.0，
##    12.0 时是 24.0）。改它之前先看一眼 _wake_pair 与坑 37。
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
## （合成点偏出真实接触区，见坑 34）时的 workaround。
## 那个公式已经被删掉了（见 collide.gd 的墓碑注释）：现在分离与穿透走**同一套**
## 参考面/入射面裁剪，接触点就是真实几何，不再有"偏移"这回事。
## 上面那条（边际必须小于子步位移上限）仍然是**独立成立**的理由。
var max_speculative_margin := 1.5
var last_substeps := 1
## 形状缓存：一个 body 的 OBB 在一步里是固定的，但旧代码在**每一对**里都重建一次。
## 实测 240 个物体、只有 26 个流形时，窄相仍占掉 75% 的帧时间 —— 几乎全是重复构建。
var _obb_cache: Array = []
var _aabb_cache: Array = []
var _radius_cache: PackedFloat32Array = PackedFloat32Array()

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
## ⚠️ 只有 **native 一条路**了。原来这里有三个开关（@@use_solver_batch@@ /
## @@use_native_collide@@ / @@use_native_broadphase@@）和一条 GDScript 回退路径，
## 全部已删除：宽相、窄相、求解都走 GDExtension。
## 缺扩展时**响亮地失败**，不再静默换一个实现（那正是坑 36 的根源）。
## 历史：双路径逐位一致曾经是最强的验证手段，但它也是最大的税 ——
## 每次改动都要写两遍，而且反复分叉（坑 18/31/36）。
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
## 求解器也走 GDExtension：直接吃宽相的打包流形，连 Manifold/Point 对象都不用建。
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
## 宽相细分：GDScript 侧准备（扫掠 AABB + 排序 + 编码） vs 纯 C++ 调用
var bp_encode_us := 0
var bp_native_us := 0
var bp_sweep_us := 0     ## 扫掠 AABB
var bp_sort_us := 0      ## 排序
var bp_prep_us := 0      ## 编码打包表
var bp_resolve_us := 0

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


## 世界自己登记到查询模块，销毁时自己注销。
##
## ⚠️ 为什么不让调用方手动 attach：Query 的注册表是**静态变量**，
## 忘了注销就会一直持有刚体引用，Godot 退出时报
## "resources still in use at exit" / "Orphan StringName: RefCounted (static: 1)"。
## 让拥有者负责生命周期，调用方就没有"记得注销"这件事。
func _init() -> void:
	Query.attach(self)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		Query.detach(self)


## 设置某材质的密度（会自动扩容表，中间没设过的按 1.0 算）。
## ---- 材质强度表 ----
##
## 与 material_density 同构：下标即材质 id，缺省 0（= 不破坏，需要显式设）。
##
## 两种强度分开是因为**同一种材料抗压远强于抗剪** —— 这正是"矛能破盾、
## 盾不能破矛"的物理来源：矛尖对盾面是压缩，盾缘对矛杆是剪切/弯曲。
##
## 单位是"应力"，即 冲量 / 接触宽度，与 Contact.impulse / Contact.contact_width 同量纲。
var material_compress := PackedFloat32Array()
var material_shear := PackedFloat32Array()


## 设某材质的抗压/抗剪强度。shear 省略时取 compress 的 30%（多数固体的大致比例）。
func set_material_strength(material: int, compress: float, shear: float = -1.0) -> void:
	# ⚠️ shear <= 0 一律按抗压的 30% 处理，**不允许真的设成 0**。
	#
	# 这套 API 里 0 的语义是「不参与破坏」（调用方用 strength_for() > 0 判断）。
	# 如果 shear=0 被当成字面的 0，那么宽接触（shear_ratio → 1）算出的强度就是
	# lerpf(100, 0, 1) = 0 → 调用方跳过 → **配了强度的材质在剪切方向永远不破坏**，
	# 而且不报任何错。PixelMaterial.shear_strength = 0 正好会走到这条路。
	var s := compress * 0.3 if shear <= 0.0 else shear
	if material_compress.size() <= material:
		var n := material + 1
		material_compress.resize(n)
		material_shear.resize(n)
	material_compress[material] = compress
	material_shear[material] = s


func material_strength(material: int) -> Vector2:
	# ⚠️ 两张表的长度可能不同（material_shear 若被直接赋值就会更短），
	#    只按其中一张做界检查会越界。
	var n := mini(material_compress.size(), material_shear.size())
	if material < 0 or material >= n:
		return Vector2.ZERO
	return Vector2(material_compress[material], material_shear[material])


## 按 Contact 的 shear_ratio 插值出该用哪个强度。返回 0 表示"这个材质不破坏"。
func strength_for(material: int, shear_ratio: float) -> float:
	var s := material_strength(material)
	if s.x <= 0.0 and s.y <= 0.0:
		return 0.0
	return lerpf(s.x, s.y, clampf(shear_ratio, 0.0, 1.0))


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
	if use_rapier and _rp != null and body.rapier_id > 0:
		var cmds := PackedByteArray()
		_rp_u8(cmds, 4)
		_rp_u32(cmds, body.rapier_id)
		_rp_send(cmds, 4)
		_rp_by_id.erase(body.rapier_id)
		body.rapier_id = 0
	bodies.erase(body)


## ---------- 标签查询 ----------
##
## 让游戏逻辑"按名字找东西"，而不是自己维护一张 id -> 刚体 的表
## （那张表一旦漏掉删除分支就会变成悬空引用）。
## 标签存在 PBody.tags 里：tag -> value（value 可以是任意值，含 null）。

func find_bodies(tag: String) -> Array:
	var out: Array = []
	for b: PBody in bodies:
		if b.tags.has(tag):
			out.append(b)
	return out


func find_body(tag: String) -> PBody:
	for b: PBody in bodies:
		if b.tags.has(tag):
			return b
	return null


## 带某个标签的刚体所拥有的全部形状。
func find_shapes(tag: String) -> Array:
	var out: Array = []
	for b: PBody in find_bodies(tag):
		for s in b.shapes:
			out.append(s)
	return out


## 与矩形范围相交的刚体。
func bodies_in(bounds: Rect2) -> Array:
	var out: Array = []
	for b: PBody in bodies:
		if not b.rects.is_empty() and bounds.intersects(b.aabb):
			out.append(b)
	return out


## ---------- Rapier 后端 ----------
##
## 打开后**整条管线**交给 Rapier（宽相 / 窄相 / 求解 / 休眠 / CCD 全是它的）。
## 手写的 native 路径先保留着，直到测试套件判定通过（见开发日志「把物理交给 Rapier」）。
##
## 每个子步只有**一次** cmd() 调用：
##     把"引擎侧改过的"推过去 -> Rapier 走一步 -> 把结果读回来
## 推之前逐字段比对 PBody 上的镜像（_rp_*），没改过的一律不推 ——
## 否则每子步把几百个刚体全推一遍纯属白烧。
##
## ⚠️ 新建刚体要**单独一趟**：Rapier 分配的 id 在结果流里，而同一趟里后面的命令
##    就要用这个 id。新建是低频事件（破坏/分裂才发生），多一趟无所谓。
var use_rapier := true
var _rp: Object = null
var _rp_gravity_pushed := Vector2(INF, INF)
var _rp_cmd_us := 0
## rapier_id -> PBody。接触事件从 Rapier 拿回来的是 id，要映射回刚体。
var _rp_by_id := {}
## 本子步被抓住的刚体（每子步重建）。
var _rp_grabbed := {}
## 阻尼与引擎 _integrate_forces 里那两行**同值**。Rapier 的公式也是 v *= 1/(1+d*dt)，
## 所以直接设进去就等价，不需要自己再乘一遍。
## ⚠️ 改引擎那两行时必须同步改这里，否则两条路径会静默分叉。
var rp_linear_damping := 0.35
var rp_angular_damping := 0.6

# 命令流的写入辅助（PackedByteArray 必须自己 resize，encode_* 不会自动扩容）
static func _rp_u8(b: PackedByteArray, v: int) -> void:
	b.resize(b.size() + 1)
	b.encode_u8(b.size() - 1, v)

static func _rp_i32(b: PackedByteArray, v: int) -> void:
	var n := b.size()
	b.resize(n + 4)
	b.encode_s32(n, v)

static func _rp_u32(b: PackedByteArray, v: int) -> void:
	var n := b.size()
	b.resize(n + 4)
	b.encode_u32(n, v)

static func _rp_f64(b: PackedByteArray, v: float) -> void:
	var n := b.size()
	b.resize(n + 8)
	b.encode_double(n, v)

static func _rp_f32(b: PackedByteArray, v: float) -> void:
	var n := b.size()
	b.resize(n + 4)
	b.encode_float(n, v)

func _rp_send(cmds: PackedByteArray, out_cap: int) -> PackedByteArray:
	var inp := PackedByteArray()
	_rp_i32(inp, out_cap)
	_rp_i32(inp, cmds.size())
	inp.append_array(cmds)
	var tmpl := PackedByteArray()
	tmpl.resize(4 + out_cap)
	var res: PackedByteArray = _rp.cmd(inp, tmpl)
	return res

## 把还没有 Rapier 身份的刚体建出来，并把分配到的 id 记回 PBody。
func _rp_create_missing() -> void:
	var cmds := PackedByteArray()
	var n := 0
	for b: PBody in bodies:
		if b.rapier_id != 0:
			continue
		_rp_u8(cmds, 3)
		_rp_i32(cmds, 1 if b.is_static else 0)
		_rp_f64(cmds, b.position.x)
		_rp_f64(cmds, b.position.y)
		_rp_f64(cmds, b.rotation)
		n += 1
	if n == 0:
		return
	var res := _rp_send(cmds, n * 4)
	var off := 4
	# ⚠️ 刚体属性必须**第二趟**设：id 是 Rapier 分配的，第一趟发命令时还不知道。
	#    阻尼少了它，Rapier 用默认 0（引擎是 0.35/0.6）—— 力矩积分会整条错掉。
	var props := PackedByteArray()
	var m := 0
	for b: PBody in bodies:
		if b.rapier_id != 0:
			continue
		b.rapier_id = res.decode_s32(off)
		_rp_by_id[b.rapier_id] = b
		off += 4
		_rp_u8(props, 16)
		_rp_u32(props, b.rapier_id)
		_rp_f64(props, rp_linear_damping)
		_rp_f64(props, rp_angular_damping)
		_rp_u8(props, 17)
		_rp_u32(props, b.rapier_id)
		_rp_f64(props, b.gravity_scale)
		b._rp_gravity_scale = b.gravity_scale
		# ⚠️ 必须**显式推一次位姿与速度**。第一版只把镜像设成当前值，于是
		#    "建体之前就设好的" angular_velocity / position 被当成"已推过"，
		#    永远送不到 Rapier —— 表现为 test_physics 的 "body did rotate" 恒为 0。
		_rp_u8(props, 6)
		_rp_u32(props, b.rapier_id)
		_rp_f64(props, b.position.x)
		_rp_f64(props, b.position.y)
		_rp_f64(props, b.rotation)
		_rp_u8(props, 7)
		_rp_u32(props, b.rapier_id)
		_rp_f64(props, b.linear_velocity.x)
		_rp_f64(props, b.linear_velocity.y)
		_rp_f64(props, b.angular_velocity)
		m += 1
		# 新刚体一律先推一次矩形与全部状态
		b._rp_rects_rev = -1
		b._rp_x = b.position.x
		b._rp_y = b.position.y
		b._rp_rot = b.rotation
		b._rp_static = b.is_static
		b._rp_vx = b.linear_velocity.x
		b._rp_vy = b.linear_velocity.y
		b._rp_w = b.angular_velocity
	if m > 0:
		_rp_send(props, 4)



## Rapier 版子步：推 -> step -> 读回。
##
## 休眠完全交给 Rapier（它的岛管理器），所以这里**不**调 _update_sleep / _wake_pass。
## 接触事件走单独的通道（见 _collect_contacts），这里不碰。
func _substep_rapier(dt: float) -> void:
	if _rp == null:
		_rp = ClassDB.instantiate("RapierPhys")
	_rp_create_missing()
	# ---- 抓取约束：必须在**推送之前**解 ----
	#
	# 这样它改出来的速度能在**同一子步**里被 Rapier 的接触求解看到（否则会慢一帧）。
	# 引擎那条路径是在求解迭代里解 10 次（约束更硬）；这里是每子步一次 —— 手感略软，
	# 但限力 max_accel * mass * dt 仍然精确成立，这是"重物要滞后"的来源。
	_rp_grabbed.clear()
	for g in grabs:
		g.apply(dt)
		if g.body != null:
			_rp_grabbed[g.body] = true
	var t0 := Time.get_ticks_usec()
	var cmds := PackedByteArray()
	# 重力变了才推
	if gravity != _rp_gravity_pushed:
		_rp_u8(cmds, 1)
		_rp_f64(cmds, gravity.x)
		_rp_f64(cmds, gravity.y)
		_rp_gravity_pushed = gravity
	var n_state := 0
	var n_sleep := 0
	for b: PBody in bodies:
		if b.rapier_id <= 0:
			continue
		# 求解前的速度 —— 接触事件的 approach 要用它（见 PBody.pre_vx 的说明）
		b.pre_vx = b.linear_velocity.x
		b.pre_vy = b.linear_velocity.y
		b.pre_w = b.angular_velocity
		if b.is_static != b._rp_static:
			_rp_u8(cmds, 15)
			_rp_u32(cmds, b.rapier_id)
			_rp_i32(cmds, 1 if b.is_static else 0)
			b._rp_static = b.is_static
		if b._rp_gravity_scale != b.gravity_scale:
			_rp_u8(cmds, 17)
			_rp_u32(cmds, b.rapier_id)
			_rp_f64(cmds, b.gravity_scale)
			b._rp_gravity_scale = b.gravity_scale
		if b._rp_rects_rev != b.rects_rev:
			_rp_u8(cmds, 5)
			_rp_u32(cmds, b.rapier_id)
			_rp_i32(cmds, b.rects.size())
			for r: Rect2 in b.rects:
				_rp_f32(cmds, r.position.x)
				_rp_f32(cmds, r.position.y)
				_rp_f32(cmds, r.size.x)
				_rp_f32(cmds, r.size.y)
			_rp_f64(cmds, solver.global_friction)
			b._rp_rects_rev = b.rects_rev
		if b.position.x != b._rp_x or b.position.y != b._rp_y or b.rotation != b._rp_rot:
			_rp_u8(cmds, 6)
			_rp_u32(cmds, b.rapier_id)
			_rp_f64(cmds, b.position.x)
			_rp_f64(cmds, b.position.y)
			_rp_f64(cmds, b.rotation)
			b._rp_x = b.position.x
			b._rp_y = b.position.y
			b._rp_rot = b.rotation
		if b.linear_velocity.x != b._rp_vx or b.linear_velocity.y != b._rp_vy \
				or b.angular_velocity != b._rp_w:
			_rp_u8(cmds, 7)
			_rp_u32(cmds, b.rapier_id)
			_rp_f64(cmds, b.linear_velocity.x)
			_rp_f64(cmds, b.linear_velocity.y)
			_rp_f64(cmds, b.angular_velocity)
			b._rp_vx = b.linear_velocity.x
			b._rp_vy = b.linear_velocity.y
			b._rp_w = b.angular_velocity
		# 外力/力矩：变了才推，而且是 **reset + add**（等价于 set）。
		# Rapier 的 add_force 跨步累积，直接每步 add 会让力矩按 1+2+…+N 涨 ——
		# 实测 60 步差 33 倍（validation_dynamics 的"持续力矩"就是这么挂的）。
		# 被抓住的刚体**每子步强制推一次**（不只是变化时）：
		# Rapier 的 add_force(f, wake_up=true) 顺带把它唤醒，
		# 这正是"被抓着不入睡"需要的 —— 不需要另写一套保醒逻辑。
		if _rp_grabbed.has(b) or b.accum_force.x != b._rp_fx or b.accum_force.y != b._rp_fy 				or b.accum_torque != b._rp_tq:
			_rp_u8(cmds, 18)
			_rp_u32(cmds, b.rapier_id)
			if b.accum_force != Vector2.ZERO or b.accum_torque != 0.0:
				_rp_u8(cmds, 14)
				_rp_u32(cmds, b.rapier_id)
				_rp_f64(cmds, b.accum_force.x)
				_rp_f64(cmds, b.accum_force.y)
				_rp_f64(cmds, b.accum_torque)
			b._rp_fx = b.accum_force.x
			b._rp_fy = b.accum_force.y
			b._rp_tq = b.accum_torque
	# ---- 走一步 ----
	_rp_u8(cmds, 2)
	_rp_f64(cmds, dt)
	# ---- 读回：先状态，后睡眠（顺序决定了结果段的布局）----
	for b2: PBody in bodies:
		if b2.rapier_id <= 0 or b2.is_static:
			continue
		_rp_u8(cmds, 8)
		_rp_u32(cmds, b2.rapier_id)
		n_state += 1
	for b3: PBody in bodies:
		if b3.rapier_id <= 0 or b3.is_static:
			continue
		_rp_u8(cmds, 9)
		_rp_u32(cmds, b3.rapier_id)
		n_sleep += 1
	var res := _rp_send(cmds, n_state * 48 + n_sleep * 4)
	var off := 4
	for b4: PBody in bodies:
		if b4.rapier_id <= 0 or b4.is_static:
			continue
		b4.position = Vector2(res.decode_double(off), res.decode_double(off + 8))
		b4.rotation = res.decode_double(off + 16)
		b4.linear_velocity = Vector2(res.decode_double(off + 24), res.decode_double(off + 32))
		b4.angular_velocity = res.decode_double(off + 40)
		b4._rp_x = b4.position.x
		b4._rp_y = b4.position.y
		b4._rp_rot = b4.rotation
		b4._rp_vx = b4.linear_velocity.x
		b4._rp_vy = b4.linear_velocity.y
		b4._rp_w = b4.angular_velocity
		off += 48
	for b5: PBody in bodies:
		if b5.rapier_id <= 0 or b5.is_static:
			continue
		b5.awake = (res.decode_s32(off) == 0)
		off += 4
	for b6: PBody in bodies:
		if b6.is_static:
			continue
		b6.refresh_com()
		b6.update_aabb()
	_rp_cmd_us = Time.get_ticks_usec() - t0
	_collect_contacts_rapier()


## 求解前的速度在接触点处的线速度（含转动贡献）。
func _vel_at_pre(b: PBody, p: Vector2) -> Vector2:
	var r := p - b.com_world()
	return Vector2(b.pre_vx, b.pre_vy) + Vector2(-b.pre_w * r.y, b.pre_w * r.x)


## Rapier 版的接触采集。
##
## 与手写路径的区别：冲量**直接用 Rapier 的**（pair.total_impulse()），
## 不再靠"求解前后的速度差 × 有效质量"去估 —— 那是拿不到真值时的替代品。
## 但 approach 仍然必须用**求解前**的速度算（求解后接触点相对速度已归零）。
func _collect_contacts_rapier() -> void:
	if not contact_events_enabled:
		return
	if _rp == null:
		return
	var cnt_cmds := PackedByteArray()
	_rp_u8(cnt_cmds, 11)
	var cnt_res := _rp_send(cnt_cmds, 4)
	var n: int = cnt_res.decode_s32(4)
	var seen := {}
	if n > 0:
		var cmds := PackedByteArray()
		for i in n:
			_rp_u8(cmds, 12)
			_rp_i32(cmds, i)
		var res := _rp_send(cmds, n * 64)
		var off := 4
		for i in n:
			var ida := int(res.decode_double(off))
			var idb := int(res.decode_double(off + 8))
			var nx := res.decode_double(off + 16)
			var ny := res.decode_double(off + 24)
			var px := res.decode_double(off + 32)
			var py := res.decode_double(off + 40)
			var imp := res.decode_double(off + 56)
			off += 64
			var a: PBody = _rp_by_id.get(ida)
			var b: PBody = _rp_by_id.get(idb)
			if a == null or b == null:
				continue
			_contact_add_rapier(a, b, Vector2(px, py), Vector2(nx, ny), imp)
			var ka := a.id
			var kb := b.id
			seen[(ka << 32) | (kb & 0xFFFFFFFF) if ka < kb else (kb << 32) | (ka & 0xFFFFFFFF)] = true
	_contact_prev = seen


func _contact_add_rapier(a: PBody, b: PBody, point: Vector2, normal: Vector2, impulse: float) -> void:
	if contacts.size() >= max_contacts:
		return
	var c := Contact.new()
	c.a = a
	c.b = b
	c.point = point
	c.normal = normal
	var rel := _vel_at_pre(b, point) - _vel_at_pre(a, point)
	c.approach = -rel.dot(normal)
	# _fill_contact_stress 会按"接近速度全部被吃掉"先填一个近似冲量，
	# 下面立刻用 Rapier 的真值覆盖它。contact_width / shear_ratio 仍然要它算。
	_fill_contact_stress(c, a, b, rel, 0.0)
	c.impulse = impulse
	var ka := a.id
	var kb := b.id
	var key := (ka << 32) | (kb & 0xFFFFFFFF) if ka < kb else (kb << 32) | (ka & 0xFFFFFFFF)
	c.is_new = not _contact_prev.has(key)
	contacts.append(c)


func step(dt: float) -> void:
	if contact_events_enabled:
		contacts.clear()          # 按**步**清空；子步会往同一个列表里追加
	for b in bodies:
		b.refresh_com()
	if use_rapier:
		# Rapier 自带 CCD（非线性 CCD + 它自己的子步），所以**不再**自己切子步。
		# 切了反而会让重力/力被重复施加 —— 子步是引擎级的乘数，Rapier 内部另有机制。
		last_substeps = 1
		_substep_rapier(dt)
		return
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
	# 抓取是**游戏层策略**（见 grab.gd）：它只往 accum_force 里塞一个受限的力，
	# 所以必须在 _integrate_forces **之前**施。求解器完全不知道抓取的存在。
	for g in grabs:
		g.apply(dt)
	for b0 in bodies:
		b0.clear_pseudo()
	_integrate_forces(dt)
	_broadphase(dt)
	_collect_contacts()      # 求解**之前**采集：带的是"撞击前的接近速度"
	_wake_pass()
	_solve(dt)
	# 求解**之后**把真实冲量回填到接触事件上（见 _fill_contact_impulses 的说明）。
	# 放在这里而不是 _collect_contacts 里，是因为冲量要等求解器算完才有 ——
	# 采集时带的是"撞击前的接近速度"，两者是同一个事件的两面。
	_fill_contact_impulses()
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
		b.linear_velocity += gravity * (b.gravity_scale * dt)
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
	# 只有 native 一条路。GDScript 宽相（SAP 配对 + 逐对 collide + 对象装配）已删除。
	# 这个字段仍然存在，是因为唤醒/休眠/接触采集三处还按它分支 —— 下一轮清掉。
	_packed_manifolds = true
	_broadphase_native(dt)


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
	var _t_sweep := Time.get_ticks_usec()
	bp_sweep_us = _t_sweep - t_full
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
	bp_sort_us = Time.get_ticks_usec() - _t_sweep
	var _t_enc := Time.get_ticks_usec()
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
				# ⚠️ 不再静默回退 GDScript（回退路径已删除）。缺扩展是**配置错误**，
				#    必须响亮地失败，而不是让物理悄悄换一个实现。
				push_error("FastPhys 扩展不可用：宽相只有 native 一条路。请先构建 gdext/fastphys.dll（见 README）。")
				assert(false, "FastPhys 扩展不可用")
				return
			_bp_phys = ClassDB.instantiate("FastPhys")
	bp_prep_us = Time.get_ticks_usec() - _t_enc        # 编码阶段
	bp_encode_us = Time.get_ticks_usec() - t_full      # 到这里为止全是 GDScript 侧的准备
	var _t_native := Time.get_ticks_usec()
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
	bp_native_us = Time.get_ticks_usec() - _t_native      # 纯 C++ 宽相
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
	# ⚠️ 抓取**不再**走求解器（见 grab.gd）：它现在是"每子步一个受限的力"，
	#    在 _substep 开头就进了 accum_force，求解器完全不需要知道它存在。
	#    这里固定送 0 个抓取，扩展侧那段抓取分支随之成为死代码（内核删除时一并清）。
	#
	#    历史：这里曾经把抓取编码给扩展，为的是不让"有抓取"整条退回对象路径 ——
	#    坑 31 实测 49 个物体拖动时 step 从 1.28 ms 涨到 10.21 ms（慢 8 倍）。
	#    现在这个问题从根上不存在了：抓取根本不在求解器里。
	_sv_bod.encode_s32(88, 0)

	var need_out := 8 + n * NATIVE_SV_OUT
	if _sv_out.size() != need_out:
		_sv_out.resize(need_out)
	if _sv_phys == null:
		if not ClassDB.class_exists("FastPhys"):
			push_error("FastPhys 扩展不可用：求解器只有 native 一条路。请先构建 gdext/fastphys.dll（见 README）。")
			assert(false, "FastPhys 扩展不可用")
			_bp_res = PackedByteArray()
			return
		_sv_phys = ClassDB.instantiate("FastPhys")
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


## ---------- 动量统计 ----------
##
## 甲方要求"能读动量/角动量"。单体量在 PBody 上，这里给**总量** ——
## 总量是守恒检查的判据（碰撞前后应当相等，除非有重力/摩擦/阻尼在做功）。


## 全部动态体的总线动量 Σ m·v。
func total_momentum() -> Vector2:
	var s := Vector2.ZERO
	for b: PBody in bodies:
		if b.is_static:
			continue
		s += b.linear_momentum()
	return s


## 全部动态体关于世界某点的总角动量 Σ (I·ω + r × m·v)。
##
## ⚠️ 关于**原点**的角动量与关于**质心**的角动量是不同的量，而且只有关于
##    质心（或固定点）的角动量在无外力矩时才守恒。做守恒检查时请传质心。
func total_angular_momentum(about := Vector2.ZERO) -> float:
	var s := 0.0
	for b: PBody in bodies:
		if b.is_static:
			continue
		s += b.angular_momentum_about(about)
	return s


## 全部动态体的总动能。
func total_kinetic_energy() -> float:
	var s := 0.0
	for b: PBody in bodies:
		if b.is_static:
			continue
		s += b.kinetic_energy()
	return s


## 全部动态体的质心（按质量加权）。做守恒检查时传它当参考点。
func center_of_mass_world() -> Vector2:
	var m := 0.0
	var s := Vector2.ZERO
	for b: PBody in bodies:
		if b.is_static:
			continue
		m += b.mass
		s += b.com_world() * b.mass
	return s / m if m > 0.0 else Vector2.ZERO


## ---------- 接触事件 ----------
##
## 游戏层做"高速碰撞触发""挨打反应"需要知道**这一步发生了哪些接触、撞得多猛**。
## 引擎在这里把数据摆出来，但**不解释它** —— "多猛算高速""高速要怎样"是游戏规则。
##
## ⚠️ 三点约定，用之前必须知道：
##
## 1. **默认关闭**。开了就有每步构造事件的分配开销（对象分配在 GDScript 里不便宜）。
##
## 2. 事件在**求解之前**采集，所以带的是"撞击前的接近速度"而不是冲量。
##    冲量在原生求解器内部，GDScript 侧拿不到；而"接近速度"恰恰是
##    "高速碰撞"这类触发条件真正想要的量（冲量还受质量和恢复系数影响）。
##
## 3. 有子步时，**同一个配对可能在一步里出现多次**（每个子步一次）。
##    引擎按步清空，不跨子步去重 —— 要"每步只触发一次"请游戏层自己按 is_new 过滤。
##    列表有上限（max_contacts），超了就不再记，避免子步多时爆内存。
var contact_events_enabled := false
var max_contacts := 512
## 本步的接触事件（Contact 数组）。step() 开头清空，各子步往里追加。
var contacts: Array = []

var _contact_prev := {}


## 一次接触。字段都是**求解前**的状态。
class Contact:
	var a: PBody
	var b: PBody
	## 世界坐标接触点（取流形的第一个点；两点流形取中点意义不大，游戏一般只用它做特效位置）
	var point := Vector2.ZERO
	## 世界坐标法向，**由 a 指向 b**
	var normal := Vector2.ZERO
	## 沿法向的接近速度：**正 = 正在靠近**，单位 px/s。这就是"撞得多猛"。
	var approach := 0.0
	## 这一步才接触上（上一步不在这对里）。做"首次撞击"触发用。
	var is_new := false

	## ---- 接触冲量的**近似值**（单位：质量·像素/秒）----
	##
	## ⚠️ 这是近似，不是求解器里的真值。原生求解器的冲量留在 C++ 里拿不到，
	##    所以这里按"有效质量 × 接近速度"估：
	##        m_eff = 1 / (1/m_a + 1/m_b)      （静态体视作无穷大质量）
	##        J ≈ m_eff · |approach|
	##    ⚠️ 这是**近似值，而且会在求解后被真值覆盖** —— 见 _fill_contact_impulses()。
	##    求解器算了精确的 normal_impulse，这里先按近似填上，只是为了让
	##    "求解器没跑到这一对"（比如它被 sleep 掉了、或没有对应流形）时仍有可用值。
	##    读取方不需要关心这个区别，读到的要么是真值要么是合理的近似。
	var impulse := 0.0

	## 接触的**切向宽度**（像素）。用两刚体世界 AABB 在切向上的重叠近似。
	##
	## 用途：算应力 σ = impulse / contact_width。矛尖宽度小 → 应力大 → 能破盾。
	var contact_width := 0.0

	## **切向（摩擦）冲量**。求解之后的真值。
	##
	## 用途：算"磨"这种破坏 —— 盾被慢慢削薄不是被撞穿，是摩擦做功。
	## 与 impulse 一起构成这一对刚体本子步的总冲量。
	var tangent_impulse := 0.0

	## 内部：有效质量 1/(1/m_a + 1/m_b)（静态体视作无穷大质量）。
	## 冲量 = m_eff × 相对法向速度的**变化量**，所以求解前要把 m_eff 存下来。
	var _m_eff := 0.0

	## **剪切比**：0 = 纯压缩（法向穿过材料厚度方向），1 = 纯剪切。
	##
	## 由"接触法向 vs 该处材料的厚度方向"决定。同一种材料抗压远强于抗剪，
	## 所以这个值直接进破坏判据的强度插值。
	## 需要先调 set_material_strength() 才有意义；没设时保持 0。
	var shear_ratio := 0.0


## **真实接触宽度**：沿接触切向从接触点向两侧走，数「两个形状都实心」的像素数。
##
## ⚠️ 不要用「两个刚体 AABB 在切向上的重叠」来近似 —— 我第一版就是这么写的，
##    结果**看不出矛是尖的**：矛的 AABB 高 16、盾也是 16，算出来宽度相同，
##    而宽体的质量大 16 倍，于是「盾的应力反而更大」，与物理完全相反。
##
##    这个量是破坏判据的分母，必须反映**真实接触面积**，所以直接数体素。
##    矛尖只有几像素宽 → 应力大 → 破盾；盾面贴上来几十像素宽 → 应力小 → 不破。
##
## 代价是沿切向走 2*half+1 步、每步查两个形状的像素。只在开了接触事件时才算。
func _contact_width(a: PBody, b: PBody, point: Vector2, normal: Vector2,
		separation: float = 0.0) -> float:
	var t := Vector2(-normal.y, normal.x)
	# ⚠️⚠️ 采样要各自往自己身体里挪，而且挪的距离必须**大于分离距离**。
	#
	#    接触点恰好落在两者界面上时，floor() 会对两边都判"空" → 宽度恒 0。
	#    更要命的是**投机接触**：那时两个刚体还没真正重叠（separation > 0），
	#    接触点悬在空隙里，固定挪 0.5 根本够不着任何一侧 ——
	#    于是"最狠的那一击"（第一次撞上、冲量最大的那一帧）宽度报 0，
	#    σ = impulse/0 直接失效。实测验収：矛尖撞墙那帧 separation 0.73~1.44，
	#    挪 0.5 → 宽度 0；挪 1.0/1.5 → 宽度 1，σ 立刻从 0 变成 1539133。
	var push := maxf(0.5, separation + 0.5)
	var ea := point - normal * push
	var eb := point + normal * push
	# ⚠️ 窗口不能写死：以前固定 ±24，于是 60 px 宽和 200 px 宽的接触都算出 49，
	#    应力分别被高估 1.2 倍和 4 倍，"宽接触应力小"的分级整个失效。
	#    改成覆盖两者 AABB 在切向上的**重叠跨度**（那才是宽度的物理上限）。
	var sa := _project_span(a.aabb, t)
	var sb := _project_span(b.aabb, t)
	var overlap := maxf(0.0, minf(sa.y, sb.y) - maxf(sa.x, sb.x))
	var half := clampi(int(ceil(overlap * 0.5)) + 4, 8, 4096)
	var n := 0
	for i in range(-half, half + 1):
		var off := t * float(i)
		if _solid_at(a, ea + off) and _solid_at(b, eb + off):
			n += 1
	return float(n)


static func _solid_at(body: PBody, world_point: Vector2) -> bool:
	var lp := body.to_local(world_point)
	var x := int(floor(lp.x))
	var y := int(floor(lp.y))
	for s: PixelShape in body.shapes:
		if s.get_pixel(x, y) != 0:
			return true
	return false


## 把世界 AABB 投影到方向 t 上，返回 [min, max] 区间。
static func _project_span(box: Rect2, t: Vector2) -> Vector2:
	var c := box.get_center()
	var e := box.size * 0.5
	var h := absf(t.x) * e.x + absf(t.y) * e.y
	var m := c.dot(t)
	return Vector2(m - h, m + h)


## 用**求解前后的相对速度变化量**算出真实冲量，回填到本子步的接触事件上。
##
## ## 为什么是这么算的
##
## 冲量的定义就是**动量变化**：J = m_eff · Δv。所以不需要从求解器内部把
## normal_impulse 掏出来 —— 求解前记下接近速度（采集时已经有了），
## 求解后再测一次相对法向速度，差值乘有效质量就是冲量。
##
## ## 为什么不用求解器的 normal_impulse
##
## 第一版是遍历流形取 Solver.Point.normal_impulse。那在**默认配置下完全空转**：
## 默认 use_native_solve && use_native_broadphase → _packed_manifolds = true →
## _broadphase_native() 把 manifolds 置空，冲量留在 C++ 里且**不回写**。
## 于是遍历的是一个空数组，Contact.impulse 永远是近似值、tangent_impulse 恒为 0，
## 而且不报任何错。
##
## 现在这个算法**对两条路径都成立** —— 它只看速度，不关心冲量是在哪算的。
## 顺便还解决了近似值的最大毛病（偏心撞击高估，因为忽略转动项）：
## velocity_at() 取的是接触点处的速度，本来就含转动贡献。
##
## 旧文档（保留说明为何废弃）：
##
## ## 为什么要这一步
##
## 冲量是求解器的产物：它在迭代中累积每个接触点的 normal_impulse / tangent_impulse。
## 而接触事件是在**求解之前**采集的（那时才有"撞击前的接近速度"），
## 所以采集时冲量还不存在 —— 必须在求解之后补一次。
##
## ## 为什么不用近似了
##
## 之前 Contact.impulse 用的是 m_eff × approach 的**近似**，在偏心撞击下会高估
## （忽略了转动项）。而破坏判据最关心的恰恰是偏心撞击（矛尖戳盾面边缘）。
## 求解器本来就算了精确值，只是没往外递 —— 这里就是那个"递"。
##
## 代价：每个子步遍历一次流形的点，O(点数)。实测对 step 时间无可测影响。
## 开关：只为基准测试对比用（关掉就是加这个功能之前的行为）
var fill_contact_impulses_enabled := true
## 本子步第一个接触的下标 —— 回填时用它区分"本子步新增的"和"整步累积的"
var _substep_contact_begin := 0


func _fill_contact_impulses() -> void:
	if not fill_contact_impulses_enabled or contacts.is_empty():
		return
	# 只处理**本子步**新增的接触（contacts 整步累积，本函数每子步跑一次）
	for i in range(_substep_contact_begin, contacts.size()):
		var c: Contact = contacts[i]
		if c._m_eff <= 0.0:
			continue
		# 求解后的相对速度（同样取接触点处，含转动贡献）
		var rel := c.b.velocity_at(c.point) - c.a.velocity_at(c.point)
		var vn := -rel.dot(c.normal)
		# 冲量 = m_eff × (接近速度 - 分离速度)，夹到非负：
		# 求解器可能过冲（把接近变成离开），那时冲量就是全部吃掉的动量
		var jn := c._m_eff * maxf(0.0, c.approach - vn)
		# 切向同理 —— 摩擦冲量。它是「磨」这种破坏的关键
		# （盾被慢慢削薄，不是被撞穿，是摩擦做功）。
		var t := Vector2(-c.normal.y, c.normal.x)
		var jt := c._m_eff * absf(rel.dot(t))
		if jn > 0.0 or jt > 0.0:
			c.impulse = jn
			c.tangent_impulse = jt



## 算出这一对接触的应力相关量：冲量、接触宽度、剪切比。
##
## 剪切比需要**法向厚度**（要沿体素走一遍），所以只在调用方配过材质强度时才算 ——
## 没配强度的话这一项毫无用处，白花时间。
func _fill_contact_stress(c: Contact, a: PBody, b: PBody, rel: Vector2,
		separation: float = 0.0) -> void:
	var ma := 0.0 if a.is_static else a.mass
	var mb := 0.0 if b.is_static else b.mass
	var inv := (1.0 / ma if ma > 0.0 else 0.0) + (1.0 / mb if mb > 0.0 else 0.0)
	var m_eff := (1.0 / inv) if inv > 0.0 else 0.0
	c._m_eff = m_eff
	# 先按「接近速度全部被吃掉」填一个上界（就是以前的近似值），
	# 求解之后 _fill_contact_impulses 会用**实际动量变化**把它替换成真值。
	# 保留这一步是为了让「求解器没跑到这一对」（被 sleep 掉）时仍有可用值。
	c.impulse = m_eff * absf(c.approach)
	c.contact_width = _contact_width(a, b, c.point, c.normal, separation)
	if material_compress.is_empty() and material_shear.is_empty():
		return
	# 剪切比：法向穿过多厚 = 压缩；法向几乎不穿过厚度 = 剪切。
	# 取两侧较薄的那个（谁先坏看谁）。
	# ⚠️⚠️ 方向必须是「从接触点**朝自己身体里**」。
	#    normal 是 A→B，所以对 A 而言要传 -normal。
	#    我第一版传反了，于是 thickness_at 从 point-normal*back 开始沿 normal 走 ——
	#    那是**离开** A 材料的方向，量到的段长恒等于 back(=4)，
	#    24 像素厚的墙和 80 像素厚的墙算出同一个 thin。
	#    症状是 shear_ratio 与材料厚度完全无关，"抗压远强于抗剪"从未生效，
	#    而且 set_material_strength 的第二个参数等于白设。
	var ta := Query.thickness_at(a, c.point, -c.normal)
	var tb := Query.thickness_at(b, c.point, c.normal)
	var thin := ta if (ta > 0.0 and (tb <= 0.0 or ta < tb)) else tb
	if thin <= 0.0:
		c.shear_ratio = 0.0
		return
	# 法向"穿过"的厚度越薄，越是正面顶上去（压缩）；
	# 用接触宽度 / 厚度 做剪切比的代理：宽而薄 = 弯曲/剪切。
	c.shear_ratio = clampf(c.contact_width / (c.contact_width + thin), 0.0, 1.0)


func _contact_add(a: PBody, b: PBody, point: Vector2, normal: Vector2,
		separation: float = 0.0) -> void:
	if contacts.size() >= max_contacts:
		return
	var c := Contact.new()
	c.a = a
	c.b = b
	c.point = point
	c.normal = normal
	# 相对速度要取**接触点处**的速度（含转动贡献），不能用质心速度 ——
	# 一个高速旋转的物体，质心可能几乎不动，但它的边缘撞得很狠。
	var rel := b.velocity_at(point) - a.velocity_at(point)
	c.approach = -rel.dot(normal)
	# ⚠️ 必须在 c.approach **赋值之后**再算应力 —— _fill_contact_stress 读的就是它。
	#    我第一版把这一句插在前面，结果冲量恒为 0（approach 还是默认值），
	#    而且不会报任何错，只是"破坏判据永远不触发"。
	# ---- 冲量近似 + 接触宽度（很便宜，总是算）----
	_fill_contact_stress(c, a, b, rel, separation)
	var ka := a.id
	var kb := b.id
	var key := (ka << 32) | (kb & 0xFFFFFFFF) if ka < kb else (kb << 32) | (ka & 0xFFFFFFFF)
	c.is_new = not _contact_prev.has(key)
	contacts.append(c)


## 采集本子步的接触。两条路径（打包流形 / 对象流形）共用 _contact_add，
## 判定与换算都只写一次 —— 这个项目在"同一规则写两处"上栽过太多次（坑 18/31/36）。
func _collect_contacts() -> void:
	if not contact_events_enabled:
		return
	var seen := {}
	# 记下本子步从哪个下标开始 —— 回填冲量时只统计这一段
	_substep_contact_begin = contacts.size()
	if _packed_manifolds:
		# 打包流形布局：+0 ia, +4 ib, +16/24 normal(f64), +32 count, +40 起 2 个点(各 5 个 f64)
		for k in _bp_count:
			var base := 8 + k * NATIVE_MAN_STRIDE
			var ia := _bp_res.decode_s32(base)
			var ib := _bp_res.decode_s32(base + 4)
			var cnt := _bp_res.decode_s32(base + 32)
			if cnt <= 0:
				continue
			var a: PBody = bodies[ia]
			var b: PBody = bodies[ib]
			var n := Vector2(_bp_res.decode_double(base + 16), _bp_res.decode_double(base + 24))
			var pt := Vector2(_bp_res.decode_double(base + 40), _bp_res.decode_double(base + 48))
			# 点布局与 _native_out 一致：x(+0) y(+8) depth(+16) separation(+24) feature(+32)
			# 少了 separation，投机接触那帧的接触宽度会算成 0（见 _contact_width 的说明）
			var sep := _bp_res.decode_double(base + 64)
			_contact_add(a, b, pt, n, sep)
			var ka := a.id
			var kb := b.id
			seen[(ka << 32) | (kb & 0xFFFFFFFF) if ka < kb else (kb << 32) | (ka & 0xFFFFFFFF)] = true
	else:
		for m: Solver.Manifold in manifolds:
			if m.points.is_empty():
				continue
			var p0: Solver.Point = m.points[0]
			_contact_add(m.a, m.b, p0.position, m.normal, p0.separation)
			var ka2 := m.a.id
			var kb2 := m.b.id
			seen[(ka2 << 32) | (kb2 & 0xFFFFFFFF) if ka2 < kb2 else (kb2 << 32) | (ka2 & 0xFFFFFFFF)] = true
	_contact_prev = seen


## ---------- 求解 ----------
## 多线程的关键在于**按岛分组**：约束图里互不相连的岛之间没有任何耦合，
## 各自跑完整套迭代拿到的结果与串行完全一致（不是近似，是可复现的相同结果）。
## 所以这是"既安全又确定"的并行方式，不需要锁、也不需要归约。
func _solve(dt: float) -> void:
	# 整条求解链走 GDExtension（宽相输出 -> 求解器）。
	# GDScript 求解器（对象路径 / SoA 批量 / 岛并行 / 着色）已全部删除。
	# 岛并行与着色当年是 GDScript 侧的优化（实测 1.37~1.64x）；native 内部自己
	# 做同样的顺序迭代，所以这里不再需要它们。
	_solve_native(dt)



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
		# 注意：这里**不需要**手动标记内容变了 —— PBody.rebuild() 里统一做了
		# （破坏、擦除、绘制都汇到那一个 choke point）。之前我在这补过，
		# 那是症状处的补丁，漏掉 PixelEditor 那条路。
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
