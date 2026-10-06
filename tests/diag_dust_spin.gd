extends SceneTree
## 轻碎片的**角速度**通道：Δω = J·r/I，而 I ∝ m —— 擦撞一下就能爆。
const PWorld := preload("res://src/physics/pworld.gd")
const PBody := preload("res://src/physics/pbody.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

func _shape(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, w, h), 1)
	return s

func _initialize() -> void:
	print("=== 重块**擦着**轻碎片过去（有力矩）===")
	for frag in [2, 4, 8, 16]:
		var w := PWorld.new()
		w.gravity = Vector2.ZERO
		var heavy := PBody.new()
		heavy.position = Vector2(0, 0)
		w.add_body(heavy, [_shape(60, 60)])          # 质量 3600
		heavy.linear_velocity = Vector2(800, 0)
		# 碎片放在重块**边缘**（y 偏 28）—— 擦撞，产生力矩
		var dust := PBody.new()
		dust.position = Vector2(60, 28)
		w.add_body(dust, [_shape(frag, frag)])
		var wmax := 0.0
		var vmax := 0.0
		for k in 30:
			w.step(1.0 / 60.0)
			wmax = maxf(wmax, absf(dust.angular_velocity))
			vmax = maxf(vmax, dust.linear_velocity.length())
		print("  %2dx%-2d（质量 %6.1f, I=%7.2f）-> 峰值 |v| %9.1f  |w| %12.1f rad/s  表面速度 %10.1f | 子步 %d" % [
			frag, frag, dust.mass, dust.inertia, vmax, wmax,
			wmax * dust.bounding_radius(), w.last_substeps])
	print("")
	print("=== 同样场景，但碎片**正撞**（无力矩）作对照 ===")
	var w2 := PWorld.new()
	w2.gravity = Vector2.ZERO
	var h2 := PBody.new()
	h2.position = Vector2(0, 0)
	w2.add_body(h2, [_shape(60, 60)])
	h2.linear_velocity = Vector2(800, 0)
	var d2 := PBody.new()
	d2.position = Vector2(60, 0)
	w2.add_body(d2, [_shape(4, 4)])
	var wmax2 := 0.0
	for k in 30:
		w2.step(1.0 / 60.0)
		wmax2 = maxf(wmax2, absf(d2.angular_velocity))
	print("  4x4 正撞 -> 峰值 |w| %.1f rad/s | 子步 %d" % [wmax2, w2.last_substeps])
	quit(0)
