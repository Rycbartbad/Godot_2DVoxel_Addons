extends SceneTree
## 凸包（多边形碰撞箱拟合）的实测代价 —— 与 AABB 并列的另一种包围体。
##
## 量三件事（都是"猜之前先量"的规矩）：
##   1. HullFit.fit() 的**首次**代价（按形状尺寸走：768x100 的地面是 1248 块）；
##   2. local_hull() 的**缓存命中**代价 —— 必须接近 0，否则"惰性"是假的；
##   3. world_hull() 在 300 个碎块上的缓存命中 / 位姿变化后重算。
##
## ⚠️ 不进 tools/test_list.py：它是**量尺**不是闸门（数字会随机器变）。
##    但数字要写进 docs/manual/performance.md —— 那里是选路的依据。

const HullFit := preload("res://src/core/hull_fit.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")
const PBody := preload("res://src/physics/pbody.gd")

var _pass := 0
var _fail := 0
func _c(n: String, ok: bool, d: String = "") -> void:
	if ok:
		_pass += 1
		print("  PASS  ", n, "  ", d)
	else:
		_fail += 1
		print("  FAIL  ", n, "  ", d)


func _us(ms: float) -> String:
	return "%.3f ms" % ms


func _time_us(call: Callable, n: int) -> float:
	var t0 := Time.get_ticks_usec()
	for i in n:
		call.call()
	return float(Time.get_ticks_usec() - t0) / float(n) / 1000.0


func _initialize() -> void:
	var ground := PixelShape.new()
	ground.fill_rect(Rect2i(0, 0, 768, 100), 1)
	var block := PixelShape.new()
	block.fill_rect(Rect2i(0, 0, 64, 64), 1)
	var lshape := PixelShape.new()
	lshape.fill_rect(Rect2i(0, 0, 64, 8), 1)
	lshape.fill_rect(Rect2i(0, 0, 8, 64), 1)
	var debris := PixelShape.new()
	debris.fill_rect(Rect2i(0, 0, 8, 8), 1)

	print("=== 凸包代价（像素数 / 块数 / 顶点数 / 首次 / 缓存命中）===")
	for s: PixelShape in [ground, block, lshape, debris]:
		# 首次：清掉缓存再量
		s._hull_rev = -1
		var t0 := Time.get_ticks_usec()
		var h := s.local_hull()
		var first := float(Time.get_ticks_usec() - t0) / 1000.0
		var cached := _time_us(func() -> void: s.local_hull(), 2000)
		print("  像素 %6d  块 %5d  顶点 %3d   首次 %s   缓存 %s"
			% [s.pixel_count(), s.chunks.size(), h.size(), _us(first), _us(cached)])
		_c("缓存命中应当远快于首次", cached < maxf(first * 0.2, 0.002),
			"首次 %s vs 缓存 %s" % [_us(first), _us(cached)])

	# ---- 300 个碎块：world_hull 的两种路径 ----
	var bodies: Array = []
	for i in 300:
		var b := PBody.new()
		b.position = Vector2(i % 20 * 20, i / 20 * 20)
		b.rotation = float(i) * 0.07
		b.rebuild([debris])
		bodies.append(b)
	var cached_w := _time_us(func() -> void:
		for b: PBody in bodies:
			b.world_hull(), 200)
	print("  300 个碎块：world_hull 缓存命中 = %s/趟（%.3f us/个）"
		% [_us(cached_w), cached_w * 1000.0 / 300.0])
	var moved_w := _time_us(func() -> void:
		for b: PBody in bodies:
			b.rotation += 0.001
			b.world_hull(), 20)
	print("  300 个碎块：位姿变了之后重算 = %s/趟（%.3f us/个）"
		% [_us(moved_w), moved_w * 1000.0 / 300.0])
	_c("world_hull 缓存命中应当极便宜", cached_w < 0.5, _us(cached_w))
	_c("位姿变化后重算仍应便宜（300 个 < 2 ms）", moved_w < 2.0, _us(moved_w))

	print("=== %d passed, %d failed ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
