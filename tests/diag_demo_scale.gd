extends SceneTree
## 量**真实 demo 场景**：规模多大、每帧多少、抓取时多少。
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
	if ps == null:
		print("场景加载失败")
		quit(1)
		return
	var root = ps.instantiate()
	get_root().add_child(root)
	await process_frame
	var pw = _find_pw(root)
	if pw == null:
		print("没找到 PixelWorld")
		quit(1)
		return
	var w = pw.world
	var rects := 0
	var pixels := 0
	var biggest = null
	var big_rects := 0
	for b in w.bodies:
		rects += b.rects.size()
		for s in b.shapes:
			pixels += s.pixel_count()
		if b.rects.size() > big_rects:
			big_rects = b.rects.size()
			biggest = b
	print("场景规模：刚体 %d 个，矩形合计 %d，像素合计 %d，最大单体 %d 矩形" % [
		w.bodies.size(), rects, pixels, big_rects])

	# 先跑 60 帧落稳，再量 120 帧
	for i in 60:
		await physics_frame
	var t := Time.get_ticks_usec()
	for i in 120:
		await physics_frame
	var base := (Time.get_ticks_usec() - t) / 1000.0
	print("不抓：%.3f ms/帧" % (base / 120.0))

	if biggest != null:
		w.grab(biggest, biggest.position)
		t = Time.get_ticks_usec()
		for i in 120:
			w.set_grab_target(biggest.position + Vector2(sin(i * 0.3) * 40.0, 0))
			await physics_frame
		var g := (Time.get_ticks_usec() - t) / 1000.0
		print("抓最大单体（%d 矩形）：%.3f ms/帧 -> %.1f 倍" % [
			big_rects, g / 120.0, g / maxf(base, 0.001)])
		w.release_grab()
	quit(0)
