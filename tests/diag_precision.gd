extends SceneTree
## 验证两件事：
## 1) Godot 的 Vector2 到底是不是 float32（这决定了"状态"的精度）
## 2) SoA 求解器算完之后，状态是不是又被舍回 float32
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

func _block(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	for y in h:
		for x in w:
			s.set_pixel(x, y, 1)
	return s

func _initialize() -> void:
	print("=== 1. Vector2 的分量宽度 ===")
	var third := 1.0 / 3.0
	var v := Vector2(third, 0.0)
	print("  float64 1/3 = %.17f" % third)
	print("  Vector2.x   = %.17f" % v.x)
	print("  相等？ %s   -> Vector2 是 %s" % [str(v.x == third), "float64" if v.x == third else "**float32**"])
	var big := 1.0 + 1e-10
	print("  Vector2(1+1e-10).x == 1.0 ? %s" % str(Vector2(big, 0.0).x == 1.0))

	print("\n=== 2. SoA 求解器算完之后，状态落到哪里？ ===")
	var w := PWorld.new()
	w.use_solver_batch = true
	w.use_threads = false
	w.sleeping_enabled = false
	var g := PBody.new()
	g.position = Vector2(-200.0, 0.0)
	g.make_static()
	w.add_body(g, [_block(400, 40)])
	var b := PBody.new()
	b.position = Vector2(0.0, -20.0)
	w.add_body(b, [_block(14, 14)])
	for i in 60:
		w.step(1.0 / 60.0)
	# SoA 数组里是多少？（float32 数组）
	var bx: float = w._batch.b_vx[1]
	var by: float = w._batch.b_vy[1]
	# 写回对象之后是多少？（Vector2）
	var ox: float = b.linear_velocity.x
	var oy: float = b.linear_velocity.y
	print("  SoA 数组里: (%.17f, %.17f)" % [bx, by])
	print("  PBody 上  : (%.17f, %.17f)" % [ox, oy])
	print("  同一位置？ %s" % str(bx == ox and by == oy))
	print("  => 每个子步结束时，状态**仍然被舍回 float32**；SoA 只是把 10 次迭代内部的舍入推迟了")
	quit(0)
