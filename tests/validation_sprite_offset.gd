extends SceneTree
## **sprite 的位置是否与形状像素对齐** —— 专抓"形状和碰撞箱之间的 offset"。
##
## ⚠️ 为什么之前的测试抓不到：
##    validation_tile_consistency 只测了**地面**，而地面的局部 aabb 原点是 (0,0)，
##    恰好是 64 的倍数 —— 那种情况下"块的网格原点"和"区域原点"相等，
##    offset 算错也看不出来。
##
##    碎片才是反例：它们的局部 aabb 起点是任意值。
##
## 判据：对每个块的 sprite，它覆盖的每个**不透明像素**，
##      映射回局部坐标后，形状在那里**必须有像素**（反之亦然）。
##      offset 错了的话，sprite 会整体盖到一片空白上 -> 立刻失败。
const AddonWorld := preload("res://src/nodes/pixel_world.gd")
const AddonBody := preload("res://src/nodes/pixel_body_2d.gd")
const AddonShape := preload("res://src/nodes/pixel_shape_2d.gd")

var _pass := 0
var _fail := 0
func _c(n: String, ok: bool, d: String = "") -> void:
	if ok: _pass += 1; print("  PASS  ", n, "  ", d)
	else: _fail += 1; print("  FAIL  ", n, "  ", d)

var _pw = null

## 检查一个刚体的所有块 sprite 是否与它的形状像素对齐。
func _check_body(b) -> int:
	var r = _pw.renderer
	var tiles: Dictionary = r._tiles.get(b.id, {})
	var tis: Dictionary = r._tile_img.get(b.id, {})
	var bad := 0
	for key in tiles.keys():
		var sp: Sprite2D = tiles[key]
		var img: Image = tis.get(key)
		if sp == null or img == null:
			continue
		var ox := int(sp.offset.x)
		var oy := int(sp.offset.y)
		for ly in img.get_height():
			for lx in img.get_width():
				var drawn: bool = img.get_pixel(lx, ly).a > 0.5
				var has := false
				for s in b.shapes:
					if s.get_pixel(ox + lx, oy + ly) != 0:
						has = true
						break
				if drawn != has:
					bad += 1
	return bad

func _initialize() -> void:
	print("=== sprite 偏移 vs 形状像素 ===")
	_pw = AddonWorld.new()
	var g = AddonBody.new(); g.position = Vector2(0, 220); g.is_static = true
	_pw.add_child(g)
	var gs = AddonShape.new(); gs.rect_size = Vector2i(768, 100); g.add_child(gs)
	get_root().add_child(_pw)
	await process_frame
	await process_frame
	_pw.rebuild()
	_pw.world.step(1.0 / 60.0)

	# 切一刀制造碎片 —— 碎片的局部 aabb 原点不是 64 的倍数
	_pw.world.damage_segment(Vector2(400, 190), Vector2(400, 340), 20.0)
	_pw.world.step(1.0 / 60.0)
	for b in _pw.world.bodies:
		_pw.renderer.sync(b)

	var nbody := 0
	var total_bad := 0
	var frag := 0
	for b in _pw.world.bodies:
		nbody += 1
		var bad := _check_body(b)
		if bad > 0:
			frag += 1
		total_bad += bad
	_c("%d 个刚体的块 sprite 全部与形状对齐" % nbody, total_bad == 0,
		"不对齐 %d 像素（涉及 %d 个刚体）" % [total_bad, frag])

	# 专门确认碎片存在（否则这个测试没测到关键路径）
	var nfrag := 0
	for b in _pw.world.bodies:
		if not b.is_static:
			nfrag += 1
	_c("确实产生了碎片（测到了非 64 对齐的 aabb）", nfrag > 0, "%d 个碎片" % nfrag)

	print("=== %d passed, %d failed ===" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
