extends SceneTree
## 临时探针（用完即删）：抓取时**子步棘轮**对每帧成本的影响。
const AddonWorld := preload("res://src/nodes/pixel_world.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")
const PBody := preload("res://src/physics/pbody.gd")

func _initialize() -> void:
	var pw = AddonWorld.new()
	get_root().add_child(pw)
	await process_frame
	var w = pw.world
	print("ccd_enabled=%s ccd_max_motion=%s ccd_substep_budget=%s ccd_substep_hold=%s" % [
		str(w.ccd_enabled), str(w.ccd_max_motion), str(w.ccd_substep_budget), str(w.ccd_substep_hold)])
	# 一个 1000 矩形的大物体 + 20 个小物体（模拟"1000 个矩形"的场景）
	var s := PixelShape.new()
	for j in 1000:
		s.fill_rect(Rect2i(0, j * 2, 200, 1), 1)
	var big := PBody.new()
	w.add_body(big, [s], Callable(), true)
	for i in 20:
		var b := PBody.new()
		b.position = Vector2(i * 30, -200)
		var s2 := PixelShape.new()
		s2.fill_rect(Rect2i(0, 0, 8, 8), 1)
		w.add_body(b, [s2], Callable(), true)
	print("刚体 %d，大物体矩形 %d" % [w.bodies.size(), big.rects.size()])
	var dt := 1.0 / 60.0
	# ① 静止（不抓）
	var t := 0.0
	for i in 10:
		var t0 := Time.get_ticks_usec()
		w.step(dt)
		t += (Time.get_ticks_usec() - t0) / 1000.0
	print("① 不抓、静止：      子步 %d，%7.3f ms/帧" % [w._substeps_held, t / 10.0])
	# ② 抓住大物体并高速挥动（空挥，不接触任何东西）
	w.grab(big, Vector2(100, 0))
	var t2 := 0.0
	var counts: Array = []
	for i in 10:
		big.linear_velocity = Vector2(0, -3000)      # 高速空挥
		var t0 := Time.get_ticks_usec()
		w.step(dt)
		t2 += (Time.get_ticks_usec() - t0) / 1000.0
		counts.append(w._substeps_held)
	print("② 抓着高速空挥：    子步序列 %s，%7.3f ms/帧" % [str(counts), t2 / 10.0])
	# ③ 停下来但**不松手**
	big.linear_velocity = Vector2.ZERO
	var t3 := 0.0
	counts = []
	for i in 40:
		big.linear_velocity = Vector2.ZERO
		var t0 := Time.get_ticks_usec()
		w.step(dt)
		t3 += (Time.get_ticks_usec() - t0) / 1000.0
		counts.append(w._substeps_held)
	print("③ 停下但不松手：    子步序列 %s，%7.3f ms/帧" % [str(counts), t3 / 40.0])
	# ④ 松手之后再静止
	w.release_grab()
	var t4 := 0.0
	counts = []
	for i in 10:
		var t0 := Time.get_ticks_usec()
		w.step(dt)
		t4 += (Time.get_ticks_usec() - t0) / 1000.0
		counts.append(w._substeps_held)
	print("④ 松手后：          子步序列 %s，%7.3f ms/帧" % [str(counts), t4 / 10.0])
	quit(0)
