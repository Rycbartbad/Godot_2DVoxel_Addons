extends SceneTree
## **贴图与形状是否一致** —— 回归测试，专抓「擦出来的图形缺一块」。
##
## ⚠️ 为什么需要这个测试：
##    分块增量重绘只重建**脏块**。只要脏信息不完整（例如 PBody.rebuild 调的
##    touch() 不记录改了哪块），就会有块留在旧状态 —— 画面上表现为
##    「缺一块」或「多一块」，而**其他任何测试都发现不了**：
##    物理是对的、形状数据是对的，只有贴图是旧的。
##
##    判据：每一块的缓存贴图，必须与"从当前形状重新生成"的图**逐像素相同**。
const AddonWorld := preload("res://src/nodes/pixel_world.gd")
const AddonBody := preload("res://src/nodes/pixel_body_2d.gd")
const AddonShape := preload("res://src/nodes/pixel_shape_2d.gd")
const Editor := preload("res://src/core/pixel_editor.gd")

var _pass := 0
var _fail := 0
func _c(n: String, ok: bool, d: String = "") -> void:
	if ok: _pass += 1; print("  PASS  ", n, "  ", d)
	else: _fail += 1; print("  FAIL  ", n, "  ", d)

var _pw = null
var _ground = null

## 逐块比对：缓存的贴图 vs 从当前形状重新生成。
func _check_tiles(label: String) -> void:
	var r = _pw.renderer
	var aabb: Rect2i = r._bounds.get(_ground.id, Rect2i())
	var tis: Dictionary = r._tile_img.get(_ground.id, {})
	var bad := 0
	var checked := 0
	for key in tis.keys():
		var k: Vector2i = key
		var rx := maxi(k.x << 6, aabb.position.x)
		var ry := maxi(k.y << 6, aabb.position.y)
		var rx2 := mini((k.x << 6) + 64, aabb.position.x + aabb.size.x)
		var ry2 := mini((k.y << 6) + 64, aabb.position.y + aabb.size.y)
		if rx2 <= rx or ry2 <= ry:
			continue
		var tr := Rect2i(rx - aabb.position.x, ry - aabb.position.y, rx2 - rx, ry2 - ry)
		var want: Image = r._build_region_image(_ground.shapes, aabb, tr)
		var got: Image = tis[key]
		checked += 1
		if got.get_width() != want.get_width() or got.get_height() != want.get_height():
			bad += 1
			continue
		for y in want.get_height():
			for x in want.get_width():
				if got.get_pixel(x, y) != want.get_pixel(x, y):
					bad += 1
					break
			if bad > 0:
				break
	var name := "%s：%d 块全部与形状一致" % [label, checked]
	var detail := "不一致 %d 块" % bad
	_c(name, bad == 0, detail)

func _initialize() -> void:
	print("=== 贴图与形状一致性（抓「缺一块」）===")
	_pw = AddonWorld.new()
	var g = AddonBody.new(); g.position = Vector2(0, 220); g.is_static = true
	_pw.add_child(g)
	var gs = AddonShape.new(); gs.rect_size = Vector2i(768, 100); g.add_child(gs)
	get_root().add_child(_pw)
	await process_frame
	await process_frame
	_pw.rebuild()
	for b in _pw.world.bodies:
		if b.is_static: _ground = b; break
	_pw.renderer.sync(_ground)
	_check_tiles("初始")

	# 内部擦（局部 y=50，世界 y=270）
	for i in 3:
		Editor.erase(_pw.world, Vector2(100.0 + i * 150.0, 270.0), Vector2(100.0 + i * 150.0, 271.0), 8.0, 25.0)
		_pw.renderer.sync(_ground)
	_check_tiles("内部擦 3 笔")

	# 边缘擦（会改 AABB）
	Editor.erase(_pw.world, Vector2(300, 222), Vector2(300, 223), 8.0, 25.0)
	_pw.renderer.sync(_ground)
	_check_tiles("边缘擦")

	# 连续快速擦（一帧内多笔，脏集合会合并成一个包围盒）
	for i in 5:
		Editor.erase(_pw.world, Vector2(500.0 + i * 20.0, 260.0), Vector2(500.0 + i * 20.0, 261.0), 8.0, 25.0)
	_pw.renderer.sync(_ground)
	_check_tiles("一帧内 5 笔")

	print("=== %d passed, %d failed ===" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
