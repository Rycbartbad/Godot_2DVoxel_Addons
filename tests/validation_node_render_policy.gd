extends SceneTree
## 节点层的**渲染归属**判据（R1）。
##
## 守四件事：
##   1. 自带 PixelSprite2D 的刚体**不进内部渲染器**（否则两份精灵重叠）；
##   2. `internal_render = false` 的刚体（仅物理：不可见的手/臂）也不进；
##   3. **破坏之后调 sync_world_bodies() 不会给它们补画一张矩形** —— ink-2 实测到的
##      "破坏瞬间多出一张矩形手、而且它停在旧位置"就是这个（游戏层跳过自有视觉的同步，
##      那张矩形就永远留在原地）；
##   4. 反过来：**以前画出来的旧贴图要被回收**（给刚体加上自有视觉之后再同步一次）。
##
## ⚠️ 判据不只看"渲染器自己记的账"（_nodes 里有没有键）—— 还要求那个 holder
##    **真的还在树里**（queue_free 是延迟的，账已经删了、节点可能还在画一帧）。
##
## ⚠️ 只测节点层：这里不碰物理结果，所以不影响 8 条逐位基准。

const PixelWorld := preload("res://src/nodes/pixel_world.gd")
const PixelBody2D := preload("res://src/nodes/pixel_body_2d.gd")
const PixelSprite2D := preload("res://src/nodes/pixel_sprite_2d.gd")

var _pass := 0
var _fail := 0
func _c(n: String, ok: bool, d: String = "") -> void:
	if ok:
		_pass += 1
		print("  PASS  ", n, "  ", d)
	else:
		_fail += 1
		print("  FAIL  ", n, "  ", d)


## 内部渲染器**正在画**这个刚体吗：账上有它，而且 holder 真的还在树里。
func _drawn(pw, body) -> bool:
	var h = pw.renderer._nodes.get(body.id)
	return h != null and is_instance_valid(h) and h.is_inside_tree()


func _body(pw, pos: Vector2, size: Vector2i) -> PixelBody2D:
	var b := PixelBody2D.new()
	b.position = pos
	b.rect_size = size
	pw.add_child(b)
	return b


func _initialize() -> void:
	print("=== 节点层的渲染归属（R1）===")
	var pw := PixelWorld.new()
	pw.name = "PixelWorld"
	get_root().add_child(pw)
	await process_frame

	var plain := _body(pw, Vector2(0, 0), Vector2i(16, 16))
	var own := _body(pw, Vector2(40, 0), Vector2i(16, 16))
	own.add_child(PixelSprite2D.new())          # 自有视觉（ink-2 的"三角形手"）
	var ghost := _body(pw, Vector2(80, 0), Vector2i(16, 16))
	ghost.internal_render = false               # 仅物理（ink-2 的"不可见 Arm"）
	var ground := _body(pw, Vector2(-100, 100), Vector2i(400, 20))
	ground.is_static = true
	await process_frame

	pw.rebuild()
	await process_frame
	_c("普通刚体由内部渲染器画（对照）", _drawn(pw, plain.body))
	_c("自带 PixelSprite2D 的刚体不画", not _drawn(pw, own.body))
	_c("internal_render=false 的刚体不画", not _drawn(pw, ghost.body))
	_c("静态地形照样画", _drawn(pw, ground.body))

	print("=== 旧贴图回收：刚体后来才拿到自有视觉 ===")
	plain.add_child(PixelSprite2D.new())
	_c("加视觉之前它是画着的", _drawn(pw, plain.body))
	pw.sync_world_bodies()
	_c("同步一次之后就回收了（不留矩形）", not _drawn(pw, plain.body))

	print("=== 连续固定步：不得再生成残影 ===")
	var plain2 := _body(pw, Vector2(120, 0), Vector2i(16, 16))
	pw.sync_world_bodies()
	for i in 6:
		await physics_frame
	_c("对照：该画的刚体仍然画着", _drawn(pw, plain2.body))
	_c("自有视觉的仍然不画", not _drawn(pw, own.body))
	_c("仅物理的仍然不画", not _drawn(pw, ghost.body))
	_c("后来加视觉的仍然不画", not _drawn(pw, plain.body))

	print("=== 破坏之后同步：碎片照画，这两类仍然不画 ===")
	# 从中间切一刀：剩下两块都还在，被切下来的那一块成为碎片（有新 id、没有节点）
	var cut := {}
	for y in 16:
		cut[Vector2i(8, y)] = true
	var removals := {own.body.shapes[0]: cut}
	var res: Dictionary = pw.fracture_pixels_and_sync(own.body, removals, 0.0)
	var frags: Array = res.get("fragments", [])
	_c("破坏产生了碎片", frags.size() > 0, "%d 个" % frags.size())
	var all_drawn := true
	for f in frags:
		if not _drawn(pw, f):
			all_drawn = false
	_c("碎片由内部渲染器画（它们没有节点）", all_drawn, "%d 个碎片" % frags.size())
	_c("破坏之后 own 仍然不画", not _drawn(pw, own.body))
	_c("破坏之后 ghost 仍然不画", not _drawn(pw, ghost.body))
	_c("破坏之后普通刚体仍然画着（对照）", _drawn(pw, plain2.body))
	for i in 4:
		await physics_frame
	_c("破坏 + 4 帧之后仍然没有残影（own）", not _drawn(pw, own.body))
	_c("破坏 + 4 帧之后仍然没有残影（ghost）", not _drawn(pw, ghost.body))
	_c("破坏 + 4 帧之后仍然没有残影（后来加视觉的）", not _drawn(pw, plain.body))

	print("---")
	if _fail == 0:
		print("全部通过：%d 项断言" % _pass)
	else:
		print("失败 %d / %d 项" % [_fail, _pass + _fail])
	quit(0 if _fail == 0 else 1)
