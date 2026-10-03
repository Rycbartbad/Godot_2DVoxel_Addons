extends SceneTree
## 探针：**拖动被焊接的刚体**到底发生了什么？
##
## ⚠️ 判据要分开量，别混成一个数：
##   · 逐帧跳变（每个刚体各自）—— 抽搐的直接度量
##   · 两体**中心距** —— 焊接有没有被拉开（用 x 差会把"整体转动"误判成拉伸）
##   · 组件**转角** —— 拖一点本来就会让组件转（物理上正确），要和抽搐区分开
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

func _shape(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, w, h), 1)
	return s

func _run(label: String, welded: bool, grab_b: bool) -> void:
	var world := PWorld.new()
	var g := PBody.new()
	g.position = Vector2(-200, 300)
	g.make_static()
	world.add_body(g, [_shape(900, 60)])
	var a := PBody.new()
	a.position = Vector2(100, 240)
	world.add_body(a, [_shape(16, 16)])
	var b: PBody = null
	if welded:
		b = PBody.new()
		b.position = Vector2(120, 240)
		world.add_body(b, [_shape(16, 16)])
		world.add_weld(a, b, Vector2(116, 248))
	var target: PBody = b if (welded and grab_b) else a
	var start := target.position + Vector2(8, 8)
	world.grab(target, start)
	var ja := 0.0
	var jb := 0.0
	var max_speed := 0.0
	var pa := a.position
	var pb := b.position if welded else Vector2.ZERO
	var d0 := a.position.distance_to(b.position) if welded else 0.0
	var max_d := d0
	var min_d := d0
	var ang := 0.0
	var ang0 := a.position.angle_to_point(b.position) if welded else 0.0
	for i in 300:
		world.set_grab_target(start + Vector2(2.0 * i, 0))
		world.step(1.0 / 60.0)
		ja = maxf(ja, a.position.distance_to(pa))
		if welded:
			jb = maxf(jb, b.position.distance_to(pb))
			var d := a.position.distance_to(b.position)
			max_d = maxf(max_d, d)
			min_d = minf(min_d, d)
			ang = maxf(ang, absf(angle_difference(a.position.angle_to_point(b.position), ang0)))
		max_speed = maxf(max_speed, a.linear_velocity.length())
		pa = a.position
		if welded:
			pb = b.position
	if welded:
		print("%-24s 跳变 A=%6.3f B=%6.3f  最大速度 %7.2f  中心距 %.2f..%.2f(初始%.2f)  转角 %.3f rad" % [
			label, ja, jb, max_speed, min_d, max_d, d0, ang])
	else:
		print("%-24s 跳变 A=%6.3f            最大速度 %7.2f" % [label, ja, max_speed])

func _initialize() -> void:
	print("=== 拖动：单体 vs 焊接组件（拖速 120 px/s，理想跳变 = 2.000）===")
	_run("单体（对照）", false, false)
	_run("焊接：抓左边", true, false)
	_run("焊接：抓右边", true, true)
	quit(0)