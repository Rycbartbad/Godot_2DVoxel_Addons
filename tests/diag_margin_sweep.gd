extends SceneTree
## 推测边际的参数扫描：接触点修对之后，边际该取多大？
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

func _block(w: int, h: int, mat: int = 1) -> PixelShape:
	var s := PixelShape.new()
	for y in h:
		for x in w:
			s.set_pixel(x, y, mat)
	return s

func _wall(world: PWorld, x: float, y: float, w: int, h: int) -> PBody:
	var b := PBody.new()
	b.position = Vector2(x, y)
	b.make_static()
	world.add_body(b, [_block(w, h)])
	return b

## 休眠场景：12 个 16x16 箱子，600 步后应当全部睡着
func _sleep(margin: float) -> String:
	var w := PWorld.new()
	w.max_speculative_margin = margin
	var g := PBody.new()
	g.position = Vector2(-2000.0, 0.0)
	g.make_static()
	w.add_body(g, [_block(4000, 40)])
	for i2 in 12:
		var b := PBody.new()
		b.position = Vector2(-100.0 + float(i2 % 4) * 18.0, -9.0 - float(i2 / 4) * 18.0)
		w.add_body(b, [_block(16, 16)])
	for i in 600:
		w.step(1.0 / 60.0)
	var awake := 0
	var acc := 0.0
	for b in w.bodies:
		if b.is_static:
			continue
		if b.awake:
			awake += 1
		acc += b.position.x * 0.001 + b.position.y * 0.01 + b.rotation * 0.1
	return "醒%2d/12 acc=%9.4f" % [awake, acc]

## 三层堆叠漂移
func _stack(margin: float) -> String:
	var w := PWorld.new()
	w.max_speculative_margin = margin
	w.sleeping_enabled = true
	var g := PBody.new()
	g.position = Vector2(-600.0, 300.0)
	g.make_static()
	w.add_body(g, [_block(1200, 40)])
	for i in 3:
		var b := PBody.new()
		b.position = Vector2(100.0, 200.0 - 16.0 * float(i + 1))
		w.add_body(b, [_block(16, 16)])
	for i in 300:
		w.step(1.0 / 60.0)
	var top: PBody = null
	var ty := 1.0e18
	for b in w.bodies:
		if b.is_static:
			continue
		if b.position.y < ty:
			ty = b.position.y
			top = b
	return "顶层 x=%8.4f rot=%9.6f" % [top.position.x, top.rotation]

## 高速撞 8 像素薄墙
func _tunnel(margin: float, speed: float) -> String:
	var w := PWorld.new()
	w.max_speculative_margin = margin
	w.gravity = Vector2.ZERO
	_wall(w, 200, 0, 8, 200)
	var b := PBody.new()
	b.position = Vector2(50, 100)
	w.add_body(b, [_block(12, 12)])
	b.linear_velocity = Vector2(speed, 0)
	for i in 120:
		w.step(1.0 / 60.0)
	return "x=%9.2f" % b.position.x

## 落地误差（40 厚墙，看嵌入）
func _embed(margin: float, speed: float) -> String:
	var w := PWorld.new()
	w.max_speculative_margin = margin
	w.gravity = Vector2.ZERO
	_wall(w, 200, 0, 40, 200)
	var b := PBody.new()
	b.position = Vector2(100, 100)
	w.add_body(b, [_block(12, 12)])
	b.linear_velocity = Vector2(speed, 0)
	var worst := 0.0
	for i in 180:
		w.step(1.0 / 60.0)
		worst = maxf(worst, (b.position.x + 12.0) - 200.0)
	return "最大嵌入 %6.2f" % worst

func _initialize() -> void:
	print("边际 | 休眠 | 堆叠漂移 | 撞墙600 | 撞墙3000 | 撞墙6000 | 嵌入3000")
	for margin in [2.0, 8.0, 32.0, 128.0]:
		print("%6.1f | %s | %s | %s | %s | %s | %s" % [
			margin, _sleep(margin), _stack(margin),
			_tunnel(margin, 600.0), _tunnel(margin, 3000.0), _tunnel(margin, 6000.0),
			_embed(margin, 3000.0)])
	quit(0)
