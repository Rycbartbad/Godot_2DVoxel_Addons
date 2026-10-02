extends RefCounted
## 从像素分布推导质量属性 —— 这是 Teardown 的核心机制：
##   mass    = Σ density(material)
##   com     = Σ density * p / mass
##   inertia = Σ density * (|p - com|^2 + 1/6)     （1x1 方块绕自身中心的极惯性矩 = 1/6）
##
## 因此"炸掉半面墙，质量自动减半"是免费的，不需要任何脚本干预。

const Bits := preload("res://addons/pixel_destruction/core/pixel_bits.gd")
const PixelChunk := preload("res://addons/pixel_destruction/core/pixel_chunk.gd")
const PixelShape := preload("res://addons/pixel_destruction/core/pixel_shape.gd")

class Props:
	var mass := 0.0
	var com := Vector2.ZERO
	var inertia := 0.0
	var pixel_count := 0

	func inv_mass() -> float:
		return 0.0 if mass <= 0.0 else 1.0 / mass

	func inv_inertia() -> float:
		return 0.0 if inertia <= 0.0 else 1.0 / inertia


## density_of: Callable(material:int) -> float，默认全部为 1.0
static func compute(shape: PixelShape, density_of: Callable = Callable()) -> Props:
	## 单趟扫描：同时累加质量、一阶矩与"绕原点的极惯性矩"，
	## 再用平行轴定理换算到质心：I_com = I_origin - m * |com|^2。
	## （逐像素循环是 GDScript 里最贵的部分，能少扫一趟就少一趟。）
	var p := Props.new()
	var m := 0.0
	var sx := 0.0
	var sy := 0.0
	var i_origin := 0.0
	var n := 0
	for k: int in shape.chunks:
		var c: PixelChunk = shape.chunks[k]
		var bx := PixelShape.key_x(k) << 3
		var by := PixelShape.key_y(k) << 3
		var bits := c.occ
		while bits != 0:
			var i := Bits.first_bit_index(bits)
			bits &= bits - 1
			var px := float(bx + (i & 7)) + 0.5
			var py := float(by + (i >> 3)) + 0.5
			var d := 1.0
			if density_of.is_valid():
				d = density_of.call(c.mat[i])
			# 形状级的密度倍率（Teardown 的 SetShapeDensity）。默认 1.0，不影响既有行为。
			d *= shape.density_scale
			m += d
			sx += d * px
			sy += d * py
			i_origin += d * (px * px + py * py + 1.0 / 6.0)
			n += 1
	p.pixel_count = n
	if m <= 0.0 or n == 0:
		return p
	p.mass = m
	p.com = Vector2(sx / m, sy / m)
	p.inertia = maxf(0.0, i_origin - m * p.com.length_squared())
	return p
