extends SceneTree
## 剔除/淘汰必须**两边一起删** —— 回归闸门，专抓「GDScript 删了、Rapier 没删」。
##
## ⚠️ 为什么需要这个测试：
##    `cull_outside` 曾经只做 `bodies.remove_at(i)`，而**只有 `remove_body()` 会向
##    原生发 op 4（body_remove）**。于是 demo 里"切割地面 -> 碎片掉进虚空 ->
##    每 60 帧剔一次"这条路上，Rapier 侧的刚体**一个都没删**：
##    实测（tests/diag_cull_leak.gd）连剔 5 轮 x 100 个之后，GDScript 侧只剩 1 个，
##    **Rapier 侧还有 501 个**。僵尸还在被积分（每个 ~0.34 us/步），
##    而且**不会有任何报错** —— 症状只是"玩久了越来越卡"。
##
##    这类 bug 只有"数一数两边"才抓得到，所以判据就是两个计数必须同步。
const AddonWorld := preload("res://src/nodes/pixel_world.gd")
const AddonBody := preload("res://src/nodes/pixel_body_2d.gd")
const AddonShape := preload("res://src/nodes/pixel_shape_2d.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PBody := preload("res://src/physics/pbody.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

var _pass := 0
var _fail := 0
func _c(n: String, ok: bool, d: String = "") -> void:
	if ok: _pass += 1; print("  PASS  ", n, "  ", d)
	else: _fail += 1; print("  FAIL  ", n, "  ", d)

func _shape(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, w, h), 1)
	return s

## 一个带静态地面的世界 + n 个动态刚体（都在"世界内"，方便对照）。
func _world(n: int, at := Vector2.ZERO) -> Array:
	var w := PWorld.new()
	w.gravity = Vector2.ZERO
	var g := PBody.new()
	g.make_static()
	w.add_body(g, [_shape(400, 20)])
	for i in n:
		var b := PBody.new()
		b.position = at + Vector2(20 + (i % 10) * 20, 20 + (i / 10) * 20)
		w.add_body(b, [_shape(12, 12)])
	w.step(1.0 / 60.0)
	return [w, g]

func _initialize() -> void:
	print("=== 剔除必须两边一起删（GDScript / Rapier）===")

	# ---- 1. cull_outside 必须真的把原生刚体也删掉 ----
	var wb := _world(40, Vector2(2000, 2000))     # 40 个全在远处 -> 会被剔
	var w: PWorld = wb[0]
	var before_gd := w.bodies.size()
	var before_rp: int = w.rp_body_count()
	_c("扩展可用（拿得到原生刚体数）", before_rp > 0, "原生=%d" % before_rp)
	var culled: int = w.cull_outside(Rect2(-100, -100, 400, 400))
	var after_rp: int = w.rp_body_count()
	_c("cull 掉了 40 个动态刚体", culled == 40, "culled=%d" % culled)
	_c("GDScript 侧只剩静态地面", w.bodies.size() == before_gd - 40, "%d -> %d" % [before_gd, w.bodies.size()])
	_c("**Rapier 侧也同步减了 40**（不是泄漏）", after_rp == before_rp - 40,
		"%d -> %d（差 %d）" % [before_rp, after_rp, before_rp - after_rp])

	# ---- 2. 剔除时挂在它上面的关节也要清 ----
	var wb2 := _world(2, Vector2(2000, 2000))
	var w2: PWorld = wb2[0]
	var a: PBody = null
	var b2: PBody = null
	for b in w2.bodies:
		if b.is_static: continue
		if a == null: a = b
		elif b2 == null: b2 = b
	w2.add_weld(a, b2, a.position)
	var rp_before2: int = w2.rp_body_count()
	_c("焊接建好了", w2.joints.size() == 1, "joints=%d" % w2.joints.size())
	w2.cull_outside(Rect2(-100, -100, 400, 400))
	_c("剔除后关节不再悬空（两边都清了）", w2.joints.is_empty(), "joints=%d" % w2.joints.size())
	_c("剔除后原生也只剩静态地面", w2.rp_body_count() == rp_before2 - 2,
		"%d -> %d" % [rp_before2, w2.rp_body_count()])

	# ---- 3. 冻着的 / 静态的**不许**被剔 ----
	var wb3 := _world(4, Vector2(2000, 2000))
	var w3: PWorld = wb3[0]
	var parked: PBody = null
	for b in w3.bodies:
		if not b.is_static: parked = b; break
	w3.freeze(parked)
	var rp_before3: int = w3.rp_body_count()
	var culled3: int = w3.cull_outside(Rect2(-100, -100, 400, 400))
	_c("冻着的没被剔", culled3 == 3 and w3.bodies.has(parked), "culled=%d" % culled3)
	_c("冻着的在原生侧也还在", w3.rp_body_count() == rp_before3 - 3,
		"%d -> %d" % [rp_before3, w3.rp_body_count()])

	# ---- 4. 碎片预算淘汰同样要两边一起删 ----
	var wb4 := _world(20)
	var w4: PWorld = wb4[0]
	w4.max_dynamic_bodies = 5
	for k in 40:
		w4.step(1.0 / 60.0)          # 让它们睡着（预算只淘汰已休眠的）
	var rp_before4: int = w4.rp_body_count()
	var dropped: int = w4.enforce_body_budget()
	_c("预算淘汰了东西", dropped > 0, "dropped=%d" % dropped)
	_c("淘汰后原生也同步减了", w4.rp_body_count() == rp_before4 - dropped,
		"%d -> %d（dropped=%d）" % [rp_before4, w4.rp_body_count(), dropped])

	# ---- 5. 节点层：剔除是绕过节点层的，realign 之后下标必须重新对上 ----
	var pw = AddonWorld.new()
	var g5 = AddonBody.new()
	g5.position = Vector2(0, 220)
	g5.is_static = true
	pw.add_child(g5)
	var gs = AddonShape.new()
	gs.rect_size = Vector2i(200, 40)
	g5.add_child(gs)
	for i in 6:
		var nb = AddonBody.new()
		nb.position = Vector2(3000 + i * 20, 3000)
		nb.is_static = false
		pw.add_child(nb)
		var ns = AddonShape.new()
		ns.rect_size = Vector2i(10, 10)
		nb.add_child(ns)
	get_root().add_child(pw)
	await process_frame
	await process_frame
	pw.rebuild()
	_c("节点层建好了（下标一一对应）", pw._body_nodes.size() == pw.world.bodies.size(),
		"nodes=%d bodies=%d" % [pw._body_nodes.size(), pw.world.bodies.size()])
	var culled5: int = pw.world.cull_outside(Rect2(-100, -100, 400, 400))
	_c("剔掉了远处的节点刚体", culled5 == 6, "culled=%d" % culled5)
	_c("**未 realign 时下标是错位的**（这正是要修的那个静默错配）",
		pw._body_nodes.size() != pw.world.bodies.size(),
		"nodes=%d bodies=%d" % [pw._body_nodes.size(), pw.world.bodies.size()])
	pw.realign_body_nodes()
	var aligned: bool = pw._body_nodes.size() == pw.world.bodies.size()
	for i in pw.world.bodies.size():
		var n = pw._body_nodes[i]
		if n != null and n.body != pw.world.bodies[i]:
			aligned = false
	_c("realign 之后下标重新对上", aligned,
		"nodes=%d bodies=%d" % [pw._body_nodes.size(), pw.world.bodies.size()])

	print("=== %d passed, %d failed ===" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)