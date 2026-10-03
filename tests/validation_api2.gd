extends SceneTree
## 新能力验证：标签查询 / 像素射线 / 形状操作 / 重力缩放
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")
const ShapeOps := preload("res://src/core/shape_ops.gd")
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

func _block(w: int, h: int, mat: int = 1) -> PixelShape:
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, w, h), mat)
	return s

func _initialize() -> void:
	var w := PWorld.new()
	w.gravity = Vector2(0.0, 900.0)
	Query.attach(w)

	# ---- 标签 ----
	var a := PBody.new()
	a.position = Vector2(0.0, 0.0)
	w.add_body(a, [_block(10, 10)])
	a.tags["crate"] = 7
	var b := PBody.new()
	b.position = Vector2(100.0, 0.0)
	w.add_body(b, [_block(10, 10)])
	b.tags["crate"] = null
	b.tags["wall"] = true
	_c("find_body 按标签找", w.find_body("crate") == a)
	_c("find_bodies 全部命中", w.find_bodies("crate").size() == 2)
	_c("标签值可读", w.find_body("crate").tags.get("crate") == 7)
	_c("不同标签区分", w.find_body("wall") == b)
	_c("find_shapes 拿到形状", w.find_shapes("wall").size() == 1)
	_c("找不到返回 null", w.find_body("nope") == null)

	# ---- 重力缩放 ----
	var light := PBody.new()
	light.position = Vector2(200.0, -100.0)
	w.add_body(light, [_block(10, 10)])
	light.gravity_scale = 0.0
	for i in 60:
		w.step(1.0 / 60.0)
	_c("gravity_scale=0 不下落", is_equal_approx(light.position.y, -100.0),
		"y=%.3f" % light.position.y)
	# 对照组
	var heavy := PBody.new()
	heavy.position = Vector2(300.0, -100.0)
	w.add_body(heavy, [_block(10, 10)])
	for i in 60:
		w.step(1.0 / 60.0)
	_c("对照组正常下落", heavy.position.y > -90.0, "y=%.1f" % heavy.position.y)

	# ---- 像素射线（门面同款入口）----
	var wall := PBody.new()
	wall.position = Vector2(-100.0, -200.0)
	wall.make_static()
	var ws := _block(8, 40, 3)
	ws.fill_rect(Rect2i(0, 16, 8, 8), 0)     # 通高的缝
	w.add_body(wall, [ws])
	Query.attach(w)
	var hit := Query.raycast(Vector2(-200.0, -195.0), Vector2(1.0, 0.0), 400.0)
	_c("射线命中实心", hit.hit, "dist=%.1f 材质=%d" % [hit.distance, hit.material])
	var miss := Query.raycast(Vector2(-200.0, -180.0), Vector2(1.0, 0.0), 400.0)
	_c("射线穿过缝", not miss.hit)
	var cp := Query.closest_point(Vector2(-96.0, -180.0), 50.0)
	_c("最近点命中", cp.hit, "point=%s" % str(cp.point))
	_c("查询排除生效", not Query.raycast(Vector2(-200.0, -195.0), Vector2(1.0, 0.0), 400.0, 0.0, [wall]).hit)

	# ---- 形状操作 ----
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, 20, 4), 1)
	s.fill_rect(Rect2i(0, 8, 20, 4), 1)      # 与上面不相连
	_c("形状被识别为不连通", ShapeOps.is_disconnected(s))
	var holder := PBody.new()
	holder.position = Vector2(500.0, 0.0)
	# ⚠️ 这里**故意**造一个多岛屿 body 来测 ShapeOps 的分裂/合并 —— 而 add_body
	#    默认会在入口处就把它拆成独立刚体（"每个实体内部连通"这条不变量）。
	#    connected_known = true 是调用方在说"我知道我在干什么，别替我拆"，
	#    正是为这种场合留的口子。断言本身测的是 ShapeOps，不是入口策略。
	w.add_body(holder, [s], Callable(), true)
	var rest := ShapeOps.split(s)
	_c("切分产生新形状", rest.size() == 1, "切出 %d 块" % rest.size())
	_c("原形状保留最大块", s.pixel_count() == 80, "%d 像素" % s.pixel_count())
	_c("同一刚体拥有两块", holder.shapes.size() == 2, "%d 个形状" % holder.shapes.size())

	# ---- 合并：把两块挪到一起再合 ----
	(holder.shapes[1] as PixelShape).translate_pixels(0, 0)
	# 两块本来就只差 y 方向 8..12，不接触；移过来
	(holder.shapes[1] as PixelShape).translate_pixels(0, -4)
	_c("相邻判定", ShapeOps.is_touching(s, holder.shapes[1]))
	ShapeOps.merge(s)
	_c("合并后只剩一块", holder.shapes.size() == 1, "%d 个形状" % holder.shapes.size())

	# ---- 材质查询 ----
	_c("局部材质查询", ShapeOps.material_at_index(s, 1, 1) == 1)
	_c("世界材质查询", ShapeOps.material_at_position(s, Vector2(501.0, 1.0)) == 1)
	_c("空处材质为 0", ShapeOps.material_at_index(s, -5, -5) == 0)

	# ---- 形状密度 ----
	var m0 := holder.mass
	ShapeOps.set_density(s, 3.0)
	_c("形状密度影响质量", is_equal_approx(holder.mass, m0 * 3.0),
		"%.0f -> %.0f" % [m0, holder.mass])

	# ---- 最近点（形状级）----
	var scp := ShapeOps.closest_point(s, Vector2(520.0, 5.0))
	_c("形状最近点", scp.hit, "dist=%.2f point=%s" % [scp.distance, str(scp.point)])

	print("=== %d passed, %d failed ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
