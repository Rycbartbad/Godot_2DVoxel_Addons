extends SceneTree
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")
const ShapeOps := preload("res://src/core/shape_ops.gd")

func _initialize() -> void:
	var w := PWorld.new()
	w.gravity = Vector2.ZERO
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, 20, 4), 1)
	s.fill_rect(Rect2i(0, 8, 20, 4), 1)
	print("原形状 aabb = ", s.local_aabb(), " 像素 ", s.pixel_count())
	var holder := PBody.new()
	holder.position = Vector2(500.0, 0.0)
	w.add_body(holder, [s])
	var rest := ShapeOps.split(s)
	print("切出 ", rest.size(), " 块")
	print("原形状 aabb = ", s.local_aabb(), " 像素 ", s.pixel_count())
	for i in holder.shapes.size():
		var sh: PixelShape = holder.shapes[i]
		print("  shapes[%d] aabb=%s 像素=%d owner=%s" % [i, str(sh.local_aabb()), sh.pixel_count(), str(sh.owner_body != null)])
	var other: PixelShape = holder.shapes[1]
	other.translate_pixels(0, -4)
	print("平移后 shapes[1] aabb = ", other.local_aabb())
	print("is_touching = ", ShapeOps.is_touching(s, other))
	print("s 的 (5,3) = ", s.get_pixel(5, 3), "  other 的 (5,4) = ", other.get_pixel(5, 4))
	print("other 的 (5,3) = ", other.get_pixel(5, 3), "  other 的 (5,5) = ", other.get_pixel(5, 5))
	quit(0)
