extends SceneTree
## 验证"在编辑器里拖动 PixelBody2D"的机制：
##   改 position -> NOTIFICATION_TRANSFORM_CHANGED -> PixelWorld 重烘焙 -> 刚体跟着走
##
## 拖动本身是 Godot 内置的（Node2D + 移动模式），这里验的是**我们的响应链**。
const PixelBody2D := preload("res://src/nodes/pixel_body_2d.gd")
const PixelWorld := preload("res://src/nodes/pixel_world.gd")
const PixelShape2D := preload("res://src/nodes/pixel_shape_2d.gd")
const PixelJoint2D := preload("res://src/nodes/pixel_joint_2d.gd")
const DebugOverlay := preload("res://src/render/debug_overlay.gd")

var _pass := 0
var _fail := 0
func _c(n: String, ok: bool, d: String = "") -> void:
	if ok:
		_pass += 1
		print("  PASS  ", n, "  ", d)
	else:
		_fail += 1
		print("  FAIL  ", n, "  ", d)

func _initialize() -> void:
	var pw := PixelWorld.new()
	root.add_child(pw)
	var a := PixelBody2D.new()
	a.name = "A"
	a.position = Vector2(10, 20)
	a.rect_size = Vector2i(16, 16)
	pw.add_child(a)
	var b := PixelBody2D.new()
	b.name = "B"
	b.position = Vector2(100, 0)
	b.rect_size = Vector2i(8, 8)
	b.is_static = true
	pw.add_child(b)

	if pw.world == null:
		pw.rebuild()
	_c("烘焙出 2 个刚体", pw.world.bodies.size() == 2, "%d" % pw.world.bodies.size())
	_c("位置来自节点 position", pw.world.bodies[0].position.is_equal_approx(Vector2(10, 20)),
		str(pw.world.bodies[0].position))
	_c("静态标记传下去了", pw.world.bodies[1].is_static)

	# ---- 拖动的两条契约 ----
	print("=== 拖动契约 ===")
	# ⚠️ 先钉住"通知真的开着"。只手动发 notification() 能骗过测试，
	#    但骗不过编辑器 —— 拖动时形状不跟着走就是这么来的。
	_c("transform 通知已开启（否则拖动不会触发重烘焙）",
		a.is_transform_notification_enabled())
	var old_id: int = pw.world.bodies[0].id
	var first_body = pw.world.bodies[0]
	a.position = Vector2(200, 60)
	# ⚠️ 这个常量定义在 Node2D 上，不在 Node 上
	a.notification(Node2D.NOTIFICATION_TRANSFORM_CHANGED)
	await process_frame
	await process_frame
	# 契约 1：**运行时**不该因为 transform 变化就重建世界 ——
	#         那时位置归物理管，重建会把模拟结果抹掉。
	_c("运行时不受 transform 通知影响（守卫 Engine.is_editor_hint）",
		pw.world.bodies[0].id == old_id, "id 保持 %d" % old_id)

	# 契约 2：显式 rebuild 之后，刚体跟到节点的新位置。
	#         （编辑器里由 on_child_moved 自动触发这条；运行时不该自动走。）
	pw.rebuild()
	_c("rebuild 后刚体跟到新位置",
		pw.world.bodies[0].position.is_equal_approx(Vector2(200, 60)),
		str(pw.world.bodies[0].position))
	# ⚠️ 不要断言"id 变了"：PWorld 的 id 是**每个世界独立计数**的，
	#    新建世界会给出同样的 id。要断言的是**刚体对象换了**。
	#    （渲染器仍然必须 prune({}) 清空 —— 因为它是按 id 索引贴图的，
	#      id 复用意味着旧贴图会被新贴图覆盖而不是留下幽灵，但依赖这一点太脆弱。）
	_c("重烘焙换了新的刚体对象", pw.world.bodies[0] != first_body,
		"id %d（每世界独立计数，会复用）" % pw.world.bodies[0].id)
	_c("刚体数不变", pw.world.bodies.size() == 2, "%d" % pw.world.bodies.size())

	# ---- 吸附：位置应当能被对齐到整数 ----
	print("=== 吸附开关 ===")
	_c("默认开启像素吸附", a.snap_to_pixel)

	# ---- 三种形状来源都能烘焙 ----
	print("=== 形状来源 ===")
	var c := PixelBody2D.new()
	c.source = PixelBody2D.Source.CIRCLE
	c.radius = 6.0
	var sc := c.build_shape()
	_c("CIRCLE 造出形状", not sc.is_empty(), "%d 像素" % sc.pixel_count())
	var d := PixelBody2D.new()
	d.source = PixelBody2D.Source.TEXTURE
	d.texture = null
	var sd := d.build_shape()
	_c("TEXTURE 没设贴图时是空形状（不崩）", sd.is_empty())

	# ---- 抓手必须和**形状子节点**对齐 ----
	#
	# ⚠️ 这里曾经用 get_shape()（刚体**自身**的内置形状）算抓手，而物理用的是
	#    collect_shapes()（**形状子节点优先**）—— 于是每个挂了形状子节点的刚体
	#    都按内置 rect_size 的默认值 16x16 画框，和真实形状完全对不上。
	#    场景里的症状就是"蓝框/绿框没和形状对齐"（地面 768x100、墙 120x90、
	#    桥板 31x6 全显示成小方块）。
	print("=== 抓手对齐 ===")
	var e := PixelBody2D.new()
	e.name = "E"
	e.position = Vector2(300, 50)
	e.rect_size = Vector2i(16, 16)      # 自身内置形状：故意和子节点不同
	pw.add_child(e)
	var se := PixelShape2D.new()
	se.name = "Shape"
	se.rect_size = Vector2i(31, 6)
	e.add_child(se)
	_c("抓手用形状子节点的外接（不是自身的 16x16）",
		e._gizmo_aabb() == Rect2i(0, 0, 31, 6), str(e._gizmo_aabb()))
	# 子节点改尺寸 -> 父刚体的抓手缓存必须跟着失效
	# （否则编辑器里"精灵已经是新尺寸、框还是旧的"，又是一次静默分叉）
	se.rect_size = Vector2i(20, 9)
	_c("子节点改尺寸后抓手跟着变", e._gizmo_aabb() == Rect2i(0, 0, 20, 9), str(e._gizmo_aabb()))
	pw.rebuild()
	var eb = pw.world.bodies[pw.world.bodies.size() - 1]
	var phys := Rect2i()
	var first := true
	for r: Rect2 in eb.rects:
		var ri := Rect2i(Vector2i(floori(r.position.x), floori(r.position.y)),
			Vector2i(ceili(r.size.x), ceili(r.size.y)))
		phys = ri if first else phys.merge(ri)
		first = false
	_c("抓手 == 物理矩形的并集", e._gizmo_aabb() == phys,
		"抓手=%s 物理=%s" % [str(e._gizmo_aabb()), str(phys)])

	# ---- 场景文件里不能有 `= null` ----
	#
	# ⚠️ **编辑器在"脚本新增导出属性"之后重存场景**时，节点实例上还没有这个属性，
	#    get() 拿到 null，于是把 `contacts_enabled = null` 这类行写进场景文件。
	#    症状是**只在运行时炸**：
	#      Invalid assignment of property or key 'contacts_enabled' with value of type 'Nil'
	#    而且烘焙中断、关节全丢。这条断言把"场景文件里不许出现 = null"钉住。
	print("=== 场景文件卫生 ===")
	var f := FileAccess.open("res://scenes/demo.tscn", FileAccess.READ)
	var bad := PackedStringArray()
	if f != null:
		while not f.eof_reached():
			var ln := f.get_line().strip_edges()
			if ln.ends_with("= null"):
				bad.append(ln)
		f.close()
	_c("demo.tscn 里没有 `= null`（编辑器重存的残留）", bad.is_empty(),
		"%d 行: %s" % [bad.size(), ", ".join(bad).substr(0, 80)])

	# ---- 约束的调试画法只在 DebugOverlay 里出现 ----
	#
	# ⚠️ 甲方要求："所有的约束只在 debugoverlay 中可见，游戏中不可见"。
	#    关节节点自己画锚点连线（不画的话编辑器里"有约束/没约束"看起来一样），
	#    所以必须在**运行时**按 DebugOverlay 的可见性把关，否则游戏画面里会挂着
	#    一堆调试线。编辑器里则始终画（Engine.is_editor_hint()）。
	print("=== 约束画法的可见性 ===")
	var jw := PixelWorld.new()
	root.add_child(jw)
	var ov := DebugOverlay.new()
	ov.name = "DebugOverlay"
	ov.visible = false
	var jn := PixelJoint2D.new()
	jn.name = "J"
	jn.body_b = NodePath("../A")
	jw.add_child(ov)
	jw.add_child(jn)
	_c("DebugOverlay 关着 -> 约束不画", not jn.debug_visible_now())
	ov.visible = true
	_c("DebugOverlay 打开 -> 约束画", jn.debug_visible_now())
	var lone := PixelJoint2D.new()
	root.add_child(lone)
	_c("没有 DebugOverlay（纯代码建）-> 不画", not lone.debug_visible_now())
	lone.free()

	# ---- 删除刚体节点：编辑器里删掉就该从世界摘掉 ----
	#
	# ⚠️ 这里曾经是空的：PixelWorld 早就有增量的 add_body_node()/remove_body_node()，
	#    但**没人调**（只有测试调）。症状：编辑器里删掉一个刚体节点，它的像素和碰撞
	#    还留在世界里继续挡路、继续画，直到下一次 rebuild() 才消失 ——
	#    而 rebuild() 会丢掉所有破坏状态，所以不能拿它兜底。
	print("=== 删除刚体节点 ===")
	var dn := PixelBody2D.new()
	dn.name = "DN"
	dn.position = Vector2(400, 40)
	dn.rect_size = Vector2i(8, 8)
	pw.add_child(dn)
	var dn_body = pw.add_body_node(dn)
	_c("add_body_node 把刚体加进世界", dn_body != null and pw.world.bodies.has(dn_body))
	var cnt: int = pw.world.bodies.size()
	_c("detach_from_world 摘掉刚体", dn.detach_from_world())
	_c("世界少了一个刚体", pw.world.bodies.size() == cnt - 1, "%d -> %d" % [cnt, pw.world.bodies.size()])
	_c("_body_nodes 与 bodies 仍然一一对应", pw._body_nodes.size() == pw.world.bodies.size(),
		"%d vs %d" % [pw._body_nodes.size(), pw.world.bodies.size()])
	# 运行时 free 节点**不**隐式摘刚体：那是玩法的事（回收碎块走 world.remove_body）。
	var rn := PixelBody2D.new()
	rn.position = Vector2(420, 40)
	rn.rect_size = Vector2i(8, 8)
	pw.add_child(rn)
	pw.add_body_node(rn)
	var cnt2: int = pw.world.bodies.size()
	rn.free()
	_c("运行时 free 节点不隐式摘刚体", pw.world.bodies.size() == cnt2,
		"bodies=%d（应当仍是 %d）" % [pw.world.bodies.size(), cnt2])

	# ---- 拖动关节节点：锚点跟着走（增量重烘焙）----
	#
	# ⚠️ 关节节点原来只 queue_redraw()，但**烘焙过之后画的是物理锚点**
	#    （anchor_a_world() 优先返回 joint.anchor_a_world()）—— 那个锚点是上次 bake() 的
	#    位置，于是编辑器里拖关节线不跟手、物理锚点也停在原地，直到下一次 rebuild()。
	print("=== 拖动关节节点 ===")
	var jdb := PixelBody2D.new()
	jdb.name = "JBN"
	jdb.position = Vector2(300, 50)
	jdb.rect_size = Vector2i(8, 8)
	pw.add_child(jdb)
	var jdrag := PixelJoint2D.new()
	jdrag.name = "JN"
	jdrag.position = Vector2(310, 60)
	jdrag.body_b = NodePath("../JBN")
	pw.add_child(jdrag)
	pw.rebuild()
	_c("关节烘焙出来了", jdrag.joint != null)
	_c("烘焙后锚点 = 节点位置", jdrag.anchor_a_world().is_equal_approx(Vector2(310, 60)),
		str(jdrag.anchor_a_world()))
	var n_joints: int = pw.world.joints.size()
	jdrag.position = Vector2(350, 80)                 # 编辑器里拖动
	_c("rebake_joint 成功", pw.rebake_joint(jdrag))
	_c("锚点跟到新位置", jdrag.anchor_a_world().is_equal_approx(Vector2(350, 80)),
		str(jdrag.anchor_a_world()))
	_c("关节数不变（旧的摘掉、新的建上）", pw.world.joints.size() == n_joints,
		"%d vs %d" % [pw.world.joints.size(), n_joints])

	print("=== %d passed, %d failed ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
