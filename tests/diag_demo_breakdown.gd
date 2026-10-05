extends SceneTree
## 把真实 demo 场景的每帧开销拆开：物理 step / 渲染 sync / 其它。
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
	for i in 60:
		await physics_frame

	# 关掉自动，手动分别量
	pw.auto_step = false
	pw.auto_render = false

	var t := Time.get_ticks_usec()
	for i in 120:
		w.step(1.0 / 60.0)
	var t_step := (Time.get_ticks_usec() - t) / 1000.0
	print("只物理 step   = %.3f ms/帧（刚体 %d）" % [t_step / 120.0, w.bodies.size()])

	t = Time.get_ticks_usec()
	for i in 120:
		for b in w.bodies:
			pw.renderer.sync(b)
	var t_rend := (Time.get_ticks_usec() - t) / 1000.0
	print("只渲染 sync   = %.3f ms/帧（%d 个刚体）" % [t_rend / 120.0, w.bodies.size()])

	# 对照：什么都不做，只跑物理帧（看引擎/节点自身的固定开销）
	t = Time.get_ticks_usec()
	for i in 120:
		await physics_frame
	var t_idle := (Time.get_ticks_usec() - t) / 1000.0
	print("空跑物理帧    = %.3f ms/帧（自动步进/渲染已关）" % [t_idle / 120.0])
	print("=> 合计 step+sync = %.3f ms，空跑 %.3f ms" % [t_step / 120.0 + t_rend / 120.0, t_idle / 120.0])
	quit(0)
