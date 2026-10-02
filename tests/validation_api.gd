extends SceneTree
## 四类接口的验证：体素颜色/材质、质量（密度表）、对点施力、程序化破坏
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

var _pass := 0
var _fail := 0

func _check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		_pass += 1
		print("  PASS  ", name, "  ", detail)
	else:
		_fail += 1
		print("  FAIL  ", name, "  ", detail)

func _block(w: int, h: int, mat: int = 1) -> PixelShape:
	var s := PixelShape.new()
	for y in h:
		for x in w:
			s.set_pixel(x, y, mat)
	return s

func _initialize() -> void:
	print("=== 引擎接口验证 ===")

	# ---- ① 体素颜色 / 材质 ----
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, 10, 10), 1)
	s.fill_rect(Rect2i(2, 2, 4, 4), 3)
	_check("fill_rect 生效", s.pixel_count() == 100, "%d 像素" % s.pixel_count())
	_check("get_pixel 读到材质", s.get_pixel(3, 3) == 3 and s.get_pixel(0, 0) == 1,
		"内=%d 外=%d" % [s.get_pixel(3, 3), s.get_pixel(0, 0)])
	_check("空处返回 0", s.get_pixel(-5, -5) == 0)
	var hist := s.count_by_material()
	_check("材质直方图", int(hist.get(1, 0)) == 84 and int(hist.get(3, 0)) == 16,
		"材质1=%d 材质3=%d" % [int(hist.get(1, 0)), int(hist.get(3, 0))])
	_check("remap_material", s.remap_material(3, 2) == 16 and s.get_pixel(3, 3) == 2)
	s.fill_rect(Rect2i(0, 0, 2, 2), 0)
	_check("fill_rect(0) 等价清空", s.pixel_count() == 96, "%d 像素" % s.pixel_count())

	# ---- ② 质量 / 密度表 ----
	var w := PWorld.new()
	w.gravity = Vector2.ZERO
	w.set_material_density(1, 1.0)
	w.set_material_density(3, 5.0)          # 金属比石头重 5 倍
	# ⚠️ 每个物体要放在不同位置 —— 全堆在原点会互相碰撞，
	# 测出来的是"接触行为"而不是"质量/力"
	var light := PBody.new()
	light.position = Vector2(0.0, 0.0)
	w.add_body(light, [_block(10, 10, 1)])
	var heavy := PBody.new()
	heavy.position = Vector2(200.0, 0.0)
	w.add_body(heavy, [_block(10, 10, 3)])
	_check("密度表决定质量", is_equal_approx(light.mass, 100.0) and is_equal_approx(heavy.mass, 500.0),
		"轻=%.1f 重=%.1f" % [light.mass, heavy.mass])
	_check("惯量随质量缩放", heavy.inertia > light.inertia * 4.0,
		"I=%.1f vs %.1f" % [heavy.inertia, light.inertia])
	# 换材质 -> refresh_mass 后质量跟着变
	for sh in heavy.shapes:
		(sh as PixelShape).remap_material(3, 1)
	w.refresh_mass(heavy)
	_check("改材质后重算质量", is_equal_approx(heavy.mass, 100.0), "%.1f" % heavy.mass)

	# ---- ③ 对某一点施加力 ----
	var box := PBody.new()
	box.position = Vector2(0.0, 200.0)
	w.add_body(box, [_block(8, 8)])
	box.clear_forces()
	box.add_force(Vector2(100.0, 0.0))      # 过质心：只平动
	for i in 60:
		w.step(1.0 / 60.0)
	# F=100, m=64 -> a=1.5625；1 秒后 v≈1.56（阻尼略减）
	_check("过质心的力只产生平动", box.linear_velocity.x > 1.0 and absf(box.angular_velocity) < 1e-6,
		"vx=%.4f w=%.5f" % [box.linear_velocity.x, box.angular_velocity])

	var box2 := PBody.new()
	box2.position = Vector2(200.0, 200.0)
	w.add_body(box2, [_block(8, 8)])
	box2.clear_forces()
	# 在质心**上方**沿 +x 推 -> 应当产生角速度（"推箱子顶部会转"）
	box2.add_force_at(Vector2(100.0, 0.0), box2.com_world() + Vector2(0.0, -4.0))
	for i in 60:
		w.step(1.0 / 60.0)
	_check("偏心施力产生力矩", absf(box2.angular_velocity) > 0.1,
		"w=%.4f" % box2.angular_velocity)

	var box3 := PBody.new()
	box3.position = Vector2(400.0, 200.0)
	w.add_body(box3, [_block(8, 8)])
	box3.apply_central_impulse(Vector2(0.0, 80.0))
	_check("冲量立即改速度", is_equal_approx(box3.linear_velocity.y, 80.0 / box3.mass),
		"vy=%.4f (期望 %.4f)" % [box3.linear_velocity.y, 80.0 / box3.mass])

	# ---- ④ 程序化破坏（世界坐标）----
	var w2 := PWorld.new()
	w2.gravity = Vector2.ZERO
	var target := PBody.new()
	target.position = Vector2(100.0, 100.0)
	w2.add_body(target, [_block(40, 40)])
	var before: int = (target.shapes[0] as PixelShape).pixel_count()
	var frags: Array = w2.damage_circle(Vector2(120.0, 100.0), 6.0)
	var after: int = (target.shapes[0] as PixelShape).pixel_count()
	_check("世界坐标挖洞生效", after < before, "%d -> %d 像素" % [before, after])
	var _f := frags

	# 用线段把方块切成两半 -> 应当产生碎片
	var w3 := PWorld.new()
	w3.gravity = Vector2.ZERO
	var t3 := PBody.new()
	w3.add_body(t3, [_block(40, 40)])
	var fr3: Array = w3.damage_segment(Vector2(-50.0, 20.0), Vector2(150.0, 20.0), 1.5)
	_check("线段切割产生碎片", fr3.size() > 0, "碎出 %d 块" % fr3.size())

	# 爆炸：既要炸开也要推走
	var w4 := PWorld.new()
	w4.gravity = Vector2.ZERO
	var t4 := PBody.new()
	t4.position = Vector2(0.0, 0.0)
	w4.add_body(t4, [_block(20, 20)])
	var near := PBody.new()
	near.position = Vector2(40.0, 0.0)
	w4.add_body(near, [_block(8, 8)])
	w4.explode(Vector2(0.0, 0.0), 80.0, 300.0)
	_check("爆炸把物体推开", near.linear_velocity.x > 50.0, "vx=%.1f" % near.linear_velocity.x)
	var t4n: int = (t4.shapes[0] as PixelShape).pixel_count()
	_check("爆炸也破坏", t4n < 400, "%d 像素" % t4n)

	# 涂色（世界坐标，不破坏）
	var w5 := PWorld.new()
	w5.gravity = Vector2.ZERO
	var t5 := PBody.new()
	w5.add_body(t5, [_block(20, 20, 1)])
	var painted := w5.paint_circle(Vector2(10.0, 10.0), 5.0, 4)
	_check("世界坐标涂色", painted > 0 and (t5.shapes[0] as PixelShape).get_pixel(10, 10) == 4,
		"改了 %d 像素" % painted)

	print("=== %d passed, %d failed ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
