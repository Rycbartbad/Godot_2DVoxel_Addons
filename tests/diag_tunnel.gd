extends SceneTree
## 穿模探针：薄几何 + 高速物体。
## Rapier 的 prediction_distance 默认 0.02 px（按米调的）等于没有推测接触，
## 快物体一步跨过薄墙就穿过去了。引擎原本的 max_speculative_margin 是 1.5 px。
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

func _block(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, w, h), 1)
	return s

## 墙厚 thickness、速度 speed，看方块能不能被挡住。
func _trial(thickness: int, speed: float, label: String) -> void:
	var w := PWorld.new()
	w.gravity = Vector2.ZERO
	var wall := PBody.new()
	wall.position = Vector2(200.0, -100.0)
	wall.make_static()
	w.add_body(wall, [_block(thickness, 200)])
	var b := PBody.new()
	b.position = Vector2(0.0, 0.0)
	w.add_body(b, [_block(8, 8)])
	b.linear_velocity = Vector2(speed, 0.0)
	var passed := false
	for i in 120:
		w.step(1.0 / 60.0)
		if b.position.x > 220.0:
			passed = true
			break
	print("  %-26s 墙厚 %2d px  速度 %6.0f px/s（每步 %5.2f px）-> %s  x=%.1f" % [
		label, thickness, speed, speed / 60.0,
		"**穿过去了**" if passed else "被挡住 OK", b.position.x])

func _initialize() -> void:
	print("=== 穿模探针（推测接触距离 = %.1f px）===" % PWorld.new().rp_prediction_distance)
	for sp in [200.0, 600.0, 1200.0, 2000.0, 3000.0]:
		_trial(4, sp, "薄墙")
	print("")
	for sp2 in [600.0, 2000.0]:
		_trial(16, sp2, "厚墙")
	quit(0)
