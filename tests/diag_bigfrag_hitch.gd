extends SceneTree
## 大物体"生成新碎片"那一帧的**端到端**开销分解（诊断探针，不是闸门）。
##
## 为什么要它：现有两个探针各有盲区 ——
##   · diag_split_profile.gd 量的是**纯破坏**（不接渲染器）；
##   · profile_sync.gd 量的是**擦除的增量贴图**（0.36 ms/笔）。
## 而玩家看到的卡顿是"破坏 + **首次渲染新碎片**"这一帧，两半加起来才是账。
##
## 口径：全部走 CPU 路径（GPU 破坏路径已删除 —— 它默认关闭、实测比 CPU 慢）。
const PWorld := preload("res://src/physics/pworld.gd")
const PBody := preload("res://src/physics/pbody.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")
const Destruction := preload("res://src/core/destruction.gd")
const PixelRenderer := preload("res://src/render/pixel_renderer.gd")

func _shape(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, w, h), 1)
	return s

func _ms(t0: int) -> float:
	return float(Time.get_ticks_usec() - t0) / 1000.0

func _new_world(stat: bool, w: int, h: int) -> Array:
	var world := PWorld.new()
	world.gravity = Vector2.ZERO
	var b := PBody.new()
	if stat:
		b.make_static()
	world.add_body(b, [_shape(w, h)])
	return [world, b]

## ① 破坏那半：best-of-5（去掉冷启动）
func _fracture_best(w: int, h: int, stat: bool, reps: int) -> float:
	var best := 1.0e9
	for r in reps:
		var wb := _new_world(stat, w, h)
		var world: PWorld = wb[0]
		var b: PBody = wb[1]
		for i in 20:
			world.step(1.0 / 60.0)
		var t := Time.get_ticks_usec()
		world.fracture(b, Destruction.Damage.segment(Vector2(w / 2, -5), Vector2(w / 2, h + 5), 2.0))
		best = minf(best, _ms(t))
	return best

## ② 渲染那半：逐像素建图 / 建 GPU 贴图 / 建 Sprite 节点
func _render_breakdown(w: int, h: int) -> void:
	var root := Node2D.new()
	get_root().add_child(root)
	var rend := PixelRenderer.new()
	root.add_child(rend)
	var s := _shape(w, h)
	var b := PBody.new()
	var world := PWorld.new()
	world.add_body(b, [s])
	var aabb: Rect2i = s.local_aabb()
	var t_img := 0.0
	var t_tex := 0.0
	var t_node := 0.0
	var n_tiles := 0
	var x0 := aabb.position.x >> 6
	var y0 := aabb.position.y >> 6
	var x1 := (aabb.position.x + aabb.size.x - 1) >> 6
	var y1 := (aabb.position.y + aabb.size.y - 1) >> 6
	for ty in range(y0, y1 + 1):
		for tx in range(x0, x1 + 1):
			var rx := maxi(tx << 6, aabb.position.x)
			var ry := maxi(ty << 6, aabb.position.y)
			var rx2 := mini((tx << 6) + 64, aabb.position.x + aabb.size.x)
			var ry2 := mini((ty << 6) + 64, aabb.position.y + aabb.size.y)
			if rx2 <= rx or ry2 <= ry:
				continue
			var tr := Rect2i(rx - aabb.position.x, ry - aabb.position.y, rx2 - rx, ry2 - ry)
			var t := Time.get_ticks_usec()
			var img: Image = rend._build_region_image([s], aabb, tr)
			t_img += _ms(t)
			t = Time.get_ticks_usec()
			var tex: ImageTexture = ImageTexture.create_from_image(img)
			t_tex += _ms(t)
			t = Time.get_ticks_usec()
			var sp := Sprite2D.new()
			sp.centered = false
			sp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			rend.add_child(sp)
			t_node += _ms(t)
			n_tiles += 1
			if tex == null or sp == null:
				print("never")
	print("=== ② 渲染冷同步分解 %dx%d（%d 像素 / %d 块）===" % [w, h, s.pixel_count(), n_tiles])
	print("  逐像素建 RGBA8 图 _build_region_image = %7.3f ms  （%.3f us/像素）" % [t_img, t_img * 1000.0 / float(s.pixel_count())])
	print("  ImageTexture.create_from_image        = %7.3f ms" % t_tex)
	print("  Sprite2D.new + add_child              = %7.3f ms" % t_node)
	print("  合计                                  = %7.3f ms" % (t_img + t_tex + t_node))
	root.queue_free()

## ③ 归属：切开之后**谁**在重建全部贴图
func _attribution(w: int, h: int) -> void:
	var root := Node2D.new()
	get_root().add_child(root)
	var rend := PixelRenderer.new()
	root.add_child(rend)
	var wb := _new_world(true, w, h)
	var world: PWorld = wb[0]
	var b: PBody = wb[1]
	rend.sync(b)
	print("=== ③ 归属（%dx%d 静态底板一刀切两半）===" % [w, h])
	var t := Time.get_ticks_usec()
	var frags: Array = world.fracture(b, Destruction.Damage.segment(Vector2(w / 2, -5), Vector2(w / 2, h + 5), 2.0))
	print("  fracture（单次，含冷启动）= %.3f ms -> %d 碎片" % [_ms(t), frags.size()])
	for x in world.bodies:
		t = Time.get_ticks_usec()
		rend.sync(x)
		print("  %s aabb=%s 像素=%d | sync=%7.3f ms  重建块=%d/%d\n        last_debug=%s" % [
			"母体" if x == b else "碎片", str(x.shapes[0].local_aabb()),
			x.shapes[0].pixel_count(), _ms(t), rend.last_tiles_rebuilt, rend.last_tiles_total,
			rend.last_debug])
	t = Time.get_ticks_usec()
	for x in world.bodies:
		rend.sync(x)
	print("  再 sync 一遍（无变化）= %.3f ms  <- 每帧的稳态成本" % _ms(t))
	root.queue_free()

## ④ 对照：内部小洞（不 split + 脏矩形增量）
func _incremental(w: int, h: int) -> void:
	var root := Node2D.new()
	get_root().add_child(root)
	var rend := PixelRenderer.new()
	root.add_child(rend)
	var wb := _new_world(true, w, h)
	var world: PWorld = wb[0]
	var b: PBody = wb[1]
	rend.sync(b)
	var t := Time.get_ticks_usec()
	world.fracture(b, Destruction.Damage.circle(Vector2(200, 50), 6.0))
	var t_fr := _ms(t)
	t = Time.get_ticks_usec()
	rend.sync(b)
	print("=== ④ 对照：%dx%d 内部小洞 r=6 ===" % [w, h])
	print("  fracture（无 split）  = %7.3f ms" % t_fr)
	print("  sync（脏矩形增量）    = %7.3f ms  重建 %d/%d 块" % [_ms(t), rend.last_tiles_rebuilt, rend.last_tiles_total])
	root.queue_free()

## ⑤ AABB 缩了但**形状对象没被换掉**（右边缘擦一笔）—— ① 的主战场。
##    对照：一刀切两半会换掉形状对象，_assemble 给每个搬运过的块都打了
##    mark_dirty_key -> 脏信息=整张 -> 仍然全量（见 development_log）。
func _edge_erase(w: int, h: int) -> void:
	var root := Node2D.new()
	get_root().add_child(root)
	var rend := PixelRenderer.new()
	root.add_child(rend)
	var wb := _new_world(true, w, h)
	var world: PWorld = wb[0]
	var b: PBody = wb[1]
	rend.sync(b)
	print("=== ⑤ 右边缘擦一笔（AABB 缩、形状对象不变）===")
	print("  擦之前：aabb=%s 块=%d" % [str(b.shapes[0].local_aabb()), rend.last_tiles_total])
	var t := Time.get_ticks_usec()
	# ⚠️⚠️ 伤害必须**贯穿整个高度**，否则 AABB 不变：只在右边缘中间咬一口的话，
	#    四角的像素还撑着 max_x —— 那就走既有的增量路径，测不到 ①（我第一版就这么错的）。
	world.fracture(b, Destruction.Damage.segment(Vector2(w - 2, -5), Vector2(w - 2, h + 5), 3.0))
	var t_fr := _ms(t)
	t = Time.get_ticks_usec()
	rend.sync(b)
	print("  fracture=%7.3f ms | sync=%7.3f ms  重建块=%d/%d" % [
		t_fr, _ms(t), rend.last_tiles_rebuilt, rend.last_tiles_total])
	print("  擦之后：aabb=%s | last_debug=%s" % [str(b.shapes[0].local_aabb()), rend.last_debug])
	root.queue_free()


func _initialize() -> void:
	print("=== ① 破坏那半：fracture best-of-5 ===")
	print("  768x100 静态 = %.3f ms | 200x200 动态 = %.3f ms" % [
		_fracture_best(768, 100, true, 5), _fracture_best(200, 200, false, 5)])
	_render_breakdown(384, 100)
	_render_breakdown(768, 100)
	_attribution(768, 100)
	_incremental(768, 100)
	_edge_erase(768, 100)
	quit(0)
