extends SceneTree
## 定位"没接触到别的物体也很卡"（拖动时）。
## (a) 抓取对物理步进的代价（对照：不抓）—— 看早先那个抓取子步上限还在不在
## (b) 渲染 sync 的代价（拖动一个物体时它每帧都在动）
const PWorld := preload("res://src/physics/pworld.gd")
const PBody := preload("res://src/physics/pbody.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")
const PixelRenderer := preload("res://src/render/pixel_renderer.gd")

func _box(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, w, h), 1)
	return s

func _scene(n: int, big: bool) -> PWorld:
	var w := PWorld.new()
	w.gravity = Vector2(0, 600)
	var g := PBody.new()
	g.position = Vector2(0, 600)
	g.make_static()
	w.add_body(g, [_box(4000, 40)], Callable(), true)
	for i in n:
		var b := PBody.new()
		b.position = Vector2((i % 20) * 60 - 600, -100 - (i / 20) * 60)
		w.add_body(b, [_box(40, 40)], Callable(), true)
	if big:
		var bb := PBody.new()
		bb.position = Vector2(0, 200)
		w.add_body(bb, [_box(300, 200)], Callable(), true)   # 大物体：贴图块多
	return w

func _steps(w, n: int, swing: bool, target: PBody) -> float:
	var t := Time.get_ticks_usec()
	for i in n:
		if swing:
			w.set_grab_target(target.position + Vector2(sin(i * 0.3) * 40.0, 0))
		w.step(1.0 / 60.0)
	return (Time.get_ticks_usec() - t) / 1000.0

func _initialize() -> void:
	var w := _scene(100, true)
	for i in 60:
		w.step(1.0 / 60.0)
	var big: PBody = w.bodies[w.bodies.size() - 1]
	var no_grab := _steps(w, 120, false, big)
	print("(a) 不抓：120 步 %.1f ms（%.3f ms/帧）" % [no_grab, no_grab / 120.0])
	w.grab(big, big.position)
	var held := _steps(w, 120, false, big)
	print("(a) 抓着不动：120 步 %.1f ms（%.3f ms/帧）-> %.1f 倍" % [
		held, held / 120.0, held / maxf(no_grab, 0.001)])
	var swung := _steps(w, 120, true, big)
	print("(a) 抓着摆动：120 步 %.1f ms（%.3f ms/帧）-> %.1f 倍" % [
		swung, swung / 120.0, swung / maxf(no_grab, 0.001)])
	w.release_grab()
	var after := _steps(w, 120, false, big)
	print("(a) 松手后：120 步 %.1f ms（%.3f ms/帧）" % [after, after / 120.0])

	# (b) 渲染 sync
	var rend := PixelRenderer.new()
	get_root().add_child(rend)
	var t := Time.get_ticks_usec()
	rend.sync(big)
	print("(b) sync 首次（建块）= %.3f ms" % ((Time.get_ticks_usec() - t) / 1000.0))
	t = Time.get_ticks_usec()
	for i in 60:
		rend.sync(big)
	print("(b) sync 未变 60 次 = %.4f ms/次" % ((Time.get_ticks_usec() - t) / 1000.0 / 60.0))
	t = Time.get_ticks_usec()
	for i in 60:
		big.position += Vector2(1, 0)
		rend.sync(big)
	print("(b) sync 每帧移动 60 次 = %.3f ms/次" % ((Time.get_ticks_usec() - t) / 1000.0 / 60.0))
	quit(0)
