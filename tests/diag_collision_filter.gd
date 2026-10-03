extends SceneTree
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

func _box(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	for y in h:
		for x in w:
			s.set_pixel(x, y, 1)
	return s

func _run(label: String, a_layer: int, a_mask: int, b_layer: int, b_mask: int) -> void:
	var world := PWorld.new()
	world.gravity = Vector2.ZERO
	var a := PBody.new()
	a.position = Vector2(100, 100)
	a.collision_layer = a_layer
	a.collision_mask = a_mask
	a.linear_velocity = Vector2(120, 0)
	world.add_body(a, [_box(16, 16)])
	var b := PBody.new()
	b.position = Vector2(140, 100)
	b.collision_layer = b_layer
	b.collision_mask = b_mask
	world.add_body(b, [_box(16, 16)])
	var trace := ""
	for i in 60:
		world.step(1.0 / 60.0)
		if i % 15 == 0:
			trace += "[%d ax=%.1f vx=%.1f c=%d] " % [i, a.position.x, a.linear_velocity.x, world.last_contacts]
	print("%s: %s -> ax=%.2f  (a.rp=%d b.rp=%d a._rp_layer=%d a._rp_mask=%d)" % [
		label, trace, a.position.x, a.rapier_id, b.rapier_id, a._rp_layer, a._rp_mask])

func _initialize() -> void:
	_run("default  ", 1, 0xFFFFFFFF, 1, 0xFFFFFFFF)
	_run("L1 vs L2 ", 1, 0xFFFFFFFF, 2, 0xFFFFFFFF)
	_run("L1m1/L2  ", 1, 1, 2, 0xFFFFFFFF)
	_run("both agr ", 1, 2, 2, 1)
	quit(0)
