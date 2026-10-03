extends SceneTree
## 交互自检：绘制 / 擦除 / 抓取拖动（驱动与 Demo 完全相同的代码路径）

const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")
const Editor := preload("res://src/core/pixel_editor.gd")

const TILE := 64

var _pass := 0
var _fail := 0

func _check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		_pass += 1
		print("  PASS  ", name, "  ", detail)
	else:
		_fail += 1
		print("  FAIL  ", name, "  ", detail)

func _block(w: int, h: int, mat: int = 1, ox: int = 0, oy: int = 0) -> PixelShape:
	var s := PixelShape.new()
	for y in h:
		for x in w:
			s.set_pixel(ox + x, oy + y, mat)
	return s

func _initialize() -> void:
	print("=== 交互自检（绘制 / 擦除 / 拖动）===")
	_test_paint_into_body()
	_test_paint_canvas()
	_test_stroke_is_continuous()
	_test_erase_and_split()
	_test_erase_removes_body()
	_test_grab_follows_target()
	_test_grab_rejects_static()
	_test_grab_prevents_sleep()
	print("=== %d passed, %d failed ===" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _test_paint_into_body() -> void:
	print("[左键绘制 - 画在刚体上]")
	var world := PWorld.new()
	world.gravity = Vector2.ZERO
	var b := PBody.new()
	b.position = Vector2(100, 100)
	world.add_body(b, [_block(16, 16)])
	var mass0 := b.mass
	var added := Editor.paint_into(b, Vector2(16, 0), Vector2(24, 8), 3.0, 3)
	_check("新增像素", added > 0, "added=%d" % added)
	_check("像素数增加", b.shapes[0].pixel_count() > 256, str(b.shapes[0].pixel_count()))
	_check("质量自动增加", b.mass > mass0, "%.1f -> %.1f" % [mass0, b.mass])
	_check("碰撞矩形已重建", b.rects.size() >= 1, "rects=%d" % b.rects.size())
	_check("AABB 已扩展", b.aabb.end.x > 116.0, str(b.aabb))
	# 重复画同一处不应再计数
	var again := Editor.paint_into(b, Vector2(16, 0), Vector2(24, 8), 3.0, 3)
	_check("重复落笔不重复计数", again == 0, "again=%d" % again)


func _test_paint_canvas() -> void:
	print("[左键绘制 - 画成地形]")
	var world := PWorld.new()
	var tiles := {}
	var touched: Array = Editor.paint_canvas(world, tiles, Vector2(10, 10), Vector2(20, 20), 4.0, 1, TILE)
	_check("产生一个画布瓦片", touched.size() == 1 and tiles.size() == 1, "touched=%d tiles=%d" % [touched.size(), tiles.size()])
	var body: PBody = tiles[Vector2i(0, 0)]
	_check("画布瓦片是静态体", body.is_static, "")
	_check("像素落进瓦片", body.shapes[0].pixel_count() > 0, str(body.shapes[0].pixel_count()))
	_check("静态体质量为 0", body.mass == 0.0, str(body.mass))
	# 跨越瓦片边界
	var tiles2 := {}
	var touched2: Array = Editor.paint_canvas(world, tiles2, Vector2(60, 10), Vector2(70, 10), 3.0, 1, TILE)
	_check("跨瓦片产生两块", tiles2.size() == 2, "tiles=%d" % tiles2.size())


func _test_stroke_is_continuous() -> void:
	print("[快速拖动不留断点]")
	var world := PWorld.new()
	var tiles := {}
	Editor.paint_canvas(world, tiles, Vector2(4.5, 20.5), Vector2(180.5, 20.5), 2.0, 1, TILE)
	var gaps := 0
	for x in range(5, 180, 5):
		var cy := int(floor(20.5 / TILE))
		var found := false
		for tx in range(0, 4):
			var b: PBody = tiles.get(Vector2i(tx, cy))
			if b == null:
				continue
			var c = b.shapes[0].chunks.get(PixelShape.make_key((x - tx * TILE) >> 3, (20 - cy * TILE) >> 3))
			if c == null:
				continue
			var lx := x - tx * TILE - (((x - tx * TILE) >> 3) << 3)
			var ly := 20 - cy * TILE - (((20 - cy * TILE) >> 3) << 3)
			if (c.occ & (1 << (lx + (ly << 3)))) != 0:
				found = true
		if not found:
			gaps += 1
	_check("线路上无断点", gaps == 0, "gaps=%d" % gaps)


func _test_erase_and_split() -> void:
	print("[右键擦除 - 切断并坠落]")
	var world := PWorld.new()
	world.gravity = Vector2(0, 900)
	var wall := PBody.new()
	wall.position = Vector2.ZERO
	wall.make_static()
	world.add_body(wall, [_block(64, 16, 4)])
	_check("墙初始 1024 像素", wall.shapes[0].pixel_count() == 1024, str(wall.shapes[0].pixel_count()))
	var results: Array = Editor.erase(world, Vector2(32, -4), Vector2(32, 20), 2.0, 25.0)
	_check("有一次擦除结果", results.size() == 1, str(results.size()))
	if results.size() == 1:
		var r: Dictionary = results[0]
		_check("删除了 64 像素", r["removed"] == 64, str(r["removed"]))
		var spawned: Array = r["spawned"]
		_check("裂出 1 块", spawned.size() == 1, str(spawned.size()))
		if spawned.size() == 1:
			var frag: PBody = spawned[0]
			_check("碎片是动态体", not frag.is_static, "")
			_check("碎片 480 像素", frag.shapes[0].pixel_count() == 480, str(frag.shapes[0].pixel_count()))
			_check("碎片有质量", frag.mass > 0.0, str(frag.mass))
			_check("碎片有碰撞矩形", frag.rects.size() >= 1, str(frag.rects.size()))
		_check("原墙保留 480", wall.shapes[0].pixel_count() == 480, str(wall.shapes[0].pixel_count()))
	# 擦空之后物体应被移除
	var before_count := world.bodies.size()
	Editor.erase(world, Vector2(-10, -10), Vector2(80, 30), 40.0, 0.0)
	_check("擦空后移除物体", world.bodies.size() < before_count,
		"%d -> %d" % [before_count, world.bodies.size()])


func _test_erase_removes_body() -> void:
	print("[擦除 - 完全擦空]")
	var world := PWorld.new()
	world.gravity = Vector2.ZERO
	var b := PBody.new()
	b.position = Vector2.ZERO
	world.add_body(b, [_block(8, 8)])
	Editor.erase(world, Vector2(4, 4), Vector2(4, 4), 20.0, 0.0)
	_check("Body 已从世界移除", not world.bodies.has(b), "bodies=%d" % world.bodies.size())


func _test_grab_follows_target() -> void:
	print("[Ctrl+左键 拖动]")
	var world := PWorld.new()
	world.gravity = Vector2(0, 900)
	var g := PBody.new()
	g.position = Vector2(0, 200)
	g.make_static()
	world.add_body(g, [_block(400, 16)])
	var box := PBody.new()
	box.position = Vector2(100, 150)
	world.add_body(box, [_block(16, 16)])
	for i in 120:
		world.step(1.0 / 60.0)
	var rest_y := box.com_world().y
	_check("先落到地面", absf(rest_y - 192.0) < 1.5, "com.y=%.2f" % rest_y)

	var grab = world.grab(box, box.com_world(), 9000.0)
	_check("抓取建立", grab != null and world.is_grabbing(), "")
	world.set_grab_target(Vector2(100, 60))
	for i in 90:
		world.step(1.0 / 60.0)
	var lifted := box.com_world()
	_check("被拉向目标", lifted.y < 80.0, "com=(%.1f, %.1f)" % [lifted.x, lifted.y])
	_check("水平不漂移", absf(lifted.x - 100.0) < 3.0, "x=%.2f" % lifted.x)

	# ⚠️ 回归断言：抓取力**绝不能**走 accum_force —— 那是**持久累加器**
	#    （要调用方 clear_forces() 才清），而 demo 直接调 PWorld.advance()，
	#    没人清。实测力每帧涨 max_accel*mass = 640000，物体冲过目标后疯狂震荡
	#    （终态 x=185.7 而目标是 158，速度 ±397 来回翻）。
	#    抓取力必须是"这一子步的约束力"：覆盖写 + 用完清零。
	_check("抓取不污染 accum_force", box.accum_force == Vector2.ZERO,
		"accum_force=%s" % str(box.accum_force))

	# 目标**静止**时应当收敛在目标上（临界阻尼），而不是来回过冲。
	# 上面那两条只看了"有没有被拉过去"，看不出震荡 —— 所以这条单独钉。
	world.set_grab_target(Vector2(100, 60))
	for i in 120:
		world.step(1.0 / 60.0)
	var settled := box.com_world()
	var miss := settled.distance_to(Vector2(100, 60))
	_check("静止目标下会收敛", miss < 3.0, "距目标 %.2f" % miss)
	_check("收敛后不再震荡", box.linear_velocity.length() < 30.0,
		"v=%.1f" % box.linear_velocity.length())

	# 甩出去：目标必须持续高速移动，并在运动中途松手。
	# （把目标停住再松手当然不会飞——那是正确的物理。）
	for i in 20:
		world.set_grab_target(Vector2(120 + i * 40, 60))
		world.step(1.0 / 60.0)
	var v_at_release := box.linear_velocity.length()
	world.release_grab()
	_check("松手后不再被抓", not world.is_grabbing(), "")
	_check("甩出时带有速度", v_at_release > 200.0, "v=%.1f" % v_at_release)
	_check("松手瞬间速度连续", absf(box.linear_velocity.length() - v_at_release) < 1.0,
		"%.1f -> %.1f" % [v_at_release, box.linear_velocity.length()])
	# 松手后应沿惯性继续飞出
	var x0 := box.com_world().x
	for i in 10:
		world.step(1.0 / 60.0)
	_check("松手后继续飞出", box.com_world().x - x0 > 20.0, "dx=%.1f" % (box.com_world().x - x0))


func _test_grab_rejects_static() -> void:
	print("[拖动 - 静态体不可拖]")
	var world := PWorld.new()
	var s := PBody.new()
	s.make_static()
	world.add_body(s, [_block(16, 16)])
	_check("静态体抓取返回 null", world.grab(s, Vector2(8, 8)) == null, "")


func _test_grab_prevents_sleep() -> void:
	print("[拖动 - 抓着不入睡]")
	var world := PWorld.new()
	world.gravity = Vector2(0, 900)
	var g := PBody.new()
	g.position = Vector2(0, 200)
	g.make_static()
	world.add_body(g, [_block(400, 16)])
	var box := PBody.new()
	box.position = Vector2(100, 150)
	world.add_body(box, [_block(16, 16)])
	for i in 120:
		world.step(1.0 / 60.0)
	_check("未抓取时会睡着", not box.awake, "awake=%s" % box.awake)
	world.grab(box, box.com_world(), 9000.0)
	world.set_grab_target(Vector2(160, 140))
	for i in 60:
		world.step(1.0 / 60.0)
	_check("抓取期间保持清醒", box.awake, "awake=%s" % box.awake)
	_check("确实被移动了", box.com_world().x > 110.0, "x=%.1f" % box.com_world().x)
