extends SceneTree
## 幽灵碰撞诊断 —— Rapier issue #669（box2d 的 "ghost collisions"）的移植版。
##
## 现象：物体滑过**由多段拼接成的表面**时被**内部边**绊住 ——
## 接缝处冒出一个**水平法向**的接触，把物体向后推；力臂又大，于是瞬间打转。
##
## 机制（实测）：
##   方块底面陷进地面 penetration_slop 之内的 0.164 px，
##   于是它的**底边**落进了下一段**左端面**的竖直范围内；
##   SAT 一算，水平间距 0.66 < 推测边际 1.5 → 生成一个水平法向的推测接触。
##   那个面**不是表面**（它被相邻的一段盖住了），但 SAT 看不见这件事。
##
## Rapier/parry 的 `compound_pseudo_normals.rs` 注释几乎就是在描述这个：
##   "each part is convex and reports contacts against its own faces regardless,
##    so a body sliding across a join catches on a face that is not a surface."
## 它的修法是**结构性的**：把被兄弟块盖住的"切割边"从边界里去掉，
## 再把接触法向投影进剩余边界边的**法向锥**；投影不进去的接触直接丢弃。
##
## 判据照抄 Rapier 的回归测试：
##   · x 不许倒退   · y 不许弹跳（偏离静止高度）   · 总位移对得上驱动速度（5% 以内）
##
## 用法：改完窄相 / 推测接触 / 矩形分解之后跑一遍。三种地面形态必须**都是 OK**。
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

func _block_at(x: int, y: int, w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	s.fill_rect(Rect2i(x, y, w, h), 1)
	return s

const SEG := 20          # 每段宽
const SEGS := 60         # 段数 → 1200 px 长的地面
const SPEED := 120.0     # px/s
const STEPS := 600       # → 1200 px
const BOX := 16

## mode: "solid" 一整块 / "onebody" 同一 body 两段（1 条内部边）/ "manybody" 60 个独立静态体
func _scene(mode: String) -> PWorld:
	var w := PWorld.new()
	w.sleeping_enabled = false
	w.ccd_enabled = false          # 先看纯粹的接触行为，不让子步掺进来
	if mode == "solid":
		var g := PBody.new()
		g.make_static()
		w.add_body(g, [_block_at(0, 0, SEG * SEGS, 40)])
	elif mode == "onebody":
		var g2 := PBody.new()
		g2.make_static()
		var half := SEG * SEGS / 2
		w.add_body(g2, [_block_at(0, 0, half, 40), _block_at(half, 0, half, 40)])
	elif mode == "manybody":
		for i in SEGS:
			var gi := PBody.new()
			gi.position = Vector2(float(i * SEG), 0.0)
			gi.make_static()
			w.add_body(gi, [_block_at(0, 0, SEG, 40)])
	var b := PBody.new()
	b.position = Vector2(10.0, -float(BOX))
	w.add_body(b, [_block_at(0, 0, BOX, BOX)])
	return w

func _run(mode: String, label: String) -> void:
	var w := _scene(mode)
	var b: PBody = w.bodies[w.bodies.size() - 1]
	for i in 60:
		w.step(1.0 / 60.0)
	var rest_y := b.position.y
	var start_x := b.position.x
	var prev_x := start_x
	var backwards := 0
	var max_dy := 0.0
	var worst_step := -1
	var first_spin := -1
	for i in STEPS:
		b.linear_velocity = Vector2(SPEED, b.linear_velocity.y)
		w.step(1.0 / 60.0)
		if b.position.x - prev_x < -1.0e-6:
			backwards += 1
		var dy: float = absf(b.position.y - rest_y)
		if dy > max_dy:
			max_dy = dy
			worst_step = i
		if first_spin < 0 and absf(rad_to_deg(b.rotation)) > 5.0:
			first_spin = i
		prev_x = b.position.x
	var traveled := prev_x - start_x
	var expected := SPEED * (1.0 / 60.0) * float(STEPS)
	var err := absf(traveled - expected) / expected
	var ok := backwards == 0 and err < 0.05 and max_dy < 1.0
	print("%-32s 前进 %8.2f / 期望 %8.2f (误差 %5.2f%%) | 倒退 %2d 次 | 最大偏离 %7.4f px (第 %3d 步) | 首次打转 第 %3d 步  %s" % [
		label, traveled, expected, err * 100.0, backwards, max_dy, worst_step, first_spin,
		"OK" if ok else "**有问题**"])

## 接缝处到底冒出什么法向？直接问窄相。
func _seam_normals() -> void:
	print("\n--- 接缝处的接触法向（4 段地面，方块 16x16 从 x=10 起步）---")
	var w := PWorld.new()
	w.sleeping_enabled = false
	w.ccd_enabled = false
	w.contact_events_enabled = true
	for i in 4:
		var gi := PBody.new()
		gi.position = Vector2(float(i * SEG), 0.0)
		gi.make_static()
		w.add_body(gi, [_block_at(0, 0, SEG, 40)])
	var b := PBody.new()
	b.position = Vector2(10.0, -float(BOX))
	w.add_body(b, [_block_at(0, 0, BOX, BOX)])
	for step in 8:
		b.linear_velocity = Vector2(SPEED, b.linear_velocity.y)
		w.step(1.0 / 60.0)
		var line := "  步 %d 方块 x∈[%.2f,%.2f] rot=%7.3f° ω=%8.4f" % [
			step, b.position.x, b.position.x + float(BOX),
			rad_to_deg(b.rotation), b.angular_velocity]
		for c in w.contacts:
			var is_box: bool = (c.a == b or c.b == b)
			if is_box and absf(c.normal.y) < 0.99:
				line += "   <-- **非竖直法向** (%.2f,%.2f) 点(%.2f,%.2f)" % [
					c.normal.x, c.normal.y, c.point.x, c.point.y]
		print(line)

func _initialize() -> void:
	print("=== 幽灵碰撞诊断（Rapier #669 判据）===")
	print("地面 %d 段 x %d px = %d px，方块 %dx%d，驱动 %.0f px/s 走 %d 步\n" % [
		SEGS, SEG, SEG * SEGS, BOX, BOX, SPEED, STEPS])
	_run("solid", "A 一整块（无内部边）")
	_run("onebody", "B 同一 body 两段（1 条内部边）")
	_run("manybody", "C 60 个独立静态体（60 条边）")
	_seam_normals()
	quit(0)
