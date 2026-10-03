extends SceneTree
## 量"吊桥的塌陷程度"和**子步数**的关系（甲方："静止时的塌陷程度和有没有物体在运动有关"）。
##
## 实测（同一座桥、20 秒、旁边一个无关的箱子一直飞）：
##   钉死 1 子步  桥板 y: 98.02 / 101.81 / 103.06 / 101.78
##   钉死 6 子步  桥板 y: 98.00 /  99.14 /  99.53 /  99.15
## 中间两块差 **3.5 px** —— 这就是甲方看到的"塌陷程度不一样"。
##
## 机制：全世界的子步数是按"最快的那个刚体"算的（PWorld._compute_substeps），
##      无关物体的运动改变了桥的积分步长。桥是两端固定、接近水平的链，
##      平衡形状对历史极其敏感，于是停下来的形状不一样。
##
## ⚠️ 已排除：求解迭代次数。把 num_solver_iterations 从默认 4 提到 12，
##    两组数字**逐位相同** —— 不是收敛不够，换迭代数没用。
## 对照组：把子步数钉死在 1（ccd_enabled=false）/ 钉死在 6（把 ccd_max_motion 调很小）。
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

func _rect(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, w, h), 1)
	return s

func _run(label: String, fixed_n: int) -> void:
	var world := PWorld.new()
	world.gravity = Vector2(0, 600)
	if fixed_n <= 1:
		world.ccd_enabled = false                      # 永远 1 子步
	else:
		world.ccd_max_motion = 0.0001                  # 永远顶到上限
		world.ccd_substep_budget = fixed_n
	var ground := PBody.new()
	ground.position = Vector2(0, 220)
	ground.make_static()
	world.add_body(ground, [_rect(768, 100)])
	var planks := []
	for i in 4:
		var b := PBody.new()
		b.position = Vector2(306 + 31 * i, 98)
		world.add_body(b, [_rect(31, 6)])
		planks.append(b)
	world.add_hinge(null, planks[0], Vector2(306, 101))
	for i in 3:
		world.add_hinge(planks[i], planks[i + 1], Vector2(337 + 31 * i, 101))
	world.add_hinge(planks[3], null, Vector2(430, 101))
	# 一个无关的物体在旁边一直动（模拟"有东西在动"）
	var box := PBody.new()
	box.position = Vector2(150, 100)
	world.add_body(box, [_rect(16, 16)])
	for i in 1200:
		if i < 600:
			box.linear_velocity = Vector2(300.0, 0.0)     # 一直甩着它跑
			box.awake = true
			box.sleep_timer = 0.0
		world.step(1.0 / 60.0)
	print('%s  末态子步 %d' % [label, world.last_substeps])
	print('   桥板 y: %s   睡着? %s' % [str(planks.map(func(b): return "%.2f" % b.position.y)), str(not planks[1].awake)])

func _initialize() -> void:
	_run("钉死 1 子步", 1)
	_run("钉死 6 子步", 6)
	quit(0)