extends SceneTree
## **形状与碰撞是否一致** —— 直接对着用户报的现象写。
##
## 渲染看 body.shapes，碰撞看 body.rects（推给 Rapier 的那份）。
## 两者都从同一个 shape 算出来，所以一旦不一致，一定是**某条路径漏了重算**。
##
## 判据：把 rects 铺成网格，与 shapes 的像素**逐格比对**，必须完全相同。
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

## 把某刚体的 rects 与 shapes 都铺成局部网格，逐格比对。
func _check(label: String) -> void:
	var bad := 0
	var total := 0
	for b in _pw.world.bodies:
		if b.shapes.is_empty():
			continue
		# ⚠️⚠️ 必须用**形状的局部 AABB**，不能用 b.aabb。
		#
		#    b.aabb 是**世界**坐标（地面在 (0,220)），而 s.get_pixel() 要的是
		#    **形状局部**坐标（从 (0,0) 起）。混用会让两边同时退化成全 0：
		#      · from_shape：查 y=220..319，而形状只到 y=100 -> 全 0
		#      · from_rect： y0 = 0 - 220 + 1 = -219 -> y 区间为空 -> 全 0
		#    于是 0 == 0 **永远通过**，测试完全空转。
		#
		#    这个 bug 是**反证时发现的**：故意把位网格的写入偏移一格，
		#    rects 变成 96 个宽 7 的梳齿（x=1,9,17,25...），明显错误，
		#    而这个测试仍然 6/6 通过。
		#
		#    教训：**"测试全绿"要先证明它能变红。** 尤其是这种"两边都由我算"
		#    的比对，很容易一起算错而互相抵消。
		var aabb := Rect2i()
		var first := true
		for s0 in b.shapes:
			var la: Rect2i = s0.local_aabb()
			if first:
				aabb = la
				first = false
			else:
				aabb = aabb.merge(la)
		if first:
			continue
		var w: int = aabb.size.x + 2
		var h: int = aabb.size.y + 2
		var from_rect := PackedByteArray()
		from_rect.resize(w * h)
		for r in b.rects:
			# rects 是**体局部**坐标
			var x0: int = int(r.position.x) - aabb.position.x + 1
			var y0: int = int(r.position.y) - aabb.position.y + 1
			var x1: int = x0 + int(r.size.x)
			var y1: int = y0 + int(r.size.y)
			for y in range(maxi(y0, 0), mini(y1, h)):
				for x in range(maxi(x0, 0), mini(x1, w)):
					from_rect[y * w + x] = 1
		var from_shape := PackedByteArray()
		from_shape.resize(w * h)
		for s in b.shapes:
			for y in range(aabb.position.y, aabb.position.y + aabb.size.y):
				for x in range(aabb.position.x, aabb.position.x + aabb.size.x):
					if s.get_pixel(x, y) != 0:
						from_shape[(y - aabb.position.y + 1) * w + (x - aabb.position.x + 1)] = 1
		for i in w * h:
			total += 1
			if from_rect[i] != from_shape[i]:
				bad += 1
	var name := "%s：%d 格全部一致" % [label, total]
	var detail := "不一致 %d 格" % bad
	_c(name, bad == 0, detail)

func _initialize() -> void:
	print("=== 形状 vs 碰撞 一致性 ===")
	_pw = AddonWorld.new()
	var g = AddonBody.new(); g.position = Vector2(0, 220); g.is_static = true
	_pw.add_child(g)
	var gs = AddonShape.new(); gs.rect_size = Vector2i(768, 100); g.add_child(gs)
	get_root().add_child(_pw)
	await process_frame
	await process_frame
	_pw.rebuild()
	_check("初始")

	for i in 3:
		Editor.erase(_pw.world, Vector2(100.0 + i * 150.0, 270.0), Vector2(100.0 + i * 150.0, 271.0), 8.0, 25.0)
		_check("内部擦 %d" % (i + 1))

	# 竖着切一刀（切穿上下边界）—— 这是"切割"最容易暴露问题的形状
	_pw.world.damage_segment(Vector2(400, 200), Vector2(400, 340), 5.0)
	_check("竖切一刀")

	# 斜切
	_pw.world.damage_segment(Vector2(600, 200), Vector2(700, 340), 5.0)
	_check("斜切")

	print("=== %d passed, %d failed ===" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
