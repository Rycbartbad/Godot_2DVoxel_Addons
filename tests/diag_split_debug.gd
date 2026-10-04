extends SceneTree
## 定位：为什么 detach 里的碎片没生成。
const PWorld := preload("res://src/physics/pworld.gd")
const PBody := preload("res://src/physics/pbody.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")
const Destruction := preload("res://src/core/destruction.gd")

func _initialize() -> void:
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, 40, 40), 1)
	var dmg = Destruction.Damage.circle(Vector2(20, 20), 6.0)
	var ex: PixelShape = Destruction.extract_damage(s, dmg)
	print("extract_damage -> 像素 %d，aabb %s" % [ex.pixel_count(), str(ex.local_aabb())])
	var w := PWorld.new()
	print("min_fragment_pixels = %d" % w.min_fragment_pixels)
	var parts: Array = Destruction.split(ex, w.min_fragment_pixels)
	print("split(min=%d) -> %d 块" % [w.min_fragment_pixels, parts.size()])
	for p in parts:
		print("   块：像素 %d，aabb %s" % [p.pixel_count(), str(p.local_aabb())])
	var parts1: Array = Destruction.split(ex, 1)
	print("split(min=1) -> %d 块" % parts1.size())
	for p in parts1:
		print("   块：像素 %d" % p.pixel_count())
	# 对照：对整个方块 split 有没有东西
	var parts2: Array = Destruction.split(s, 1)
	print("对照 split(整个方块, 1) -> %d 块" % parts2.size())
	quit(0)
