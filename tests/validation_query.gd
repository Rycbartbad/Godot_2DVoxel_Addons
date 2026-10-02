extends SceneTree
## 像素级射线检测验证
##
## ⚠️ 场景设计：要测"射线穿过洞"，洞必须**开在射线的入口面上**。
## 第一版把洞开在墙的正中间 —— 水平射线照样先撞上左表面，测不出东西。
## 所以这里用一块 8 宽 x 40 高的墙，在局部 y∈[16,24] 挖一条**通高的缝**。
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")
const Query := preload("res://src/physics/query.gd")

var _pass := 0
var _fail := 0
func _c(n: String, ok: bool, d: String = "") -> void:
	if ok:
		_pass += 1
		print("  PASS  ", n, "  ", d)
	else:
		_fail += 1
		print("  FAIL  ", n, "  ", d)

func _slab(mat: int) -> PixelShape:
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, 8, 40), mat)
	s.fill_rect(Rect2i(0, 16, 8, 8), 0)      # 通高的缝
	return s

func _initialize() -> void:
	var w := PWorld.new()
	w.gravity = Vector2.ZERO
	var wall := PBody.new()
	wall.position = Vector2(100.0, 0.0)
	wall.make_static()
	w.add_body(wall, [_slab(3)])
	Query.attach(w)
	# 墙：世界 x∈[100,108]，y∈[0,40]；缝：世界 y∈[16,24]

	# 1. 实心
	var h := Query.raycast(Vector2(-50.0, 5.0), Vector2(1.0, 0.0), 400.0)
	_c("命中实心", h.hit, "dist=%.2f 材质=%d" % [h.distance, h.material])
	_c("距离正确", is_equal_approx(h.distance, 150.0), "%.4f" % h.distance)
	_c("法线朝来向", h.normal.is_equal_approx(Vector2(-1.0, 0.0)), str(h.normal))
	_c("材质正确", h.material == 3, "%d" % h.material)
	_c("命中点在表面", is_equal_approx(h.point.x, 100.0), str(h.point))

	# 2. 穿过缝（y=20 落在缝 y∈[16,24] 内）
	var h2 := Query.raycast(Vector2(-50.0, 20.0), Vector2(1.0, 0.0), 400.0)
	_c("穿过像素缝", not h2.hit, "dist=%.2f" % h2.distance)

	# 3. 斜射打到缝壁
	var h3 := Query.raycast(Vector2(104.0, 8.0), Vector2(0.0, 1.0), 400.0)
	_c("垂直打到缝的下壁", h3.hit and h3.normal.y < 0.0,
		"dist=%.2f 法线=%s 材质=%d" % [h3.distance, str(h3.normal), h3.material])

	# 4. 加粗射线：细射线穿缝而过，半径 5 会擦到缝边
	var h5 := Query.raycast(Vector2(-50.0, 20.0), Vector2(1.0, 0.0), 400.0, 5.0)
	_c("加粗射线擦到缝边", h5.hit, "dist=%.2f" % h5.distance)

	# 5. 最近点
	var h6 := Query.closest_point(Vector2(104.0, 20.0), 50.0)
	_c("最近点命中", h6.hit, "dist=%.2f point=%s" % [h6.distance, str(h6.point)])
	_c("最近点在缝壁上", h6.point.y >= 15.0 and h6.point.y <= 25.0, str(h6.point))

	# 6. AABB
	_c("AABB 查刚体", Query.aabb_bodies(Rect2(90.0, 10.0, 60.0, 20.0)).size() == 1)
	_c("AABB 查形状", Query.aabb_shapes(Rect2(90.0, 10.0, 60.0, 20.0)).size() == 1)
	_c("AABB 查空处", Query.aabb_bodies(Rect2(-500.0, -500.0, 10.0, 10.0)).size() == 0)

	# 7. reject
	var h7 := Query.raycast(Vector2(-50.0, 5.0), Vector2(1.0, 0.0), 400.0, 0.0, [wall])
	_c("reject 生效", not h7.hit)

	# 8. 起点已在实心内（在旋转之前测）
	var h8 := Query.raycast(Vector2(104.0, 10.0), Vector2(1.0, 0.0), 400.0)
	_c("起点在实心内直接命中", h8.hit and is_equal_approx(h8.distance, 0.0), "dist=%.3f" % h8.distance)

	# 9. 旋转 90 度：局部 (0..8, 0..40) 绕原点转 -> 世界 x∈[60,100], y∈[0,8]
	var rot := PBody.new()
	rot.position = Vector2(100.0, 0.0)
	rot.rotation = PI * 0.5
	rot.make_static()
	w.add_body(rot, [_slab(3)])
	Query.attach(w)
	# to_local(world) = (wy, 100 - wx)；要打到实心处就取局部 y=5 -> 世界 x=95
	var h9 := Query.raycast(Vector2(95.0, -50.0), Vector2(0.0, 1.0), 400.0)
	_c("旋转后仍能命中", h9.hit and h9.normal.is_equal_approx(Vector2(0.0, -1.0)),
		"dist=%.2f 法线=%s" % [h9.distance, str(h9.normal)])

	print("=== %d passed, %d failed ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
