extends SceneTree
## 密度（质量）对**抓取稳定性**的影响 —— 这里曾经是「越重越抖」。
## demo 的焊件是材质 3（密度 7.8 -> 质量 1996.8），
## 我之前的合成场景用的是默认密度（质量 256）。质量差 7.8 倍会不会就是振动的原因？
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

func _shape(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, w, h), 1)
	return s

func _run(density: float, grab_offset: Vector2) -> void:
	var world := PWorld.new()
	var d := func(_b) -> float: return density
	var a := PBody.new()
	a.position = Vector2(346, 70)
	world.add_body(a, [_shape(16, 16)], d)
	var b := PBody.new()
	b.position = Vector2(365, 56)
	world.add_body(b, [_shape(16, 16)], d)
	world.add_weld(a, b, Vector2(361, 70))
	var hold: Vector2 = a.position + grab_offset
	world.grab(a, hold)
	var vs := PackedFloat32Array()
	var dmin := 999.0
	var dmax := 0.0
	var d0: float = a.position.distance_to(b.position)
	for i in 300:
		world.set_grab_target(hold)
		world.step(1.0 / 60.0)
		var dd: float = a.position.distance_to(b.position)
		dmin = minf(dmin, dd)
		dmax = maxf(dmax, dd)
		if i % 60 == 59:
			vs.append(snappedf(maxf(a.linear_velocity.length(), b.linear_velocity.length()), 0.01))
	print('密度 %-4s 质量 %-7.1f 抓点偏移 %-9s -> 每 60 步速度 %s  两体距离 %.2f..%.2f(初始 %.2f)' % [
		str(density), a.mass, str(grab_offset), str(vs), dmin, dmax, d0])

func _initialize() -> void:
	print('=== 密度（质量）对比，目标不动 ===')
	_run(1.0, Vector2(8, 8))
	_run(7.8, Vector2(8, 8))
	_run(7.8, Vector2(0, 0))
	_run(2.5, Vector2(8, 8))
	quit(0)