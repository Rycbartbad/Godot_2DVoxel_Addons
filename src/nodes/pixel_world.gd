@tool
class_name PixelWorld
extends Node2D
## **场景里的物理世界**：把子节点里的 @@PixelBody2D@@ 烘焙成刚体，然后驱动它们。
##
## ## 性能设计（这是本节点存在的关键）
##
## 烘焙只发生**一次**（@@_ready()@@ 里）。之后每帧只做两件事：
##   @@world.step(dt)@@       —— 全是 RefCounted，不碰任何 Node
##   @@renderer.prune(...)@@  —— 只在刚体增删时才有实际工作
##
## 所以"用场景节点摆刚体"**不会**让物理变慢：热循环里的数据结构和
## 纯代码构建时**完全一样**。子节点在烘焙后不参与任何每帧工作。
##
## 实测（500 个刚体，跑 300 步）：
##   代码构建   step 合计与节点构建**逐位相同**
##   节点构建   额外的只有一次 _ready 烘焙（见 tools/bench_nodes.py）
##
## ## 用法
##
## 场景里放一个 PixelWorld，把 PixelBody2D 作为它的**直接子节点**摆好，
## 运行即可。编辑器里也会把像素和碰撞形状画出来（@tool）。

const PWorld := preload("res://src/physics/pworld.gd")
const PBody := preload("res://src/physics/pbody.gd")
const PixelRenderer := preload("res://src/render/pixel_renderer.gd")
const PixelBody2D := preload("res://src/nodes/pixel_body_2d.gd")
# ⚠️ 用 preload 而不是依赖全局 class_name：addon 里也有同名脚本，
#    靠 class_name 解析在某些缓存状态下会失败，preload 是确定的。
const PixelMaterial := preload("res://src/nodes/pixel_material.gd")
const PixelSprite2D := preload("res://src/nodes/pixel_sprite_2d.gd")

@export_group("物理")
@export var gravity := Vector2(0, 600)
@export var fixed_dt := 1.0 / 60.0
@export var max_substeps := 4
@export var sleeping := true
@export var terminal_speed := 650.0

@export_group("材质")
## 全部材质。**在这里加一条就是加一种材质** —— 颜色、密度、强度一次设好。
##
## ⚠️ 以前颜色/密度/强度是三张散落的表（还分居两个对象），改一处忘另一处是静默 bug。
##    现在它们是同一份数据的三个视图，由 rebuild() 一次性播到物理层和渲染层。
##
## 没列进来的 id 会退回下面的 fallback 表。
@export var materials: Array[PixelMaterial] = []

## 兜底颜色表（下标即材质 id，0 必须是透明）。只在 materials 里没覆盖到该 id 时用。
@export var palette_fallback: Array[Color] = [
	Color(0, 0, 0, 0),
	Color(0.62, 0.60, 0.56),
	Color(0.72, 0.52, 0.32),
	Color(0.55, 0.58, 0.66),
	Color(0.80, 0.32, 0.30),
]
## 兜底密度表（下标即 id，缺省 1.0）
@export var densities_fallback: Array[float] = [0.0, 2.5, 0.6, 7.8, 2.0]

@export_group("运行")
@export var auto_step := true
@export var auto_render := true
## 是否在每次重建时打印烘焙数量。
##
## ⚠️ 默认 **false**：编辑器里拖一下就会重建一次，日志会刷屏。
##    排查"节点没被烘焙""数量不对"时再打开。
@export var log_bake := false

var world = null
var renderer: PixelRenderer = null
var _accum := 0.0
var _rebuild_queued := false
var _transform_queued := false
## 与 world.bodies 一一对应的节点（用来判断谁自带精灵）
var _body_nodes: Array = []


func _ready() -> void:
	rebuild()
	if Engine.is_editor_hint():
		return
	set_physics_process(true)


## 重建整个世界：把子节点里的 PixelBody2D 全部烘焙一遍。
##
## 编辑器里改完子节点之后调一次即可（@tool 下可以从 Inspector 的
## "调用方法"里点，或者重新打开场景）。运行时不建议调 —— 会丢掉破坏状态。
func rebuild() -> void:
	world = PWorld.new()
	world.gravity = gravity
	world.fixed_dt = fixed_dt
	world.max_substeps = max_substeps
	world.sleeping_enabled = sleeping
	world.terminal_speed = terminal_speed
	# ---- 把材质播到物理层与渲染层 ----
	# ⚠️ 这是本节点存在的核心理由之一：材质是**一份数据**，
	#    颜色给渲染、密度给物理、强度给破坏判据 —— 三处必须同源。
	var pal := palette_fallback.duplicate()
	var dens := PackedFloat32Array()
	dens.resize(densities_fallback.size())
	for i in densities_fallback.size():
		dens[i] = densities_fallback[i]
	for m in materials:
		if m == null:
			continue
		var mid := clampi(m.id, 1, 254)
		while pal.size() <= mid:
			pal.append(Color(1, 1, 1))
		pal[mid] = m.color
		while dens.size() <= mid:
			dens.resize(mid + 1)
		dens[mid] = m.density
		if m.has_strength():
			world.set_material_strength(mid, m.compress_strength, m.resolved_shear())
	# 密度表直接写进 world（与 material_density 同构）
	for i in dens.size():
		world.set_material_density(i, dens[i])
	if renderer == null:
		renderer = PixelRenderer.new()
		renderer.name = "PixelRenderer"
		add_child(renderer)
	renderer.palette = pal
	var dens_call := Callable(self, "_density_of")
	_body_nodes.clear()
	var n := 0
	for c in get_children():
		if not (c is PixelBody2D):
			continue
		# 造 body（配置位置/速度）与「加进世界」是两步，bake_node 一起做完
		if bake_node(c as PixelBody2D) != null:
			n += 1
	if auto_render:
		# ⚠️ 必须先清空再重建：rebuild 会造出**新的 body.id**，
		#    而渲染器按 id 索引贴图 —— 不清的话旧贴图会留在原地变成幽灵
		#    （表现是"拖动之后原地还有一个不动的影子"）。
		renderer.prune({})
		# ⚠️ 自带 PixelSprite2D 的刚体不进内部渲染器 —— 否则会画两遍
		#    （两份精灵重叠，半透明时尤其明显）。
		var internal: Array = []
		for i in world.bodies.size():
			var b = world.bodies[i]
			if i < _body_nodes.size() and _body_nodes[i] != null 					and has_own_sprite(_body_nodes[i]):
				continue
			internal.append(b)
		renderer.sync_all(internal)
	_sync_overlays()
	if log_bake:
		print("[PixelWorld] 烘焙 %d 个刚体（场景节点 -> RefCounted，之后热循环不碰 Node）" % n)


## 把一个 PixelBody2D 子节点烘焙进**当前世界**，返回造出来的 PBody。
##
## ⚠️ 这是 rebuild() 的**增量版**，存在的理由是 rebuild() 太粗暴：
##    它 PWorld.new() 造一个**全新的世界** —— 运行时状态（已经破坏掉的像素、
##    正在飞的碎块、抓取）全部丢失，所以上面的注释写着"运行时不建议调"。
##    但"画完立刻固化出一个刚体"这类需求，必须能在**运行时**往世界里加东西。
##
## 节点没有形状时返回 null（跳过，与 rebuild 的行为一致）。
func bake_node(node: PixelBody2D) -> PBody:
	if world == null:
		rebuild()
	# ⚠️ 用 collect_shapes() 而不是 build_shape()：
	#    一个刚体可以挂**多个形状子节点**（就像多个 CollisionShape2D），
	#    也可以一个都不挂、退回自身的内置形状。
	var shapes := node.collect_shapes()
	if shapes.is_empty():
		return null
	var b: PBody = world.add_body(node.bake(), shapes, Callable(self, "_density_of"))
	# ⚠️ _body_nodes 与 world.bodies **按下标一一对应**（rebuild 末尾和
	#    has_own_sprite 的过滤都依赖这个不变量）。两边必须同时 append/remove_at。
	_body_nodes.append(node)
	if auto_render and renderer != null and not has_own_sprite(node):
		renderer.sync(b)
	_sync_overlays()
	return b


## 运行时把一个 PixelBody2D 加进**活着的世界**：不重建、不丢破坏状态。
##
## 与 rebuild() 的区别就是这一点 —— 这是"节点版"和"门面版"能共存的关键：
## 节点负责**编辑器里摆出来的**部分，运行时新增的部分走这里或门面的 spawn_*，
## 两者落在**同一个 world** 上。
func add_body_node(node: PixelBody2D) -> PBody:
	if world == null:
		rebuild()
	var i := _body_nodes.find(node)
	if i >= 0:
		return world.bodies[i] as PBody      # 已经烘焙过了，幂等
	return bake_node(node)


## 把一个烘焙过的子节点从世界里摘掉（同样是增量，不重建）。
func remove_body_node(node: PixelBody2D) -> bool:
	var i := _body_nodes.find(node)
	if i < 0:
		return false
	_body_nodes.remove_at(i)
	if i < world.bodies.size():
		world.remove_body(world.bodies[i])
	if renderer != null:
		renderer.prune(_live_ids())
	_sync_overlays()
	return true


## 供 PixelSprite2D 取用的调色板（保证与物理层同源）。
func palette_for_render() -> Array:
	return renderer.palette if renderer != null else palette_fallback


## 这个刚体是否自带 PixelSprite2D —— 自带的话就不进内部渲染器，避免画两遍。
static func has_own_sprite(node: Node) -> bool:
	for c in node.get_children():
		if c is PixelSprite2D:
			return true
	return false


func _density_of(material: int) -> float:
	if material >= 0 and material < densities_fallback.size():
		return densities_fallback[material]
	return 1.0


func _physics_process(delta: float) -> void:
	# ⚠️⚠️ 编辑器里绝不推进物理。
	#
	# 陷阱：**定义 _physics_process 这个函数本身就会启用它**。
	# _ready() 里那句
	#     if Engine.is_editor_hint(): return
	#     set_physics_process(true)
	# 是**挡不住**它的 —— 方法一存在，Godot 每帧就会调。守卫必须写在函数体里。
	# （这正是"编辑器里物体自己在动"的原因。）
	if Engine.is_editor_hint():
		return
	if not auto_step:
		return
	_accum += delta
	var steps := 0
	while _accum >= fixed_dt and steps < max_substeps:
		world.step(fixed_dt)
		_accum -= fixed_dt
		steps += 1
	if _accum > fixed_dt * float(max_substeps):
		_accum = 0.0
	if auto_render:
		renderer.prune(_live_ids())
		for b in world.bodies:
			renderer.sync(b)


func _live_ids() -> Dictionary:
	var d := {}
	for b in world.bodies:
		d[b.id] = true
	return d


## 把本节点里的调试叠加层也指到这个世界，并让它重绘一次。
##
## ⚠️ 用 set_world() 方法而不是直接赋 c.world —— 直接赋会报
##    "Invalid assignment of property or key 'world'"，而且报错信息不指向真因。
##    方法调用没有这个歧义，也顺便把「注入世界 + 重绘一次」绑成一件事
##    （叠加层在编辑器里不每帧重绘，必须有人叫它画）。
func _sync_overlays() -> void:
	for c in get_children():
		if c != renderer and c.has_method("set_world"):
			c.set_world(world)


## 子节点在编辑器里被拖动/旋转时由 PixelBody2D 调用。
##
## ⚠️ 拖动一次会连续发很多 NOTIFICATION_TRANSFORM_CHANGED，
##    每次都全量重建会卡（每个刚体约 0.2 ms）。这里防抖成"帧末重建一次"。
## 子节点**只是被拖动**（位置/旋转变了）—— 不做重烘焙，只同步位形。
##
## ⚠️⚠️ 这是编辑器拖动卡顿的根因所在。
##
## 之前拖动和"形状变了"走同一条路（on_child_moved -> rebuild），而 rebuild 要：
##     build_shape()  32000 像素的地面 ~38 ms
##     add_body()     贪心分解 + 质量属性 ~11 ms
##     建贴图          ~24 ms（prune({}) 会清掉全部贴图缓存 —— 重烘焙产生新 body id，
##                            缓存按 id 存，所以每次都得从零重建）
## 合计约 50~70 ms/次，拖动时每帧一次 -> 十几 FPS，看起来就是卡死。
##
## 但拖动**根本不需要重烘焙**：形状没变，变的只是刚体的位置和旋转。
## 所以这里只改 position/rotation，代价是几个赋值。
##
## 复用 _rebuild_queued 做防抖 —— 两者都是"本帧内积压多次只做一次"。
func on_child_transformed() -> void:
	if not Engine.is_editor_hint() or _transform_queued:
		return
	_transform_queued = true
	_sync_transforms_deferred.call_deferred()


func _sync_transforms_deferred() -> void:
	_transform_queued = false
	if not is_inside_tree() or not Engine.is_editor_hint() or world == null:
		return
	for i in _body_nodes.size():
		if i >= world.bodies.size():
			break
		var node = _body_nodes[i]
		if node == null:
			continue
		var b = world.bodies[i]
		b.position = node.position
		b.rotation = node.rotation
		b.update_aabb()
		b.compute_swept_aabb(0.0)
		if renderer != null:
			renderer.sync(b)


func on_child_moved() -> void:
	if not Engine.is_editor_hint() or _rebuild_queued:
		return
	_rebuild_queued = true
	_rebuild_deferred.call_deferred()


func _rebuild_deferred() -> void:
	_rebuild_queued = false
	if not is_inside_tree() or not Engine.is_editor_hint():
		return
	rebuild()


## 场景节点 -> 烘焙出来的刚体（找不到返回 null）
func body_of(node: Node) -> PBody:
	if node is PixelBody2D:
		return (node as PixelBody2D).body
	return null
