extends SceneTree
## 甲方定的语义：向鼠标施力 + **在抓取点上**补偿重力。
## 平衡状态判据：**质心应当落在鼠标正下方**（同一竖直线），且不掉、不摆。
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

func _shape(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, w, h), 1)
	return s

func _run(label: String, welded: bool) -> void:
	var world := PWorld.new()
	var a := PBody.new()
	a.position = Vector2(100, 240)
	world.add_body(a, [_shape(16, 16)])
	var b: PBody = null
	if welded:
		b = PBody.new()
		b.position = Vector2(120, 240)
		world.add_body(b, [_shape(16, 16)])
		world.add_weld(a, b, Vector2(116, 248))
	# 抓 A 的左上角（故意偏离质心）
	var grab_pt: Vector2 = a.position + Vector2(-6, -6)
	var g = world.grab(a, grab_pt)
	var tgt: Vector2 = grab_pt + Vector2(0, 0)
	var coms := []
	for i in 600:
		world.set_grab_target(tgt)
		world.step(1.0 / 60.0)
		if i % 120 == 119:
			var m_tot: float = a.mass + (b.mass if welded else 0.0)
			var com: Vector2 = (a.com_world() * a.mass + (b.com_world() * b.mass if welded else Vector2.ZERO)) / m_tot
			coms.append("x%+.1f" % (com.x - tgt.x))
	var m_tot2: float = a.mass + (b.mass if welded else 0.0)
	var com2: Vector2 = (a.com_world() * a.mass + (b.com_world() * b.mass if welded else Vector2.ZERO)) / m_tot2
	print('%s' % label)
	print('   抓点 %s  鼠标 %s' % [str(grab_pt), str(tgt)])
	print('   每 2 秒质心相对鼠标的**水平**偏差: %s' % str(coms))
	print('   末态：质心 %s  水平偏差 %+.2f px（应当 ~0）  质心在鼠标下方 %.1f px' % [
		str(com2), com2.x - tgt.x, com2.y - tgt.y])

func _initialize() -> void:
	_run("单体（抓左上角）", false)
	_run("焊接组件（抓 A 左上角）", true)
	quit(0)