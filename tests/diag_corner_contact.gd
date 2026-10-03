extends SceneTree
## 角接触诊断：接触点在哪、力臂多大、方块倒不倒。
##
## 这个脚本是"坑 38"的常驻探针。背景：推测接触曾经**合成**一个接触点
## （切向重叠区间的中心），而地面比箱子宽得多时那个中心恒等于**箱子自己的形心** ——
## 角接触的力臂因此恒为 0，40° 的方块永远不倒。
##
## 用法：改完窄相/接触点相关的东西之后跑一遍，看三件事
##   1. 分离态的点是不是落在**真实角点**上；
##   2. 角接触的力臂是不是**非零**；
##   3. 40° 的方块会不会倒。
## 全部只读，不改任何公式。
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")
const Collide := preload("res://src/physics/collide.gd")

const DEG := PI / 180.0

func _block(w: int, h: int) -> PixelShape:
	var s := PixelShape.new()
	for y in h:
		for x in w:
			s.set_pixel(x, y, 1)
	return s

## 平地 + 24x24 方块转 angle_deg，sink > 0 表示压进地面
func _scene(angle_deg: float, sink: float) -> PWorld:
	var world := PWorld.new()
	world.contact_events_enabled = false
	var g := PBody.new()
	g.position = Vector2(-2000.0, 0.0)
	g.make_static()
	world.add_body(g, [_block(4000, 40)])
	var b := PBody.new()
	var th := angle_deg * DEG
	b.rotation = th
	b.position = Vector2(0.0, -24.0 * (sin(th) + cos(th)) + sink)
	world.add_body(b, [_block(24, 24)])
	return world

func _run(tag: String, angle_deg: float, sink: float, margin: float, steps: int) -> void:
	var w := _scene(angle_deg, sink)
	w.max_speculative_margin = margin
	var b: PBody = w.bodies[1]
	var turned := -1
	for i in steps:
		w.step(1.0 / 60.0)
		if turned < 0 and absf(rad_to_deg(b.rotation) - angle_deg) > 1.0:
			turned = i
	print("%-34s margin=%-4.1f 压进 %-4.1f | 第 %3d 步转超 1° | 终态 %8.3f° (转了 %7.3f°) awake=%s" % [
		tag, margin, sink, turned, rad_to_deg(b.rotation),
		rad_to_deg(b.rotation) - angle_deg, str(b.awake)])

## 分离态下，窄相把点放在哪？和真实角点 / 质心比一比
func _where() -> void:
	print("\n--- 分离态：窄相把点放在哪（24x24 方块 40°，悬在平地上方）---")
	var g := PBody.new()
	g.position = Vector2(-2000.0, 0.0)
	g.make_static()
	g.rebuild([_block(4000, 40)])
	var th := 40.0 * DEG
	var b := PBody.new()
	b.rotation = th
	b.position = Vector2(0.0, -24.0 * (sin(th) + cos(th)))
	b.rebuild([_block(24, 24)])
	var oa := Collide.obb_from_local_rect(g, g.rects[0])
	var com: Vector2 = b.com_world()
	var corner: Vector2 = b.to_world(Vector2(24, 24))
	print("  真实角点 x=%.4f | 质心 x=%.4f | 角点力臂=%.5f" % [
		corner.x, com.x, (corner - com).cross(Vector2(0.0, -1.0))])
	for gap in [0.2, 0.5, 1.0, 1.4]:
		var bb := PBody.new()
		bb.rotation = th
		bb.position = b.position - Vector2(0.0, gap)
		bb.rebuild([_block(24, 24)])
		var obb := Collide.obb_from_local_rect(bb, bb.rects[0])
		var sat := Collide.Sat.new()
		var res: Dictionary = Collide.collide(oa, obb, 1.5, sat)
		var pts: Array = res["points"]
		if pts.is_empty():
			print("  gap=%.2f  sep=%8.4f  无点" % [gap, sat.sep])
			continue
		var pos: Vector2 = pts[0]["position"]
		var lever: float = (pos - com).cross(res["normal"])
		print("  gap=%.2f  sep=%8.4f  点数=%d 点 x=%9.4f  力臂=%9.5f  %s" % [
			gap, sat.sep, pts.size(), pos.x, lever,
			"OK（落在角点上）" if absf(lever) > 1.0 else "**力臂为 0 —— 又合成了点？**"])

func _initialize() -> void:
	print("=== 角接触诊断 ===")
	_where()
	print("\n--- 倾倒实验（第 6 步左右开始倒 = 正常）---")
	_run("默认（角刚碰上）", 40.0, 0.0, 1.5, 120)
	_run("关掉推测接触", 40.0, 0.0, 0.0, 120)
	_run("边际很小", 40.0, 0.0, 0.3, 120)
	_run("初始压进 2px", 40.0, 2.0, 1.5, 120)
	quit(0)
