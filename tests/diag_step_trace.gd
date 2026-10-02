extends SceneTree
## 用真实 step() 追（不手工拆阶段，避免 AABB 陈旧）
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

func _block(w: int, h: int, mat: int = 1) -> PixelShape:
	var s := PixelShape.new()
	for y in h:
		for x in w:
			s.set_pixel(x, y, mat)
	return s

func _run(tag: String, maxsub: int) -> void:
	var w := PWorld.new()
	w.gravity = Vector2.ZERO
	if maxsub > 0:
		w.ccd_max_substeps = maxsub
	var wall := PBody.new()
	wall.position = Vector2(200, 0)
	wall.make_static()
	w.add_body(wall, [_block(8, 200)])
	var b := PBody.new()
	b.position = Vector2(50, 100)
	w.add_body(b, [_block(12, 12)])
	b.linear_velocity = Vector2(600, 0)
	print("=== %s（上限 %d 子步）===" % [tag, maxsub])
	for f in 120:
		w.step(1.0 / 60.0)
		if f % 20 == 0 or f > 100:
			print("  帧%3d x=%9.3f vx=%9.2f w=%9.3f rot=%.5f 子步=%2d 流形=%d 点数=%d" % [
				f, b.position.x, b.linear_velocity.x, b.angular_velocity, b.rotation,
				w.last_substeps, w._bp_count, w.last_contacts])

func _initialize() -> void:
	_run("默认（细分到每子步 2 单位）", 0)

	quit(0)
