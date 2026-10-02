extends SceneTree
## 复现两类问题：高速嵌入/隧穿 + 嵌入后的粘黏

const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")
const Destruction := preload("res://src/core/destruction.gd")

func _block(w: int, h: int, mat: int = 1) -> PixelShape:
	var s := PixelShape.new()
	for y in h:
		for x in w:
			s.set_pixel(x, y, mat)
	return s

func _wall(world: PWorld, x: float, y: float, w: int, h: int):
	var b := PBody.new()
	b.position = Vector2(x, y)
	b.make_static()
	world.add_body(b, [_block(w, h)])
	return b

func _initialize() -> void:
	print("=== 高速 / 嵌入 / 粘黏 诊断 ===")
	_test_tunnel()
	_test_embed_depth()
	_test_stick_overlap()
	_test_pull_out()
	quit(0)


## 真·粘黏测试：两个嵌在一起的动态体，给其中一个离开对方的速度，看能不能干净地分开
func _check_stick_pull() -> void:
	print("\n[粘黏] 互相重叠的动态体能否被干净地拉开")
	var world := PWorld.new()
	world.gravity = Vector2.ZERO
	var a := PBody.new()
	a.position = Vector2(100, 100)
	world.add_body(a, [_block(20, 20)])
	var b := PBody.new()
	b.position = Vector2(108, 100)
	world.add_body(b, [_block(20, 20)])
	a.linear_velocity = Vector2(-400, 0)
	for i in 60:
		world.step(1.0 / 60.0)
	var dx_a := a.position.x - 100.0
	var dx_b := b.position.x - 108.0
	print("  给 A 一个 -400 px/s 的离开速度，1 秒后：A 位移 %7.2f px | B 位移 %7.2f px  %s" % [
		dx_a, dx_b, "-> 分开且没带走 B" if dx_a < -250.0 and absf(dx_b) < 40.0 else "-> 被拖住了!"])


## 深嵌物体的切向自由度：位置修正不应该凭空产生摩擦把它钉住
func _check_tangential_slide() -> void:
	print("\n[粘黏] 深嵌物体在无正压力时不应被「钉」住")
	var world := PWorld.new()
	world.gravity = Vector2.ZERO
	var wall := PBody.new()
	wall.position = Vector2(200, 0)
	wall.make_static()
	world.add_body(wall, [_block(40, 400)])
	var box := PBody.new()
	box.position = Vector2(200.0 - 12.0 + 8.0, 100)
	world.add_body(box, [_block(12, 12)])
	var pen0 := (box.position.x + 12.0) - 200.0
	box.linear_velocity = Vector2(0, 300)      # 纯切向
	for i in 60:
		world.step(1.0 / 60.0)
	print("  嵌入 %5.2f px 后给 300 px/s 纯切向速度：1 秒后 y 位移 %7.2f px (期望接近 300)  %s" % [
		pen0, box.position.y - 100.0,
		"-> 自由滑动" if box.position.y - 100.0 > 200.0 else "-> 被摩擦钉住了!"])

func _test_tunnel() -> void:
	print("\n[隧穿] 8 像素厚的墙，12x12 箱子水平撞过去")
	for speed in [600.0, 1500.0, 3000.0, 6000.0]:
		var world := PWorld.new()
		world.gravity = Vector2.ZERO
		_wall(world, 200, 0, 8, 200)
		var b := PBody.new()
		b.position = Vector2(50, 100)
		world.add_body(b, [_block(12, 12)])
		b.linear_velocity = Vector2(speed, 0)
		for i in 120:
			world.step(1.0 / 60.0)
		var through := b.position.x > 260.0
		var rest := b.position.x
		print("  速度 %6.0f px/s (每步 %5.1f px): x = %8.2f  %s" % [
			speed, speed / 60.0, rest, "-> 穿过去了!" if through else "(被挡住)"])

func _test_embed_depth() -> void:
	print("\n[嵌入深度] 40 像素厚的墙，箱子水平撞")
	for speed in [300.0, 800.0, 2000.0]:
		var world := PWorld.new()
		world.gravity = Vector2.ZERO
		_wall(world, 200, 0, 40, 200)
		var b := PBody.new()
		b.position = Vector2(100, 100)
		world.add_body(b, [_block(12, 12)])
		b.linear_velocity = Vector2(speed, 0)
		var worst := 0.0
		for i in 180:
			world.step(1.0 / 60.0)
			var pen := (b.position.x + 12.0) - 200.0
			worst = maxf(worst, pen)
		# 稳定后还嵌在里面多少
		var final_pen := maxf(0.0, (b.position.x + 12.0) - 200.0)
		print("  速度 %6.0f: 最大嵌入 %6.2f px | 最终残留嵌入 %6.2f px | 终速 %7.1f" % [
			speed, worst, final_pen, b.linear_velocity.length()])

func _test_stick_overlap() -> void:
	print("\n[粘黏] 两个 20x20 动态箱子初始重叠 10 像素（无重力）")
	var world := PWorld.new()
	world.gravity = Vector2.ZERO
	var a := PBody.new()
	a.position = Vector2(100, 100)
	world.add_body(a, [_block(20, 20)])
	var b := PBody.new()
	b.position = Vector2(110, 100)
	world.add_body(b, [_block(20, 20)])
	for i in 240:
		world.step(1.0 / 60.0)
	var gap := b.position.x - (a.position.x + 20.0)
	var va := a.linear_velocity.length()
	var vb := b.linear_velocity.length()
	# 允许 penetration_slop(0.5) 以内的重叠 —— 那是"静止接触"，不是粘住
	print("  最终间隙 %6.2f px (slop 内为正常接触) | |vA| %6.2f | |vB| %6.2f  %s" % [
		gap, va, vb, "-> 已分离" if gap > -1.0 else "-> 还粘在一起!"])
	_check_stick_pull()
	_check_tangential_slide()

func _test_pull_out() -> void:
	print("\n[深嵌后能否拉出] 12x12 箱子嵌进静态墙 8 像素，然后往外拖")
	var world := PWorld.new()
	world.gravity = Vector2.ZERO
	_wall(world, 200, 100, 40, 60)
	var b := PBody.new()
	b.position = Vector2(200.0 - 12.0 + 8.0, 120)
	world.add_body(b, [_block(12, 12)])
	var pen0 := (b.position.x + 12.0) - 200.0
	world.grab(b, b.com_world(), 20000.0)
	world.set_grab_target(Vector2(120, 126))
	for i in 300:
		world.step(1.0 / 60.0)
	var pen1 := (b.position.x + 12.0) - 200.0
	print("  初始嵌入 %5.2f px -> 拖动 5 秒后 %5.2f px | x=%7.2f (墙左沿 200)  %s" % [
		pen0, pen1, b.position.x, "-> 拉出来了" if pen1 < 0.5 else "-> 被粘住了!"])
