extends SceneTree
## 多边形形状 + 「接口」验证：
## 一个新形状类型**不改 PixelBody2D / PixelWorld / 渲染器一行代码**就能用。
const PixelShape := preload("res://src/core/pixel_shape.gd")
const PolygonShape := preload("res://src/nodes/pixel_shape_polygon_2d.gd")
const PixelBody2D := preload("res://src/nodes/pixel_body_2d.gd")
const PixelWorld := preload("res://src/nodes/pixel_world.gd")
const PixelShape2D := preload("res://src/nodes/pixel_shape_2d.gd")

var _pass := 0
var _fail := 0
func _c(n: String, ok: bool, d: String = "") -> void:
	if ok:
		_pass += 1
		print("  PASS  ", n, "  ", d)
	else:
		_fail += 1
		print("  FAIL  ", n, "  ", d)

func _initialize() -> void:
	print("=== 1. 多边形填充 ===")
	var tri := PolygonShape.new()
	# 直角三角形：底 32、高 32 -> 面积约 512
	tri.points = PackedVector2Array([Vector2(0, 32), Vector2(32, 32), Vector2(0, 0)])
	var s = tri.build_shape()
	_c("三角形填出了像素", s.pixel_count() > 0, "%d 像素" % s.pixel_count())
	# 三角形面积 ≈ 底*高/2 = 512，允许量化误差
	_c("面积接近理论值 512", absf(float(s.pixel_count()) - 512.0) < 70.0,
		"实测 %d" % s.pixel_count())
	# 直角边上的点应当实心，斜边外应当空
	_c("左下角实心", s.get_pixel(0, 31) != 0)
	_c("斜边外为空", s.get_pixel(31, 0) == 0)
	_c("原点在左上角（无负坐标像素）", s.local_aabb().position.x >= 0 and s.local_aabb().position.y >= 0,
		"外接 %s" % str(s.local_aabb()))

	print("=== 2. 斜坡（像素游戏里最需要的）===")
	var slope := PolygonShape.new()
	slope.points = PackedVector2Array([Vector2(0, 0), Vector2(64, 32), Vector2(0, 32)])
	var s2 = slope.build_shape()
	_c("斜坡填出了像素", s2.pixel_count() > 0, "%d 像素" % s2.pixel_count())
	# 斜面的关键性质：每一列的最高实心像素随 x 上升（单调）
	var heights := PackedInt32Array()
	for x in 64:
		var top := -1
		for y in 32:
			if s2.get_pixel(x, y) != 0:
				top = y
				break
		heights.append(top)
	var mono := true
	var prev := -1
	for h in heights:
		if h >= 0:
			if prev >= 0 and h < prev:
				mono = false
			prev = h
	_c("斜面高度单调下降（是坡不是锯齿）", mono)

	print("=== 3. 接口：不改任何既有代码就能用 ===")
	var world_node := PixelWorld.new()
	root.add_child(world_node)
	var body := PixelBody2D.new()
	body.position = Vector2(0, 0)
	world_node.add_child(body)
	# ⚠️ 关键：挂一个**新类型**的形状子节点上去。
	#    PixelBody2D.collect_shapes() 只认 build_shape() 方法，不检查类型，
	#    所以这里不需要在 PixelBody2D 里加任何分支。
	var child := PolygonShape.new()
	child.points = PackedVector2Array([Vector2(0, 0), Vector2(20, 0), Vector2(20, 20)])
	body.add_child(child)
	var shapes := body.collect_shapes()
	_c("collect_shapes 收到了自定义形状", shapes.size() == 1, "%d 个" % shapes.size())
	_c("收到的确实是多边形填出来的", shapes.size() == 1 and (shapes[0] as PixelShape).pixel_count() > 0,
		"%d 像素" % ((shapes[0] as PixelShape).pixel_count() if shapes.size() > 0 else 0))

	# 内置的 Rect 形状子节点也能共存（组合）
	var rect_child := PixelShape2D.new()
	rect_child.rect_size = Vector2i(8, 8)
	rect_child.position = Vector2(30, 0)
	body.add_child(rect_child)
	_c("多边形 + 矩形可组合在一个刚体上", body.collect_shapes().size() == 2,
		"%d 个形状" % body.collect_shapes().size())

	# 烘焙进世界应当真的成功
	world_node.rebuild()
	_c("世界烘焙成功（不需要为多边形改 PixelWorld）", world_node.world != null and world_node.world.bodies.size() >= 1,
		"%d 个刚体" % (world_node.world.bodies.size() if world_node.world != null else 0))
	if world_node.world != null and world_node.world.bodies.size() >= 1:
		var pb = world_node.world.bodies[0]
		_c("物理体拿到了两个形状", pb.shapes.size() == 2, "%d 个" % pb.shapes.size())
		_c("碰撞矩形非空（多边形真的参与碰撞了）", pb.rects.size() > 0, "%d 个矩形" % pb.rects.size())

	print("=== %d passed, %d failed ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
