extends SceneTree
## 回答"刚体变成场景节点会不会影响性能"
##
## 做法：同样 500 个刚体，两种来源各跑一遍，比 step() 耗时。
## 关键设计：节点只在 _ready 烘焙一次成 RefCounted，之后热循环不碰 Node。
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")
const PixelBody2D := preload("res://src/nodes/pixel_body_2d.gd")
const PixelWorld := preload("res://src/nodes/pixel_world.gd")

const N := 500
const STEPS := 120
const DT := 1.0 / 60.0

func _box(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, w, h), 1)
	return s

## 地面 + N 个方块，位置完全一样
func _layout(i: int) -> Vector2:
	return Vector2(-400.0 + float(i % 40) * 20.0, -20.0 - float(i / 40) * 20.0)

## ---- A. 纯代码构建 ----
func _build_code() -> PWorld:
	var w := PWorld.new()
	var g := PBody.new()
	g.position = Vector2(-500.0, 0.0)
	g.make_static()
	w.add_body(g, [_box(1000, 40)])
	for i in N:
		var b := PBody.new()
		b.position = _layout(i)
		w.add_body(b, [_box(14, 14)])
	return w

## ---- B. 场景节点构建 ----
func _build_nodes() -> PixelWorld:
	var pw := PixelWorld.new()
	root.add_child(pw)
	var g := PixelBody2D.new()
	g.position = Vector2(-500.0, 0.0)
	g.rect_size = Vector2i(1000, 40)
	g.is_static = true
	pw.add_child(g)
	for i in N:
		var n := PixelBody2D.new()
		n.position = _layout(i)
		n.rect_size = Vector2i(14, 14)
		pw.add_child(n)
	return pw

func _hash(world: PWorld) -> float:
	var h := 0.0
	for b in world.bodies:
		h += b.position.x * 0.001 + b.position.y * 1.7 + b.rotation * 13.0
	return h

func _initialize() -> void:
	print("=== A. 纯代码构建 %d 个刚体 ===" % N)
	var t0 := Time.get_ticks_usec()
	var wa := _build_code()
	var t1 := Time.get_ticks_usec()
	for i in 20:
		wa.step(DT)
	var ta0 := Time.get_ticks_usec()
	for i in STEPS:
		wa.step(DT)
	var ta1 := Time.get_ticks_usec()
	var code_build := t1 - t0
	var code_step := ta1 - ta0
	print("  构建 %.1f ms | %d 步 %.1f ms（每步 %.3f ms）" % [
		code_build / 1000.0, STEPS, code_step / 1000.0, code_step / 1000.0 / STEPS])
	print("  状态校验和 %.6f" % _hash(wa))

	print("=== B. 场景节点构建 %d 个刚体 ===" % N)
	var t2 := Time.get_ticks_usec()
	var pw := _build_nodes()
	# ⚠️ 裸 SceneTree 脚本里 add_child 触发的 _ready() 是**延迟**的，
	#    这里要显式确认烘焙完成（正常游戏里 _ready 早于你的代码，不需要这句）。
	if pw.world == null:
		pw.rebuild()
	var t3 := Time.get_ticks_usec()
	for i in 20:
		pw.world.step(DT)
	var tb0 := Time.get_ticks_usec()
	for i in STEPS:
		pw.world.step(DT)
	var tb1 := Time.get_ticks_usec()
	var node_build := t3 - t2
	var node_step := tb1 - tb0
	print("  构建 %.1f ms | %d 步 %.1f ms（每步 %.3f ms）" % [
		node_build / 1000.0, STEPS, node_step / 1000.0, node_step / 1000.0 / STEPS])
	print("  状态校验和 %.6f" % _hash(pw.world))

	print("=== 结论 ===")
	var d := absf(float(node_step) - float(code_step)) / maxf(1.0, float(code_step))
	print("  step() 差异 %.4f%%（噪声范围内即为相同）" % (d * 100.0))
	print("  每步差 %.4f ms" % ((float(node_step) - float(code_step)) / 1000.0 / STEPS))
	print("  一次性烘焙成本 %.1f ms（%.2f ms/刚体，只在 _ready 发生一次）" % [
		(node_build - code_build) / 1000.0, (node_build - code_build) / 1000.0 / N])
	print("  刚体数 %d vs %d" % [wa.bodies.size(), pw.world.bodies.size()])
	quit(0)
