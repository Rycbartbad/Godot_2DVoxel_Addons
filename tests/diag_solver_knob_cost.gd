extends SceneTree
## 求解迭代旋钮的**代价曲线** —— 看"设大了会不会卡死"。
## 诊断用（不是闸门）。
const PWorld := preload("res://src/physics/pworld.gd")
const PBody := preload("res://src/physics/pbody.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

func _shape(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, w, h), 1)
	return s

func _world(n_bodies: int) -> PWorld:
	var w := PWorld.new()
	w.gravity = Vector2(0, 300)
	var ground := PBody.new()
	ground.make_static()
	w.add_body(ground, [_shape(400, 20)])
	for i in n_bodies:
		var b := PBody.new()
		b.position = Vector2(20 + (i % 20) * 18, -20 - (i / 20) * 18)
		w.add_body(b, [_shape(16, 16)])
	for k in 30:
		w.step(1.0 / 60.0)
	return w

func _step_ms(w: PWorld, reps: int) -> float:
	var t0 := Time.get_ticks_usec()
	for i in reps:
		w.step(1.0 / 60.0)
	return float(Time.get_ticks_usec() - t0) / 1000.0 / float(reps)

func _initialize() -> void:
	print("=== 世界级迭代 rp_joint_solver_iterations（240 个刚体）===")
	for iters in [0, 4, 40, 200, 1000]:
		var w := _world(240)
		w.rp_joint_solver_iterations = iters
		print("  iters=%-5d  step = %8.3f ms" % [iters, _step_ms(w, 10)])
	print("=== 局部迭代 additional_solver_iterations（240 个刚体，每个都设）===")
	for n in [0, 4, 40, 200, 1000]:
		var w2 := _world(240)
		for b in w2.bodies:
			b.additional_solver_iterations = n
		print("  additional=%-5d  step = %8.3f ms" % [n, _step_ms(w2, 10)])
	quit(0)
