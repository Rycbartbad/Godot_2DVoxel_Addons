extends SceneTree
## 验证切向（摩擦）冲量的导出。
## 判据：滑动接触应当给出**非零**切向冲量，且满足库仑约束 |切向| <= mu * |法向|。
## （法向冲量在滑动中主要支撑重力，切向冲量就是那 17 px/s/帧 的减速来源。）
const PWorld := preload("res://src/physics/pworld.gd")
const PBody := preload("res://src/physics/pbody.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

func _box(w: int, h: int, mat: int) -> PixelShape:
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, w, h), mat)
	return s

func _initialize() -> void:
	var w := PWorld.new()
	w.gravity = Vector2(0, 600)
	var ground := PBody.new()
	ground.position = Vector2(0, 100)
	ground.make_static()
	w.add_body(ground, [_box(400, 8, 1)], Callable(), true)
	var box := PBody.new()
	box.position = Vector2(-60, 84)
	w.add_body(box, [_box(32, 8, 2)], Callable(), true)
	box.linear_velocity = Vector2(200, 0)          # 横向滑动 -> 制造摩擦
	w._rp_ensure()
	var shown := 0
	for i in 90:
		w.step(1.0 / 60.0)
		var pts: Array = w.contact_points(0)
		if pts.is_empty() or shown >= 3:
			continue
		shown += 1
		var sx := 0.0
		var st := 0.0
		print("--- 采样 %d（盒速度 x = %.2f）---" % [shown, box.linear_velocity.x])
		for p in pts:
			sx += absf(p["impulse"])
			st += absf(p["tangent_impulse"])
			print("  法向=%.4f 切向=%.4f | |切向|/|法向| = %.4f" % [
				p["impulse"], p["tangent_impulse"],
				absf(p["tangent_impulse"]) / maxf(absf(p["impulse"]), 1e-9)])
		print("  合计：法向 %.4f，切向 %.4f -> |切向|/|法向| = %.4f" % [sx, st, st / maxf(sx, 1e-9)])
	quit(0)
