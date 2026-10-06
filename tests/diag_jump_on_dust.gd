extends SceneTree
## 复现"玩家跳在**很小**的碎片上掉帧"（参数照 ink-2：玩家 24x32 密度 8.0，碎片密度 1.0）
const PWorld := preload("res://src/physics/pworld.gd")
const PBody := preload("res://src/physics/pbody.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

func _shape(w: int, h: int, mat := 1) -> PixelShape:
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, w, h), mat)
	return s

func _run(frag_px: int, ignore_mass: float) -> void:
	var w := PWorld.new()
	w.gravity = Vector2(0, 600)
	w.set_material_density(1, 1.0)
	w.set_material_density(2, 8.0)
	w.rp_max_linear_velocity = 1000.0
	w.max_angular_velocity = 300.0
	w.ccd_ignore_mass = ignore_mass
	var ground := PBody.new()
	ground.position = Vector2(0, 100)
	ground.make_static()
	w.add_body(ground, [_shape(800, 40, 1)])
	var frag := PBody.new()
	frag.position = Vector2(100, 100 - frag_px)
	w.add_body(frag, [_shape(frag_px, frag_px, 1)])
	for k in 30:
		w.step(1.0 / 60.0)
	var player := PBody.new()
	player.position = Vector2(88, 100 - 40 - 32)
	w.add_body(player, [_shape(24, 32, 2)])
	player.linear_velocity = Vector2(0, 400)
	var peak_v := 0.0
	var peak_w := 0.0
	var peak_sub := 0
	var worst_ms := 0.0
	var worst_frame := -1
	var total_ms := 0.0
	for k in 25:
		var t0 := Time.get_ticks_usec()
		w.step(1.0 / 60.0)
		var ms := float(Time.get_ticks_usec() - t0) / 1000.0
		total_ms += ms
		peak_v = maxf(peak_v, frag.linear_velocity.length())
		peak_w = maxf(peak_w, absf(frag.angular_velocity))
		peak_sub = maxi(peak_sub, w.last_substeps)
		if ms > worst_ms:
			worst_ms = ms
			worst_frame = k
	print("  %-6s 碎片质量 %6.0f | ccd_ignore_mass %-5s | 峰值|v| %9.1f | 峰值|w| %9.1f | 峰值子步 %4d | 最坏一帧 %8.2f ms（第 %d 帧）| 25 帧合计 %8.1f ms" % [
		"%dx%d" % [frag_px, frag_px], frag.mass, "关" if ignore_mass <= 0.0 else "%.0f" % ignore_mass,
		peak_v, peak_w, peak_sub, worst_ms, worst_frame, total_ms])

func _initialize() -> void:
	print("=== 玩家（质量 6144，密度 8.0）落在很小的碎片上（碎片密度 1.0）===")
	for frag_px in [2, 4]:
		for ignore in [0.0, 64.0]:
			_run(frag_px, ignore)
	quit(0)
