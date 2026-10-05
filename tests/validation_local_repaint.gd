extends SceneTree
## **局部贴图更新**的闸门（表 ①）。
##
## 守两件事：
##   1. 破坏的**内部**小掩码之后，渲染器只重建**脏块**（不是整张）——
##      判据是 renderer.last_tiles_rebuilt / last_tiles_total 与 last_debug 里的 untracked；
##   2. **不能少画**：每个块贴图的每个像素，与"这个块覆盖的局部区域里形状有没有像素"
##      逐像素一致（两个方向都要对）—— 脏矩形给小了就会在这里炸。
##
## ⚠️ 为什么两个都要：只查"重建了几块"的话，把脏矩形给**过大**能通过（那只是慢），
##    给**过小**才是真 bug（画面缺一块，而且**不报错**）。反过来只查像素的话，
##    全量重建也能通过 —— 那就测不到 ① 的收益了。
##
## ⚠️ 判据不依赖引擎自己的说法：块数来自渲染器的计数器（那是它的账），
##    像素对齐是**独立算的**（形状里有没有像素 vs 贴图画没画）。
const PixelWorld := preload("res://src/nodes/pixel_world.gd")
const PixelBody2D := preload("res://src/nodes/pixel_body_2d.gd")
const PixelShape2D := preload("res://src/nodes/pixel_shape_2d.gd")
const Destruction := preload("res://src/core/destruction.gd")

var _pass := 0
var _fail := 0
func _c(n: String, ok: bool, d: String = "") -> void:
	if ok:
		_pass += 1
		print("  PASS  ", n, "  ", d)
	else:
		_fail += 1
		print("  FAIL  ", n, "  ", d)


## 逐像素核对一个刚体的所有块贴图与形状是否一致（两个方向都查）。
func _pixel_mismatch(pw, b) -> int:
	var r = pw.renderer
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


func _sync_and_report(pw, b, label: String) -> Array:
	var r = pw.renderer
	var t0 := Time.get_ticks_usec()
	r.sync(b)
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	print("  %s：sync %.2f ms | 重建 %d/%d 块 | %s" % [
		label, ms, r.last_tiles_rebuilt, r.last_tiles_total, r.last_debug])
	return [r.last_tiles_rebuilt, r.last_tiles_total, r.last_debug]


## 造一个干净的世界 + 768x100 底板（12x2 = 24 块），并把它 sync 满。
## ⚠️ 每个原语都要**全新的世界**：前一个原语留下的洞会进 touches_boundary 的探测框，
##    于是下一个原语可能被误判成"贴边界"（走 split 那条路，形状被换掉 -> 必然全量重建）。
##    我第一版就是共用一个底板，detach 那条因此拿到 24/24 的假结果。
func _fresh() -> Array:
	var pw := PixelWorld.new()
	var ground := PixelBody2D.new()
	ground.position = Vector2(0, 200)
	ground.is_static = true
	pw.add_child(ground)
	var gs := PixelShape2D.new()
	gs.rect_size = Vector2i(768, 100)
	ground.add_child(gs)
	get_root().add_child(pw)
	await process_frame
	await process_frame
	pw.rebuild()
	pw.renderer.sync(ground.body)
	print("  底板 %dx%d：%d 块" % [768, 100, pw.renderer.last_tiles_total])
	return [pw, ground.body]


func _initialize() -> void:
	print("=== 局部贴图更新（表 ①）===")
	var fw := await _fresh()
	var pw = fw[0]
	var w = pw.world
	var gb = fw[1]

	# ---- ① fracture_pixels：内部 20x20（不动边界） ----
	var mask := {}
	for y in range(40, 60):
		for x in range(370, 390):
			mask[Vector2i(x, y)] = true
	w.fracture_pixels(gb, {gb.shapes[0]: mask})
	var a := _sync_and_report(pw, gb, "fracture_pixels 内部 20x20")
	_c("fracture_pixels：只重建脏块（<= 2）", a[0] <= 2, "%d/%d" % [a[0], a[1]])
	_c("fracture_pixels：untracked=false（脏集合是完整的）", String(a[2]).contains("untracked=false"), a[2])
	_c("fracture_pixels：贴图与形状逐像素一致", _pixel_mismatch(pw, gb) == 0,
		"不一致 %d 像素" % _pixel_mismatch(pw, gb))

	# ---- ② fracture：内部 20x20（**新世界**） ----
	var f2 := await _fresh()
	pw = f2[0]
	w = pw.world
	gb = f2[1]
	w.fracture(gb, Destruction.Damage.rect(Vector2(500, 50), Vector2(10, 10)))
	var b := _sync_and_report(pw, gb, "fracture 内部 20x20")
	_c("fracture：只重建脏块（<= 2）", b[0] <= 2, "%d/%d" % [b[0], b[1]])
	_c("fracture：贴图与形状逐像素一致", _pixel_mismatch(pw, gb) == 0,
		"不一致 %d 像素" % _pixel_mismatch(pw, gb))

	# ---- ③ detach：内部 20x20（**新世界**，走非边界分支） ----
	var f3 := await _fresh()
	pw = f3[0]
	w = pw.world
	gb = f3[1]
	w.detach(gb, Destruction.Damage.rect(Vector2(600, 50), Vector2(10, 10)))
	var c := _sync_and_report(pw, gb, "detach 内部 20x20")
	_c("detach：只重建脏块（<= 2）", c[0] <= 2, "%d/%d" % [c[0], c[1]])
	_c("detach：untracked=false", String(c[2]).contains("untracked=false"), c[2])
	_c("detach：贴图与形状逐像素一致", _pixel_mismatch(pw, gb) == 0,
		"不一致 %d 像素" % _pixel_mismatch(pw, gb))

	# ---- ④ 对照：**跨到边界**的一笔（新世界） ----
	var f4 := await _fresh()
	pw = f4[0]
	w = pw.world
	gb = f4[1]
	w.fracture(gb, Destruction.Damage.rect(Vector2(10, 10), Vector2(6, 6)))
	var d := _sync_and_report(pw, gb, "fracture 贴边界（对照）")
	_c("对照：贴边界的破坏仍然逐像素一致", _pixel_mismatch(pw, gb) == 0,
		"不一致 %d 像素" % _pixel_mismatch(pw, gb))

	print("---")
	if _fail == 0:
		print("全部通过：%d 项断言" % _pass)
	else:
		print("失败 %d / %d 项" % [_fail, _pass + _fail])
	quit(0 if _fail == 0 else 1)