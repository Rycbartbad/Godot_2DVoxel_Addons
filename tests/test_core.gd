extends SceneTree
## 无头自检：数据层 / 破坏 / 分片 / 矩形分解 / 质量属性

const Bits := preload("res://src/core/pixel_bits.gd")
const PixelChunk := preload("res://src/core/pixel_chunk.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")
const Destruction := preload("res://src/core/destruction.gd")
const GreedyRects := preload("res://src/core/greedy_rects.gd")
const MassProps := preload("res://src/core/mass_props.gd")

var _pass := 0
var _fail := 0

func _check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		_pass += 1
		print("  PASS  ", name, "  ", detail)
	else:
		_fail += 1
		print("  FAIL  ", name, "  ", detail)

func _initialize() -> void:
	print("=== pixel core self-test ===")
	_test_bits()
	_test_chunk()
	_test_damage()
	_test_split()
	_test_diagonal_is_not_connected()
	_test_greedy_rects()
	_test_mass_props()
	print("=== %d passed, %d failed ===" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

func _test_bits() -> void:
	print("[bits]")
	Bits.ensure()
	_check("popcount(0)", Bits.popcount(0) == 0)
	_check("popcount(full)", Bits.popcount(-1) == 64, str(Bits.popcount(-1)))
	_check("popcount(one)", Bits.popcount(1) == 1)
	var full := -1
	_check("dilate4 keeps full", Bits.dilate4(full) == full)
	# 左上角一个像素向右膨胀 -> 应覆盖 (0,0),(1,0),(0,1)
	var f := Bits.flood(Bits.bit(0, 0), Bits.bit(0, 0) | Bits.bit(1, 0) | Bits.bit(0, 1))
	_check("flood 3 px", Bits.popcount(f) == 3, str(Bits.popcount(f)))
	# 同一 chunk 内被隔断：只应拿到 1 个
	var occ2 := Bits.bit(0, 0) | Bits.bit(2, 0)
	_check("flood isolated", Bits.popcount(Bits.flood(Bits.bit(0, 0), occ2)) == 1)
	# 列位压缩
	var col := Bits.col_mask(3)
	_check("col_bits col3", Bits.col_bits(-1, 3) == 0xFF, str(Bits.col_bits(-1, 3)))

func _test_chunk() -> void:
	print("[chunk]")
	var c := PixelChunk.new()
	for y in 8:
		for x in 8:
			c.set_pixel(x, y, (x + y) % 7 + 1)
	_check("full count", c.count() == 64, str(c.count()))
	_check("material", c.get_material(3, 4) == (3 + 4) % 7 + 1)
	var keep := 0
	for y in 4:
		for x in 8:
			keep |= Bits.bit(x, y)
	c.apply_keep_mask(keep)
	_check("half count", c.count() == 32, str(c.count()))
	_check("cleared material", c.get_material(3, 4) == 0)
	_check("kept material", c.get_material(3, 1) == (3 + 1) % 7 + 1)

func _test_damage() -> void:
	print("[damage]")
	var s := PixelShape.new()
	for y in 8:
		for x in 16:
			s.set_pixel(x, y, 1)
	_check("16x8 pixels", s.pixel_count() == 128, str(s.pixel_count()))
	var rm := Destruction.apply_damage(s, Destruction.Damage.rect(Vector2(8.5, 4.0), Vector2(0.5, 4.0)))
	_check("removed 8 px", rm == 8, str(rm))
	_check("left 120", s.pixel_count() == 120, str(s.pixel_count()))
	var aabb := s.local_aabb()
	_check("aabb", aabb == Rect2i(0, 0, 16, 8), str(aabb))

func _test_split() -> void:
	print("[split]")
	var s := PixelShape.new()
	for y in 8:
		for x in 16:
			s.set_pixel(x, y, 1)
	Destruction.apply_damage(s, Destruction.Damage.rect(Vector2(8.5, 4.0), Vector2(0.5, 4.0)))
	var parts := Destruction.split(s, 1)
	_check("2 components", parts.size() == 2, str(parts.size()))
	if parts.size() == 2:
		var a: int = parts[0].pixel_count()
		var b: int = parts[1].pixel_count()
		_check("64+56", a + b == 120 and mini(a, b) == 56, "%d + %d" % [a, b])
		var ax: Rect2i = parts[0].local_aabb()
		var bx: Rect2i = parts[1].local_aabb()
		_check("bboxes disjoint", not ax.intersects(bx), "%s / %s" % [ax, bx])

func _test_diagonal_is_not_connected() -> void:
	print("[connectivity rule]")
	var s := PixelShape.new()
	s.set_pixel(0, 0, 1)
	s.set_pixel(1, 1, 1)
	var parts := Destruction.split(s, 1)
	_check("diagonal does NOT connect", parts.size() == 2, str(parts.size()))
	# 共面则连通
	var s2 := PixelShape.new()
	s2.set_pixel(0, 0, 1)
	s2.set_pixel(1, 0, 1)
	_check("side connects", Destruction.split(s2, 1).size() == 1)
	# 跨 chunk 共面连通（x=7 与 x=8）
	var s3 := PixelShape.new()
	s3.set_pixel(7, 0, 1)
	s3.set_pixel(8, 0, 1)
	_check("cross-chunk side connects", Destruction.split(s3, 1).size() == 1)
	# 跨 chunk 对角不连通
	var s4 := PixelShape.new()
	s4.set_pixel(7, 0, 1)
	s4.set_pixel(8, 1, 1)
	_check("cross-chunk diagonal no", Destruction.split(s4, 1).size() == 2)
	# 跨 chunk 上下连通（y=7 与 y=8）
	var s5 := PixelShape.new()
	s5.set_pixel(0, 7, 1)
	s5.set_pixel(0, 8, 1)
	_check("cross-chunk vertical connects", Destruction.split(s5, 1).size() == 1)

func _test_greedy_rects() -> void:
	print("[greedy rects]")
	var solid := PixelShape.new()
	for y in 8:
		for x in 16:
			solid.set_pixel(x, y, 1)
	var r1 := GreedyRects.decompose(solid)
	_check("solid 16x8 -> 1 rect", r1.rect_count() == 1, str(r1.rects))
	_check("area exact", is_equal_approx(r1.covered_area(), 128.0), str(r1.covered_area()))

	var l := PixelShape.new()
	for x in 8:
		l.set_pixel(x, 0, 1)
	for y in 8:
		l.set_pixel(0, y, 1)
	var r2 := GreedyRects.decompose(l)
	_check("L -> 2 rects", r2.rect_count() == 2, str(r2.rects))
	_check("L area == 15", is_equal_approx(r2.covered_area(), 15.0), str(r2.covered_area()))

	# 破坏后的残块
	Destruction.apply_damage(solid, Destruction.Damage.circle(Vector2(8.0, 4.0), 3.5))
	var r3 := GreedyRects.decompose(solid)
	_check("damaged area == pixels", is_equal_approx(r3.covered_area(), float(solid.pixel_count())),
		"%f vs %d (rects=%d)" % [r3.covered_area(), solid.pixel_count(), r3.rect_count()])
	# 不重叠
	var overlap := false
	for i in r3.rects.size():
		for j in range(i + 1, r3.rects.size()):
			var a: Rect2 = r3.rects[i]
			var b: Rect2 = r3.rects[j]
			if a.intersects(b, false):
				overlap = true
	_check("rects do not overlap", not overlap)

func _test_mass_props() -> void:
	print("[mass props]")
	var s := PixelShape.new()
	for y in 8:
		for x in 8:
			s.set_pixel(x, y, 1)
	var p := MassProps.compute(s)
	_check("mass == 64", is_equal_approx(p.mass, 64.0), str(p.mass))
	_check("com centered", p.com.is_equal_approx(Vector2(4.0, 4.0)), str(p.com))
	_check("inertia ~682.67", absf(p.inertia - 682.6667) < 0.01, str(p.inertia))
	# 破坏后质量自动下降
	Destruction.apply_damage(s, Destruction.Damage.rect(Vector2(6.0, 4.0), Vector2(2.0, 4.0)))
	var p2 := MassProps.compute(s)
	_check("mass after damage", is_equal_approx(p2.mass, 32.0), str(p2.mass))
	_check("com shifts to x=2", p2.com.is_equal_approx(Vector2(2.0, 4.0)), str(p2.com))
