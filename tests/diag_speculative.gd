extends SceneTree
## 推测接触还活着吗？
## 让一个方块以已知速度接近另一个，看"第一次出现流形"时两者相距多远。
## 如果余量是活的，第一次接触时的间距应该约等于 max_speculative_margin。
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")
func _block(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, w, h), 1)
	return s

func _probe(margin: float, speed: float) -> void:
	var w := PWorld.new()
	w.gravity = Vector2.ZERO
	w.max_speculative_margin = margin
	var target := PBody.new()
	target.position = Vector2(0.0, 200.0)
	target.make_static()
	w.add_body(target, [_block(20, 20)])
	var mover := PBody.new()
	mover.position = Vector2(0.0, 100.0)
	w.add_body(mover, [_block(20, 20)])
	mover.linear_velocity = Vector2(0.0, speed)
	# mover 底边初始在 120，target 顶边在 200 -> 初始间距 80
	var first_gap := -1.0
	var first_pen := 0.0
	for step in 200:
		w.step(1.0 / 60.0)
		var gap: float = 200.0 - (mover.position.y + 20.0)     # 正 = 还有间距
		if w.last_contacts > 0 and first_gap < 0.0:
			first_gap = gap
			first_pen = -gap
	print("  余量 %4.1f 速度 %5.0f px/s -> 首次接触时间距 %8.4f（穿透 %8.4f） 子步 %d 流形 %d" % [
		margin, speed, first_gap, first_pen, w.last_substeps, w.last_contacts])

func _initialize() -> void:
	print("=== 首次接触时的间距 vs 推测接触余量 ===")
	print("（如果余量是活的，间距应当约等于余量）")
	for m in [1.5, 3.0, 6.0, 12.0]:
		_probe(m, 60.0)
	print("=== 同样但速度更快 ===")
	for m in [1.5, 6.0]:
		_probe(m, 300.0)
	quit(0)
