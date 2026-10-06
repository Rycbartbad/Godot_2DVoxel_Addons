extends SceneTree
## ccd_ignore_mass 到底有没有用？以及它的代价（穿墙）到底有多真？
## ⚠️ 第三条用**甲方那条路**（pre_step + _substep_rapier），确认自己驱动子步时也生效。
const PWorld := preload("res://src/physics/pworld.gd")
const PBody := preload("res://src/physics/pbody.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

func _shape(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, w, h), 1)
	return s

func _world_with_fast_heavy() -> Array:
	var w := PWorld.new()
	w.gravity = Vector2.ZERO
	var g := PBody.new()
	g.make_static()
	w.add_body(g, [_shape(400, 40)])
	var f := PBody.new()
	f.position = Vector2(-150, 100)          # 在方块上方飞（不碰地面）
	w.add_body(f, [_shape(10, 10)])          # 质量 100
	f.linear_velocity = Vector2(30000, 0)
	return [w, f]

func _initialize() -> void:
	print("=== ① 同一个快速重块：豁免前 / 后 ===")
	for ignore in [0.0, 200.0]:
		var sc := _world_with_fast_heavy()
		var w: PWorld = sc[0]
		var f: PBody = sc[1]
		w.ccd_ignore_mass = ignore
		w.step(1.0 / 60.0)
		print("  ccd_ignore_mass = %-6s（方块质量 %.0f）-> 子步 %3d" % [
			str(ignore), f.mass, w.last_substeps])

	print("")
	print("=== ② 豁免的代价：会不会**穿过**薄墙？===")
	for ignore in [0.0, 200.0]:
		var w2 := PWorld.new()
		w2.gravity = Vector2.ZERO
		var wall := PBody.new()
		wall.position = Vector2(0, 0)
		wall.make_static()
		w2.add_body(wall, [_shape(4, 200)])       # 4 像素厚的墙
		var f2 := PBody.new()
		f2.position = Vector2(-60, 0)
		w2.add_body(f2, [_shape(10, 10)])
		f2.linear_velocity = Vector2(3000, 0)     # 每步 50 px，墙只有 4 px 厚
		w2.ccd_ignore_mass = ignore
		for k in 30:
			w2.step(1.0 / 60.0)
		var passed: bool = f2.position.x > 20.0
		print("  ccd_ignore_mass = %-6s -> 30 步后 x = %8.1f  %s（子步 %d）" % [
			str(ignore), f2.position.x, "**穿过去了**" if passed else "被墙挡住", w2.last_substeps])

	print("")
	print("=== ③ 甲方那条路（pre_step + _substep_rapier）里也生效吗 ===")
	for ignore in [0.0, 200.0]:
		var sc3 := _world_with_fast_heavy()
		var w3: PWorld = sc3[0]
		w3.ccd_ignore_mass = ignore
		var n: int = w3.pre_step(1.0 / 60.0)
		for i in n:
			w3._substep_rapier(1.0 / 60.0 / float(n))
		print("  ccd_ignore_mass = %-6s -> pre_step 返回 %3d 子步" % [str(ignore), n])
	quit(0)
