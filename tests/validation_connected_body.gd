extends SceneTree
## "**每个实体内部连通**"这条不变量的闸门。
##
## ⚠️ 为什么要有它：引擎的破坏路径一直维持这条不变量，但游戏层直接造的多岛屿 shape
##    不受约束。以前它只会在"贴边界擦一下"时被 split 顺手拆开 —— 副作用，不可预期。
##    现在改成**建造时**保证：body 进世界时就拆干净。
##
## 这里钉三件事：
##   1. 多岛屿 body 进世界后被拆成多个 body，且**每个都单连通**
##   2. **像素一个都不许丢**（建造时丢像素 = 删内容）
##   3. 单连通 body 不受影响（不多出 body，像素不变）

const AddonWorld := preload("res://src/nodes/pixel_world.gd")
const Destruction := preload("res://src/core/destruction.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")
const PBody := preload("res://src/physics/pbody.gd")

var passed := 0
var failed := 0

func _assert(cond: bool, msg: String) -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		if failed <= 10:
			print("  [失败] " + msg)

func _total_pixels(pw) -> int:
	var n := 0
	for b in pw.world.bodies:
		for s in b.shapes:
			n += s.pixel_count()
	return n

func _islands(pw) -> Array:
	var out: Array = []
	for b in pw.world.bodies:
		for s in b.shapes:
			out.append(Destruction.components(s).size())
	return out

func _blob(s: PixelShape, x0: int, y0: int, w: int, h: int) -> void:
	for y in h:
		for x in w:
			s.set_pixel(x0 + x, y0 + y, 1)

func _mk_body(pos: Vector2) -> PBody:
	var b := PBody.new()
	b.position = pos
	b.is_static = true
	return b

func _initialize() -> void:
	print("=== 每个实体内部连通（建造时保证）===")
	# ① 两团不相连的料（相隔 8 像素）
	var pw = AddonWorld.new()
	get_root().add_child(pw)
	await process_frame
	var s1 := PixelShape.new()
	_blob(s1, 0, 0, 20, 20)
	_blob(s1, 28, 0, 20, 20)
	var before := s1.pixel_count()
	pw.world.add_body(_mk_body(Vector2(100, 100)), [s1])
	var isl := _islands(pw)
	print("  两团料 -> 刚体 %d，各体岛屿数 %s，像素 %d（原 %d）" % [pw.world.bodies.size(), str(isl), _total_pixels(pw), before])
	_assert(pw.world.bodies.size() == 2, "两团料应该拆成 2 个刚体，实际 %d" % pw.world.bodies.size())
	for n in isl:
		_assert(int(n) == 1, "拆出来的刚体必须单连通，实际有 %d 个岛屿" % n)
	_assert(_total_pixels(pw) == before, "像素丢了：%d -> %d" % [before, _total_pixels(pw)])
	# ② 三团料
	var pw2 = AddonWorld.new()
	get_root().add_child(pw2)
	await process_frame
	var s2 := PixelShape.new()
	_blob(s2, 0, 0, 10, 10)
	_blob(s2, 20, 0, 10, 10)
	_blob(s2, 40, 0, 10, 10)
	var before2 := s2.pixel_count()
	pw2.world.add_body(_mk_body(Vector2.ZERO), [s2])
	print("  三团料 -> 刚体 %d，各体岛屿数 %s，像素 %d（原 %d）" % [pw2.world.bodies.size(), str(_islands(pw2)), _total_pixels(pw2), before2])
	_assert(pw2.world.bodies.size() == 3, "三团料应该拆成 3 个刚体，实际 %d" % pw2.world.bodies.size())
	_assert(_total_pixels(pw2) == before2, "像素丢了：%d -> %d" % [before2, _total_pixels(pw2)])
	# ③ 单连通 body 不受影响
	var pw3 = AddonWorld.new()
	get_root().add_child(pw3)
	await process_frame
	var s3 := PixelShape.new()
	_blob(s3, 0, 0, 30, 30)
	var before3 := s3.pixel_count()
	pw3.world.add_body(_mk_body(Vector2.ZERO), [s3])
	print("  单连通 -> 刚体 %d，各体岛屿数 %s，像素 %d（原 %d）" % [pw3.world.bodies.size(), str(_islands(pw3)), _total_pixels(pw3), before3])
	_assert(pw3.world.bodies.size() == 1, "单连通 body 不该被拆，实际 %d 个刚体" % pw3.world.bodies.size())
	_assert(_total_pixels(pw3) == before3, "像素变了：%d -> %d" % [before3, _total_pixels(pw3)])
	# ④ 空 shape 不炸、不多体
	var pw4 = AddonWorld.new()
	get_root().add_child(pw4)
	await process_frame
	pw4.world.add_body(_mk_body(Vector2.ZERO), [PixelShape.new()])
	_assert(pw4.world.bodies.size() == 1, "空 shape 不该多出刚体")
	# ⑤ 破坏产生的碎片仍然单连通
	var pw5 = AddonWorld.new()
	get_root().add_child(pw5)
	await process_frame
	var s5 := PixelShape.new()
	_blob(s5, 0, 0, 200, 40)
	var b5 := _mk_body(Vector2.ZERO)
	pw5.world.add_body(b5, [s5])
	var spawned: Array = pw5.world.fracture(b5, Destruction.Damage.circle(Vector2(100.0, 20.0), 30.0))
	print("  一刀切开 -> 刚体 %d（碎片 %d）" % [pw5.world.bodies.size(), spawned.size()])
	for b in pw5.world.bodies:
		for s in b.shapes:
			_assert(Destruction.components(s).size() == 1, "破坏后仍有刚体是多岛屿的")
	print("---")
	if failed == 0:
		print("全部通过：%d 项断言" % passed)
	else:
		print("失败 %d / %d 项" % [failed, passed + failed])
	quit(0 if failed == 0 else 1)
