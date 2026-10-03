@tool
extends Node2D
## @@tool@@ 是为了**在场景编辑器里就能看到关卡**（甲方要求）。
##
## 编辑器里只做一件事：把世界和关卡**建出来**，然后交给 PixelRenderer / 调试叠加层去画。
## 绝不推进物理、不跑输入、不写截图 —— 否则编辑器会被污染，而且存盘时把结果写进去。
## 2D 像素破坏沙盒 —— Aseprite 式操作
##
##   左键拖动   = 绘制（加像素）
##   右键拖动   = 擦除（删像素，自动做连通性分裂，切下来的部分会掉）
##   中键拖动   = 平移视角
##   滚轮       = 缩放
##   Ctrl+左键  = 抓取/拖动物体（刚体拖拽）
##   [ ]        = 笔刷半径
##   X          = 切换材质
##   Shift+左键 = 绘制动态刚体（而不是地形）
##   R          = 重置    空格 = 暂停物理

const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")
const Destruction := preload("res://src/core/destruction.gd")
const Editor := preload("res://src/core/pixel_editor.gd")
const PixelRenderer := preload("res://src/render/pixel_renderer.gd")
const PixelScale := preload("res://src/core/pixel_scale.gd")

const WORLD_W := 768          ## 关卡尺寸（世界单位 = 体素）
const WORLD_H := 320
const GROUND_Y := 220         ## 地面顶面高度
const CANVAS_TILE := 64      ## 自由绘制瓦片（太小的话一笔会横跨 4 块，无谓地多出 Body）
const MIN_BRUSH := 1.0
const MAX_BRUSH := 40.0
const ERASE_BURST := 25.0

# world / renderer 由 PixelWorld 节点在 _ready 里建好，这里只取引用。
# camera / hud 直接是场景节点，见下面的 @onready。
var world: PWorld
var renderer: PixelRenderer

var paused := false
var brush_radius := 6.0
var material_id := 1

var _canvas_tiles := {}       # Vector2i -> PBody（静态画布瓦片）
var _stroke_body: PBody = null  # Shift 绘制时本次笔画归属的动态体
var _lmb := false
var _rmb := false
var _mmb := false
var _last_paint := Vector2.ZERO
var _last_erase := Vector2.ZERO
var _fps := 0.0
var _fps_accum := 0.0
var _fps_frames := 0
var _budget_tick := 0
var _shot_at := -1


@onready var _world_node: Node2D = $PixelWorld
@onready var camera: Camera2D = $Camera2D
@onready var hud: Label = $UI/Hint


func _ready() -> void:
	# ---- 世界 / 渲染器 / 相机 / UI / 关卡**全部来自场景节点** ----
	#
	# ⚠️ 这里以前是 45 行 new 代码：PWorld.new() / PixelRenderer.new() /
	#    Camera2D.new() / Label.new() / _build_level() —— 编辑器里看不到、调不了，
	#    而且完全没用上 src/nodes/ 那套节点层。
	#
	#    现在场景文件（scenes/demo.tscn）里把地形、相机、UI 都摆好了，这里只取引用。
	#    能这么做的前提是 PixelShape2D 的 source=RECT：地面就是"一个 768x100 的
	#    矩形"，不需要在 .tscn 里手写几十万个像素。
	#
	#    分工：场景节点 = 结构（可见、可调）；本脚本 = 行为（笔刷 / 擦除 / 拖动 / 回收）。
	var editing := Engine.is_editor_hint()
	world = _world_node.world
	renderer = _world_node.renderer

	# 视野跟着体素尺寸走：体素越大，相机越"推近"，看到的体素数越少
	# 屏幕上体素边长 = voxel_world_size * render_scale * camera.zoom
	#   前两个是"渲染单位"（体素多大、显示分辨率多少），最后一个是视角缩放。
	# 三个量互相独立：改显示分辨率只会改变"一个体素落到几个真实像素"，
	# 取景由 zoom 补偿保持不变。
	# 「大像素」= 相机拉近。物理世界完全不动，所以视觉和碰撞永远一致。
	# 显示分辨率补偿：体素尺寸不变、取景不变，只是每个体素画到更多真实像素上。
	# 基准高度 540 对应"1 体素 = voxel_world_size 像素"的历史观感，
	# 换到 1080p 时 zoom 自动翻倍，于是画面构图完全一致、只是更细腻。
	# ⚠️ 编辑器里视口尺寸/缩放可能拿不到有效值，zoom 为 0 会让 Godot 报
	#    "Zoom level must be different from 0" 并且相机失效。
	#    这里兜一下底，编辑器预览用 1.0 就够（预览不需要精确取景）。
	var s0 := PixelScale.get_scale() * PixelScale.render_scale()
	if s0 <= 0.0 or not is_finite(s0):
		s0 = 1.0
	camera.zoom = Vector2(s0, s0)
	camera.make_current()
	# ⚠️ 编辑器里到此为止：不跑输入、不截图、不推进物理。
	#    关卡已经建好，渲染器和调试叠加层会把它们画出来。
	if editing:
		renderer.sync_all(world.bodies)
		return
	if OS.get_cmdline_user_args().has("--shot"):
		_shot_at = 260      # 重力调慢后要给它落地的时间
		_demo_blast()


# ---------------------------------------------------------------- 关卡

# ⚠️ 这里以前是 _build_level()：用 PBody + PixelShape 把地面 / 砖墙 / 木箱
#    全部**在代码里生成**（约 45 行）。现在它们是 scenes/demo.tscn 里的场景节点
#    （PixelBody2D + PixelShape2D），编辑器里能选中、能拖、能改尺寸。
#
#    关卡几何之所以能节点化，是因为 PixelShape2D 支持 source=RECT ——
#    地面就是"一个 768x100 的矩形"，不需要在 .tscn 里手写几十万个像素。
#    （更复杂的关卡仍然可以在代码里生成后 add_body，两条路并存。）


# ---------------------------------------------------------------- 主循环

func _process(delta: float) -> void:
	# ⚠️ 编辑器里不推进物理、不处理输入
	if Engine.is_editor_hint():
		return
	_fps_accum += delta
	_fps_frames += 1
	if _fps_accum >= 0.5:
		_fps = _fps_frames / _fps_accum
		_fps_accum = 0.0
		_fps_frames = 0

	var mouse := get_global_mouse_position()
	if _lmb and not world.is_grabbing():
		_paint(_last_paint, mouse)
		_last_paint = mouse
	if _rmb:
		_erase(_last_erase, mouse)
		_last_erase = mouse
	if world.is_grabbing():
		world.set_grab_target(mouse)

	if not paused:
		world.advance(delta)

	_budget_tick += 1
	if _budget_tick % 60 == 0:
		# 掉出关卡的物体必须回收，否则它们会永远加速，把子步数永久顶满
		var culled: int = world.cull_outside(Rect2(-600, -800, WORLD_W + 1200, WORLD_H + 1400))
		if culled > 0:
			renderer.prune(_live_ids())
		var dropped: int = world.enforce_body_budget()
		if dropped > 0:
			renderer.prune(_live_ids())

	var live := _live_ids()
	for b in world.bodies:
		if not b.is_static:
			renderer.sync(b)
	renderer.prune(live)

	_update_hud()
	_maybe_screenshot()


func _live_ids() -> Dictionary:
	var d := {}
	for b in world.bodies:
		d[b.id] = true
	return d


## 截图模式专用：在墙上打出几个洞，让"大块像素被炸掉"的观感直接可见
func _demo_blast() -> void:
	var holes := [Vector2(330, 170), Vector2(370, 165), Vector2(400, 185), Vector2(345, 200)]
	for i in holes.size():
		var hp: Vector2 = holes[i]
		var hit := _body_at(hp, false)
		if hit == null:
			continue
		var spawned: Array = world.fracture(hit, Destruction.Damage.circle(hit.to_local(hp), 9.0), 40.0)
		renderer.sync(hit)
		for f in spawned:
			renderer.sync(f)


func _maybe_screenshot() -> void:
	if _shot_at < 0:
		return
	# 诊断用：截图前给动态体加自转，这样能看出抗锯齿对**旋转边缘**的作用
	if _shot_at == 1 and OS.get_cmdline_user_args().has("--spin"):
		for b in world.bodies:
			if not b.is_static:
				b.awake = true
				b.angular_velocity = 4.0
	_shot_at -= 1
	if _shot_at > 0:
		return
	_shot_at = -1
	await RenderingServer.frame_post_draw
	var settled := 0
	var floating := 0
	for b in world.bodies:
		if b.is_static:
			continue
		if b.aabb.end.y >= GROUND_Y - 2.0:
			settled += 1
		else:
			floating += 1
	var vp := get_viewport()
	print("DEBUG 落地 %d 个 / 悬空 %d 个 | substeps=%d | 视口 %dx%d | msaa_2d=%d | fps=%d" % [
		settled, floating, world.last_substeps,
		int(vp.get_visible_rect().size.x), int(vp.get_visible_rect().size.y),
		int(vp.msaa_2d), Engine.get_frames_per_second()])
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://demo_shot.png")
	print("saved demo_shot.png ", img.get_width(), "x", img.get_height())
	get_tree().quit()


func _update_hud() -> void:
	var mode := "Ctrl+左键=拖动" if world.is_grabbing() else "左键=绘制 右键=擦除 中键=平移"
	var rects := 0
	for b in world.bodies:
		if not b.is_static:
			rects += b.rects.size()
	hud.text = "FPS %.0f | Body %d | 接触 %d | 碰撞矩形 %d | 笔刷 %.0f | 材质 %d | 体素 %sx%s | %s\n滚轮 笔刷大小   [ ] 微调   X 材质   - / = 体素大小   Ctrl+滚轮 视角缩放   Shift+左键 画刚体(松手生效)   Ctrl+左键 拖动   R 重置   空格 暂停" % [
		_fps, world.bodies.size(), world.last_contacts, rects, brush_radius, material_id,
		String.num(PixelScale.get_scale(), 1), String.num(PixelScale.get_scale(), 1), mode]


# ---------------------------------------------------------------- 输入

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		var pos := get_global_mouse_position()
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			if mb.ctrl_pressed:
				camera.zoom = (camera.zoom * 1.12).limit_length(12.0)
			else:
				_brush_step(1.0)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			if mb.ctrl_pressed:
				var z := camera.zoom / 1.12
				if z.x < 0.1:
					z = Vector2(0.1, 0.1)
				camera.zoom = z
			else:
				_brush_step(-1.0)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			# Ctrl+左键 = 拖动，此时**绝不能**再置 _lmb。
			# 以前这里先无条件写了 _lmb = mb.pressed，于是 Ctrl 点在空处
			# （抓取失败、is_grabbing() 为 false）就直接落笔了。
			if mb.ctrl_pressed:
				_lmb = false
				_last_paint = pos      # 同步，免得松开 Ctrl 后补出一条长笔触
				if mb.pressed:
					var target := _body_at(pos, true)
					if target != null:
						world.grab(target, pos)
				else:
					world.release_grab()
			else:
				_lmb = mb.pressed
				if mb.pressed:
					_last_paint = pos
					if mb.shift_pressed:
						_stroke_body = _spawn_stroke_body(pos)
				else:
					world.release_grab()
					_finalize_stroke()
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			_rmb = mb.pressed
			if mb.pressed:
				_last_erase = pos
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_mmb = mb.pressed
	elif event is InputEventMouseMotion and _mmb:
		var mm := event as InputEventMouseMotion
		camera.position -= mm.relative / camera.zoom
	elif event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		match k.keycode:
			KEY_BRACKETLEFT:
				brush_radius = maxf(MIN_BRUSH, brush_radius - 1.0)
			KEY_BRACKETRIGHT:
				brush_radius = minf(MAX_BRUSH, brush_radius + 1.0)
			KEY_X:
				material_id = material_id % 6 + 1
			KEY_MINUS:
				_set_voxel_scale(PixelScale.get_scale() / 1.5)
			KEY_EQUAL:
				_set_voxel_scale(PixelScale.get_scale() * 1.5)
			KEY_0:
				_set_voxel_scale(3.0)
			KEY_R:
				get_tree().reload_current_scene()
			KEY_SPACE:
				paused = not paused
			KEY_F11:
				var win := get_window()
				win.mode = Window.MODE_WINDOWED if win.mode == Window.MODE_FULLSCREEN \
					else Window.MODE_FULLSCREEN


# ---------------------------------------------------------------- 绘制

## Shift 绘制：笔画期间是**静态**的，所以不会边画边掉；
## 松开左键时才转成动态刚体（质量/惯性在这一刻才算）。
func _spawn_stroke_body(at: Vector2) -> PBody:
	var b := PBody.new()
	# 必须对齐到像素栅格（floor），不能减 0.5。
	# 全项目统一约定"像素中心在 整数+0.5"，而 -0.5 会把这一笔的局部栅格
	# 整体挪半格，同一个圆盘被光栅化成**不同的图案** ——
	# 于是 Shift 画出来的笔触和普通绘制肉眼可见地不一样（实测最多差 152 像素）。
	b.position = at.floor()
	b.make_static()
	var s := PixelShape.new()
	s.set_pixel(0, 0, material_id)
	world.add_body(b, [s])
	renderer.sync(b)
	return b


## 松开左键：把这一笔"实体化"
func _finalize_stroke() -> void:
	var b := _stroke_body
	_stroke_body = null
	if b == null:
		return
	var pixels := 0
	for s: PixelShape in b.shapes:
		pixels += s.pixel_count()
	if pixels == 0:
		world.remove_body(b)
		renderer.forget(b.id)
		return
	b.make_dynamic()
	b.update_aabb()
	renderer.sync(b)


## 滚轮调笔刷大小。笔刷越大步进越大，否则从 1 调到 40 要滚几十下。
func _brush_step(dir: float) -> void:
	var step := 1.0
	if brush_radius >= 8.0:
		step = maxf(1.0, roundf(brush_radius * 0.15))
	brush_radius = clampf(brush_radius + dir * step, MIN_BRUSH, MAX_BRUSH)


func _paint(from: Vector2, to: Vector2) -> void:
	if _stroke_body != null:
		if Editor.paint_into(_stroke_body, from - _stroke_body.position, to - _stroke_body.position,
				brush_radius, material_id) > 0:
			renderer.sync(_stroke_body)
		return
	# 画在已有的可动体上（给它"补肉"）
	var hit := Editor.body_at(world.bodies, to, true)
	if hit != null:
		if Editor.paint_into(hit, hit.to_local(from), hit.to_local(to), brush_radius, material_id) > 0:
			renderer.sync(hit)
		return
	# 否则画成地形（静态画布瓦片）
	for b in Editor.paint_canvas(world, _canvas_tiles, from, to, brush_radius, material_id, CANVAS_TILE):
		renderer.sync(b)


## 改"大块像素"的尺寸：逻辑世界不动，只改渲染缩放与相机视野。
## 所有体素数据保持原样，所以物理、质量、破坏结果完全不受影响。
func _set_voxel_scale(v: float) -> void:
	var old := PixelScale.get_scale()
	PixelScale.set_scale(v)
	var newv := PixelScale.get_scale()
	if is_equal_approx(old, newv):
		return
	# 方块大小 = 相机缩放（唯一的一处缩放，不会叠乘）。
	# ⚠️ 必须乘上分辨率补偿，否则运行时改体素尺寸会把 1080p 的补偿丢掉、
	#    画面突然跳到另一种取景（这个补偿是"显示分辨率"的事，和体素尺寸无关）。
	camera.zoom = Vector2(newv, newv) * PixelScale.render_scale()
	for b in world.bodies:
		renderer.sync(b)


# ---------------------------------------------------------------- 擦除

func _erase(from: Vector2, to: Vector2) -> void:
	for r in Editor.erase(world, from, to, brush_radius, ERASE_BURST):
		renderer.sync(r["body"])
		for f in r["spawned"]:
			renderer.sync(f)


# ---------------------------------------------------------------- 拾取

func _body_at(world_point: Vector2, dynamic_only: bool) -> PBody:
	return Editor.body_at(world.bodies, world_point, dynamic_only)
