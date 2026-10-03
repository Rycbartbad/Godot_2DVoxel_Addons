extends SceneTree
## 运行中改几何：破坏/擦除后 rebuild() 有没有把新矩形同步给 Rapier？
##
## 这是 demo 穿模最可疑的一条路径 —— 静态/动态体在**运行中**换形状，
## 如果新矩形没推过去，Rapier 那边还是旧碰撞体（或干脆没有），就会穿。
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

func _block(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, w, h), 1)
	return s

func _initialize() -> void:
	print("=== 运行中改几何 -> Rapier 同步 ===")

	# 1) 动态体：飞行途中把 8x8 换成 40x40，之后应当按新尺寸被挡住
	var w := PWorld.new()
	w.gravity = Vector2.ZERO
	var wall := PBody.new()
	wall.position = Vector2(200.0, -100.0)
	wall.make_static()
	w.add_body(wall, [_block(4, 200)])
	var b := PBody.new()
	b.position = Vector2(0.0, -20.0)
	w.add_body(b, [_block(8, 8)])
	b.linear_velocity = Vector2(600.0, 0.0)
	for i in 10:
		w.step(1.0 / 60.0)
	print("换形状前：位置 x=%.2f  rects=%d  rects_rev=%d" % [b.position.x, b.rects.size(), b.rects_rev])
	b.rebuild([_block(40, 40)], w.density_callable(), w.max_rects_per_shape)
	print("rebuild 后：rects=%d  rects_rev=%d" % [b.rects.size(), b.rects_rev])
	for i in 60:
		w.step(1.0 / 60.0)
	print("换形状后：位置 x=%.2f（应当被墙挡住，x 明显小于 220）" % b.position.x)

	# 2) 静态体：运行中加一段墙，飞来的物体应当被挡住
	var w2 := PWorld.new()
	w2.gravity = Vector2.ZERO
	var wb := PBody.new()
	wb.position = Vector2(200.0, -100.0)
	wb.make_static()
	w2.add_body(wb, [_block(4, 4)])          # 先给一小块
	var b2 := PBody.new()
	b2.position = Vector2(0.0, 0.0)
	w2.add_body(b2, [_block(8, 8)])
	b2.linear_velocity = Vector2(600.0, 0.0)
	for i in 5:
		w2.step(1.0 / 60.0)
	# 运行中把墙加高
	wb.rebuild([_block(4, 200)], w2.density_callable(), w2.max_rects_per_shape)
	for i in 60:
		w2.step(1.0 / 60.0)
	print("静态体加高后：x=%.2f（应当被挡住）" % b2.position.x)
	quit(0)
