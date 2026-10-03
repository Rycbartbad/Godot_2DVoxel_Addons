extends SceneTree
## CCD 参数 A/B：soft_ccd_prediction（逐刚体软 CCD 预测距离）× max_ccd_substeps（世界级子步上限）。
##
## 上一轮想量但没量成 —— 当时 rapier_bridge.dll 是旧的，所有刚体拿到 id=-1 全冻住，
## 症状（物体不动）完全指不到构建问题。
##
## 判据：
##   穿模  —— 4 px 薄墙 + 高速物体，能不能挡住
##   落定  —— 方块落到地面后是否稳定、是否入睡
##   成本  —— 每步耗时
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

func _block(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, w, h), 1)
	return s

func _tunnel(soft: float, sub: int, speed: float) -> bool:
	var w := PWorld.new()
	w.gravity = Vector2.ZERO
	w.rp_soft_ccd_prediction = soft
	w.rp_ccd_substeps = sub
	var wall := PBody.new()
	wall.position = Vector2(200.0, -100.0)
	wall.make_static()
	w.add_body(wall, [_block(4, 200)])
	var b := PBody.new()
	b.position = Vector2(0.0, 0.0)
	w.add_body(b, [_block(8, 8)])
	b.linear_velocity = Vector2(speed, 0.0)
	for i in 120:
		w.step(1.0 / 60.0)
		if b.position.x > 220.0:
			return true
	return false

func _settle(soft: float, sub: int) -> Array:
	var w := PWorld.new()
	w.rp_soft_ccd_prediction = soft
	w.rp_ccd_substeps = sub
	var g := PBody.new()
	g.position = Vector2(-200.0, 0.0)
	g.make_static()
	w.add_body(g, [_block(400, 40)])
	var b := PBody.new()
	b.position = Vector2(0.0, -60.0)
	w.add_body(b, [_block(16, 16)])
	var t0 := Time.get_ticks_usec()
	for i in 180:
		w.step(1.0 / 60.0)
	var us := (Time.get_ticks_usec() - t0) / 180.0
	return [b.position.y + 16.0, b.awake, us]

func _initialize() -> void:
	print("=== CCD 参数 A/B ===")
	print("soft=软CCD预测距离(px)  sub=max_ccd_substeps")
	print("")
	print("soft   sub   200px/s 600px/s 1200px/s 2000px/s 3000px/s | 底边y   入睡  每步us")
	for soft in [0.0, 1.5, 3.0]:
		for sub in [1, 4]:
			var r: Array = []
			for sp in [200.0, 600.0, 1200.0, 2000.0, 3000.0]:
				r.append("穿" if _tunnel(soft, sub, sp) else "挡")
			var st := _settle(soft, sub)
			print("%4.1f   %d     %s | %7.3f  %-5s %6.1f" % [
				soft, sub, "  ".join(r), st[0], str(st[1]), st[2]])
	quit(0)
