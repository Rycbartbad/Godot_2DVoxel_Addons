extends SceneTree
## 最小复现：一个睡着的箱子 + 一个抓取
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")
const Grab := preload("res://src/physics/grab.gd")

func _block(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	for y in h:
		for x in w:
			s.set_pixel(x, y, 1)
	return s

func _mk(native: bool, sleeping: bool) -> Dictionary:
	var w := PWorld.new()
	w.sleeping_enabled = sleeping
	var g := PBody.new()
	g.position = Vector2(-200.0, 0.0)
	g.make_static()
	w.add_body(g, [_block(400, 40)])
	var b := PBody.new()
	b.position = Vector2(0.0, -16.0)
	w.add_body(b, [_block(16, 16)])
	for i in 60:
		w.step(1.0 / 60.0)
	var gr := Grab.new()
	gr.body = b
	gr.local_anchor = Vector2.ZERO
	w.grabs.append(gr)
	return {"w": w, "g": gr, "b": b}

func _initialize() -> void:
	for sleeping in [true, false]:
		print("=== sleeping_enabled=%s ===" % str(sleeping))
		var A := _mk(false, sleeping)
		var B := _mk(true, sleeping)
		for s in 6:
			for d in [A, B]:
				(d["g"] as Grab).target = Vector2(0.0, -150.0)
				(d["w"] as PWorld).step(1.0 / 60.0)
			var ba: PBody = A["b"]
			var bb: PBody = B["b"]
			print("  步%d 对象 pos=(%.4f,%.4f) vel=(%.4f,%.4f) awake=%s | 扩展 pos=(%.4f,%.4f) vel=(%.4f,%.4f) awake=%s" % [
				s, ba.position.x, ba.position.y, ba.linear_velocity.x, ba.linear_velocity.y, str(ba.awake),
				bb.position.x, bb.position.y, bb.linear_velocity.x, bb.linear_velocity.y, str(bb.awake)])
	quit(0)
