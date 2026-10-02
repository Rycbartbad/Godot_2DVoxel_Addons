extends SceneTree
## 决定性实验：塌陷是不是"接触没来得及建立"
## 手段：扫 max_speculative_margin / ccd_max_motion / 子步上限
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")
func _block(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, w, h), 1)
	return s

func _run(name: String, gap: float, margin: float, ccd_motion: float, maxsub: int) -> void:
	var w := PWorld.new()
	w.max_speculative_margin = margin
	w.ccd_max_motion = ccd_motion
	w.max_substeps = maxsub
	var g := PBody.new()
	g.position = Vector2(-300.0, 400.0)
	g.make_static()
	w.add_body(g, [_block(600, 40)])
	var boxes: Array = []
	for i in 3:
		var b := PBody.new()
		b.position = Vector2(0.0, 400.0 - 20.0 * (i + 1) - gap * (i + 1))
		w.add_body(b, [_block(20, 20)])
		boxes.append(b)
	var maxsub_seen := 0
	for step in 300:
		w.step(1.0 / 60.0)
		maxsub_seen = maxi(maxsub_seen, w.last_substeps)
	var pen1: float = (boxes[1].position.y + 20.0) - boxes[0].position.y
	var pen2: float = (boxes[2].position.y + 20.0) - boxes[1].position.y
	var awake := 0
	for b in boxes:
		if b.awake:
			awake += 1
	var ok := pen1 < 2.0 and pen2 < 2.0
	print("  %-34s 穿透 %6.2f %6.2f | 子步峰值 %d | 清醒 %d/3  %s" % [
		name, pen1, pen2, maxsub_seen, awake, "稳定" if ok else "塌陷"])

func _initialize() -> void:
	print("=== gap=4，扫推测接触余量 ===")
	for m in [1.5, 2.0, 3.0, 4.0, 6.0]:
		_run("margin=%.1f" % m, 4.0, m, 2.0, 4)
	print("=== gap=4，扫 ccd_max_motion（余量固定 1.5）===")
	for c in [2.0, 1.0, 0.5, 0.25]:
		_run("ccd_motion=%.2f" % c, 4.0, 1.5, c, 4)
	print("=== gap=4，抬子步上限 ===")
	for s in [4, 8, 16]:
		_run("max_substeps=%d" % s, 4.0, 1.5, 2.0, s)
	print("=== gap=8，同样扫 ===")
	for m in [1.5, 3.0, 6.0]:
		_run("margin=%.1f" % m, 8.0, m, 2.0, 4)
	quit(0)
