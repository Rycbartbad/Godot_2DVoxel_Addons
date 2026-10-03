extends SceneTree
## 每块独立贴图：**正确性** + 性能。
##
## "少画"是静默故障（擦掉了画面上却还在），所以这里逐像素读回验证。
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
## ⚠️ 传的是**体局部**像素坐标（= 世界坐标 - body.position）。
##    渲染器的块格是按 _local_bounds() 分的，那是**局部**外接盒 ——
##    我第一版把世界坐标当局部坐标用，于是键全 miss、读回全 null，
##    而断言还"假通过"（null 返回 -1，-1 < 0.5 成立）。
func _alpha(local_x: int, local_y: int) -> float:
	var img: Image = _pw.renderer.tile_image_at(_ground.id, local_x, local_y)
	if img == null: return -1.0
	return img.get_pixel(local_x & 63, local_y & 63).a

func _initialize() -> void:
	print("=== 每块独立贴图：正确性 ===")
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
	var ntiles: int = (_pw.renderer._tiles.get(_ground.id, {}) as Dictionary).size()
	_c("块建出来了", ntiles > 0, "%d 块" % ntiles)
	# 地面在 (0,220)，所以世界 (x, y) -> 局部 (x, y-220)
	_c("擦之前实心", _alpha(200, 30) > 0.5, "alpha=%.2f" % _alpha(200, 30))

	Editor.erase(_pw.world, Vector2(200, 250), Vector2(200, 251), 8.0, 25.0)
	_pw.renderer.sync(_ground)
	# ⚠️ 先要求 alpha >= 0：读不到块时返回 -1，而 -1 < 0.5 成立 ——
	#    不加这一条，断言会**假通过**（"擦之后透明了"其实是根本没读到）。
	_c("读得到块", _alpha(200, 30) >= 0.0, "alpha=%.2f" % _alpha(200, 30))
	_c("擦之后透明了", _alpha(200, 30) >= 0.0 and _alpha(200, 30) < 0.5, "alpha=%.2f" % _alpha(200, 30))
	_c("洞外仍实心（块位置没算错）", _alpha(600, 30) > 0.5, "alpha=%.2f" % _alpha(600, 30))
	_c("另一块也仍实心", _alpha(100, 30) > 0.5, "alpha=%.2f" % _alpha(100, 30))

	Editor.erase(_pw.world, Vector2(400, 240), Vector2(400, 241), 8.0, 25.0)
	_pw.renderer.sync(_ground)
	_c("第二笔也画出来了", _alpha(400, 20) < 0.5)
	_c("第一笔的洞还在", _alpha(200, 30) < 0.5)
	_c("别处仍然实心", _alpha(600, 30) > 0.5)

	print("")
	print("=== 性能：擦一笔 + sync ===")
	var STEPS := 30
	var t0 := Time.get_ticks_usec()
	for i in STEPS:
		Editor.erase(_pw.world, Vector2(60.0 + i * 5.0, 210.0), Vector2(60.0 + i * 5.0, 211.0), 6.0, 25.0)
		_pw.renderer.sync(_ground)
	var per := (Time.get_ticks_usec() - t0) / float(STEPS) / 1000.0
	print("  合计 = %.2f ms/笔（拆分基准见 tests/bench_erase.gd）" % per)

	print("=== %d passed, %d failed ===" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
