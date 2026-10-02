extends SceneTree
## 第 3 层验证：体素遍历原语（neighbors / component_map / flood）
const PixelShape := preload("res://src/core/pixel_shape.gd")
const Destruction := preload("res://src/core/destruction.gd")

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
	# 两个互不相连的块 + 一条穿过多个 chunk 的长线
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, 4, 4), 1)          # 块 A（chunk 0,0）
	s.fill_rect(Rect2i(20, 20, 4, 4), 1)        # 块 B（chunk 2,2）
	s.fill_rect(Rect2i(0, 40, 40, 1), 2)        # 长线（跨 5 个 chunk，材质 2）

	print("=== neighbors ===")
	_c("4 邻域有 4 个", s.neighbors(5, 5).size() == 4)
	_c("8 邻域有 8 个", s.neighbors(5, 5, true).size() == 8)

	print("=== component_map ===")
	var cm := s.component_map()
	_c("三个连通分量", int(cm["count"]) == 3, "count=%d" % int(cm["count"]))
	var chunks: Dictionary = cm["chunks"]
	# 块 A 在 (1,1)，块 B 在 (21,21)，长线在 (5,40)
	var kA := PixelShape.make_key(0, 0)
	var kB := PixelShape.make_key(2, 2)
	var kL := PixelShape.make_key(0, 5)
	_c("块 A 的像素有分量号", (chunks[kA] as PackedInt32Array)[1 * 8 + 1] >= 0)
	_c("块 B 与块 A 不同分量",
		(chunks[kA] as PackedInt32Array)[1 * 8 + 1] != (chunks[kB] as PackedInt32Array)[5 * 8 + 5])
	_c("长线跨 chunk 是同一个分量",
		(chunks[kL] as PackedInt32Array)[0 * 8 + 0] == (chunks[kL] as PackedInt32Array)[0 * 8 + 7],
		"%d vs %d" % [(chunks[kL] as PackedInt32Array)[0], (chunks[kL] as PackedInt32Array)[7]])
	_c("空像素是 -1", (chunks[kA] as PackedInt32Array)[7 * 8 + 7] == -1)

	print("=== flood ===")
	# 从块 A 出发：只能走到块 A 的 16 个像素
	var n1 := s.flood(Vector2i(1, 1), Callable(), Callable())
	_c("flood 不会跨到别的连通体", n1 == 16, "访问 %d 个（块 A 是 16）" % n1)
	# 从长线出发：应当走满 40 个
	var n2 := s.flood(Vector2i(0, 40), Callable(), Callable())
	_c("flood 走满整条长线", n2 == 40, "访问 %d 个" % n2)
	# matches 限材质：长线是材质 2，块 A 是材质 1
	var n3 := s.flood(Vector2i(0, 40), func(_x, _y, m, _d): return m == 2, Callable())
	_c("matches 谓词生效", n3 == 40, "%d" % n3)
	var n4 := s.flood(Vector2i(0, 40), func(_x, _y, m, _d): return m == 1, Callable())
	_c("matches 拒绝起点则返回 0", n4 == 0, "%d" % n4)
	# 从空像素出发
	_c("起点为空返回 0", s.flood(Vector2i(100, 100), Callable(), Callable()) == 0)

	print("=== visit 的距离与中断 ===")
	# ⚠️ 累积必须用**引用类型**（Dictionary/Array/对象成员）：
	#    GDScript 的 lambda 按值捕获局部标量，改外面的 int 是改副本。
	var acc := {"max_d": -1, "seen": 0}
	var total := s.flood(Vector2i(0, 40),
		Callable(),
		func(_x, _y, _m, d):
			acc["max_d"] = maxi(int(acc["max_d"]), d)
			acc["seen"] = int(acc["seen"]) + 1
			return true)
	_c("visit 收到距离且递增", int(acc["max_d"]) == 39 and int(acc["seen"]) == 40,
		"max_d=%d seen=%d" % [int(acc["max_d"]), int(acc["seen"])])
	_c("flood 返回值与 visit 次数一致", total == int(acc["seen"]))
	# visit 返回 false 立即停止
	var st := {"n": 0}
	var n5 := s.flood(Vector2i(0, 40),
		Callable(),
		func(_x, _y, _m, _d):
			st["n"] = int(st["n"]) + 1
			return int(st["n"]) < 5)
	_c("visit 返回 false 就停", n5 == 5 and int(st["n"]) == 5,
		"flood 返回 %d，visit 被调 %d 次" % [n5, int(st["n"])])

	print("=== components 与 split 用的是同一份计算 ===")
	var groups := Destruction.components(s)
	_c("components 返回 3 组", groups.size() == 3, "%d" % groups.size())
	var parts := Destruction.split(s, 1)
	_c("split 的块数与 components 一致", parts.size() == 3, "%d vs %d" % [parts.size(), groups.size()])

	print("=== %d passed, %d failed ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
