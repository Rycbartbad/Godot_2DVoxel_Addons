extends Node2D
## 物理调试叠加层：把引擎内部状态画出来，**运行时和编辑器里都能看**。
##
## 甲方要求「能在场景编辑器中可视化」。这里的做法是 @tool + _draw()：
##   · 编辑器里画的是**当前场景里已有的刚体**（静态摆好的那些），不推进物理；
##   · 运行时每帧重画。
##
## ⚠️ 绝对不要在这个脚本里推进物理。@tool 的 _process 在编辑器里也会跑，
##    一旦 step 就会污染场景、还会让编辑器卡死（而且存盘时把结果写进去）。
##
## 用法：把本节点加到场景里，把 world_source 指到 PixelPhysics 节点即可。
## 什么都不指的话会自动往上找兄弟节点里的 PixelPhysics。

@export var world_source: NodePath

## ---- 画什么（Inspector 里勾）----
@export_group("显示内容")
@export var show_obbs := true              ## 碰撞矩形（贪心分解的结果，物理实际用的形状）
@export var show_aabbs := false            ## 刚体 AABB（宽相用的粗包围盒）
@export var show_swept_aabbs := false      ## 扫掠 AABB（含本步位移，CCD 用）
@export var show_contacts := true          ## 接触点 + 法向
@export var show_velocity := false         ## 线速度矢量
@export var show_angular := false          ## 角速度弧线
@export var show_com := true               ## 质心
@export var show_awake := true             ## 用颜色区分清醒/休眠
@export var show_ids := false              ## 刚体 id
@export var show_stats := true             ## 左上角统计文字

@export_group("外观")
@export var obb_color := Color(0.3, 0.9, 1.0, 0.9)
@export var aabb_color := Color(0.5, 0.5, 0.5, 0.5)
@export var swept_color := Color(1.0, 0.6, 0.2, 0.4)
@export var contact_color := Color(1.0, 0.25, 0.25, 1.0)
@export var velocity_color := Color(0.4, 1.0, 0.4, 0.9)
@export var angular_color := Color(1.0, 0.9, 0.3, 0.9)
@export var com_color := Color(1.0, 1.0, 1.0, 0.9)
@export var asleep_color := Color(0.4, 0.4, 0.45, 0.8)
@export var awake_color := Color(0.3, 0.9, 1.0, 0.9)
@export var stats_color := Color(1, 1, 1, 0.85)

@export_group("比例")
## 速度矢量的长度 = 速度 × 这个系数（像素/（像素·秒⁻¹））
@export var velocity_scale := 0.25
@export var contact_normal_len := 12.0
@export var font_size := 12

var _world = null
## 统计文字的字号要按相机 zoom 反算，否则拉近之后字会占满整个屏幕
var font_size_draw := 12.0


func _ready() -> void:
	_resolve_world()
	set_process(true)


func _process(_dt: float) -> void:
	# ⚠️ 只重画，**不推进物理**。编辑器里也走这条路。
	if _world == null:
		_resolve_world()
	queue_redraw()


func _resolve_world() -> void:
	var src: Node = null
	if not world_source.is_empty():
		src = get_node_or_null(world_source)
	if src == null:
		# 没指定就自动找。⚠️ 必须**先看父节点自己**再看它的子节点 ——
		#    Demo 场景里 world 就在父节点 Demo 身上，只遍历 children 会找不到，
		#    表现是"叠加层在场景里但什么都不画"，很难查。
		var parent := get_parent()
		if parent != null:
			if "world" in parent:
				src = parent
			else:
				for c in parent.get_children():
					if c != self and "world" in c:
						src = c
						break
	if src != null and "world" in src:
		_world = src.world
	else:
		_world = null
	if OS.get_cmdline_user_args().has("--shot"):
		print("[DebugOverlay] src=%s world=%s" % [src, _world != null])


## 世界里的刚体（没有世界就返回空，编辑器里没摆 PixelPhysics 时不该报错）
func _bodies() -> Array:
	if _world == null:
		return []
	return _world.bodies


func _draw() -> void:
	if _world == null:
		if show_stats:
			draw_string(ThemeDB.fallback_font, Vector2(8, 18),
				"调试叠加层：找不到 world_source（把 world_source 指到 PixelPhysics 节点）",
				HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1, 0.5, 0.5, 0.9))
		return

	var bodies: Array = _bodies()
	var font := ThemeDB.fallback_font

	for b in bodies:
		var col := obb_color
		if show_awake:
			col = awake_color if b.awake else asleep_color

		# ---- AABB / 扫掠 AABB ----
		if show_aabbs:
			draw_rect(b.aabb, aabb_color, false, 1.0)
		if show_swept_aabbs:
			draw_rect(b.swept_aabb, swept_color, false, 1.0)

		# ---- 碰撞矩形（物理真正用的形状）----
		if show_obbs:
			for r: Rect2 in b.rects:
				_draw_obb(b, r, col)

		# ---- 质心 ----
		if show_com and not b.is_static:
			var c: Vector2 = b.com_world()
			draw_line(c - Vector2(5, 0), c + Vector2(5, 0), com_color, 1.0)
			draw_line(c - Vector2(0, 5), c + Vector2(0, 5), com_color, 1.0)

		# ---- 速度矢量 ----
		if show_velocity and not b.is_static:
			var v: Vector2 = b.linear_velocity * velocity_scale
			if v.length_squared() > 1.0:
				var o: Vector2 = b.com_world()
				draw_line(o, o + v, velocity_color, 2.0)
				_draw_arrow_head(o + v, v.normalized(), velocity_color)

		# ---- 角速度弧线（半径按角速度大小，正负用方向区分）----
		if show_angular and not b.is_static and absf(b.angular_velocity) > 0.01:
			var o2: Vector2 = b.com_world()
			var r2: float = clampf(8.0 + absf(b.angular_velocity) * 4.0, 8.0, 40.0)
			var a0 := 0.0
			var a1: float = clampf(b.angular_velocity * 0.5, -PI, PI)
			draw_arc(o2, r2, a0, a1, 16, angular_color, 2.0)

		# ---- id ----
		if show_ids:
			draw_string(font, b.position + Vector2(2, -2), str(b.id),
				HORIZONTAL_ALIGNMENT_LEFT, -1, font_size - 2, col)

	# ---- 接触点 + 法向 ----
	if show_contacts:
		for m in _world.manifolds:
			for p in m.points:
				draw_circle(p.position, 2.5, contact_color)
				draw_line(p.position, p.position + m.normal * contact_normal_len,
					contact_color, 1.5)

	# ---- 统计 ----
	if show_stats:
		_draw_stats(bodies, font)


## 把一个局部矩形按刚体变换画成四边形（**不是**画轴对齐矩形 ——
## 刚体可以旋转，画 AABB 会骗人）。
func _draw_obb(b, r: Rect2, col: Color) -> void:
	var pts := PackedVector2Array([
		b.to_world(r.position),
		b.to_world(r.position + Vector2(r.size.x, 0)),
		b.to_world(r.position + r.size),
		b.to_world(r.position + Vector2(0, r.size.y)),
	])
	draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), col, 1.0)


func _draw_arrow_head(tip: Vector2, dir: Vector2, col: Color) -> void:
	var n := Vector2(-dir.y, dir.x)
	draw_line(tip, tip - dir * 6.0 + n * 3.0, col, 1.5)
	draw_line(tip, tip - dir * 6.0 - n * 3.0, col, 1.5)


func _draw_stats(bodies: Array, font: Font) -> void:
	var awake := 0
	var dyn := 0
	for b in bodies:
		if b.is_static:
			continue
		dyn += 1
		if b.awake:
			awake += 1
	var lines := PackedStringArray([
		"刚体 %d（动态 %d，清醒 %d，休眠 %d）" % [bodies.size(), dyn, awake, dyn - awake],
		"流形 %d  接触点 %d  子步 %d" % [
			_world.manifolds.size(), _world.last_contacts, _world.last_substeps],
		"总动量 (%.1f, %.1f)  总角动量 %.1f  总动能 %.1f" % [
			_world.total_momentum().x, _world.total_momentum().y,
			_world.total_angular_momentum(_world.center_of_mass_world()),
			_world.total_kinetic_energy()],
	])
	# ⚠️ _draw() 画的是**世界坐标**，直接写 (8,18) 会跑到镜头外面去
	#    （表现是"叠加层在画但看不到字"）。要跟着相机走：
	#    取视口尺寸 ÷ 相机 zoom 得到"屏幕上 1 像素 = 多少世界单位"，
	#    再把文字放在相机可视区的左上角。
	var origin := Vector2(8, 18)
	var z := Vector2.ONE
	var cam := get_viewport().get_camera_2d()
	if cam != null:
		z = cam.zoom
		if z.x <= 0.0 or z.y <= 0.0:
			z = Vector2.ONE
		var vs: Vector2 = get_viewport_rect().size
		origin = cam.get_screen_center_position() - vs * 0.5 / z + Vector2(8, 18) / z
	font_size_draw = maxf(1.0, float(font_size) / maxf(0.001, z.y))
	var y := origin.y
	for s in lines:
		draw_string(font, Vector2(origin.x, y), s, HORIZONTAL_ALIGNMENT_LEFT, -1,
			int(font_size_draw), stats_color)
		y += font_size_draw + 3.0 / maxf(0.001, z.y)
