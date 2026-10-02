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
	if what == NOTIFICATION_TRANSFORM_CHANGED and Engine.is_editor_hint():
		var p := get_parent()
		if p != null and p.has_method("on_child_moved"):
			p.on_child_moved()


func _draw() -> void:
	# 编辑器里的抓手：没有可见图形的话节点很难选中和拖动。
	if not Engine.is_editor_hint():
		return
	var c := Color(1.0, 0.75, 0.2, 0.95)
	draw_line(Vector2(-6, 0), Vector2(6, 0), c, 1.0)
	draw_line(Vector2(0, -6), Vector2(0, 6), c, 1.0)
	draw_circle(Vector2.ZERO, 2.0, c)
	if is_static:
		# 静态体额外画一个方框，一眼区分
		var s := Vector2(rect_size)
		draw_rect(Rect2(-s * 0.5, s), Color(0.4, 0.7, 1.0, 0.5), false, 1.0)

@export var source: Source = Source.RECT

@export_group("形状")
@export var rect_size := Vector2i(16, 16)      ## source=RECT
@export var radius := 8.0                      ## source=CIRCLE
@export var texture: Texture2D                 ## source=TEXTURE
@export_range(1, 254) var alpha_threshold := 128

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
	match source:
		Source.RECT:
			var w := maxi(1, rect_size.x)
			var h := maxi(1, rect_size.y)
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
			var r := maxf(0.5, radius)
			var ri := int(ceil(r))
			for y in range(0, ri * 2 + 1):
				for x in range(0, ri * 2 + 1):
					if Vector2(float(x) - r, float(y) - r).length() <= r:
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
					for y2 in h2:
						for x2 in w2:
							if img.get_pixel(x2, y2).a * 255.0 >= float(alpha_threshold):
								s.set_pixel(x2, y2, material_id)
	return s


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
