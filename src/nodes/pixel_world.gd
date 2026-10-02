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

@export_group("物理")
@export var gravity := Vector2(0, 600)
@export var fixed_dt := 1.0 / 60.0
@export var max_substeps := 4
@export var sleeping := true
@export var terminal_speed := 650.0
@export var use_native := true

@export_group("材质")
## 材质 id -> 颜色。下标就是材质 id，0 必须是透明。
@export var palette: Array[Color] = [
	Color(0, 0, 0, 0),
	Color(0.62, 0.60, 0.56),
	Color(0.72, 0.52, 0.32),
	Color(0.55, 0.58, 0.66),
	Color(0.80, 0.32, 0.30),
]
## 材质 id -> 密度（下标即 id，缺省 1.0）
@export var densities: Array[float] = [0.0, 2.5, 0.6, 7.8, 2.0]

@export_group("运行")
@export var auto_step := true
@export var auto_render := true

var world = null
var renderer: PixelRenderer = null
var _accum := 0.0
var _rebuild_queued := false


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
	world.use_native_broadphase = use_native
	world.use_native_collide = use_native
	world.use_native_solve = use_native
	# 颜色表给渲染器、密度表给物理 —— 两张表都从本节点这一处导出，不会不同步。
	# （这是门面层存在的理由之一：以前这两张表分居两处，改一处忘另一处是静默 bug。）
	if renderer == null:
		renderer = PixelRenderer.new()
		renderer.name = "PixelRenderer"
		add_child(renderer)
	renderer.palette = palette.duplicate()
	var dens := Callable(self, "_density_of")
	var n := 0
	for c in get_children():
		if c is PixelBody2D:
			var node := c as PixelBody2D
			var shape := node.build_shape()
			if shape.is_empty():
				continue
			# 造 body（配置位置/速度）与"加进世界"是两步，这里一起做完
			world.add_body(node.bake(), [shape], dens)
			n += 1
	if auto_render:
		# ⚠️ 必须先清空再重建：rebuild 会造出**新的 body.id**，
		#    而渲染器按 id 索引贴图 —— 不清的话旧贴图会留在原地变成幽灵
		#    （表现是"拖动之后原地还有一个不动的影子"）。
		renderer.prune({})
		renderer.sync_all(world.bodies)
	_sync_overlays()
	print("[PixelWorld] 烘焙 %d 个刚体（场景节点 -> RefCounted，之后热循环不碰 Node）" % n)


func _density_of(material: int) -> float:
	if material >= 0 and material < densities.size():
		return densities[material]
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
