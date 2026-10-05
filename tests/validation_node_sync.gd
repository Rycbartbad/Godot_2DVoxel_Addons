extends SceneTree
## 交付3 的闸门：破坏之后节点层与 world 的对齐。
##   ① 碎片用 null 占位，下标不串位（全删 + 多碎片都要对）
##   ② 原体完全删除后不留悬空节点引用
##   ③ 静态 Ground 被破坏后**画面与碰撞一致**（渲染器确实同步了它）
##   ④ 关节：锚点被删的关节被清掉；锚在静态世界（body_a=null）的**保留**
##
## ⚠️ 用鸭子类型 stub 代替真 PixelBody2D：真节点进树会触发 _ready -> rebuild()，
##    那条路在 headless 下会中止（本项目的老陷阱）。对齐逻辑只用到 node.body，
##    所以 stub 足够。
const PixelWorld := preload("res://src/nodes/pixel_world.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PBody := preload("res://src/physics/pbody.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")
const PixelRenderer := preload("res://src/render/pixel_renderer.gd")
const Joint := preload("res://src/physics/joint.gd")

class StubNode extends RefCounted:
	var body = null

var passed := 0
var failed := 0

func _assert(cond: bool, msg: String) -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		print("  [失败] " + msg)


func _shape(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, w, h), 1)
	return s


func _initialize() -> void:
	print("=== 交付3：破坏后的节点层对齐 ===")
	var pw = PixelWorld.new()
	pw.world = PWorld.new()
	pw.auto_render = false
	var rend := PixelRenderer.new()
	get_root().add_child(rend)
	pw.renderer = rend
	var w = pw.world

	# 静态 Ground + 两个动态体，并给它们配 stub 节点（按下标一一对应）
	var ground := PBody.new()
	ground.position = Vector2(0, 200)
	ground.make_static()
	w.add_body(ground, [_shape(200, 20)], Callable(), true)
	var b1 := PBody.new()
	b1.position = Vector2(-40, 100)
	w.add_body(b1, [_shape(40, 40)], Callable(), true)
	var b2 := PBody.new()
	b2.position = Vector2(40, 100)
	w.add_body(b2, [_shape(40, 40)], Callable(), true)
	var s1 := StubNode.new()
	s1.body = ground
	var s2 := StubNode.new()
	s2.body = b1
	var s3 := StubNode.new()
	s3.body = b2
	pw._body_nodes = [s1, s2, s3]
	print("初始：刚体 %d，节点项 %d" % [w.bodies.size(), pw._body_nodes.size()])

	# 关节：j_valid 锚在静态世界（body_a=null），j_bad 锚在 b2 上
	var j_valid = Joint.new()
	j_valid.body_a = null
	j_valid.body_b = b1
	w.joints.append(j_valid)
	var j_bad = Joint.new()
	j_bad.body_a = b2
	j_bad.body_b = null
	w.joints.append(j_bad)

	# ① 在 b1 上删掉一半（跨 chunk 不规则掩码）-> 产生碎片
	# ⚠️ 删**中间一条**（会断开 -> 产生 1 个碎片），而不是删半边（半边不断 -> 0 碎片，
	#    那样就测不到 null 占位那条路径了 —— 我第一版就是删半边）。
	var mask := {}
	for y in range(0, 40):
		for x in range(18, 22):
			mask[Vector2i(x, y)] = true
	var res: Dictionary = pw.fracture_pixels_and_sync(b1, {b1.shapes[0]: mask})
	print("① b1 删一半：removed=%d，fragments=%d，刚体 %d，节点项 %d" % [
		res["removed"], (res["fragments"] as Array).size(), w.bodies.size(), pw._body_nodes.size()])
	_assert(pw._body_nodes.size() == w.bodies.size(), "节点项应与刚体数相等（%d vs %d）" % [
		pw._body_nodes.size(), w.bodies.size()])
	var i1: int = w.bodies.find(b1)
	_assert(i1 >= 0 and pw._body_nodes[i1] == s2, "b1 的节点应还在它自己的下标上（不串位）")
	var i_g: int = w.bodies.find(ground)
	_assert(i_g >= 0 and pw._body_nodes[i_g] == s1, "Ground 的节点应还在它自己的下标上")
	var nulls := 0
	for n in pw._body_nodes:
		if n == null:
			nulls += 1
	print("   碎片用 null 占位的数量 = %d（应等于碎片数）" % nulls)
	_assert(nulls >= (res["fragments"] as Array).size(), "碎片应有 null 占位（%d < %d）" % [
		nulls, (res["fragments"] as Array).size()])

	# ② 把 b2 全部删光 -> 不留悬空引用
	var mask2 := {}
	var s2shape: PixelShape = b2.shapes[0]
	for y in range(0, 40):
		for x in range(0, 40):
			mask2[Vector2i(x, y)] = true
	var res2: Dictionary = pw.fracture_pixels_and_sync(b2, {s2shape: mask2})
	print("② b2 全删：removed=%d，body_alive=%s，刚体 %d，节点项 %d" % [
		res2["removed"], str(res2["body_alive"]), w.bodies.size(), pw._body_nodes.size()])
	_assert(not res2["body_alive"], "全删后 body_alive 应为 false")
	_assert(not pw._body_nodes.has(s3), "被全删的刚体不该留下节点引用（悬空）")
	_assert(pw._body_nodes.size() == w.bodies.size(), "全删后节点项仍应与刚体数相等")

	# ③ 静态 Ground 被破坏后渲染器要同步它（画面与碰撞一致）
	var gmask := {}
	for x in range(0, 10):
		gmask[Vector2i(x, 0)] = true
	pw.fracture_pixels_and_sync(ground, {ground.shapes[0]: gmask})
	var synced: bool = rend._nodes.has(ground.id)
	print("③ 静态 Ground 被破坏后，渲染器里有它的块 = %s" % str(synced))
	_assert(synced, "静态 Ground 破坏后必须同步渲染器（否则画面与碰撞不一致）")

	# ④ 关节
	print("④ 关节数 = %d（j_bad 的锚点 b2 已被删，应只剩 j_valid）" % w.joints.size())
	_assert(not w.joints.has(j_bad), "锚点被删的关节必须清掉（不留悬空引用）")
	_assert(w.joints.has(j_valid), "锚在静态世界（body_a=null）的关节必须保留")

	print("---")
	if failed == 0:
		print("全部通过：%d 项断言" % passed)
	else:
		print("失败 %d / %d 项" % [failed, passed + failed])
	quit(0 if failed == 0 else 1)
