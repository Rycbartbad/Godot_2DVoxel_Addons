extends SceneTree
const PixelShape := preload("res://addons/pixel_destruction/core/pixel_shape.gd")
const Destruction := preload("res://addons/pixel_destruction/core/destruction.gd")

func _initialize() -> void:
	var s := PixelShape.new()
	for y in 24:
		for x in 24:
			if (x - 12) * (x - 12) + (y - 12) * (y - 12) <= 144:
				s.set_pixel(x, y, 1)
	print("初始像素数 = ", s.pixel_count())
	var d := Destruction.Damage.circle(Vector2(12.0, 12.0), 5.0)
	var removed := Destruction.apply_damage(s, d)
	print("移除 = ", removed, "  剩余 = ", s.pixel_count())
	var parts: Array = Destruction.split(s, 1)
	print("分裂成 ", parts.size(), " 块")
	for p in parts:
		print("   一块 ", (p as PixelShape).pixel_count(), " 像素")
	# 换成切掉右半边，应当分裂
	var s2 := PixelShape.new()
	for y in 20:
		for x in 20:
			s2.set_pixel(x, y, 1)
	var d2 := Destruction.Damage.rect(Vector2(10.0, 10.0), Vector2(1.0, 10.0))
	var rm2 := Destruction.apply_damage(s2, d2)
	print("切两半：移除 = ", rm2, " 剩余 = ", s2.pixel_count())
	var parts2: Array = Destruction.split(s2, 1)
	print("分裂成 ", parts2.size(), " 块")
	quit(0)
