extends SceneTree
## **Rapier 实际持有的碰撞体**是否与形状一致 —— 用行为验证，不读 rects。
##
## ⚠️ 之前的 validation_shape_vs_rects 只比了 body.rects（GDScript 侧），
##    而 Rapier 拿到的是**推过去的那一份**。两者可能不同步：
##    渲染对、rects 对、但 Rapier 里还是旧碰撞体 —— 表现就是
##    "碰撞箱和形状不一致"（物体停在看不见的几何上 / 穿过看得见的像素）。
##
## 判据：在地面切一个足够宽的竖缝，往缝里丢一个很小的探针。
##       · 掉下去  -> Rapier 的碰撞体是新的（正确）
##       · 停在缝口 -> Rapier 还持有旧的实心地面（复现了不一致）
const AddonWorld := preload("res://src/nodes/pixel_world.gd")
const AddonBody := preload("res://src/nodes/pixel_body_2d.gd")
const AddonShape := preload("res://src/nodes/pixel_shape_2d.gd")

var _pass := 0
var _fail := 0
func _c(n: String, ok: bool, d: String = "") -> void:
	if ok: _pass += 1; print("  PASS  ", n, "  ", d)
	else: _fail += 1; print("  FAIL  ", n, "  ", d)

func _initialize() -> void:
	print("=== Rapier 碰撞体 vs 形状（行为验证）===")
	var pw = AddonWorld.new()
	var g = AddonBody.new(); g.position = Vector2(0, 220); g.is_static = true
	pw.add_child(g)
	var gs = AddonShape.new(); gs.rect_size = Vector2i(768, 100); g.add_child(gs)
	get_root().add_child(pw)
	await process_frame
	await process_frame
	pw.rebuild()
	var ground = null
	for b in pw.world.bodies:
		if b.is_static: ground = b; break
	print("  地面 rects = %d 个，aabb = %s" % [ground.rects.size(), str(ground.aabb)])

	# 切一条足够宽的竖缝（世界 x=400，从地面之上切到之下）
	pw.world.damage_segment(Vector2(400, 190), Vector2(400, 340), 20.0)
	pw.world.step(1.0 / 60.0)
	print("  切后 rects = %d 个" % ground.rects.size())

	# 往缝里丢一个很小的探针
	var probe = AddonBody.new()
	probe.name = "Probe"
	probe.position = Vector2(400, 150)
	pw.add_child(probe)
	var ps = AddonShape.new(); ps.rect_size = Vector2i(6, 6); probe.add_child(ps)
	pw.add_body_node(probe)

	print("  探针 rapier_id=%d rects=%d shapes=%d aabb=%s" % [
		probe.rapier_id, probe.rects.size(), probe.shapes.size(), str(probe.aabb)])
	var y0: float = probe.position.y
	for i in 180:
		pw.world.step(1.0 / 60.0)
	var y1: float = probe.position.y
	print("  探针 y %.1f -> %.1f（地面顶面 220，底 320）" % [y0, y1])
	_c("探针穿过切口掉下去了（Rapier 碰撞体是新的）", y1 > 320.0, "y=%.1f" % y1)

	print("=== %d passed, %d failed ===" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
