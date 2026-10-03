extends SceneTree
## **节点版与门面版的融合**验证。
##
## 原本这是两个并列的前端，各自 PWorld.new() 一个世界 —— 编辑器里摆出来的关卡
## 和代码里 spawn 的刚体活在两个世界里：互相看不见、也不碰撞。
##
## ⚠️⚠️ 必须用 **addon 里的那一份**节点层，不能用 src/ 的。
##
##    原因是 addon 会**自带一份**引擎脚本的副本（它要能脱离本仓库独立分发）。
##    于是开发仓库里同时存在：
##        res://src/physics/pworld.gd                        （源码）
##        res://addons/pixel_destruction/physics/pworld.gd   （构建产物，逐字拷贝）
##    两份是**不同的 GDScript 资源**，Godot 按脚本身份做类型检查 ——
##    跨副本传对象会报
##        "The Object-derived class of argument 1 (pbody.gd) is not a subclass
##         of the expected argument class"
##    （两边名字一模一样，报错却看不出所以然）。
##
##    真实用户项目里**只有 addon 那一份**，节点层和门面都来自它，所以不存在这个问题。
##    这个测试要验证的是那个场景 —— 用 addon 的节点层才是对的。
##
## ⚠️ 先跑 python tools/build_addon.py（addon 平时不住在项目树里）。
const AddonWorld := preload("res://addons/pixel_destruction/nodes/pixel_world.gd")
const AddonBody := preload("res://addons/pixel_destruction/nodes/pixel_body_2d.gd")
const AddonShape := preload("res://addons/pixel_destruction/nodes/pixel_shape_2d.gd")
const FacadePath := "res://addons/pixel_destruction/pixel_physics.gd"

var _pass := 0
var _fail := 0

func _c(n: String, ok: bool, d: String = "") -> void:
	if ok:
		_pass += 1
		print("  PASS  ", n, "  ", d)
	else:
		_fail += 1
		print("  FAIL  ", n, "  ", d)

## 按"场景里摆节点"的方式造一个世界：地面 + 一个箱子。
func _make_node_world() -> Node2D:
	var pw = AddonWorld.new()
	pw.name = "PixelWorld"

	var ground = AddonBody.new()
	ground.name = "Ground"
	ground.position = Vector2(0, 220)
	ground.is_static = true
	pw.add_child(ground)
	var gs = AddonShape.new()
	gs.name = "Shape"
	gs.rect_size = Vector2i(768, 100)
	ground.add_child(gs)

	var box = AddonBody.new()
	box.name = "Box"
	box.position = Vector2(150, 30)
	pw.add_child(box)
	var bs = AddonShape.new()
	bs.name = "Shape"
	bs.rect_size = Vector2i(16, 16)
	bs.material_id = 2
	box.add_child(bs)

	get_root().add_child(pw)
	return pw

func _initialize() -> void:
	print("=== 节点 + 门面 融合验证 ===")
	var Facade = load(FacadePath)
	if Facade == null:
		print("  FAIL  找不到 ", FacadePath, " —— 先跑 python tools/build_addon.py")
		print("=== 0 passed, 1 failed ===")
		quit(1)
		return

	var pw = _make_node_world()
	await process_frame
	await process_frame
	# ⚠️ 再烘焙一次：形状节点的 get_shape() 有缓存，而上面是在**进树之前**
	#    挂上去的 —— 那时 _enter_tree 还没跑，缓存是空的，于是 collect_shapes()
	#    返回空、烘焙出 0 个刚体。真实用法是 .tscn（节点先建好再进树），没这一步。
	pw.rebuild()

	_c("节点已烘焙出世界", pw.world != null,
		"%d 个刚体" % (pw.world.bodies.size() if pw.world else 0))
	var n0: int = pw.world.bodies.size()

	# ---- 1) 接管：两边必须是**同一个世界** ----
	var f = Facade.new()
	pw.add_child(f)
	f.attach_to(pw)
	_c("接管后 world 是同一个对象", f.world == pw.world)
	_c("接管后门面不再自己 step / 自己画", not f.auto_step and not f.auto_render)

	# ---- 2) 门面 spawn 的刚体要落在**节点摆的地面**上 ----
	var box = f.spawn_rect(Vector2(400, 100), Vector2(16, 16), 1)
	_c("门面 spawn 出了刚体", box != null)
	_c("它进了同一个世界", pw.world.bodies.size() == n0 + 1,
		"%d -> %d" % [n0, pw.world.bodies.size()])

	for i in 300:
		pw.world.step(1.0 / 60.0)
	_c("落在节点摆的地面上（真碰撞）", absf(box.aabb.end.y - 220.0) < 2.0,
		"底边 y=%.2f（地面顶面 220）" % box.aabb.end.y)

	# ---- 3) 反向：节点摆的箱子会被门面 spawn 的东西撞到 ----
	var node_box = null
	for b in pw.world.bodies:
		if not b.is_static and b.position.x < 200.0:
			node_box = b
			break
	_c("节点摆的箱子也在同一个世界里", node_box != null)
	if node_box != null:
		_c("它已经落到地面附近", node_box.aabb.end.y > 200.0,
			"底边 y=%.2f" % node_box.aabb.end.y)

	# ---- 4) 运行时 add_body_node **不重建世界** ----
	var probe = f.spawn_rect(Vector2(600, 150), Vector2(12, 12), 1)
	for i in 20:
		pw.world.step(1.0 / 60.0)
	var probe_y: float = probe.position.y
	var count_before: int = pw.world.bodies.size()

	var extra = AddonBody.new()
	extra.name = "Extra"
	extra.position = Vector2(650, 100)
	pw.add_child(extra)
	var baked = pw.add_body_node(extra)
	_c("add_body_node 烘焙出了刚体", baked != null)
	_c("世界多了一个", pw.world.bodies.size() == count_before + 1,
		"%d -> %d" % [count_before, pw.world.bodies.size()])
	_c("**已有刚体状态没被重置**（没重建世界）",
		absf(probe.position.y - probe_y) < 1.0,
		"探针 y %.2f -> %.2f" % [probe_y, probe.position.y])
	_c("add_body_node 幂等", pw.add_body_node(extra) == baked)
	_c("remove_body_node 能摘掉", pw.remove_body_node(extra))
	_c("摘掉后世界少一个", pw.world.bodies.size() == count_before)

	print("=== %d passed, %d failed ===" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
