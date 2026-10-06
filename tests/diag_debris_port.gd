extends SceneTree
## 甲方移植场景（mass=20 / speed=1 什么都没清）的复现与归因。
##
## 结论两条（都是实测）：
##   ① **静止的碎片 motion 恒为 0** —— 任何正的速度阈值都拦得住躺在地上的碎块
##      （speed = 1 / 0.5 / 0.1 / 0.01 / 0.001 全都没清）；
##   ② **质量 = 像素数 x 材质密度**，不是像素数 —— 同一个 4x4 碎片，
##      密度 2.5 下是质量 40、密度 7.8 下是 124.8。
const PWorld := preload("res://src/physics/pworld.gd")
const PBody := preload("res://src/physics/pbody.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

func _shape(w: int, h: int, mat := 1) -> PixelShape:
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, w, h), mat)
	return s

func _motion(b) -> float:
	return b.linear_velocity.length() + absf(b.angular_velocity) * b.bounding_radius()

## 造一个"落定的小碎片"，设阈值走一步，返回 [质量, 运动, 是否被清]
func _run(size: int, mat: int, mass: float, min_speed: float) -> Array:
	var w := PWorld.new()
	w.gravity = Vector2(0, 300)
	w.set_material_density(1, 2.5)
	w.set_material_density(3, 7.8)
	var g := PBody.new()
	g.make_static()
	w.add_body(g, [_shape(400, 40, 1)])
	var f := PBody.new()
	f.position = Vector2(100, -20)
	w.add_body(f, [_shape(size, size, mat)])
	for k in 200:
		w.step(1.0 / 60.0)              # 落定
	var m := f.mass
	var mot := _motion(f)
	w.debris_max_mass = mass
	w.debris_min_speed = min_speed
	w.step(1.0 / 60.0)
	return [m, mot, not w.bodies.has(f)]

func _initialize() -> void:
	print("=== 同一个世界里三种碎片，两种阈值组合（质量按密度算）===")
	print("  %-16s %6s %10s %10s %12s %12s" % ["碎片", "密度", "质量", "motion", "mass20/sp1", "mass20/sp0"])
	for spec in [[2, 1], [4, 1], [4, 3]]:
		var size: int = spec[0]
		var mat: int = spec[1]
		var dens := 2.5 if mat == 1 else 7.8
		var r1: Array = _run(size, mat, 20.0, 1.0)
		var r0: Array = _run(size, mat, 20.0, 0.0)
		print("  %-16s %6.1f %10.2f %10.4f %12s %12s" % [
			"%dx%d 材质%d" % [size, size, mat], dens, r1[0], r1[1],
			"已清" if r1[2] else "没清", "已清" if r0[2] else "没清"])
	print("")
	print("=== 4x4/材质3（质量 124.8）要多大的 mass 才清得掉？（speed = 0）===")
	for mass in [20.0, 100.0, 200.0]:
		var r: Array = _run(4, 3, mass, 0.0)
		print("  mass = %-6s（碎片质量 %7.2f）-> %s" % [
			str(mass), r[0], "已清" if r[2] else "**没清**"])
	print("")
	print("=== 默认关（mass = 0）时 speed = 0 也不许删 ===")
	var rc: Array = _run(2, 1, 0.0, 0.0)
	print("  mass = 0 / speed = 0（碎片质量 %7.2f）-> %s" % [rc[0], "已清" if rc[2] else "**没清**"])
	quit(0)
