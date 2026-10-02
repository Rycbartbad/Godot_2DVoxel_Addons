extends SceneTree
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")
const Query := preload("res://src/physics/query.gd")

func _initialize() -> void:
	var w := PWorld.new()
	w.gravity = Vector2.ZERO
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, 40, 40), 3)
	var wall := PBody.new()
	wall.position = Vector2(100.0, 0.0)
	wall.make_static()
	w.add_body(wall, [s])
	print("世界刚体数 = ", w.bodies.size())
	print("wall.rects = ", wall.rects.size(), "  wall.aabb = ", wall.aabb)
	Query.attach(w)
	var got := Query.aabb_bodies(Rect2(90.0, 10.0, 60.0, 20.0))
	print("aabb_bodies 返回 = ", got.size())
	print("全图查询 = ", Query.aabb_bodies(Rect2(-10000.0, -10000.0, 20000.0, 20000.0)).size())
	# 直接问内部
	print("world.bodies 是同一个数组吗: ", w.bodies == Query._bodies)
	print("_bodies 内容 = ", Query._bodies.size())
	quit(0)
