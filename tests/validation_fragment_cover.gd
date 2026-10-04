extends SceneTree
## **分片的矩形覆盖必须逐像素精确** —— 这是 8 条基准和像素覆盖闸门都漏掉的一角。
##
## ⚠️⚠️ 为什么需要它：validation_rect_shapes 测的是**独立形状**的分解，
##    而 split 产出的分片走的是另一条路（_assemble 里继承母体按块缓存 +
##    自建块 key 列表）。我在这里栽过一次：块 key 去重写成"相邻相同就跳过"
##    （错，chunk 迭代顺序不保证按块聚簇）-> 同一个块的矩形被 append 多次
##    -> 每片 380 个矩形里每个像素被覆盖 2 次 -> **碰撞体成对重叠**。
##    8 条基准逐位不变（它们不走 split），没有任何闸门报错。
##
## 所以这里对**破坏 + 分裂之后**的每一片，逐像素比对 rects 与形状：
##    phantom（有矩形盖住空像素）/ missing（占用像素没被盖）/ overlap（盖了多次）
## 三个都必须为 0。

const AddonWorld := preload("res://src/nodes/pixel_world.gd")
const Destruction := preload("res://src/core/destruction.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")
const PBody := preload("res://src/physics/pbody.gd")
const GreedyRects := preload("res://src/core/greedy_rects.gd")

var passed := 0
var failed := 0

func _assert(cond: bool, msg: String) -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		if failed <= 8:
			print("  [失败] " + msg)

## 逐像素比对：rects 是否精确覆盖 shape
func _cover(shape: PixelShape, rects: Array, label: String) -> void:
	var bb := Rect2i()
	var first := true
	for k: int in shape.chunks:
		var c = shape.chunks[k]
		if c.occ == 0:
			continue
		var r := Rect2i(PixelShape.key_x(k) << 3, PixelShape.key_y(k) << 3, 8, 8)
		bb = r if first else bb.merge(r)
		first = false
	if first:
		_assert(rects.is_empty(), "%s：空形状却有 %d 个矩形" % [label, rects.size()])
		return
	var w := bb.size.x
	var h := bb.size.y
	var m := PackedByteArray()
	m.resize(w * h)
	for r2: Rect2 in rects:
		var x0 := int(r2.position.x) - bb.position.x
		var y0 := int(r2.position.y) - bb.position.y
		for yy in int(r2.size.y):
			for xx in int(r2.size.x):
				m[(y0 + yy) * w + x0 + xx] += 1
	var phantom := 0
	var missing := 0
	var overlap := 0
	for k2: int in shape.chunks:
		var c2 = shape.chunks[k2]
		var bx2 := PixelShape.key_x(k2) << 3
		var by2 := PixelShape.key_y(k2) << 3
		for yy2 in 8:
			for xx2 in 8:
				var idx := (by2 + yy2 - bb.position.y) * w + (bx2 + xx2 - bb.position.x)
				var cnt := m[idx]
				var occ: bool = (c2.occ & (1 << (xx2 + (yy2 << 3)))) != 0
				if occ and cnt == 0:
					missing += 1
				elif not occ and cnt > 0:
					phantom += 1
				elif cnt > 1:
					overlap += 1
	_assert(phantom == 0 and missing == 0 and overlap == 0,
		"%s：覆盖不精确（phantom %d / missing %d / overlap %d，矩形 %d）" % [label, phantom, missing, overlap, rects.size()])

func _block(w: int, h: int, mat: int = 1) -> PixelShape:
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, w, h), mat)
	return s

func _case(src: PixelShape, dmg, label: String) -> void:
	var s := PixelShape.new()
	for k in src.chunks:
		s.chunks[k] = src.chunks[k].clone()
	Destruction.apply_damage(s, dmg)
	var parts: Array = Destruction.split(s, 1)
	for i in parts.size():
		var r = GreedyRects.decompose(parts[i], 64)
		_cover(parts[i], r.rects, "%s/片%d" % [label, i])

func _initialize() -> void:
	print("=== 分片矩形覆盖（逐像素精确）===")
	var big := _block(768, 100)
	_case(big, Destruction.Damage.circle(Vector2(384.0, 50.0), 60.0), "大物体-切断")
	_case(big, Destruction.Damage.circle(Vector2(100.0, 1.0), 5.0), "大物体-边界小洞")
	_case(big, Destruction.Damage.circle(Vector2(300.0, 50.0), 6.0), "大物体-内部洞")
	_case(big, Destruction.Damage.segment(Vector2(400.0, -5.0), Vector2(400.0, 105.0), 4.0), "大物体-竖切")
	var bar := _block(200, 4)
	_case(bar, Destruction.Damage.circle(Vector2(100.0, 2.0), 4.0), "细杆-切断")
	var comb := PixelShape.new()
	for y in 30:
		for x in 60:
			if (x / 10) % 2 == 0 or y < 4:
				comb.set_pixel(x, y, 1)
	_case(comb, Destruction.Damage.circle(Vector2(5.0, 29.0), 4.0), "梳子-齿根")
	_case(comb, Destruction.Damage.circle(Vector2(5.0, 1.0), 8.0), "梳子-横梁切断")
	# 经 fracture 的整条路（body 的 rects 也要精确）
	var pw = AddonWorld.new()
	get_root().add_child(pw)
	await process_frame
	var s3 := _block(400, 40)
	var b3 := PBody.new()
	b3.is_static = true
	pw.world.add_body(b3, [s3], Callable(), true)
	pw.world.fracture(b3, Destruction.Damage.circle(Vector2(200.0, 20.0), 30.0))
	for b in pw.world.bodies:
		for sh in b.shapes:
			var rr = GreedyRects.decompose(sh, 64)
			_cover(sh, rr.rects, "fracture 后 body 的形状")
	print("---")
	if failed == 0:
		print("全部通过：%d 项断言" % passed)
	else:
		print("失败 %d / %d 项" % [failed, passed + failed])
	quit(0 if failed == 0 else 1)
