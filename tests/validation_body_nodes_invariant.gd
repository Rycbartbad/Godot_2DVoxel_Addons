extends SceneTree
## 节点层不变量闸门：`_body_nodes` 与 `world.bodies` **按下标一一对应**。
##
## ⚠️ 为什么钉这条：任何绕过节点层增删刚体的路径都会破坏它，而破坏后的症状**不是报错** ——
##    数组变长时静默错位（渲染归属去问**别人的节点**）；数组变短时会让"按下标取节点"的
##    消费方越界中断，那之后的刚体（通常正是新碎片）这一帧不再被 sync，贴图停在旧位姿。
##    用户报的"碎片有位置偏差"就是这么来的（ink-2 里 30 帧 8 次 Invalid access of index）。
##    现在 `PixelWorld` 按 `world.bodies_rev` 自动对齐，所以**消费者不用再记这条规矩**。
const AddonWorld := preload("res://src/nodes/pixel_world.gd")
const AddonBody := preload("res://src/nodes/pixel_body_2d.gd")
const AddonShape := preload("res://src/nodes/pixel_shape_2d.gd")
const PBody := preload("res://src/physics/pbody.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

var _pass := 0
var _fail := 0
func _c(n: String, ok: bool, d: String = "") -> void:
	if ok: _pass += 1; print("  PASS  ", n, "  ", d)
	else: _fail += 1; print("  FAIL  ", n, "  ", d)

func _aligned(pw) -> bool:
	if pw._body_nodes.size() != pw.world.bodies.size():
		return false
	for i in pw.world.bodies.size():
		var n = pw._body_nodes[i]
		if n != null and n.body != pw.world.bodies[i]:
			return false
	return true

func _mk() -> Node:
	var pw = AddonWorld.new()
	var g = AddonBody.new()
	g.position = Vector2(0, 200)
	g.is_static = true
	pw.add_child(g)
	var gs = AddonShape.new()
	gs.rect_size = Vector2i(400, 40)
	g.add_child(gs)
	get_root().add_child(pw)
	return pw

func _initialize() -> void:
	print("=== _body_nodes 不变量（绕过节点层也要自动对齐）===")
	var pw = await _mk()
	await process_frame
	await process_frame
	pw.rebuild()
	_c("初始状态对齐", _aligned(pw), "nodes %d / bodies %d" % [pw._body_nodes.size(), pw.world.bodies.size()])

	# ① 绕过节点层**直接加**刚体（= 门面 spawn_* / 调试脚本的 add_body）
	var w = pw.world
	var b1 := PBody.new()
	var s1 := PixelShape.new()
	s1.fill_rect(Rect2i(0, 0, 16, 16), 1)
	w.add_body(b1, [s1])
	_c("直接 add_body 后：不变量暂时被破坏（这是预期）", not _aligned(pw),
		"nodes %d / bodies %d" % [pw._body_nodes.size(), w.bodies.size()])
	pw._physics_process(1.0 / 60.0)                 # 节点走一帧 -> 自动对齐
	_c("走一帧后：**自动对齐**（消费者不用管）", _aligned(pw),
		"nodes %d / bodies %d" % [pw._body_nodes.size(), w.bodies.size()])

	# ② 绕过节点层**直接删**刚体（= 灰尘策略的 remove_body）
	w.remove_body(b1)
	_c("直接 remove_body 后：不变量暂时被破坏（这是预期）", not _aligned(pw))
	pw._physics_process(1.0 / 60.0)
	_c("走一帧后：自动对齐", _aligned(pw),
		"nodes %d / bodies %d" % [pw._body_nodes.size(), w.bodies.size()])

	# ③ 版本号必须真的动了（否则自动对齐是空转）
	var rev0: int = w.bodies_rev
	var b2 := PBody.new()
	var s2 := PixelShape.new()
	s2.fill_rect(Rect2i(0, 0, 8, 8), 1)
	w.add_body(b2, [s2])
	_c("add_body 会 bump bodies_rev", w.bodies_rev > rev0, "%d -> %d" % [rev0, w.bodies_rev])
	var rev1: int = w.bodies_rev
	w.remove_body(b2)
	_c("remove_body 会 bump bodies_rev", w.bodies_rev > rev1, "%d -> %d" % [rev1, w.bodies_rev])

	# ④ 没增删时不许重复对齐（版本号没变就不动）
	var nodes_before: Array = pw._body_nodes.duplicate()
	pw._physics_process(1.0 / 60.0)
	_c("没有增删时不动数组（省掉每帧 O(n)）", pw._body_nodes == nodes_before)

	print("=== %d passed, %d failed ===" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
