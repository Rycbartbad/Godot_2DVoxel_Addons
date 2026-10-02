extends SceneTree
## 直接测 _fill_contact_impulses 的成本：同一场景，开/关各跑 5 次取最好。
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

func _build(n: int) -> PWorld:
	var w := PWorld.new()
	w.gravity = Vector2(0, 400)
	w.contact_events_enabled = true
	var g := PBody.new()
	g.position = Vector2(-500, 300)
	g.make_static()
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, 1000, 40), 1)
	w.add_body(g, [s])
	for i in n:
		var b := PBody.new()
		b.position = Vector2(-400 + (i % 25) * 32, -200 - (i / 25) * 20)
		var bs := PixelShape.new()
		bs.fill_rect(Rect2i(0, 0, 12, 12), 1)
		w.add_body(b, [bs])
	return w

func _time(n: int, steps: int, enable: bool) -> float:
	var best := 1.0e9
	for rep in 3:
		var w := _build(n)
		w.fill_contact_impulses_enabled = enable
		# 先热身 60 步让它们落到地上、产生大量接触
		for i in 60:
			w.step(1.0 / 60.0)
		var t0 := Time.get_ticks_usec()
		for i in steps:
			w.step(1.0 / 60.0)
		var dt := float(Time.get_ticks_usec() - t0) / 1000.0 / float(steps)
		best = minf(best, dt)
	return best

func _initialize() -> void:
	await process_frame
	for n in [300, 600]:
		var on := _time(n, 300, true)
		var off := _time(n, 300, false)
		var d := on - off
		print("%4d 体：开 %7.3f ms/step   关 %7.3f ms/step   差值 %+7.4f ms (%+.2f%%)"
			% [n, on, off, d, d / off * 100.0])
	quit(0)
