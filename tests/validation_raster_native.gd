extends SceneTree
## 原生栅格化（PixelRaster.fill_region）vs GDScript 参照实现的**逐字节对拍**闸门。
##
## ⚠️ 为什么必须有这一条："形状 -> RGBA8 图"这条规则现在写了**两份** ——
##    gdext/fastphys.cpp 的 op 1，与 src/render/pixel_renderer.gd 的
##    _build_region_image_gd。本仓库在"同一规则写两处"上栽过太多次
##    （GDScript 侧改了 C++ 侧没改，接触点差出 3.88 个单位），所以原生化必须配
##    一条**逐字节**判据 —— 不是"看起来一样"。
##
## 判据有两条，缺一不可：
##   ① 两条路的 Image.get_data() 逐字节相等；
##   ② **原生那条真的被走了**（native_calls / native_fallbacks 计数）——
##      否则"退回了 GDScript"会让本闸门静默变成同义反复（结果当然一样）。
const PixelRenderer := preload("res://src/render/pixel_renderer.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

var _pass := 0
var _fail := 0
func _c(n: String, ok: bool, d: String = "") -> void:
	if ok: _pass += 1; print("  PASS  ", n, "  ", d)
	else: _fail += 1; print("  FAIL  ", n, "  ", d)

var _r = null
var _rng := RandomNumberGenerator.new()
var _cases := 0

## 两条路各画一次，逐字节比。
func _cmp(label: String, shapes: Array, aabb: Rect2i, region: Rect2i) -> void:
	_cases += 1
	_r.native_calls = 0
	_r.native_fallbacks = 0
	var a: Image = _r._build_region_image_native(shapes, aabb, region)
	var calls: int = _r.native_calls
	var backs: int = _r.native_fallbacks
	var b: Image = _r._build_region_image_gd(shapes, aabb, region)
	var same: bool = a.get_width() == b.get_width() and a.get_height() == b.get_height() \
			and a.get_data() == b.get_data()
	var took: bool = calls == 1 and backs == 0
	_c(label, same and took, "aabb=%s region=%s%s" % [str(aabb), str(region),
		"" if took else " **没走原生**（calls=%d fallbacks=%d）" % [calls, backs]])

## 随机造形状：一块底板 + 若干随机小矩形（材质 id 故意超出调色板长度）。
func _random_shape(w: int, h: int, origin: Vector2i, mat_max: int, rects: int) -> PixelShape:
	var s := PixelShape.new()
	s.fill_rect(Rect2i(origin, Vector2i(w, h)), _rng.randi_range(1, mat_max))
	for i in rects:
		var rw := _rng.randi_range(1, maxi(2, w / 2))
		var rh := _rng.randi_range(1, maxi(2, h / 2))
		var rx := origin.x + _rng.randi_range(-4, w)
		var ry := origin.y + _rng.randi_range(-4, h)
		s.fill_rect(Rect2i(rx, ry, rw, rh), _rng.randi_range(1, mat_max))
	return s

## 一个形状的几种区域：整块 / 一块 64 的瓦片 / 跨块边界 / 部分越界 / 完全在外。
func _sweep(label: String, s: PixelShape) -> void:
	var aabb: Rect2i = s.local_aabb()
	if aabb.size.x <= 0 or aabb.size.y <= 0:
		return
	_cmp(label + " 整个 aabb", [s], aabb, aabb)
	_cmp(label + " 64 瓦片", [s], aabb, Rect2i(0, 0, mini(64, aabb.size.x), mini(64, aabb.size.y)))
	_cmp(label + " 跨块边界", [s], aabb, Rect2i(3, 5, 27, 19))
	_cmp(label + " 右下半", [s], aabb,
		Rect2i(aabb.size.x / 2, aabb.size.y / 2, aabb.size.x - aabb.size.x / 2, aabb.size.y - aabb.size.y / 2))
	_cmp(label + " 部分越界", [s], aabb, Rect2i(-10, -10, aabb.size.x + 5, aabb.size.y + 5))
	_cmp(label + " 完全在外", [s], aabb, Rect2i(aabb.size.x + 500, aabb.size.y + 500, 16, 16))

func _initialize() -> void:
	print("=== 原生栅格化 vs GDScript 参照实现（逐字节）===")
	if not ClassDB.class_exists("PixelRaster"):
		printerr("PixelRaster 扩展不可用 —— 先跑 python tools/build_native.py 重编 fastphys.dll")
		print("=== 0 passed, 1 failed ===")
		quit(1)
		return
	_r = PixelRenderer.new()
	get_root().add_child(_r)
	_r._ensure_raster()
	_rng.seed = 20261006

	# ---- 1. 手工边界情形 ----
	var empty := PixelShape.new()
	var one := PixelShape.new(); one.set_pixel(3, 4, 1)
	var full8 := PixelShape.new(); full8.fill_rect(Rect2i(0, 0, 8, 8), 2)
	var big := PixelShape.new(); big.fill_rect(Rect2i(-20, -20, 100, 50), 1)
	var hole := PixelShape.new()
	hole.fill_rect(Rect2i(0, 0, 64, 64), 3)
	hole.clear_pixel(10, 10)
	hole.clear_pixel(63, 63)
	_cmp("单个像素", [one], one.local_aabb(), one.local_aabb())
	_cmp("刚好一块 8x8", [full8], full8.local_aabb(), full8.local_aabb())
	_cmp("负原点", [big], big.local_aabb(), Rect2i(-25, -25, 60, 40))
	_cmp("带洞的块", [hole], hole.local_aabb(), Rect2i(0, 0, 64, 64))
	_cmp("带洞的块（洞那一小块）", [hole], hole.local_aabb(), Rect2i(8, 8, 8, 8))
	_cmp("空形状", [empty], Rect2i(0, 0, 1, 1), Rect2i(0, 0, 1, 1))
	_cmp("空形状（大区域）", [empty], Rect2i(0, 0, 1, 1), Rect2i(0, 0, 32, 32))

	# ---- 2. 多 shape（同一局部坐标系，一个 body 挂几个形状）----
	var s1 := PixelShape.new(); s1.fill_rect(Rect2i(0, 0, 30, 30), 1)
	var s2 := PixelShape.new(); s2.fill_rect(Rect2i(20, 20, 30, 30), 4)
	var both: Rect2i = s1.local_aabb().merge(s2.local_aabb())
	_cmp("两个形状（重叠区）", [s1, s2], both, Rect2i(15, 15, 20, 20))
	_cmp("两个形状（全部）", [s1, s2], both, both)

	# ---- 3. 随机（含非 8 倍数原点、负数原点、越界材质 id）----
	for i in 60:
		var w := _rng.randi_range(1, 90)
		var h := _rng.randi_range(1, 70)
		var org := Vector2i(_rng.randi_range(-30, 30), _rng.randi_range(-30, 30))
		var s := _random_shape(w, h, org, 12, 6)
		_sweep("随机 #%d" % i, s)
	print("  随机形状比对 %d 组" % _cases)

	# ---- 4. 调色板变体（表是预算好交给原生的，最容易在这里分叉）----
	var probe := PixelShape.new(); probe.fill_rect(Rect2i(0, 0, 40, 40), 5)
	var pa := probe.local_aabb()
	_r.palette = [Color(0, 0, 0, 0), Color(1.0, 0.5, 0.25, 0.3)]
	_cmp("2 项调色板（材质 id 要 clamp + alpha 半透明）", [probe], pa, Rect2i(0, 0, 24, 24))
	_r.palette = [Color(0.9, 0.1, 0.2, 0.05)]
	_cmp("1 项调色板（全部 clamp 到 0）", [probe], pa, Rect2i(0, 0, 16, 16))
	var long_pal: Array = []
	for i in 300:
		long_pal.append(Color(float(i % 7) / 7.0, float(i % 5) / 5.0, float(i % 3) / 3.0, 1.0))
	_r.palette = long_pal
	_cmp("300 项调色板", [probe], pa, Rect2i(0, 0, 32, 32))
	_r.palette = [Color(0, 0, 0, 0), Color(1, 0, 0), Color(0, 1, 0), Color(0, 0, 1), Color(1, 1, 0), Color(1, 0, 1)]
	_cmp("换表之后第一笔", [probe], pa, Rect2i(0, 0, 20, 20))
	_r.palette[1] = Color(0.0, 1.0, 1.0, 0.0)     # 就地改一格
	_cmp("就地改一格调色板", [probe], pa, Rect2i(0, 0, 20, 20))
	_r.palette = [Color(0, 0, 0, 0), Color(0.62, 0.60, 0.56), Color(0.72, 0.52, 0.32)]

	# ---- 5. 分发：shading 关走原生；shading 开只能走 GDScript ----
	_r.shading = false
	_r.native_calls = 0
	var img1: Image = _r._build_region_image([probe], pa, Rect2i(0, 0, 16, 16))
	_c("shading 关时 _build_region_image 走原生", _r.native_calls == 1, "calls=%d" % _r.native_calls)
	_r.shading = true
	_r.native_calls = 0
	var img2: Image = _r._build_region_image([probe], pa, Rect2i(0, 0, 16, 16))
	_c("shading 开时不走原生", _r.native_calls == 0, "calls=%d" % _r.native_calls)
	var img3: Image = _r._build_region_image_gd([probe], pa, Rect2i(0, 0, 16, 16))
	_c("shading 开时与参照实现逐字节一致", img2.get_data() == img3.get_data())
	_r.shading = false
	_c("关掉 shading 之后原生又能走", _r._build_region_image([probe], pa, Rect2i(0, 0, 8, 8)) != null)
	if img1 == null:
		print("never")

	print("=== %d passed, %d failed（共 %d 组逐字节比对）===" % [_pass, _fail, _cases])
	quit(1 if _fail > 0 else 0)