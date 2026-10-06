extends SceneTree
## 复现"快速多次擦除 -> 卡死；慢速没事"。
## 每帧打印：帧耗时峰值 / 活刚体 / Rapier 刚体 / 渲染重建块数 / 子步。
const AddonWorld := preload("res://src/nodes/pixel_world.gd")
const AddonBody := preload("res://src/nodes/pixel_body_2d.gd")
const AddonShape := preload("res://src/nodes/pixel_shape_2d.gd")
const Editor := preload("res://src/core/pixel_editor.gd")

var _pw = null
var _ground = null

func _setup() -> void:
	_pw = AddonWorld.new()
	var g = AddonBody.new()
	g.position = Vector2(0, 220)
	g.is_static = true
	_pw.add_child(g)
	var gs = AddonShape.new()
	gs.rect_size = Vector2i(768, 100)
	g.add_child(gs)
	get_root().add_child(_pw)
	await process_frame
	await process_frame
	_pw.rebuild()
	for b in _pw.world.bodies:
		if b.is_static:
			_ground = b
			break
	_pw.renderer.sync(_ground)

## 一笔擦除（与 demo 的 _erase 同一路径）
func _stroke(x: float) -> void:
	for r in Editor.erase(_pw.world, Vector2(x, 270.0), Vector2(x + 6.0, 270.0), 6.0, 25.0):
		_pw.renderer.sync(r["body"])
		for f in r["spawned"]:
			_pw.renderer.sync(f)

func _run(label: String, per_frame: int, frames: int) -> void:
	await _setup()
	var worst := 0.0
	var worst_frame := -1
	var x := 30.0
	var total_tiles := 0
	for frame in frames:
		var t0 := Time.get_ticks_usec()
		for k in per_frame:
			x += 11.0
			if x > 740.0:
				x = 30.0
			_stroke(x)
		# 模拟 PixelWorld 的每帧：step + prune + 逐体 sync
		_pw.world.step(1.0 / 60.0)
		_pw.renderer.prune(_pw._live_ids())
		var rebuilt := 0
		for i in _pw.world.bodies.size():
			var b = _pw.world.bodies[i]
			if b.is_static:
				continue
			if i < _pw._body_nodes.size() and not _pw.uses_internal_render(_pw._body_nodes[i]):
				_pw.renderer.forget(b.id)
				continue
			_pw.renderer.sync(b)
			rebuilt += _pw.renderer.last_tiles_rebuilt
		total_tiles += rebuilt
		var ms := float(Time.get_ticks_usec() - t0) / 1000.0
		if ms > worst:
			worst = ms
			worst_frame = frame
		if frame % 120 == 0:
			print("  [%s] 帧 %4d | 本帧 %7.3f ms | 活刚体 %4d | Rapier %5d | 本帧重建块 %4d | 子步 %3d | 节点数组 %4d" % [
				label, frame, ms, _pw.world.bodies.size(), _pw.world.rp_body_count(),
				rebuilt, _pw.world.last_substeps, _pw._body_nodes.size()])
	print("  [%s] 最坏一帧 %8.3f ms（第 %d 帧）| 累计重建块 %d" % [label, worst, worst_frame, total_tiles])
	_pw.queue_free()

func _initialize() -> void:
	print("=== 慢速擦除：每 30 帧一笔 ===")
	await _run("慢", 1, 600)
	print("=== 快速擦除：每帧 5 笔 ===")
	await _run("快", 5, 600)
	quit(0)
