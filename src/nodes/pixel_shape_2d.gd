@tool
class_name PixelShape2D
extends Node2D
## 一个**形状子节点** —— 对应 Godot 内置的 CollisionShape2D。
##
## ## 为什么形状要做成子节点
##
## 内置引擎就是这么分的：RigidBody2D 管动力学，CollisionShape2D 管形状，
## 两者是父子关系。好处是：
##   · **可组合** —— 一个刚体挂多个形状子节点，每个独立变换；
##   · **可继承** —— 把一个形状做成场景，到处实例化；
##   · **可视** —— 每个形状在编辑器里单独选中、拖动、改属性。
##
## 之前形状是 PixelBody2D 上的一个属性，以上一条都做不到。
##
## ## 接口约定
##
## 本节点只承诺一个方法：build_shape() -> PixelShape。
## PixelBody2D 不关心子节点是什么类型，**只认这个方法** ——
## 以后要加「从 SVG 生成」「程序化生成」的形状子节点，继承本类重写它即可，
## 不用改 PixelBody2D 一行代码。
##
## position 就是形状的**原点**（局部像素 (0,0)），可以相对刚体拖动。
## 旋转会让像素格相对刚体倾斜 —— 引擎支持，但像素画一般不这么用。

const PixelShape := preload("res://src/core/pixel_shape.gd")

enum Source { RECT, CIRCLE, TEXTURE }

@export var source: Source = Source.RECT

@export_group("形状")
@export var rect_size := Vector2i(16, 16)      ## source=RECT
@export var radius := 8.0                      ## source=CIRCLE
@export var texture: Texture2D                 ## source=TEXTURE
@export_range(1, 254) var alpha_threshold := 128

@export_group("材质")
## 材质 id。决定颜色与密度（材质表在 PixelWorld 上）。
@export_range(1, 254) var material_id := 1


## ---- 接口：继承本类并重写它，就能提供任意形状 ----
func build_shape() -> PixelShape:
	var s := PixelShape.new()
	var sc := Vector2(maxf(0.01, absf(scale.x)), maxf(0.01, absf(scale.y)))
	# 形状子节点相对刚体的偏移 —— 像素格必须落在整数上
	var ox := int(round(position.x))
	var oy := int(round(position.y))
	match source:
		Source.RECT:
			var w := maxi(1, roundi(float(rect_size.x) * sc.x))
			var h := maxi(1, roundi(float(rect_size.y) * sc.y))
			s.fill_rect(Rect2i(ox, oy, w, h), material_id)
		Source.CIRCLE:
			var rx := maxf(0.5, radius * sc.x)
			var ry := maxf(0.5, radius * sc.y)
			for y in int(ceil(ry)) * 2 + 1:
				for x in int(ceil(rx)) * 2 + 1:
					var nx := (float(x) - rx) / rx
					var ny := (float(y) - ry) / ry
					if nx * nx + ny * ny <= 1.0:
						s.set_pixel(ox + x, oy + y, material_id)
		Source.TEXTURE:
			if texture != null:
				var img := texture.get_image()
				if img != null:
					if img.is_compressed():
						img.decompress()
					img.convert(Image.FORMAT_RGBA8)
					var w2 := img.get_width()
					var h2 := img.get_height()
					var ow := maxi(1, roundi(float(w2) * sc.x))
					var oh := maxi(1, roundi(float(h2) * sc.y))
					var sx := float(w2) / float(ow)
					var sy := float(h2) / float(oh)
					for y2 in oh:
						var src_y := clampi(int(float(y2) * sy), 0, h2 - 1)
						for x2 in ow:
							var src_x := clampi(int(float(x2) * sx), 0, w2 - 1)
							if img.get_pixel(src_x, src_y).a * 255.0 >= float(alpha_threshold):
								s.set_pixel(ox + x2, oy + y2, material_id)
			else:
				push_warning("PixelShape2D: source=TEXTURE 但没设 texture")
	return s
