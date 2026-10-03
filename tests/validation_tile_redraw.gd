extends SceneTree
## 分块增量重绘的**正确性**验证 —— 这是重点。
##
## "少画"是静默故障：右键擦掉了像素，画面上却还在。
## 所以这里不看计时，只看**贴图里那块像素到底有没有变**。
const AddonWorld := preload("res://src/nodes/pixel_world.gd")
const AddonBody := preload("res://src/nodes/pixel_body_2d.gd")
const AddonShape := preload("res://src/nodes/pixel_shape_2d.gd")
const Editor := preload("res://src/core/pixel_editor.gd")

var _pass := 0
var _fail := 0
func _c(n: String, ok: bool, d: String = "") -> void:
	if ok: _pass += 1; print("  PASS  ", n, "  ", d)
	else: _fail += 1; print("  FAIL  ", n, "  ", d)

func _initialize() -> void:
	print("=== 分块增量重绘：正确性 ===")
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

	pw.renderer.sync(ground)
	var img: Image = pw.renderer._images.get(ground.id)
	_c("贴图建出来了", img != null, "%dx%d" % [img.get_width(), img.get_height()] if img else "-")
	if img == null: print("=== 0 passed, 1 failed ==="); quit(1); return

	# 擦一个洞：世界坐标 (200, 250)，地面局部就是同一坐标（地面在 0,220）
	var probe_world := Vector2(200, 250)
	var lx: int = int(probe_world.x) - ground.aabb.position.x
	var ly: int = int(probe_world.y) - ground.aabb.position.y
	_c("擦之前该点是实心", img.get_pixel(lx, ly).a > 0.5,
		"alpha=%.2f" % img.get_pixel(lx, ly).a)

	Editor.erase(pw.world, probe_world, probe_world + Vector2(0, 1), 8.0, 25.0)
	pw.renderer.sync(ground)

	var img2: Image = pw.renderer._images.get(ground.id)
	_c("擦之后该点透明了", img2.get_pixel(lx, ly).a < 0.5,
		"alpha=%.2f" % img2.get_pixel(lx, ly).a)
	# 洞外必须**还是实心** —— 分块重绘最容易在这里出错（blit 位置算错）
	var far_x: int = 600 - ground.aabb.position.x
	var far_y: int = 250 - ground.aabb.position.y
	_c("洞外仍然是实心（blit 位置没算错）", img2.get_pixel(far_x, far_y).a > 0.5,
		"alpha=%.2f" % img2.get_pixel(far_x, far_y).a)

	# 再来一笔，验证**连续**分块重绘也对
	var p2: Vector2 = Vector2(400, 240)
	Editor.erase(pw.world, p2, p2 + Vector2(0, 1), 8.0, 25.0)
	pw.renderer.sync(ground)
	var img3: Image = pw.renderer._images.get(ground.id)
	_c("第二笔也画出来了", img3.get_pixel(int(p2.x) - ground.aabb.position.x, int(p2.y) - ground.aabb.position.y).a < 0.5)
	_c("第一笔的洞还在", img3.get_pixel(lx, ly).a < 0.5)
	_c("别处仍然实心", img3.get_pixel(far_x, far_y).a > 0.5)

	print("=== %d passed, %d failed ===" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
