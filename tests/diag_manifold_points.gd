extends SceneTree
## 直接测窄相：平面对平面的重叠，到底出几个接触点
const Collide := preload("res://src/physics/collide.gd")
const PBody := preload("res://src/physics/pbody.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

func _block(w: int, h: int, mat: int = 1) -> PixelShape:
	var s := PixelShape.new()
	for y in h:
		for x in w:
			s.set_pixel(x, y, mat)
	return s

func _show(tag: String, wall: PBody, box: PBody, margin: float) -> void:
	var sat := Collide.Sat.new()
	var res: Dictionary = Collide.collide(Collide.obb_from_local_rect(box, box.rects[0]),
		Collide.obb_from_local_rect(wall, wall.rects[0]), margin, sat)
	var pts: Array = res["points"]
	print("%s sep=%.4f 法向=(%.3f,%.3f) 点数=%d" % [tag, sat.sep, res["normal"].x, res["normal"].y, pts.size()])
	for p in pts:
		print("    接触点 (%8.3f,%8.3f) depth=%.4f sep=%.4f feat=%d" % [
			p["position"].x, p["position"].y, p["depth"], p["sep"], p["feature"]])

func _initialize() -> void:
	var wall := PBody.new()
	wall.position = Vector2(200, 0)
	wall.make_static()
	wall.rebuild([_block(8, 200)])
	var box := PBody.new()
	box.position = Vector2(188.194, 100)
	box.rebuild([_block(12, 12)])
	print("墙 x∈[200,208] y∈[0,200]；箱 12x12，左下角在 position")
	_show("重叠 0.194：", wall, box, 2.0)
	box.position = Vector2(190.0, 100)
	_show("重叠 2.0：", wall, box, 2.0)
	box.position = Vector2(187.0, 100)
	_show("重叠 1.0：", wall, box, 2.0)
	box.position = Vector2(185.0, 100)
	_show("间隙 3.0：", wall, box, 2.0)
	box.position = Vector2(188.0, 100)
	box.rotation = 0.05
	box.refresh_com()
	_show("重叠+转0.05：", wall, box, 2.0)
	quit(0)
