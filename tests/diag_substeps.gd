extends SceneTree
## 拖动一个物体时，全世界的**子步数**会不会来回跳。
##
## ⚠️ 子步数是按"全世界最快的那个刚体"算的，它一变，**所有**刚体的积分步长就跟着变。
##    修之前实测拖动 4 秒：{1:36, 2:30, 3:46, 4:62, 5:58, 6:8}，采样 [4,1,5,3,2,5] ——
##    静止物体的亚像素平衡位置随之来回变，画面症状是"抓起别的物体时，吊桥跟着抽搐"。
##    修之后（抓着东西时子步数只涨不落）：{1:35, 2:6, 3:11, 4:12, 5:9, 6:167}，采样 [4,1,6,6,6,6]。
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

func _rect(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, w, h), 1)
	return s

func _initialize() -> void:
	var world := PWorld.new()
	world.gravity = Vector2(0, 600)
	var ground := PBody.new()
	ground.position = Vector2(0, 220)
	ground.make_static()
	world.add_body(ground, [_rect(768, 100)])
	var planks := []
	for i in 4:
		var b := PBody.new()
		b.position = Vector2(306 + 31 * i, 98)
		world.add_body(b, [_rect(31, 6)])
		planks.append(b)
	world.add_hinge(null, planks[0], Vector2(306, 101))
	for i in 3:
		world.add_hinge(planks[i], planks[i + 1], Vector2(337 + 31 * i, 101))
	world.add_hinge(planks[3], null, Vector2(430, 101))
	var box := PBody.new()
	box.position = Vector2(150, 200)
	world.add_body(box, [_rect(16, 16)])
	for i in 900:
		world.step(1.0 / 60.0)
	print("静置后：子步数 %d" % world.last_substeps)
	# 抓起箱子，来回快慢拖动 —— 看子步数怎么变
	world.grab(box, box.position)
	var counts := {}
	var seq := []
	for i in 240:
		# 速度按正弦变化：0 -> 600 px/s -> 0
		var spd := 600.0 * sin(float(i) * 0.05)
		world.set_grab_target(world.grabs[0].target + Vector2(spd / 60.0, 0))
		world.step(1.0 / 60.0)
		var n: int = world.last_substeps
		counts[n] = counts.get(n, 0) + 1
		if i % 40 == 39:
			seq.append(n)
	print("拖动时子步数分布: %s" % str(counts))
	print("每 40 帧采样子步数: %s" % str(seq))
	quit(0)