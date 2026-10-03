extends SceneTree
## **只依赖 Rapier 状态**的判据：从切口正中往下打射线。
##
## ⚠️ 之前所有测试都在比 body.rects（GDScript 侧）vs body.shapes，
##    而 Rapier 拿到的是**推过去的那一份**。两者可能不同步 ——
##    渲染对、rects 对，但 Rapier 里还是旧碰撞体。
##    用户报的"碰撞箱和形状不一致"就在这一层，而我一次都没测过。
##
## 判据：地面 y 220..320，在 x=400 切一条 40 像素宽的竖缝。
##      · 射线穿到 y≈320 才命中  -> Rapier 里**有**那条缝（正确）
##      · 射线在 y≈220 就命中    -> Rapier 里还是**实心**地面（不一致）
const AddonWorld := preload("res://src/nodes/pixel_world.gd")
const AddonBody := preload("res://src/nodes/pixel_body_2d.gd")
const AddonShape := preload("res://src/nodes/pixel_shape_2d.gd")
const Query := preload("res://src/physics/query.gd")

var _pass := 0
var _fail := 0
func _c(n: String, ok: bool, d: String = "") -> void:
	if ok: _pass += 1; print("  PASS  ", n, "  ", d)
	else: _fail += 1; print("  FAIL  ", n, "  ", d)

var _pw = null
func _ray_hit_y(x: float) -> float:
	# 从地面之上竖直往下打
	var hit = _pw.world.raycast(Vector2(x, 150), Vector2(0, 1), 400.0)
	if hit == null or not hit.hit:
		return -1.0
	return hit.point.y

func _initialize() -> void:
	print("=== Rapier 碰撞体 vs 形状（射线判据）===")
	_pw = AddonWorld.new()
	var g = AddonBody.new(); g.position = Vector2(0, 220); g.is_static = true
	_pw.add_child(g)
	var gs = AddonShape.new(); gs.rect_size = Vector2i(768, 100); g.add_child(gs)
	get_root().add_child(_pw)
	await process_frame
	await process_frame
	_pw.rebuild()
	Query.attach(_pw.world)          # 射线查询是模块级的，必须先绑定世界
	_pw.world.step(1.0 / 60.0)

	var y_far := _ray_hit_y(100.0)
	_c("实心处射线命中地面顶面（基线）", absf(y_far - 220.0) < 2.0, "y=%.1f" % y_far)

	# 切一条 40 像素宽的竖缝（x=400）
	_pw.world.damage_segment(Vector2(400, 190), Vector2(400, 340), 20.0)
	_pw.world.step(1.0 / 60.0)

	var y_cut := _ray_hit_y(400.0)
	print("  缝中心射线命中 y=%.1f（缝底 320，缝口 220）" % y_cut)
	_c("缝里射线穿过去了（Rapier 有那条缝）", y_cut < 0.0 or y_cut > 300.0, "y=%.1f" % y_cut)

	# 缝外应当仍是实心
	var y_side := _ray_hit_y(300.0)
	_c("缝外仍是实心", absf(y_side - 220.0) < 2.0, "y=%.1f" % y_side)

	print("=== %d passed, %d failed ===" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
