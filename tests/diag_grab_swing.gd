extends SceneTree
## 抓取时摆动**幅度的衰减**（每 2 秒窗口内的最大偏角）与平均角速度。
##
## ⚠️ 这个探针是为了查"焊接体摆动停不下来"（甲方反馈）而写的，结论如下：
##
##   · 抓取控制器是"按位置误差一直推"的驱动，力的作用点（抓点）绕着组件质心转、
##     力的方向朝着鼠标 —— 每转一圈都做净功，等于把物体当转子驱动（"泵"）；
##   · 光靠角阻尼压不住：ang_damp 加到 55（接近 1/dt 上限）、力上限降到 0.78g，
##     摆幅都恒在 140~180 度；
##   · 试过"抓取力矩只许刹车"（spin_limit = 0）能把摆动停死（0~10 度），
##     但它**把普通抓取也弄坏了**：单体被抓着时完全不能转（挂不住、也甩不出去），
##     抓取力还会随自转被软化。已整体回退（见 development_log 的"回退"一节）。
##
## 现在这个探针的用途：量"泵"有多强，给以后想认真解决它的人一个现成的尺子。
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

func _shape(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, w, h), 1)
	return s

func _run(accel: float, damp: float) -> void:
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
	print('力上限 %-6s 阻尼 %-5s 每 2 秒窗口 摆幅|平均角速度: %s' % [str(accel), str(damp), str(amps)])

func _initialize() -> void:
	print('=== 摆幅衰减（窗口: 0~2s, 2~4s, ... 10~12s）===')
	for pair in [[1500.0, 4.0], [1500.0, 0.0], [900.0, 4.0]]:
		_run(pair[0], pair[1])
	quit(0)