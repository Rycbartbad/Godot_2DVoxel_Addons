extends SceneTree
## 抓取到底需不需要"在求解器迭代里解"？—— 用数据回答，不靠直觉。
##
## 两条路径现在同时存在：
##   · use_rapier = false：grab 是**速度层约束**，塞进求解器的 10 次迭代里（accumulated 跨迭代累积）
##   · use_rapier = true ：每子步只解**一次**，等价于一个限力 max_accel*mass 的力
## 两条路径 test_interaction 都是 35/35 —— 但"都过测试"不等于"行为一样"。
## 这里把同一场景的**轨迹**打出来对比：误差、超调、稳定时间。
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

func _block(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, w, h), 1)
	return s

## 返回 [是否到达, 最大超调, 首次进入目标 1px 的步数, 终态误差]
func _drag(rapier: bool, size: int, move: float) -> Array:
	var w := PWorld.new()
	w.use_rapier = rapier
	w.sleeping_enabled = true
	var g := PBody.new()
	g.position = Vector2(-300.0, 0.0)
	g.make_static()
	w.add_body(g, [_block(600, 40)])
	var b := PBody.new()
	b.position = Vector2(0.0, -float(size))
	w.add_body(b, [_block(size, size)])
	for i in 60:
		w.step(1.0 / 60.0)
	var gb := w.grab(b, b.com_world(), 2500.0)
	var target := b.com_world() + Vector2(move, 0.0)
	w.set_grab_target(target)
	var overshoot := 0.0
	var arrived := -1
	for i in 90:
		w.step(1.0 / 60.0)
		var d := b.com_world().distance_to(target)
		if arrived < 0 and d < 1.0:
			arrived = i
		# 超调：越过目标多少（只算 x 方向）
		overshoot = maxf(overshoot, b.com_world().x - target.x)
	var fin := b.com_world().distance_to(target)
	return [arrived, overshoot, fin, b.mass]

func _run(label: String, size: int, move: float) -> void:
	print("\n--- %s（%dx%d 方块，目标平移 %.0f px）---" % [label, size, size, move])
	for rapier in [false, true]:
		var r := _drag(rapier, size, move)
		print("  %-14s 到达@第 %3d 步 | 最大超调 %7.3f px | 终态误差 %7.4f px | 质量 %.0f" % [
			"Rapier" if rapier else "引擎(10 迭代)",
			int(r[0]), float(r[1]), float(r[2]), float(r[3])])

func _initialize() -> void:
	print("=== 抓取：'求解器迭代里解' vs '每子步一个力' ===")
	_run("轻物体", 16, 150.0)
	_run("重物体", 64, 150.0)
	_run("很重的物体", 128, 150.0)
	quit(0)
