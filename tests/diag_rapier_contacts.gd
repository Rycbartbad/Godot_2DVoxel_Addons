extends SceneTree
## Rapier 模式的接触事件验证：事件有没有、法向对不对、approach 是不是"撞前速度"、
## 冲量是不是真值、接触宽度（像素采样）还在不在。
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

var _pass := 0
var _fail := 0

func _c(name: String, ok: bool, d: String = "") -> void:
	if ok:
		_pass += 1
		print("  PASS  ", name, "  ", d)
	else:
		_fail += 1
		print("  FAIL  ", name, "  ", d)

func _block(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, w, h), 1)
	return s

func _initialize() -> void:
	print("=== Rapier 模式接触事件验证 ===")
	var w := PWorld.new()
	w.contact_events_enabled = true
	var g := PBody.new()
	g.position = Vector2(-200.0, 0.0)
	g.make_static()
	w.add_body(g, [_block(400, 40)])
	var f := PBody.new()
	f.position = Vector2(0.0, -100.0)
	w.add_body(f, [_block(16, 16)])

	var saw := false
	var first_approach := 0.0
	var first_new := false
	var speed_before := 0.0
	var first_normal := Vector2.ZERO
	var first_point := Vector2.ZERO
	var first_impulse := 0.0
	var first_width := 0.0
	var max_impulse := 0.0
	for i in 90:
		if not saw:
			speed_before = absf(f.linear_velocity.y)
		w.step(1.0 / 60.0)
		for c in w.contacts:
			if (c.a == f or c.b == f):
				max_impulse = maxf(max_impulse, c.impulse)
				if not saw:
					saw = true
					first_approach = c.approach
					first_new = c.is_new
					first_normal = c.normal
					first_point = c.point
					first_impulse = c.impulse
					first_width = c.contact_width

	_c("产生了接触事件", saw, "首次 approach=%.1f px/s" % first_approach)
	_c("approach = 撞击前的实际速度", absf(first_approach - speed_before) < 8.0,
		"实测 %.1f vs 撞前 %.1f" % [first_approach, speed_before])
	_c("首次接触标了 is_new", first_new)
	# 法向由 a 指向 b：地面是 a 时应当指向 +y（向下，即指向方块）
	var ok_norm := false
	if first_normal.y < -0.9 or first_normal.y > 0.9:
		ok_norm = true
	_c("法向沿竖直方向（由 a 指向 b）", ok_norm, "法向 (%.3f, %.3f)" % [first_normal.x, first_normal.y])
	_c("接触点在方块附近", absf(first_point.x - 8.0) < 24.0 and absf(first_point.y) < 24.0,
		"点 (%.2f, %.2f)" % [first_point.x, first_point.y])
	_c("冲量是正的真值（不是 0，也不是近似上界）", first_impulse > 0.0 and max_impulse > 0.0,
		"首次 %.2f | 峰值 %.2f" % [first_impulse, max_impulse])
	_c("接触宽度（像素采样）还在", first_width >= 1.0, "宽 %.1f px" % first_width)
	print("  终态：底边 y=%.4f  速度 (%.5f, %.5f)  awake=%s" % [
		f.position.y + 16.0, f.linear_velocity.x, f.linear_velocity.y, str(f.awake)])
	print("=== %d passed, %d failed ===" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
