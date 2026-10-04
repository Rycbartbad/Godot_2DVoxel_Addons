extends SceneTree
## 验证 GDScript 侧的接触点接口（PWorld.contact_points / contact_pair_count）。
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
	w.add_body(ground, [_box(200, 8, 1)], Callable(), true)
	var box := PBody.new()
	box.position = Vector2(50, 84)
	w.add_body(box, [_box(32, 8, 2)], Callable(), true)
	w._rp_ensure()
	var best := 0
	for i in 90:
		w.step(1.0 / 60.0)
		best = maxi(best, w.contact_pair_count())
	print("contact_pair_count 最大 = %d" % best)
	var pts: Array = w.contact_points(0)
	print("contact_points(0) -> %d 个点" % pts.size())
	var s := 0.0
	for p in pts:
		s += absf(p["impulse"])
		print("  pos=(%.2f,%.2f) dist=%.3f 冲量=%.4f fid=(%d,%d)" % [
			p["position"].x, p["position"].y, p["dist"], p["impulse"], p["fid1"], p["fid2"]])
	print("各点冲量之和 = %.4f" % s)
	var g: Dictionary = w.contact_info(0)
	print("contact_info(0)：点数=%d 总冲量=%.4f id=(%d,%d)" % [
		(g["points"] as Array).size(), g["total_impulse"], g["id_a"], g["id_b"]])
	print("  => 各点冲量之和 / 总冲量 = %.4f（共同分配预算的份额之和）" % (s / maxf(g["total_impulse"], 1e-9)))
	quit(0)
