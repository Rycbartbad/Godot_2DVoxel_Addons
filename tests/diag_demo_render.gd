extends SceneTree
## 真实 demo 场景：**渲染**在拖动时的代价（物理已排除：0.13~0.26 ms/帧）。
## 假设：拖动时被拖物体的贴图块每帧重建（实测每块约 1 ms），块多就直接 8 fps。
func _find_pw(n):
	if n.has_method("game_view_size") and n.get("world") != null:
		return n
	for c in n.get_children():
		var r = _find_pw(c)
		if r != null:
			return r
	return null

func _initialize() -> void:
	var ps: PackedScene = load("res://scenes/demo.tscn")
	var root = ps.instantiate()
	get_root().add_child(root)
	await process_frame
	var pw = _find_pw(root)
	var w = pw.world
	var rend = pw.renderer
	pw.auto_step = false
	pw.auto_render = false
	for i in 60:
		w.step(1.0 / 60.0)

	var biggest = null
	var big_rects := 0
	for b in w.bodies:
		if b.rects.size() > big_rects:
			big_rects = b.rects.size()
			biggest = b

	# 贴图块总数
	var total_tiles := 0
	var holder = rend._nodes.get(biggest.id)
	if holder != null:
		total_tiles = holder.get_child_count()
	print("最大单体 %d 矩形，它的贴图块 %d 个；全场贴图块 %d 个" % [
		big_rects, total_tiles, _count_tiles(rend)])

	rend.sync(biggest)

	var t := Time.get_ticks_usec()
	for i in 120:
		rend.sync(biggest)
	var sync_rest := (Time.get_ticks_usec() - t) / 1000.0
	print("不拖：sync 该物体 = %.4f ms/帧" % (sync_rest / 120.0))

	w.grab(biggest, biggest.position)
	t = Time.get_ticks_usec()
	for i in 120:
		w.set_grab_target(biggest.position + Vector2(sin(i * 0.3) * 40.0, 0))
		w.step(1.0 / 60.0)
		rend.sync(biggest)
	var sync_drag := (Time.get_ticks_usec() - t) / 1000.0
	print("拖动：step + sync 该物体 = %.3f ms/帧" % (sync_drag / 120.0))

	# 只 sync（物体已由上面拖动过，看是不是每帧重建）
	t = Time.get_ticks_usec()
	for i in 120:
		rend.sync(biggest)
	var sync_only := (Time.get_ticks_usec() - t) / 1000.0
	print("松手后：sync 该物体 = %.4f ms/帧" % (sync_only / 120.0))
	quit(0)

func _count_tiles(rend) -> int:
	var n := 0
	for k in rend._nodes:
		var h = rend._nodes[k]
		if h != null and h.get_child_count() > 0:
			n += h.get_child_count()
	return n
