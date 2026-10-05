extends SceneTree
## 用引用计数找"外部持有者"：量刚体/形状/chunk 各自被谁持着。
## 期望（只有世界内部持有）：body 被 world.bodies + _rp_by_id 持；shape 被 body.shapes 持。
const PWorld := preload("res://src/physics/pworld.gd")
const PBody := preload("res://src/physics/pbody.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

func _initialize() -> void:
	var w := PWorld.new()
	w._rp_ensure()
	var b := PBody.new()
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, 8, 8), 1)
	w.add_body(b, [s], Callable(), true)
	var c = s.chunk_at(0, 0)
	print("body=%d（期望 3：world.bodies + _rp_by_id + 局部变量）" % b.get_reference_count())
	print("shape=%d（期望 2：body.shapes + 局部变量）" % s.get_reference_count())
	print("chunk=%d（期望 2：shape.chunks + 局部变量）" % c.get_reference_count())
	# 把局部变量放掉，看还剩几
	var c2 = c
	c = null
	print("放掉 chunk 局部后 = %d（期望 1：只有 shape.chunks）" % c2.get_reference_count())
	quit(0)
