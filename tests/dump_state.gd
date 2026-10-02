extends SceneTree
## 求解器改动的**行为等价性**参照：把若干场景跑固定步数后的刚体状态原样打出来。
## 优化前后各跑一次、diff 一下，就能确认"是否逐位一致"，
## 而不是靠"测试都过了"这种弱证据。
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

func _block(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	for y in h:
		for x in w:
			s.set_pixel(x, y, 1)
	return s

## ⚠️ 休眠场景单独成一份：dump 默认是**关休眠**的（那是纯求解器行为），
## 但休眠同样会改变物理结果。这个 harness 一开始漏了这一点 ——
## "改休眠判据"这种改动它一个字都不会变，等于没有等价性判据。
func _build_sleeping(kind: String) -> PWorld:
	var world := PWorld.new()
	world.sleeping_enabled = true
	var g := PBody.new()
	g.position = Vector2(-2000.0, 0.0)
	g.make_static()
	world.add_body(g, [_block(4000, 40)])
	if kind == "sleep_frag":
		for i in 120:
			var f := PBody.new()
			f.position = Vector2(-400.0 + float(i % 30) * 14.0, -200.0 - float(i / 30) * 14.0)
			world.add_body(f, [_block(6, 6)])
			f.linear_velocity = Vector2(-40.0 + float(i % 7) * 12.0, 30.0)
	elif kind == "sleep_box":
		for i2 in 12:
			var b := PBody.new()
			b.position = Vector2(-100.0 + float(i2 % 4) * 18.0, -9.0 - float(i2 / 4) * 18.0)
			world.add_body(b, [_block(16, 16)])
	return world

func _dump_sleep(kind: String, steps: int) -> void:
	var world := _build_sleeping(kind)
	for i in steps:
		world.step(1.0 / 60.0)
	var acc := 0.0
	var awake := 0
	for b in world.bodies:
		if b.is_static:
			continue
		if b.awake:
			awake += 1
		acc += b.position.x * 0.001 + b.position.y * 0.01 + b.rotation * 0.1 			+ b.linear_velocity.x * 0.0001 + b.linear_velocity.y * 0.00001
	print("%-12s steps=%-4d 状态摘要 %.12f | 仍清醒 %d/%d" % [
		kind, steps, acc, awake, world.bodies.size() - 1])

func _build(kind: String) -> PWorld:
	var world := PWorld.new()
	world.sleeping_enabled = false
	world.ccd_enabled = false
	world.use_threads = false
	var g := PBody.new()
	g.position = Vector2(-2000.0, 0.0)
	g.make_static()
	world.add_body(g, [_block(4000, 40)])
	var parts := kind.split(":")
	match parts[0]:
		"stack":
			for c in int(parts[1]):
				for r in int(parts[2]):
					var b := PBody.new()
					b.position = Vector2(-200.0 + float(c) * 60.0, -7.0 - float(r) * 14.0)
					world.add_body(b, [_block(14, 14)])
		"pile":
			for r2 in int(parts[2]):
				for c2 in int(parts[1]):
					var b2 := PBody.new()
					b2.position = Vector2(-200.0 + float(c2) * 14.0 + 7.0, -7.0 - float(r2) * 14.0)
					world.add_body(b2, [_block(14, 14)])
		"frags":
			for i in int(parts[1]):
				var f := PBody.new()
				f.position = Vector2(-1200.0 + float(i % 60) * 12.0, -400.0 - float(i / 60) * 14.0)
				world.add_body(f, [_block(4, 4)])
				f.linear_velocity = Vector2(-120.0 + float(i % 13) * 20.0, 100.0)
		"mixed":
			for c3 in 6:
				for r3 in 5:
					var b3 := PBody.new()
					b3.position = Vector2(-200.0 + float(c3) * 60.0, -7.0 - float(r3) * 14.0)
					world.add_body(b3, [_block(14, 14)])
			for i2 in 60:
				var f2 := PBody.new()
				f2.position = Vector2(200.0 + float(i2 % 20) * 10.0, -300.0 - float(i2 / 20) * 10.0)
				world.add_body(f2, [_block(6, 6)])
	return world

func _dump(kind: String, steps: int) -> void:
	var world := _build(kind)
	for i in steps:
		world.step(1.0 / 60.0)
	var acc := 0.0
	for b in world.bodies:
		if b.is_static:
			continue
		acc += b.position.x * 0.001 + b.position.y * 0.01 + b.rotation * 0.1 \
			+ b.linear_velocity.x * 0.0001 + b.linear_velocity.y * 0.00001 + b.angular_velocity * 0.001
	print("%-12s steps=%-4d 状态摘要 %.12f | 质心和 %.6f %.6f" % [
		kind, steps, acc,
		world.bodies[1].position.x if world.bodies.size() > 1 else 0.0,
		world.bodies[1].position.y if world.bodies.size() > 1 else 0.0])

func _initialize() -> void:
	print("=== 求解器行为参照 dump ===")
	for spec in [["stack:6:5", 300], ["pile:8:6", 300], ["frags:240", 300],
			["mixed", 300], ["stack:2:3", 900], ["pile:4:4", 900]]:
		_dump(spec[0], spec[1])
	print("--- 休眠场景（这一组测的是休眠判据本身）---")
	_dump_sleep("sleep_box", 600)
	_dump_sleep("sleep_frag", 1200)
	quit(0)
