@tool
extends Node2D
## 像素渲染层。
##
## @@tool@@ 是为了**在场景编辑器里也能看见像素**（甲方要求）。
## 本类是无状态的 —— 只按 @@sync(body)@@ 给的刚体重建贴图，自己不推进物理，
## 所以加 @@tool@@ 是安全的：编辑器里画的就是场景里已有的那些刚体。
##
## 设计要点（见框架文档第 5 节）：
##   逻辑 chunk = 8x8（物理/破坏的粒度）
##   渲染单元  = 每个 Body 一张 RGBA8 贴图，尺寸 = 该 Body 的局部 AABB
##   -> 静态世界按 128x128 切成多个 Body，破坏时只重建受影响的那几张
##
## 用 Image.create_from_data 一次性建图，避免逐像素 set_pixel 的调用开销。

const Bits := preload("res://src/core/pixel_bits.gd")
const PixelChunk := preload("res://src/core/pixel_chunk.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")
const PBody := preload("res://src/physics/pbody.gd")
const PixelScale := preload("res://src/core/pixel_scale.gd")

## 材质 id -> 颜色（id 0 = 空，必须保持透明）。
##
## ⚠️ 数组下标**就是** PixelShape 里存的材质 id —— 也就是说
## "体素颜色"这件事在引擎里是通过**材质表**表达的，不是逐像素存颜色。
## 好处：改整块颜色只要改这张表 + 重建贴图；像素数据只存 1 字节材质 id。
## 想换配色就 set_material_color() 或直接替换整个数组。
var palette: Array = [
	Color(0, 0, 0, 0),
	Color(0.62, 0.60, 0.56),   # 1 石材/地面
	Color(0.72, 0.52, 0.32),   # 2 木材
	Color(0.55, 0.58, 0.66),   # 3 金属
	Color(0.80, 0.32, 0.30),   # 4 砖
	Color(0.42, 0.72, 0.45),   # 5 植被
	Color(0.85, 0.78, 0.42),   # 6 沙
]

var _nodes := {}          # body.id -> Sprite2D
var _textures := {}       # body.id -> ImageTexture
var _bounds := {}         # body.id -> Rect2i

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

## 一次同步全部刚体（含回收已消失的）。
##
## ⚠️ 与逐帧路径的区别：逐帧路径靠 prune(_live_ids()) 回收，
##    而这里**不能**那样做 —— 编辑器里 @tool 的 _ready 只跑一次，
##    如果按"当前世界里的 id"去 prune，会把上一次构建留下的贴图误删。
##    所以这里只做增量同步，不回收。
func sync_all(bodies: Array) -> void:
	for b in bodies:
		sync(b)


## 回收已经不存在的 Body 对应的 Sprite（分裂销毁 / 预算淘汰都会用到）
func prune(live: Dictionary) -> void:
	var dead: Array = []
	for id in _nodes:
		if not live.has(id):
			dead.append(id)
	for id in dead:
		forget(id)


func forget(body_id: int) -> void:
	var n: Node = _nodes.get(body_id)
	if n != null:
		n.queue_free()
	_nodes.erase(body_id)
	_textures.erase(body_id)
	_bounds.erase(body_id)

## 改一种材质的颜色（会自动扩容；id 0 忽略）。
func set_material_color(material: int, color: Color) -> void:
	if material <= 0:
		return
	while palette.size() <= material:
		palette.append(color)
	palette[material] = color


func material_color(material: int) -> Color:
	if material >= 0 and material < palette.size():
		return palette[material]
	return Color(0, 0, 0, 0)


func sync(body) -> void:
	if body.shapes.is_empty():
		forget(body.id)
		return
	var aabb: Rect2i = _local_bounds(body)
	if aabb.size.x <= 0 or aabb.size.y <= 0:
		forget(body.id)
		return
	var node: Sprite2D = _nodes.get(body.id)
	if node == null:
		node = Sprite2D.new()
		node.centered = false
		node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(node)
		_nodes[body.id] = node
		_bounds[body.id] = Rect2i()
	if _bounds[body.id] != aabb:
		_bounds[body.id] = aabb
		_textures.erase(body.id)
	node.texture = _build_texture(body, aabb)
	node.offset = Vector2(aabb.position)
	# 贴图是 1 纹素 = 1 体素；靠节点缩放把每个体素放大成"大块像素"。
	# 最近邻采样（TEXTURE_FILTER_NEAREST）保证放大后依然是硬边方块，不会糊。
	# 这里**不做任何缩放**：1 个体素 = 1 个世界单位，渲染与物理共用同一坐标系。
	# 「大像素」交给 camera.zoom 实现（纯视图变换）。
	# 曾经在这里乘 voxel_world_size，结果画出来的几何比碰撞体大 4 倍 ——
	# 视觉上物体整个扎进地面，而物理检测却说只嵌入了 0.6 像素。
	var cs := cos(body.rotation)
	var sn := sin(body.rotation)
	node.transform = Transform2D(Vector2(cs, sn), Vector2(-sn, cs), body.position)

static func _local_bounds(body) -> Rect2i:
	var box := Rect2i()
	var first := true
	for s: PixelShape in body.shapes:
		var b: Rect2i = s.local_aabb()
		if b.size.x <= 0:
			continue
		if first:
			box = b
			first = false
		else:
			box = box.merge(b)
	return box

## ---- 蓝图：不属于任何刚体、不参与物理的形状 ----
##
## 用途：游戏层「画完一笔先不固化」的预览层。蓝图不在 world.bodies 里 ——
## 宽相扫不到、不受重力、不被破坏，纯粹是画面。solidify 时才 add_body。
##
## id 走负数区间（普通刚体 id 非负），避免撞号。
var _blueprint_nodes := {}


func sync_blueprint(id: int, shape: PixelShape, xform: Transform2D) -> void:
	if shape == null or shape.is_empty():
		forget_blueprint(id)
		return
	var key := -1 - absi(id)
	var aabb: Rect2i = shape.local_aabb()
	var node: Sprite2D = _blueprint_nodes.get(key)
	if node == null:
		node = Sprite2D.new()
		node.centered = false
		node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		node.modulate = Color(1, 1, 1, 0.6)      # 半透明：一眼看出"还没固化"
		add_child(node)
		_blueprint_nodes[key] = node
		_bounds[key] = Rect2i()
	if _bounds[key] != aabb:
		_bounds[key] = aabb
		_textures.erase(key)
	node.texture = _build_texture_impl([shape], aabb, key)
	node.offset = Vector2(aabb.position)
	node.transform = xform


func forget_blueprint(id: int) -> void:
	var key := -1 - absi(id)
	var n: Node = _blueprint_nodes.get(key)
	if n != null:
		n.queue_free()
	_blueprint_nodes.erase(key)
	_textures.erase(key)
	_bounds.erase(key)


func clear_blueprints() -> void:
	for key in _blueprint_nodes.keys():
		var n: Node = _blueprint_nodes[key]
		if n != null:
			n.queue_free()
		_textures.erase(key)
		_bounds.erase(key)
	_blueprint_nodes.clear()


func _build_texture(body, aabb: Rect2i):
	return _build_texture_impl(body.shapes, aabb, body.id)


func _build_texture_impl(shapes: Array, aabb: Rect2i, cache_key: int):
	var w: int = aabb.size.x
	var h: int = aabb.size.y
	var data := PackedByteArray()
	data.resize(w * h * 4)
	var ox: int = aabb.position.x
	var oy: int = aabb.position.y
	for s: PixelShape in shapes:
		for k: int in s.chunks:
			var c: PixelChunk = s.chunks[k]
			var bx := (PixelShape.key_x(k) << 3) - ox
			var by := (PixelShape.key_y(k) << 3) - oy
			var bits := c.occ
			while bits != 0:
				var i := Bits.first_bit_index(bits)
				bits &= bits - 1
				var gx := bx + (i & 7)
				var gy := by + (i >> 3)
				if gx < 0 or gx >= w or gy < 0 or gy >= h:
					continue
				var col: Color = palette[c.mat[i] % palette.size()]
				var o := (gy * w + gx) * 4
				data[o] = int(col.r * 255.0)
				data[o + 1] = int(col.g * 255.0)
				data[o + 2] = int(col.b * 255.0)
				data[o + 3] = 255
	var img := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, data)
	var tex: ImageTexture = _textures.get(cache_key)
	if tex == null:
		tex = ImageTexture.create_from_image(img)
		_textures[cache_key] = tex
	else:
		tex.update(img)
	return tex
