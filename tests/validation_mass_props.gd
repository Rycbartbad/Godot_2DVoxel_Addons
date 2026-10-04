extends SceneTree
## 质量属性快路径（整块同材质 -> 行/列 popcount 边际量）的**差分闸门**。
##
## ⚠️⚠️ 为什么参照物必须是**冻结的旧公式**而不是"新实现自己"：
##    MassProps.compute 现在有两条路 —— 整块同材质走边际量快路径，
##    混材质走逐像素慢路径。快路径做的是**数值重排**（浮点累加顺序变了），
##    算错了不会报错，只会让质量/惯量悄悄偏一点，然后物理慢慢漂。
##    所以这里把旧的逐像素公式原样抄一份当参照物，逐项比对。
##
## ⚠️ 判据是 1e-12 **相对**误差：重排必然带来末位差异，不能要求逐位相同；
##    但物理上 1e-12 与逐位相同没有区别（交给 Rapier 时还要过一遍 f32）。
##    ⚠️ 另一道闸门是 8 条基准**逐位不变** —— 那才是最终判据。

const PixelShape := preload("res://src/core/pixel_shape.gd")
const MassProps := preload("res://src/core/mass_props.gd")
const Bits := preload("res://src/core/pixel_bits.gd")

var passed := 0
var failed := 0

func _assert(cond: bool, msg: String) -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		print("  [失败] " + msg)

## 旧公式原样冻结：逐像素累加
func _old(s: PixelShape) -> Array:
	var m := 0.0
	var sx := 0.0
	var sy := 0.0
	var io := 0.0
	var n := 0
	for k: int in s.chunks:
		var c = s.chunks[k]
		var bx := PixelShape.key_x(k) << 3
		var by := PixelShape.key_y(k) << 3
		var bits: int = c.occ
		while bits != 0:
			var i: int = Bits.first_bit_index(bits)
			bits &= bits - 1
			var px := float(bx + (i & 7)) + 0.5
			var py := float(by + (i >> 3)) + 0.5
			m += 1.0
			sx += px
			sy += py
			io += px * px + py * py + 1.0 / 6.0
			n += 1
	var com := Vector2(sx / m, sy / m) if m > 0.0 else Vector2.ZERO
	var inertia := maxf(0.0, io - m * com.length_squared())
	return [m, com, inertia, n]

func _rel(a: float, b: float) -> float:
	var d: float = absf(a - b)
	var s: float = maxf(absf(a), absf(b))
	return 0.0 if s < 1e-12 else d / s

func _check(s: PixelShape, label: String) -> void:
	var old := _old(s)
	var p := MassProps.compute(s, Callable())
	_assert(p.pixel_count == int(old[3]), "%s：像素数 %d != %d" % [label, p.pixel_count, old[3]])
	_assert(_rel(p.mass, old[0]) <= 1e-12, "%s：质量 %.15f != %.15f" % [label, p.mass, old[0]])
	_assert(_rel(p.com.x, (old[1] as Vector2).x) <= 1e-12, "%s：质心 x 不一致" % label)
	_assert(_rel(p.com.y, (old[1] as Vector2).y) <= 1e-12, "%s：质心 y 不一致" % label)
	_assert(_rel(p.inertia, old[2]) <= 1e-12, "%s：惯量 %.15f != %.15f" % [label, p.inertia, old[2]])
	print("  %-24s 质量 %10.4f 惯量 %14.4f 像素 %6d" % [label, p.mass, p.inertia, p.pixel_count])

func _initialize() -> void:
	print("=== 质量快路径 vs 冻结的旧逐像素公式 ===")
	var a := PixelShape.new()
	a.fill_rect(Rect2i(0, 0, 100, 40), 1)
	_check(a, "实心 100x40（单材质）")
	var b := PixelShape.new()
	b.fill_rect(Rect2i(0, 0, 100, 40), 1)
	b.fill_rect(Rect2i(10, 10, 30, 20), 2)
	_check(b, "混材质（块内两种）")
	var c := PixelShape.new()
	c.fill_rect(Rect2i(3, 5, 17, 9), 1)
	_check(c, "不满块 17x9")
	var d := PixelShape.new()
	d.fill_rect(Rect2i(-20, -20, 30, 30), 3)
	_check(d, "负坐标 30x30")
	var e := PixelShape.new()
	for i in 40:
		e.set_pixel(i * 3, (i * 7) % 23, 1 + (i % 3))
	_check(e, "稀疏多材质")
	var f := PixelShape.new()
	_check(f, "空形状")
	# 单像素（极端：n=1，n/6 与逐像素 1/6 必须一致）
	var g := PixelShape.new()
	g.set_pixel(7, 9, 1)
	_check(g, "单像素")
	print("---")
	if failed == 0:
		print("全部通过：%d 项断言" % passed)
	else:
		print("失败 %d / %d 项" % [failed, passed + failed])
	quit(0 if failed == 0 else 1)
