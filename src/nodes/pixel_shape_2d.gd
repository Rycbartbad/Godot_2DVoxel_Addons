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

@export var source: Source = Source.RECT:
	set(v):
		source = v
		invalidate_shape()

@export_group("形状")
@export var rect_size := Vector2i(16, 16):     ## source=RECT
	set(v):
		rect_size = v
		invalidate_shape()
@export var radius := 8.0:                     ## source=CIRCLE
	set(v):
		radius = v
		invalidate_shape()
@export var texture: Texture2D:                ## source=TEXTURE
	set(v):
		texture = v
		invalidate_shape()
@export_range(1, 254) var alpha_threshold := 128:
	set(v):
		alpha_threshold = v
		invalidate_shape()

@export_group("材质")
## 材质 id。决定颜色与密度（材质表在 PixelWorld 上）。
@export_range(1, 254) var material_id := 1:
	set(v):
		material_id = v
		invalidate_shape()


## ---- 形状缓存 ----
##
## ## 为什么缓存必须由框架做，而不是留给子类
##
## build_shape() 可能很贵：800x40 的地面是 **32000 次 set_pixel**。
## 而编辑器里拖一下刚体，父 PixelWorld 就会**重建整个世界** ——
## 也就是对每个形状重算一遍。**拖动卡顿的根因就在这里。**
##
## 子类只管实现 build_shape()，缓存由本类负责（setter 与变换通知会自动失效）。
var _cache: PixelShape = null
var _cache_valid := false


func _enter_tree() -> void:
	# ⚠️ 必须显式打开，否则 NOTIFICATION_TRANSFORM_CHANGED 不会发 ——
	#    拖动本形状子节点时缓存就不会失效，形状停在旧位置。
	set_notify_transform(true)
	_apply_editor_visibility()


## 编辑器里是否隐藏本节点（默认隐藏）。
##
## ## 为什么必须隐藏
##
## 形状子节点的 position 与刚体原点**必然重合**（形状原点就是刚体原点），
## 而 2D 编辑器的拾取在重叠时**优先命中子节点** ——
## 于是每次想拖刚体，拖到的都是形状。实测就是这个问题。
##
## 编辑器**不拾取不可见的 item**，这是唯一能改的场景图机制。
##
## 损失为零：形状本来什么都不画（碰撞外接是 PixelBody2D 画的），
## 所以隐藏前后画面完全一样，只是不再抢点击。
##
## 想改形状参数：在场景树里选中它，或者直接在 Inspector 里改数值。
## 真的需要它可见（比如一个刚体挂多个形状、要对齐它们），把这里关掉即可。
@export var hide_in_editor := true


func _apply_editor_visibility() -> void:
	if Engine.is_editor_hint():
		visible = not hide_in_editor


func _notification(what: int) -> void:
	# 变换（position/scale/rotation）变了，形状的生成结果就变了
	if what == NOTIFICATION_TRANSFORM_CHANGED and Engine.is_editor_hint():
		invalidate_shape()
		_apply_editor_visibility()


## 取形状（带缓存）。**PixelBody2D 用这个，不要直接调 build_shape()。**
func get_shape() -> PixelShape:
	if not _cache_valid:
		_cache = build_shape()
		_cache_valid = true
	return _cache


## 让缓存失效，并通知父世界重烘焙。
##
## ⚠️ 不通知父世界的话，编辑器里改 rect_size 会出现"抓手和精灵都变新了，
##    但世界里的刚体还是旧尺寸"—— 画面与碰撞分叉，而且只有再拖一下节点才会好
##    （改导出属性不发 TRANSFORM_CHANGED）。父世界有防抖，重复调用是安全的。
func invalidate_shape() -> void:
	_cache_valid = false
	queue_redraw()
	if Engine.is_editor_hint():
		var p := get_parent()
		while p != null and not p.has_method("on_child_moved"):
			p = p.get_parent()
		if p != null:
			p.on_child_moved()


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
