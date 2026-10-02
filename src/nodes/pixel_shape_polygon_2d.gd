@tool
class_name PixelShapePolygon2D
# ⚠️ 用**路径式 extends** 而不是 "extends PixelShape2D"：
#    addon 里也有一份同名脚本，靠全局 class_name 解析在缓存不一致时会失败
#    （实测报 "Could not find base class PixelShape2D"）。路径是确定的。
extends "res://src/nodes/pixel_shape_2d.gd"
## 用**任意多边形**填充像素 —— 演示「继承 PixelShape2D 就能加一种新形状」。
##
## ## 它证明了什么
##
## 这个文件**没有改 PixelBody2D / PixelWorld / 渲染器的任何一行代码**。
## 只要继承 PixelShape2D 并重写 build_shape()，新形状就自动获得：
##   · 碰撞（PixelBody2D 的 collect_shapes() 只认方法，不认类型）
##   · 渲染（PixelSprite2D 同理）
##   · 编辑器可视化（父类的 _draw 抓手）
##   · 物理的一切（质量、惯量、破坏、查询都作用于"像素集"，不关心它怎么来的）
##
## ## 为什么多边形有用
##
## 关卡地形用矩形拼是折磨。有了它，斜坡、三角形屋顶、任意轮廓都能直接填成体素。
## 斜坡尤其重要 —— 像素游戏里的"斜坡"实际就是阶梯状的体素，这个类就是那个转换器。
##
## ## 用点
##
## 顶点的坐标就是**局部像素坐标**（和形状的原点同一套）。
## 因为是像素画，"坡度"最终会量化成阶梯 —— 这是对的，物理用的就是那些像素。

## 多边形顶点（局部像素坐标，按顺序，自动闭合）
@export var points := PackedVector2Array([
	Vector2(0, 32), Vector2(32, 0), Vector2(64, 32), Vector2(64, 64), Vector2(0, 64),
])
## 顶点按这个倍数缩放（做"整体拉伸"用；改 points 也行，这个更方便）
@export var point_scale := Vector2(1, 1)
## 轮廓向内收缩的像素数。>0 给形状留一圈边（避免斜坡顶端只有 1 像素宽而抖）
@export var inset := 0


func build_shape() -> PixelShape:
	var s := PixelShape.new()
	if points.size() < 3:
		push_warning("PixelShapePolygon2D: 顶点少于 3 个，形状为空")
		return s
	var sc := Vector2(maxf(0.01, absf(scale.x)), maxf(0.01, absf(scale.y)))
	var k := Vector2(point_scale.x * sc.x, point_scale.y * sc.y)
	# 形状子节点相对刚体的偏移
	var ox := int(round(position.x))
	var oy := int(round(position.y))
	# 顶点转到整数像素坐标
	var poly := PackedVector2Array()
	var min_x := 1 << 30
	var max_x := -(1 << 30)
	var min_y := 1 << 30
	var max_y := -(1 << 30)
	for p in points:
		var q := Vector2(p.x * k.x, p.y * k.y)
		poly.append(q)
		min_x = mini(min_x, int(floor(q.x)))
		max_x = maxi(max_x, int(ceil(q.x)))
		min_y = mini(min_y, int(floor(q.y)))
		max_y = maxi(max_y, int(ceil(q.y)))
	if max_x <= min_x or max_y <= min_y:
		return s
	# 扫描线：逐行求与多边形边的交点，再按交点区间填充。
	# 比"逐像素做奇偶判定"快得多（一行只算几个交点），而且天然处理凹多边形。
	for y in range(min_y, max_y):
		var cy := float(y) + 0.5
		var xs := PackedFloat32Array()
		var n := poly.size()
		for i in n:
			var a := poly[i]
			var b := poly[(i + 1) % n]
			# 半开区间 [ay, by) 避免顶点被数两次（经典陷阱）
			if (a.y <= cy and b.y > cy) or (b.y <= cy and a.y > cy):
				var t := (cy - a.y) / (b.y - a.y)
				xs.append(a.x + (b.x - a.x) * t)
		if xs.size() < 2:
			continue
		xs.sort()
		var j := 0
		while j + 1 < xs.size():
			var x0 := int(ceil(xs[j] - 0.5)) + inset
			var x1 := int(floor(xs[j + 1] - 0.5)) - inset
			for x in range(x0, x1 + 1):
				s.set_pixel(ox + x, oy + y, material_id)
			j += 2
	return s
