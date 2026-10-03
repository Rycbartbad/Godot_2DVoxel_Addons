extends SceneTree
## 抓取时摆动**幅度的衰减**（每 2 秒窗口内的最大偏角）。
## 应当单调衰减到接近 0；不衰减 = 被抓取控制器泵起来了，或者角阻尼太弱。
##
## 实测结论（2026 这轮）：
##   · 抓取控制器是"按位置误差一直推"的驱动，物体转起来后它会**持续泵能量**；
##   · 所以角阻尼必须够强才压得住 —— ang_damp = 4 只能让衰减变慢，压不住；
##   · ang_damp 的硬上限是 1/dt（60Hz 下 60）：显式积分 ω*(1-k*dt) 超过 1 就发散。
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

func _shape(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, w, h), 1)
	return s

func _run(accel: float, damp: float, slimit: float) -> void:
	var world := PWorld.new()
	var a := PBody.new()
	a.position = Vector2(100, 240)
	world.add_body(a, [_shape(16, 16)])
	var b := PBody.new()
	b.position = Vector2(120, 240)
	world.add_body(b, [_shape(16, 16)])
	world.add_weld(a, b, Vector2(116, 248))
	var hold: Vector2 = a.position + Vector2(8, 8) + Vector2(-40, -20)
	var g = world.grab(a, hold, accel)
	g.ang_damp = damp
	g.spin_limit = slimit
	var ang0: float = a.position.angle_to_point(b.position)
	var amps := []
	var win := 0.0
	var wsum := 0.0
	var wn := 0
	for i in 720:
		world.set_grab_target(hold)
		world.step(1.0 / 60.0)
		win = maxf(win, absf(rad_to_deg(angle_difference(a.position.angle_to_point(b.position), ang0))))
		wsum += absf(a.angular_velocity)
		wn += 1
		if i % 120 == 119:
			amps.append("%d|%.2f" % [int(win), wsum / maxf(1.0, float(wn))])
			win = 0.0
			wsum = 0.0
			wn = 0
	print('力上限 %-6s 阻尼 %-5s spin_limit %-5s 每 2 秒窗口 摆幅|平均角速度: %s' % [str(accel), str(damp), str(slimit), str(amps)])

func _initialize() -> void:
	print('=== 摆幅衰减（窗口: 0~2s, 2~4s, ... 10~12s）===')
	for pair in [[900.0, 20.0, 1.0], [900.0, 20.0, 0.3], [900.0, 20.0, 0.1], [900.0, 40.0, 0.3]]:
		_run(pair[0], pair[1], pair[2])
	quit(0)