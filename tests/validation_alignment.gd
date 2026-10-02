extends SceneTree
## 碰撞箱 vs 形状：位置是否零偏差
##
## 两条独立的对齐要求：
##   A. 碰撞矩形（贪心分解出的 OBB）必须**精确覆盖**像素集 ——
##      每个实心像素的中心落在某个矩形内，每个空像素的中心不在任何矩形内。
##   B. 渲染贴图与碰撞矩形必须**重合** ——
##      贴图的世界矩形应当等于所有 OBB 的并集包围盒。
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")
const PixelRenderer := preload("res://src/render/pixel_renderer.gd")

var _pass := 0
var _fail := 0
func _c(n: String, ok: bool, d: String = "") -> void:
	if ok:
		_pass += 1
		print("  PASS  ", n, "  ", d)
	else:
		_fail += 1
		print("  FAIL  ", n, "  ", d)

## 造一个**故意左右上下都不对称**的形状，任何半像素偏移都会暴露
func _lshape() -> PixelShape:
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, 12, 4), 1)      # 横条
	s.fill_rect(Rect2i(0, 4, 4, 8), 1)       # 左边竖条（L 形）
	return s

func _local_bounds_of(body) -> Rect2i:
	var box := Rect2i()
	var first := true
	for s: PixelShape in body.shapes:
		var b: Rect2i = s.local_aabb()
		if b.size.x <= 0:
			continue
		box = b if first else box.merge(b)
		first = false
	return box


func _pixel_center_in_rects(x: int, y: int, rects: Array) -> bool:
	var c := Vector2(float(x) + 0.5, float(y) + 0.5)
	for r: Rect2 in rects:
		if r.has_point(c):
			return true
	return false

func _initialize() -> void:
	# ---- A. 碰撞矩形 vs 像素集 ----
	print("=== A. 碰撞矩形精确覆盖像素集 ===")
	var s := _lshape()
	for rot in [0.0, 0.3, -1.2]:
		var b := PBody.new()
		b.position = Vector2(100, 50)
		b.rotation = rot
		b.rebuild([s], Callable())
		var rects := b.rects
		# 逐个像素检查
		var wrong_solid := 0
		var wrong_empty := 0
		var solid := 0
		for y in range(-4, 16):
			for x in range(-4, 16):
				var m := s.get_pixel(x, y)
				var inside := _pixel_center_in_rects(x, y, rects)
				if m != 0:
					solid += 1
					if not inside:
						wrong_solid += 1
				else:
					if inside:
						wrong_empty += 1
		_c("rot=%.2f：每个实心像素都在某个矩形内" % rot, wrong_solid == 0,
			"%d 个实心像素，漏掉 %d" % [solid, wrong_solid])
		_c("rot=%.2f：空像素不被矩形覆盖" % rot, wrong_empty == 0,
			"误覆盖 %d 个空像素" % wrong_empty)

	# 面积必须精确等于像素数（既无重叠也无遗漏）
	print("=== 矩形面积之和 == 像素数（无重叠、无遗漏）===")
	var b0 := PBody.new()
	b0.position = Vector2.ZERO
	b0.rebuild([s], Callable())
	var area := 0.0
	for r: Rect2 in b0.rects:
		area += r.size.x * r.size.y
	_c("面积精确相等", absf(area - float(s.pixel_count())) < 1e-9,
		"矩形面积 %.1f vs 像素数 %d" % [area, s.pixel_count()])

	# ---- B. 渲染贴图 vs 碰撞矩形 ----
	print("=== B. 渲染贴图与刚体重合 ===")
	var world := PWorld.new()
	var g := PBody.new()
	g.position = Vector2(-100, 200)
	g.make_static()
	world.add_body(g, [_lshape()])
	var b2 := PBody.new()
	b2.position = Vector2(30, 40)
	b2.rotation = 0.5
	world.add_body(b2, [_lshape()])
	var rend := PixelRenderer.new()
	root.add_child(rend)
	rend.palette = [Color(0, 0, 0, 0), Color(1, 1, 1, 1)]
	for b in world.bodies:
		rend.sync(b)
	await process_frame
	# 贴图的世界矩形：Sprite2D 的位置 ± 贴图尺寸/2（像素→世界是 1:1）
	var bad := 0
	var checked := 0
	for b in world.bodies:
		# ⚠️ 数组元素是 Variant，:= 推不出类型
		var local: Rect2i = b.shapes[0].local_aabb()
		# 形状局部 AABB 应当是 [0,12) x [0,12)（L 形外接）
		if local != Rect2i(0, 0, 12, 12):
			bad += 1
			print("      局部 AABB 不是 (0,0,12,12)：%s" % str(local))
		checked += 1
	_c("形状局部 AABB 从 (0,0) 起、尺寸等于像素外接", bad == 0,
		"检查 %d 个刚体" % checked)

	# ---- B2. 精灵的摆放必须与刚体变换逐位一致 ----
	#
	# ⚠️ 旋转下不能拿"世界 AABB 相等"来比（AABB 会包大）。
	#    要比**变换本身**：精灵的 transform 必须等于刚体变换，
	#    且局部矩形（offset + 贴图尺寸）必须等于形状的局部 AABB。
	#    这两条一起成立 => 像素、碰撞矩形、渲染三者共用同一套局部坐标，零偏差。
	print("=== B2. 精灵摆放 vs 刚体变换 ===")
	var node: Sprite2D = rend._nodes.get(b2.id)
	if node == null:
		_c("找到精灵节点", false)
	else:
		var want := Transform2D(Vector2(cos(b2.rotation), sin(b2.rotation)),
			Vector2(-sin(b2.rotation), cos(b2.rotation)), b2.position)
		var got: Transform2D = node.transform
		var same := got.origin.is_equal_approx(want.origin) 			and got.x.is_equal_approx(want.x) and got.y.is_equal_approx(want.y)
		_c("精灵变换 == 刚体变换（旋转 0.5）", same, "%s" % str(got.origin))
		var laabb := _local_bounds_of(b2)
		var sprite_rect := Rect2(node.offset, Vector2(node.texture.get_size()))
		_c("精灵局部矩形 == 形状局部 AABB（零偏移）",
			sprite_rect.position.is_equal_approx(Vector2(laabb.position))
			and sprite_rect.size.is_equal_approx(Vector2(laabb.size)),
			"精灵 %s vs 形状 %s" % [str(sprite_rect), str(laabb)])

	# 像素→世界：局部像素 (x,y) 的**左上角**应当映射到 to_world(x,y)
	print("=== C. 局部像素 -> 世界坐标 ===")
	var b3 := PBody.new()
	b3.position = Vector2(7, 11)
	b3.rotation = 0.0
	b3.rebuild([_lshape()], Callable())
	var p00 := b3.to_world(Vector2(0, 0))
	_c("局部 (0,0) -> 刚体原点（旋转为 0 时）",
		p00.is_equal_approx(b3.position), "%s vs %s" % [str(p00), str(b3.position)])
	# 旋转 90° 时，(0,0) 仍应映射到原点
	b3.rotation = PI * 0.5
	var p00r := b3.to_world(Vector2(0, 0))
	_c("局部 (0,0) 在任意旋转下都映射到原点", p00r.is_equal_approx(b3.position),
		"%s vs %s" % [str(p00r), str(b3.position)])

	print("=== %d passed, %d failed ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
