extends SceneTree
## 真实 demo 场景：抓取 vs 不抓 —— **不用 await**（await 会被帧节流掩盖）。
## 上一版我用 await physics_frame 计时，得到"1.0 倍"，那是错的。
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
	pw.auto_step = false
	pw.auto_render = false
	# 落稳（直接 step，不用 await）
	for i in 60:
		w.step(1.0 / 60.0)

	var biggest = null
	var big_rects := 0
	for b in w.bodies:
		if b.rects.size() > big_rects:
			big_rects = b.rects.size()
			biggest = b
	print("场景：刚体 %d，最大单体 %d 矩形，max_substeps=%s" % [
		w.bodies.size(), big_rects, str(pw.max_substeps)])

	var t := Time.get_ticks_usec()
	for i in 120:
		w.step(1.0 / 60.0)
	var base := (Time.get_ticks_usec() - t) / 1000.0
	print("不抓     = %.3f ms/帧" % (base / 120.0))

	w.grab(biggest, biggest.position)
	t = Time.get_ticks_usec()
	for i in 120:
		w.step(1.0 / 60.0)
	var held := (Time.get_ticks_usec() - t) / 1000.0
	print("抓着不动 = %.3f ms/帧 -> %.1f 倍" % [held / 120.0, held / maxf(base, 0.001)])

	t = Time.get_ticks_usec()
	for i in 120:
		w.set_grab_target(biggest.position + Vector2(sin(i * 0.3) * 40.0, 0))
		w.step(1.0 / 60.0)
	var swung := (Time.get_ticks_usec() - t) / 1000.0
	print("抓着摆动 = %.3f ms/帧 -> %.1f 倍" % [swung / 120.0, swung / maxf(base, 0.001)])
	quit(0)
