extends SceneTree
## 节点摆的 + 代码生成的，能不能共存？
##
## 甲方问："先用节点摆放一个正方形，再在游戏中通过代码生成一个正方形"。
## 这条是节点版与门面版共存的**核心契约**，所以钉成测试：
##   1. 代码加进去的刚体**不重建世界** —— 节点那个的 body 对象必须还是同一个；
##   2. 两个都进物理、都会掉、都睡；
##   3. 运行时加的东西不丢（前提：不调 rebuild）。
const PixelWorld := preload("res://src/nodes/pixel_world.gd")
const PixelBody2D := preload("res://src/nodes/pixel_body_2d.gd")

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
	print("=== 节点摆的 + 代码生成的 ===")
	var pw := PixelWorld.new()
	pw.name = "PixelWorld"
	root.add_child(pw)
	var ground := PixelBody2D.new()
	ground.name = "Ground"
	ground.position = Vector2(0, 200)
	ground.is_static = true
	ground.rect_size = Vector2i(400, 40)
	pw.add_child(ground)

	# ---- 1) 节点摆的 ----
	var placed := PixelBody2D.new()
	placed.name = "Placed"
	placed.position = Vector2(100, 40)
	placed.rect_size = Vector2i(16, 16)
	pw.add_child(placed)
	pw.rebuild()
	var placed_body = pw.world.bodies[1]                 # [0] 是地面
	var n0: int = pw.world.bodies.size()
	_c("节点摆的进世界了", placed_body != null and n0 == 2, "刚体数 %d" % n0)

	# ---- 2) 运行时用代码再生成一个 ----
	var made := PixelBody2D.new()
	made.name = "MadeByCode"
	made.position = Vector2(160, 40)
	made.rect_size = Vector2i(16, 16)
	pw.add_child(made)
	var made_body = pw.add_body_node(made)               # ← 增量，不重建世界
	_c("代码生成的也进世界了", made_body != null and pw.world.bodies.size() == 3,
		"刚体数 %d" % pw.world.bodies.size())
	_c("节点那个 body 对象没被换掉（= 没有重建世界）", pw.world.bodies[1] == placed_body,
		"id=%d" % placed_body.id)
	_c("两者质量一致（同一套材质/尺寸推导）",
		is_equal_approx(placed_body.mass, made_body.mass),
		"%.1f vs %.1f" % [placed_body.mass, made_body.mass])

	# ---- 3) 一起掉 ----
	for i in 180:
		pw.world.step(1.0 / 60.0)
	_c("两个都落地了", absf(placed_body.position.y - made_body.position.y) < 1.0,
		"y=%.1f / %.1f" % [placed_body.position.y, made_body.position.y])
	_c("两个都睡着了", not placed_body.awake and not made_body.awake)
	_c("运行时加的那个仍然在（没被 rebuild 清掉）", pw.world.bodies.has(made_body))

	print("=== %d passed, %d failed ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)