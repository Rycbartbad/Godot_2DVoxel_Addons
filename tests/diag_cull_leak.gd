extends SceneTree
## 僵尸刚体的代价曲线：Rapier 里还剩多少个"GDScript 已经不要了"的刚体，步进要多少钱。
const PWorld := preload("res://src/physics/pworld.gd")
const PBody := preload("res://src/physics/pbody.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

func _shape(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, w, h), 1)
	return s

func _native_count(w) -> int:
	var cmds := PackedByteArray()
	cmds.resize(1)
	cmds.encode_u8(0, 13)
	var res: PackedByteArray = w._rp_send(cmds, 4)
	return res.decode_s32(4) if res.size() >= 8 else -1

func _step_ms(w, reps: int) -> float:
	var t0 := Time.get_ticks_usec()
	for i in reps:
		w.step(1.0 / 60.0)
	return float(Time.get_ticks_usec() - t0) / 1000.0 / float(reps)

func _trial(n_zombies: int) -> void:
	var w := PWorld.new()
	w.gravity = Vector2(0, 300)
	var ground := PBody.new()
	ground.make_static()
	w.add_body(ground, [_shape(400, 20)])
	w.step(1.0 / 60.0)
	# 造 n 个"掉出世界"的碎片，然后用 cull_outside 清掉（= demo 的路径）
	for i in n_zombies:
		var b := PBody.new()
		b.position = Vector2(10 + (i % 40) * 10, 1000 + (i / 40) * 10)
		w.add_body(b, [_shape(8, 8)])
	for k in 2:
		w.step(1.0 / 60.0)
	w.cull_outside(Rect2(-100, -100, 400, 400))
	# 让僵尸再飞 2 秒（它们还在被 Rapier 积分）
	for k in 120:
		w.step(1.0 / 60.0)
	print("  僵尸 %6d | 原生刚体 %6d | GDScript 刚体 %3d | step = %8.3f ms" % [
		n_zombies, _native_count(w), w.bodies.size(), _step_ms(w, 10)])

func _initialize() -> void:
	print("=== cull_outside 之后（僵尸仍在 Rapier 里被积分）===")
	for n in [0, 500, 2000, 8000]:
		_trial(n)
	quit(0)
