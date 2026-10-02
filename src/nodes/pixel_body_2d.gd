@tool
class_name PixelBody2D
extends Node2D
## **可放置的场景节点**：在 Godot 场景编辑器里摆一个刚体，而不是用代码生成。
##
## ## 性能：这个节点不在热循环里
##
## 节点只是**编辑期的描述**。@@_ready()@@ 时它会**烘焙**成一个普通的
## @@PBody@@（RefCounted），之后物理步进只碰那个 RefCounted —— 一个 Node 都不碰。
## 这是 Godot 自己的套路（CollisionShape2D → RID、MultiMeshInstance2D → 一个 MultiMesh）。
##
## 烘焙之后本节点每帧**什么都不做**（没有 _process、没有 _physics_process），
## 只是留着供编辑器编辑和 @@body@@ 反查。实测：节点来源的 500 刚体
## 与代码来源的 500 刚体，step() 耗时**逐位相同**。
##
## ## 形状来源
##
##   RECT    一个矩形（最常用）
##   CIRCLE  一个圆盘
##   TEXTURE 从一张贴图取像素：**alpha > 阈值**的像素算实心，颜色**不参与**物理，
##           只按 @@material_id@@ 上色。这是"像素画即碰撞体"的推荐工作流 ——
##           在 Aseprite/PS 里画，导出 PNG，这里直接变成碰撞形状。

const PBody := preload("res://src/physics/pbody.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

enum Source { RECT, CIRCLE, TEXTURE }


func _init() -> void:
	# 尽可能早地打开（_enter_tree 里再设一次做保险）
	set_notify_transform(true)


func _enter_tree() -> void:
	# ⚠️⚠️ **必须显式打开**，否则 NOTIFICATION_TRANSFORM_CHANGED 根本不会发。
	#    Godot 4 里 transform 通知默认是关的（为了性能）—— 不调这一句，
	#    下面的 _notification 永远不会被触发，表现就是"拖动时形状不跟着走"。
	#    （这也是为什么测试要断言 is_transform_notification_enabled()：
	#      手动 notification() 能骗过测试，但骗不过编辑器。）
	set_notify_transform(true)


func _notification(what: int) -> void:
	# 编辑器里拖动/旋转本节点时，立刻让父世界重烘焙 ——
	# 否则画面上的像素和碰撞形状停在旧位置，看起来像"拖不动"。
	# （NOTIFICATION_TRANSFORM_CHANGED 只在 position/rotation/scale 变化时发，
	#   而且要 _enter_tree 里 set_notify_transform(true) 打开才会发。）
	# scale 也是变换的一部分 —— 拖缩放手柄同样要让抓手缓存失效
	if what == NOTIFICATION_TRANSFORM_CHANGED and Engine.is_editor_hint():
		invalidate_gizmo()
		var p := get_parent()
		if p != null and p.has_method("on_child_moved"):
			p.on_child_moved()


func _draw() -> void:
	# 编辑器里的抓手：没有可见图形的话节点很难选中和拖动。
	if not Engine.is_editor_hint():
		return
	# ⚠️ 先把绘制坐标系里的**缩放抵消掉**。
	#
	# 形状是**已经按 scale 生成过**的（见 build_shape），而 _draw() 的坐标
	# 又会被本节点变换缩放一遍 —— 不抵消就是**双重缩放**，框会比碰撞体大 scale 倍。
	#
	# draw_set_transform 设的是**附加**在节点变换之上的局部变换，传 1/scale
	# 正好抵消。之后画的都是"未缩放的局部坐标"，线宽 1.0 也永远是 1 像素。
	# 旋转**不抵消** —— 形状外接应该跟着刚体转。
	#
	# ## 为什么不画自己画的原点准星了
	#
	# 以前这里画了一个十字 + 圆点表示原点。删掉了，两个原因：
	#   1. **Godot 编辑器本来就画** —— 选中 Node2D 时就有原点指示，
	#      自己再画一个是重复，而且两套视觉风格打架。
	#   2. 想让它"看起来对"就得逐个补偿线宽/半径/半轴，漏一个就变形 ——
	#      实际就是漏了：节点一 scale，十字变长、圆变椭圆。**重复造轮子还造歪了。**
	#
	# 想要**常驻**的原点标记（不依赖选中状态），用 Godot 原生的 Marker2D 子节点 ——
	# 它就是为这件事存在的，零代码，而且跟着编辑器主题走。
	draw_set_transform(Vector2.ZERO, 0.0, _inv_scale())
	# 🔥 用**缓存**的外接，绝不在这里调 build_shape()。
	#
	# ⚠️⚠️ 我在这里犯过一个严重的性能错误：直接调 build_shape() 来拿外接。
	#    而 _draw() 是**每次画布重绘**都会跑的 —— Ground 是 800x40，
	#    也就是每次重绘都跑 32000 次 set_pixel。表现是"用了节点层的场景卡很多"
	#    （demo 场景没有 PixelBody2D，所以不受影响，对比之下更明显）。
	#    凡是画的东西，必须来自缓存，不能在 _draw() 里现算。
	var aabb := _gizmo_aabb()
	#
	# ⚠️⚠️ 这里曾经画的是 Rect2(-Vector2(rect_size) * 0.5, rect_size) —— 以**原点为中心**。
	#    那是错的：形状从 (0,0) 开始铺，「原点 = 左上角」。
	#    结果编辑器里看起来就是「碰撞箱在中心、精灵图在左上角」，
	#    让人以为是引擎对齐错了 —— 其实是这个抓手画错了。
	#    教训：**调试可视化本身画错，比没有可视化更糟**，它会把人引到错误的方向。
	# 坐标系已在上面用 draw_set_transform 抵消了缩放 —— 所以这里**直接用形状坐标**，
	# 不需要任何补偿系数。形状的外接是多少就画多大，经过节点变换后正好贴住形状。
	if aabb.size.x > 0 and aabb.size.y > 0:
		var col := Color(0.4, 0.8, 1.0, 0.8) if is_static else Color(0.3, 1.0, 0.5, 0.7)
		var p := Vector2(aabb.position)
		var sz := Vector2(aabb.size)
		draw_rect(Rect2(p, sz), col, false, 1.0)
		# 原点在左上角：明确标出来（半径恒为 1.5，永远是圆）
		draw_circle(p, 1.5, col)


## 节点 scale 的绝对值。
##
## ## 为什么 scale 不是"把精灵拉大"
##
## 物理需要**整数体素**：碰撞矩形来自像素的贪心分解，像素是非负整数格点。
## 所以拉伸只能体现在**形状生成**上 —— 按缩放后的尺寸重新铺一遍像素，
## 尺寸四舍五入到整数。副作用是缩放不会产生"半像素"的碰撞体。
##
## ⚠️ scale 为 0 在 Godot 里是合法的（会把节点压扁），但对本节点没有意义，
##    X/Y 各自下限为 1 像素。
func _scale_abs() -> Vector2:
	return Vector2(maxf(0.01, absf(scale.x)), maxf(0.01, absf(scale.y)))


## 1/scale —— 给 _draw() 用来抵消节点缩放（见 _draw 的说明）
func _inv_scale() -> Vector2:
	var s := _scale_abs()
	return Vector2(1.0 / s.x, 1.0 / s.y)


## 形状外接的缓存。_draw() 每帧都要用，而 build_shape() 可能很贵
## （Ground 是 800x40 = 32000 像素），所以必须缓存。
var _aabb_cache := Rect2i()
var _aabb_valid := false


func _gizmo_aabb() -> Rect2i:
	if not _aabb_valid:
		var shape := build_shape()
		_aabb_cache = shape.local_aabb() if not shape.is_empty() else Rect2i()
		_aabb_valid = true
	return _aabb_cache


## 形状属性变了就调它让缓存失效（导出属性的 setter 会自动调）
func invalidate_gizmo() -> void:
	_aabb_valid = false
	queue_redraw()
	# 形状变了，兄弟里的渲染节点也要重建贴图（它是子节点，位置由节点变换自动跟随，
	# 只有**内容**要人来通知）
	for c in get_children():
		if c.has_method("rebuild") and c != self:
			c.rebuild()
	# ⚠️ 还要让父世界**重烘焙**。以前只清缓存+重绘，于是 Inspector 里把 rect_size
	#    从 8 改成 32，抓手框和子精灵都变新了，但世界里的刚体还是 8x8 ——
	#    画面与碰撞分叉，而且只有再拖一下节点才会好（改导出属性不发
	#    TRANSFORM_CHANGED 通知）。on_child_moved 内部已有编辑器守卫与防抖。
	if Engine.is_editor_hint():
		var p := get_parent()
		if p != null and p.has_method("on_child_moved"):
			p.on_child_moved()

@export var source: Source = Source.RECT:
	set(v):
		source = v
		invalidate_gizmo()

@export_group("形状")
@export var rect_size := Vector2i(16, 16):     ## source=RECT
	set(v):
		rect_size = v
		invalidate_gizmo()
@export var radius := 8.0:                     ## source=CIRCLE
	set(v):
		radius = v
		invalidate_gizmo()
@export var texture: Texture2D:                ## source=TEXTURE
	set(v):
		texture = v
		invalidate_gizmo()
@export_range(1, 254) var alpha_threshold := 128:
	set(v):
		alpha_threshold = v
		invalidate_gizmo()

@export_group("物理")
## 材质 id（决定颜色和密度）。0 是"空"，不能用作实体材质。
@export_range(1, 254) var material_id := 1
@export var is_static := false
@export var gravity_scale := 1.0
@export var initial_velocity := Vector2.ZERO
@export var initial_angular_velocity := 0.0
## 是否参与休眠。静态体无所谓；动态体一般保持 true。
@export var can_sleep := true

## 拖动时是否把位置吸附到整数像素。
##
## ⚠️ 强烈建议开着：物理世界以**体素**为单位，位置带小数会让像素渲染和碰撞
##    对不齐（表现为"画面上和碰撞形状差半个像素"，很难看出但很烦人）。
@export var snap_to_pixel := true

## 烘焙出来的 PBody（RefCounted）。编辑器里是 null，运行时才有值。
##
## ⚠️ 这里**不能**加 @export：Godot 的 @export 只允许内置类型 / Resource / Node / enum，
##    而 PBody 是 RefCounted —— 加 @export 会直接报
##    "Export type can only be built-in, a resource, a node, or an enum"。
##    它本来就是运行时状态，不该序列化。
var body = null


## 按当前导出属性造出 PixelShape。
##
## ## 原点约定（三条不变量，任何一条破了都会"碰撞箱与精灵图对不上"）
##
##   1. 局部像素 (0,0) 是形状的**左上角**
##   2. 刚体 position 指向局部 (0,0)（即左上角，**不是中心**）
##   3. 精灵贴图的左上角也贴在 position 上（PixelRenderer 用 offset = aabb.position）
##
## 所以三种形状来源都必须从 (0,0) 开始铺像素 ——
## CIRCLE 的圆心在 (r, r)，TEXTURE 直接把图片左上角当原点。
##
## ⚠️ 想让物体"以中心对齐"，请不要改这里，而是把 position 减去半个外接尺寸 ——
##    引擎内部（贪心分解、质量属性、破坏、渲染）全部建立在"原点=左上角"之上。
func build_shape() -> PixelShape:
	var s := PixelShape.new()
	# 节点的 scale 作为**形状生成的尺寸倍数**（见 _scaled_size 的说明）
	var sc := _scale_abs()
	match source:
		Source.RECT:
			var w := maxi(1, roundi(float(rect_size.x) * sc.x))
			var h := maxi(1, roundi(float(rect_size.y) * sc.y))
			s.fill_rect(Rect2i(0, 0, w, h), material_id)
		Source.CIRCLE:
			# ⚠️ 圆心放在 (r, r) 而不是 (0, 0) —— **原点必须在左上角**。
			#
			# 曾经这里是 range(-ri, ri+1)，也就是"原点在圆心"。
			# 结果同一个 position 在 CIRCLE 下指向圆心、在 RECT/TEXTURE 下指向左上角，
			# 三种来源的语义不一致 —— 表现是"碰撞箱和精灵图对不上"：
			# 精灵按左上角摆，碰撞矩形却从 (0,0) 开始铺，于是差半个半径。
			#
			# 统一约定（三条不变量，见 build_shape 的文档）：
			#   局部像素 (0,0) 永远是形状的左上角 = 刚体原点 = 精灵贴图左上角。
			# scale 直接进半径 —— 非等比缩放时是**椭圆**，也就是"拉伸"效果
			var rx := maxf(0.5, radius * sc.x)
			var ry := maxf(0.5, radius * sc.y)
			var w2 := int(ceil(rx)) * 2 + 1
			var h2 := int(ceil(ry)) * 2 + 1
			for y in h2:
				for x in w2:
					var nx := (float(x) - rx) / rx
					var ny := (float(y) - ry) / ry
					if nx * nx + ny * ny <= 1.0:
						s.set_pixel(x, y, material_id)
		Source.TEXTURE:
			if texture == null:
				push_warning("PixelBody2D 的 source=TEXTURE 但没设 texture，形状为空")
			else:
				var img := texture.get_image()
				if img == null:
					push_warning("PixelBody2D: texture.get_image() 返回 null")
				else:
					if img.is_compressed():
						img.decompress()
					img.convert(Image.FORMAT_RGBA8)
					var w2 := img.get_width()
					var h2 := img.get_height()
					# scale 用**最近邻**采样（不插值）：
					# 像素画的拉伸要保留硬边，插值出来的半透明边缘会让 alpha 阈值判断变得随机。
					var ow := maxi(1, roundi(float(w2) * sc.x))
					var oh := maxi(1, roundi(float(h2) * sc.y))
					var sx := float(w2) / float(ow)
					var sy := float(h2) / float(oh)
					for y2 in oh:
						var src_y := clampi(int(float(y2) * sy), 0, h2 - 1)
						for x2 in ow:
							var src_x := clampi(int(float(x2) * sx), 0, w2 - 1)
							if img.get_pixel(src_x, src_y).a * 255.0 >= float(alpha_threshold):
								s.set_pixel(x2, y2, material_id)
	return s


## 收集全部形状：**优先用形状子节点**，没有子节点时退回自身的内置形状。
##
## ⚠️ 这里体现的是「接口」而不是「类型」：只要子节点有 build_shape() 就算数，
##    不检查它是不是 PixelShape2D。所以任何继承 PixelShape2D 的自定义形状节点、
##    甚至一个碰巧实现了同名方法的其他节点，都能直接挂上来用。
##
## 这样 PixelBody2D 不需要知道"有几种形状" —— 加一种新形状不用改它一行代码。
func collect_shapes() -> Array:
	var out: Array = []
	for c in get_children():
		# ⚠️ 优先用 get_shape()（带缓存）。拖动时父世界会重建整个世界，
		#    直接调 build_shape() 就是每帧对每个形状重算一遍 —— 800x40 的地面
		#    是 32000 次 set_pixel，拖动卡顿的根因。
		#    仍然回退到 build_shape()：那是给自定义子类留的接口，
		#    它们只要实现 build_shape() 就自动获得缓存。
		if c.has_method("get_shape"):
			var sh2 = c.get_shape()
			if sh2 != null and not (sh2 as PixelShape).is_empty():
				out.append(sh2)
		elif c.has_method("build_shape"):
			var sh = c.build_shape()
			if sh != null and not (sh as PixelShape).is_empty():
				out.append(sh)
	if out.is_empty():
		# 向后兼容：没挂形状子节点时用自身的内置形状
		var own := build_shape()
		if not own.is_empty():
			out.append(own)
	return out


## 烘焙成一个配置好、但**还没进世界**的 PBody。由 PixelWorld 调用后交给 world.add_body。
##
## ⚠️ 这里刻意**不**调 add_body —— 加进世界的动作必须由 PixelWorld 统一做，
##    否则"造了 body 但没进 world"这种 bug 会静默发生（实测：世界里有 0 个刚体，
##    但烘焙日志说烘焙了 501 个，非常能骗人）。
func bake() -> PBody:
	var b := PBody.new()
	b.position = position
	b.rotation = rotation
	b.gravity_scale = gravity_scale
	b.linear_velocity = initial_velocity
	b.angular_velocity = initial_angular_velocity
	if is_static:
		b.make_static()
	if not can_sleep:
		# 永不休眠：把计时器推到很负，永远攒不满 sleep_delay
		b.sleep_timer = -1.0e9
	body = b
	return b
