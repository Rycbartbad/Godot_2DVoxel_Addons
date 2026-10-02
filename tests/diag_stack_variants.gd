extends SceneTree
## 找出"三个方块叠起来会抖"的具体配置
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

func _block(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, w, h), 1)
	return s

## 返回 [后段极差, 是否睡着, 末速度]
func _run(name: String, size: float, gap: float, dx: Array, rot: Array, steps: int = 240) -> void:
	var w := PWorld.new()
	var g := PBody.new()
	g.position = Vector2(-300.0, 400.0)
	g.make_static()
	w.add_body(g, [_block(600, 40)])
	var boxes: Array = []
	for i in 3:
		var b := PBody.new()
		b.position = Vector2(dx[i], 400.0 - size * (i + 1) - gap * (i + 1))
		b.rotation = rot[i]
		w.add_body(b, [_block(int(size), int(size))])
		boxes.append(b)
	var hist: Array = []
	for step in steps:
		w.step(1.0 / 60.0)
		if step >= steps - 60:
			hist.append([boxes[0].position.y, boxes[1].position.y, boxes[2].position.y,
				boxes[0].rotation, boxes[1].rotation, boxes[2].rotation])
	var worst := 0.0
	var worst_pos := 0.0
	var worst_rot := 0.0
	for i in 3:
		var lo := 1e9
		var hi := -1e9
		for h in hist:
			lo = minf(lo, h[i])
			hi = maxf(hi, h[i])
		worst_pos = maxf(worst_pos, hi - lo)
		worst = maxf(worst, hi - lo)
	for i in 3:
		var lo := 1e9
		var hi := -1e9
		for h in hist:
			lo = minf(lo, h[3 + i])
			hi = maxf(hi, h[3 + i])
		worst_rot = maxf(worst_rot, hi - lo)
	var awake := 0
	for b in boxes:
		if b.awake:
			awake += 1
	print("  %-34s 位置极差 %8.5f px   转角极差 %8.6f rad   清醒 %d/3" % [
		name, worst_pos, worst_rot, awake])

func _initialize() -> void:
	print("=== 变体对照（都静置 240 步，看后 60 步）===")
	_run("A 完美对齐、无间隙", 20.0, 0.0, [0.0, 0.0, 0.0], [0.0, 0.0, 0.0])
	_run("B 完美对齐、留 2px 间隙", 20.0, 2.0, [0.0, 0.0, 0.0], [0.0, 0.0, 0.0])
	_run("C 完美对齐、留 8px 间隙", 20.0, 8.0, [0.0, 0.0, 0.0], [0.0, 0.0, 0.0])
	_run("D x 偏移 1px", 20.0, 0.0, [0.0, 1.0, 0.0], [0.0, 0.0, 0.0])
	_run("E x 偏移 3px", 20.0, 0.0, [0.0, 3.0, -2.0], [0.0, 0.0, 0.0])
	_run("F 带 0.02 rad 初始转角", 20.0, 0.0, [0.0, 0.0, 0.0], [0.0, 0.02, -0.02])
	_run("G 带 0.1 rad 初始转角", 20.0, 0.0, [0.0, 0.0, 0.0], [0.0, 0.1, -0.1])
	_run("H 大块 40x40 对齐", 40.0, 0.0, [0.0, 0.0, 0.0], [0.0, 0.0, 0.0])
	_run("I 大块 40x40 + 间隙", 40.0, 4.0, [0.0, 0.0, 0.0], [0.0, 0.0, 0.0])
	_run("J 完美对齐、1px 间隙", 20.0, 1.0, [0.0, 0.0, 0.0], [0.0, 0.0, 0.0])
	quit(0)
