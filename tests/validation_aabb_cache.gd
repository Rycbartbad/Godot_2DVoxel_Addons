extends SceneTree
## 验证：AABB 缓存必须"该留的留、该扔的扔"，而且留下来的值必须是对的。
##
## ⚠️⚠️ 为什么必须有这个测试：
##    local_aabb() 是缓存，而**缓存判错不会报错** —— 它只会让 decompose() 拿着
##    一个过期的 AABB 去建网格，于是画出来的形状和碰撞体错位
##    （用户报过两次，两次都是"看起来差不多、其实差几十像素"那种）。
##    所以这里用**独立算法**（逐像素扫 get_pixel）当参照物，
##    绝不拿缓存自己的值当预期值 —— 那等于用被检验的东西证明它自己。
##
## 背景见 PixelShape._bounds_rev 的说明：内部擦除严格在 AABB 内部，
## 不可能改变 AABB，所以不该作废缓存（768x100 地面每笔省 3.3 ms 起）。

const PixelShape := preload("res://src/core/pixel_shape.gd")

var _pass := 0
var _fail := 0

func _check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		_pass += 1
		print("  PASS  %s   %s" % [name, detail])
	else:
		_fail += 1
		print("  FAIL  %s   %s" % [name, detail])

## 独立参照物：逐像素扫出 AABB，完全不碰缓存。
func _brute_aabb(s: PixelShape, x0: int, y0: int, x1: int, y1: int) -> Rect2i:
	var min_x := 1 << 30
	var min_y := 1 << 30
	var max_x := -(1 << 30)
	var max_y := -(1 << 30)
	for y in range(y0, y1):
		for x in range(x0, x1):
			if s.get_pixel(x, y) != 0:
				min_x = mini(min_x, x)
				max_x = maxi(max_x, x + 1)
				min_y = mini(min_y, y)
				max_y = maxi(max_y, y + 1)
	if max_x <= min_x:
		return Rect2i()
	return Rect2i(min_x, min_y, max_x - min_x, max_y - min_y)

func _initialize() -> void:
	print("=== AABB 缓存 ===")
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, 40, 30), 1)
	var ref := _brute_aabb(s, -8, -8, 48, 38)
	_check("初始 AABB 与逐像素扫描一致", s.local_aabb() == ref, "%s" % str(s.local_aabb()))
	_check("初始 AABB 就是 40x30", ref == Rect2i(0, 0, 40, 30), "%s" % str(ref))

	# 1) 严格在内部 -> 缓存必须留下
	var rev0: int = s._bounds_rev
	s.mark_dirty_range(Rect2i(10, 10, 4, 4))
	_check("内部 mark_dirty_range 保留缓存", s._bounds_rev == rev0, "_bounds_rev=%d" % s._bounds_rev)
	_check("内部改动后仍与扫描一致", s.local_aabb() == ref, "%s" % str(s.local_aabb()))

	# 2) 贴边（左沿）-> 必须作废
	s.mark_dirty_range(Rect2i(0, 10, 2, 2))
	_check("贴左沿 mark_dirty_range 作废缓存", s._bounds_rev != rev0, "_bounds_rev=%d" % s._bounds_rev)

	# 3) 贴边（右下开区间那一侧）-> 必须作废
	s.local_aabb()
	var rev_r: int = s._bounds_rev
	s.mark_dirty_range(Rect2i(38, 10, 2, 2))
	_check("贴右沿（x+size == AABB 右沿）作废缓存", s._bounds_rev != rev_r, "_bounds_rev=%d" % s._bounds_rev)

	# 4) 正好差 1 像素在里面 -> 保留；差 0 像素（贴边）-> 作废
	s.local_aabb()
	var rev_t: int = s._bounds_rev
	s.mark_dirty_range(Rect2i(1, 1, 4, 4))
	_check("离左沿 1 像素的改动保留缓存", s._bounds_rev == rev_t, "_bounds_rev=%d" % s._bounds_rev)

	# 5) touch() 不知道改了哪里 -> 必须作废
	var rev1: int = s._bounds_rev
	s.touch()
	_check("touch() 作废缓存", s._bounds_rev != rev1)

	# 6) 逐像素写 -> 必须作废
	var rev2: int = s._bounds_rev
	s.clear_pixel(20, 20)
	_check("clear_pixel 作废缓存", s._bounds_rev != rev2)

	# 7) 缓存过期时，_aabb_survives 不许"装作知道"
	_check("缓存过期时 _aabb_survives 一律 false", not s._aabb_survives(Rect2i(21, 21, 2, 2)))

	# 8) 真的把 AABB 擦小了 -> 重算后必须跟上（缓存不能是"只进不出"）
	var s2 := PixelShape.new()
	s2.fill_rect(Rect2i(0, 0, 20, 20), 1)
	var r_a := s2.local_aabb()
	s2.fill_rect(Rect2i(0, 0, 20, 1), 0)
	var r_b := s2.local_aabb()
	_check("擦掉顶行后 AABB 收缩", r_a == Rect2i(0, 0, 20, 20) and r_b == Rect2i(0, 1, 20, 19),
			"%s -> %s" % [str(r_a), str(r_b)])
	_check("收缩后仍与扫描一致", r_b == _brute_aabb(s2, -8, -8, 28, 28), "%s" % str(r_b))

	# 9) 空形状：任何改动都不许被当成"内部"
	var s3 := PixelShape.new()
	s3.local_aabb()
	_check("空形状 _aabb_survives 为 false", not s3._aabb_survives(Rect2i(0, 0, 1, 1)))
	_check("空形状 AABB 为空", s3.local_aabb() == Rect2i())

	# 10) 负坐标（形状可以整个在原点左上）
	var s4 := PixelShape.new()
	s4.fill_rect(Rect2i(-30, -20, 12, 9), 1)
	_check("负坐标 AABB 与扫描一致", s4.local_aabb() == _brute_aabb(s4, -40, -30, -10, 0),
			"%s" % str(s4.local_aabb()))

	print("=== %d passed, %d failed ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
