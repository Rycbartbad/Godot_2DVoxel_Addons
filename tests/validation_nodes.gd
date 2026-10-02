extends SceneTree
## 验证"在编辑器里拖动 PixelBody2D"的机制：
##   改 position -> NOTIFICATION_TRANSFORM_CHANGED -> PixelWorld 重烘焙 -> 刚体跟着走
##
## 拖动本身是 Godot 内置的（Node2D + 移动模式），这里验的是**我们的响应链**。
const PixelBody2D := preload("res://src/nodes/pixel_body_2d.gd")
const PixelWorld := preload("res://src/nodes/pixel_world.gd")

var _pass := 0
var _fail := 0
func _c(n: String, ok: bool, d: String = "") -> void:
	if ok:
		_pass += 1
		print("  PASS  ", n, "  ", d)
	else:
		_fail += 1
		print("  FAIL  ", n, "  ", d)

func _initialize() -> void:
	var pw := PixelWorld.new()
	root.add_child(pw)
	var a := PixelBody2D.new()
	a.name = "A"
	a.position = Vector2(10, 20)
	a.rect_size = Vector2i(16, 16)
	pw.add_child(a)
	var b := PixelBody2D.new()
	b.name = "B"
	b.position = Vector2(100, 0)
	b.rect_size = Vector2i(8, 8)
	b.is_static = true
	pw.add_child(b)

	if pw.world == null:
		pw.rebuild()
	_c("烘焙出 2 个刚体", pw.world.bodies.size() == 2, "%d" % pw.world.bodies.size())
	_c("位置来自节点 position", pw.world.bodies[0].position.is_equal_approx(Vector2(10, 20)),
		str(pw.world.bodies[0].position))
	_c("静态标记传下去了", pw.world.bodies[1].is_static)

	# ---- 拖动的两条契约 ----
	print("=== 拖动契约 ===")
	var old_id: int = pw.world.bodies[0].id
	a.position = Vector2(200, 60)
	# ⚠️ 这个常量定义在 Node2D 上，不在 Node 上
	a.notification(Node2D.NOTIFICATION_TRANSFORM_CHANGED)
	await process_frame
	await process_frame
	# 契约 1：**运行时**不该因为 transform 变化就重建世界 ——
	#         那时位置归物理管，重建会把模拟结果抹掉。
	_c("运行时不受 transform 通知影响（守卫 Engine.is_editor_hint）",
		pw.world.bodies[0].id == old_id, "id 保持 %d" % old_id)

	# 契约 2：显式 rebuild 之后，刚体跟到节点的新位置。
	#         （编辑器里由 on_child_moved 自动触发这条；运行时不该自动走。）
	pw.rebuild()
	_c("rebuild 后刚体跟到新位置",
		pw.world.bodies[0].position.is_equal_approx(Vector2(200, 60)),
		str(pw.world.bodies[0].position))
	_c("重烘焙换新 id（所以渲染器必须 prune({}) 清空重建）",
		pw.world.bodies[0].id != old_id, "%d -> %d" % [old_id, pw.world.bodies[0].id])
	_c("刚体数不变", pw.world.bodies.size() == 2, "%d" % pw.world.bodies.size())

	# ---- 吸附：位置应当能被对齐到整数 ----
	print("=== 吸附开关 ===")
	_c("默认开启像素吸附", a.snap_to_pixel)

	# ---- 三种形状来源都能烘焙 ----
	print("=== 形状来源 ===")
	var c := PixelBody2D.new()
	c.source = PixelBody2D.Source.CIRCLE
	c.radius = 6.0
	var sc := c.build_shape()
	_c("CIRCLE 造出形状", not sc.is_empty(), "%d 像素" % sc.pixel_count())
	var d := PixelBody2D.new()
	d.source = PixelBody2D.Source.TEXTURE
	d.texture = null
	var sd := d.build_shape()
	_c("TEXTURE 没设贴图时是空形状（不崩）", sd.is_empty())

	print("=== %d passed, %d failed ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
