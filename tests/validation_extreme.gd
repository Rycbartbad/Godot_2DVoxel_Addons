extends SceneTree
## 极端情况压力测试：逐项推到失效，找出真实边界
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

func _block(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	for y in h:
		for x in w:
			s.set_pixel(x, y, 1)
	return s

func _wall(world: PWorld, x: float, y: float, w: int, h: int) -> PBody:
	var b := PBody.new()
	b.position = Vector2(x, y)
	b.make_static()
	world.add_body(b, [_block(w, h)])
	return b

## 返回 [是否穿过, 最终x, 最大嵌入深度]
func _hit_test(speed: float, wall_w: int, box: int, steps: int = 180) -> Array:
	var world := PWorld.new()
	world.gravity = Vector2.ZERO
	_wall(world, 200, 0, wall_w, 300)
	var b := PBody.new()
	b.position = Vector2(60, 140)
	world.add_body(b, [_block(box, box)])
	if speed > 8000.0:
		b.ccd = true       # 超高速物体交给扫掠 CCD
	b.linear_velocity = Vector2(speed, 0)
	var worst := 0.0
	for i in steps:
		world.step(1.0 / 60.0)
		worst = maxf(worst, (b.position.x + box) - 200.0)
	return [b.position.x > 240.0, b.position.x, worst]

func _initialize() -> void:
	print("=== 极端情况压力测试 ===")
	print("\n[A] 速度扫描 (1 像素薄墙, 12x12 箱子)")
	print("   速度        每步位移   结果")
	for sp in [1000.0, 5000.0, 20000.0, 50000.0, 200000.0, 1000000.0]:
		var r := _hit_test(sp, 1, 12)
		print("   %9.0f  %8.1f   %s" % [sp, sp / 60.0, "穿过!" if r[0] else "挡住 (x=%.1f, 最深嵌入 %.1f)" % [r[1], r[2]]])

	print("\n[B] 薄墙扫描 (速度 5000 px/s, 12x12 箱子)")
	for w in [1, 2, 4, 8]:
		var r2 := _hit_test(5000.0, w, 12)
		print("   墙厚 %2d px: %s" % [w, "穿过!" if r2[0] else "挡住"])

	print("\n[C] 微小高速弹丸 (2x2)")
	for cfg in [[5000.0, 1, false], [5000.0, 4, false], [20000.0, 1, true]]:
		var world := PWorld.new()
		world.gravity = Vector2.ZERO
		_wall(world, 200, 0, cfg[1], 300)
		var pb2 := PBody.new()
		pb2.position = Vector2(60, 140)
		world.add_body(pb2, [_block(2, 2)])
		pb2.ccd = cfg[2]
		pb2.linear_velocity = Vector2(cfg[0], 0)
		for i in 120:
			world.step(1.0 / 60.0)
		print("   速度 %6.0f, 墙厚 %d px, ccd=%-5s: %s (x=%.1f)" % [
			cfg[0], cfg[1], str(cfg[2]), "穿过!" if pb2.position.x > 240.0 else "挡住", pb2.position.x])

	print("\n[D] 时间步尖峰 (一帧 advance(0.25s), 箱子以 3000 px/s 撞 4px 墙)")
	var wd := PWorld.new()
	wd.gravity = Vector2.ZERO
	_wall(wd, 200, 0, 4, 300)
	var bd := PBody.new()
	bd.position = Vector2(60, 140)
	wd.add_body(bd, [_block(12, 12)])
	bd.linear_velocity = Vector2(3000, 0)
	var spike_steps := wd.advance(0.25)
	for i in 30:
		wd.step(1.0 / 60.0)
	print("   advance(0.25) 跑了 %d 个子步, 结果: %s (x=%.1f)" % [spike_steps, "穿过!" if bd.position.x > 240.0 else "挡住", bd.position.x])

	print("\n[E] 极深重叠 (两个 20x20 重叠 90%%)")
	var we := PWorld.new()
	we.gravity = Vector2.ZERO
	var ea := PBody.new()
	ea.position = Vector2(100, 100)
	we.add_body(ea, [_block(20, 20)])
	var eb := PBody.new()
	eb.position = Vector2(118, 100)
	we.add_body(eb, [_block(20, 20)])
	var g0 := eb.position.x - (ea.position.x + 20.0)
	for i in 300:
		we.step(1.0 / 60.0)
	var g1 := eb.position.x - (ea.position.x + 20.0)
	print("   间隙 %.1f -> %.2f px  %s" % [g0, g1, "已分离" if g1 > -1.0 else "分不开!"])

	print("\n[F] 极端质量比 1000:1 (重块压在轻块上)")
	var wf := PWorld.new()
	var gf := PBody.new()
	gf.position = Vector2(0, 300)
	gf.make_static()
	wf.add_body(gf, [_block(200, 20)])
	var heavy := PixelShape.new()
	for y in 100:
		for x in 100:
			heavy.set_pixel(x, y, 1)
	var hb := PBody.new()
	hb.position = Vector2(80, 80)
	wf.add_body(hb, [heavy])
	var light := PBody.new()
	light.position = Vector2(100, 260)
	wf.add_body(light, [_block(20, 20)])
	var mh := hb.mass
	var ml := light.mass
	for i in 400:
		wf.step(1.0 / 60.0)
	print("   质量比 %.0f:1, 轻块最终 y=%.1f (地面顶 300, 期望 ~280)  %s" % [
		mh / ml, light.position.y, "正常" if light.position.y > 250.0 else "被压穿了!"])

	print("\n[G] 高速自转细杆 (60x4, 40 rad/s) 扫过墙面")
	var wg := PWorld.new()
	wg.gravity = Vector2.ZERO
	_wall(wg, 300, 0, 8, 400)
	var rod := PixelShape.new()
	for y in 4:
		for x in 60:
			rod.set_pixel(x, y, 1)
	var rb := PBody.new()
	rb.position = Vector2(240, 200)
	wg.add_body(rb, [rod])
	rb.angular_velocity = 40.0
	for i in 180:
		wg.step(1.0 / 60.0)
	print("   最终位置 x=%.1f (墙面 300)  %s" % [rb.position.x, "没插进墙里" if rb.position.x < 300.0 else "插进墙里了!"])

	print("\n[H] 极远坐标 (x = 1,000,000)")
	var wh := PWorld.new()
	_wall(wh, 1000000.0, 300, 100, 20)
	var hb2 := PBody.new()
	hb2.position = Vector2(1000000.0 + 40.0, 200)
	wh.add_body(hb2, [_block(16, 16)])
	for i in 300:
		wh.step(1.0 / 60.0)
	print("   落地后底边 y=%.3f (地面顶 300)  误差 %.3f px" % [hb2.aabb.end.y, absf(hb2.aabb.end.y - 300.0)])
	quit(0)
