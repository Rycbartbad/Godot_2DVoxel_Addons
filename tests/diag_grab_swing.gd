extends SceneTree
## 抓取时摆动**幅度的衰减**（每 2 秒窗口内的最大偏角）。
## 应当单调衰减；不衰减 = 被抓取控制器泵起来了（或角阻尼没生效）。
## 同时扫 ang_damp（物理阻尼力矩）与"转动时软化抓取力"两种抑制手段。
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
	for i in 720:
		world.set_grab_target(hold)
		world.step(1.0 / 60.0)
		win = maxf(win, absf(rad_to_deg(angle_difference(a.position.angle_to_point(b.position), ang0))))
		if i % 120 == 119:
			amps.append(snappedf(win, 1.0))
			win = 0.0
	print('力上限 %-6s 阻尼 %-5s 每 2 秒窗口的摆幅: %s' % [str(accel), str(damp), str(amps)])

func _initialize() -> void:
	print('=== 摆幅衰减（第 1 个窗口 0~2 秒 ... 第 6 个 10~12 秒）===')
	for pair in [[1500.0, 8.0], [1500.0, 16.0], [1500.0, 30.0]]:
		_run(pair[0], pair[1])
	quit(0)