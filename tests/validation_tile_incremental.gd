extends SceneTree
## 分块贴图**增量 patch** 的闸门：持久图必须与"从零重建"**逐位相同**。
##
## ⚠️ 为什么必须有：sync 现在只画"脏矩形 ∩ 本块"再 blit 进持久图
##    （sync 3.04 -> 0.36 ms/笔）。如果脏矩形没覆盖全部改动、或该走全量时走了增量，
##    持久图就会**静默**落后 —— 症状是"擦掉了画面上还在 / 图形缺一块"，
##    而物理是对的（用户报过同类 bug）。
##    所以参照物是**从零重建**（forget + sync），不是增量自己。
##
## 覆盖：内部擦除 / 边缘擦除（AABB 变）/ 绘制 / apply_damage /
##      touch()（未记录改动）/ 连续多笔 / 跨块边界的一笔

const AddonWorld := preload("res://src/nodes/pixel_world.gd")
const AddonBody := preload("res://src/nodes/pixel_body_2d.gd")
const AddonShape := preload("res://src/nodes/pixel_shape_2d.gd")
const Editor := preload("res://src/core/pixel_editor.gd")
const Destruction := preload("res://src/core/destruction.gd")

var passed := 0
var failed := 0

func _assert(cond: bool, msg: String) -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		if failed <= 8:
			print("  [失败] " + msg)

func _snapshot(r, body_id: int) -> Dictionary:
	var out := {}
	var tiles: Dictionary = r._tile_img.get(body_id, {})
	for key: Vector2i in tiles:
		var img: Image = tiles[key]
		out[key] = img.get_data()
	return out

## 增量结果 vs 从零重建
func _check(r, body, label: String) -> void:
	var inc := _snapshot(r, body.id)
	r.forget(body.id)
	r.sync(body)
	var full := _snapshot(r, body.id)
	_assert(inc.size() == full.size(), "%s：块数不同（增量 %d / 从零 %d）" % [label, inc.size(), full.size()])
	var bad := 0
	var first := ""
	for key: Vector2i in full:
		if not inc.has(key):
			bad += 1
			if first == "":
				first = str(key) + " 缺"
			continue
		if inc[key] != full[key]:
			bad += 1
			if first == "":
				first = str(key) + " 像素不同"
	_assert(bad == 0, "%s：增量贴图与从零重建不一致（%d 块，首例 %s）" % [label, bad, first])

func _initialize() -> void:
	print("=== 分块贴图增量 patch：vs 从零重建 ===")
	var pw = AddonWorld.new()
	var g = AddonBody.new()
	g.position = Vector2(0, 220)
	g.is_static = true
	pw.add_child(g)
	var gs = AddonShape.new()
	gs.rect_size = Vector2i(768, 100)
	g.add_child(gs)
	get_root().add_child(pw)
	await process_frame
	await process_frame
	pw.rebuild()
	var ground = null
	for b in pw.world.bodies:
		if b.is_static:
			ground = b
			break
	var r = pw.renderer
	r.sync(ground)
	_check(r, ground, "初始实心")
	var s = ground.shapes[0]
	# 内部擦除（主路径）
	for i in 5:
		Editor.erase(pw.world, Vector2(120.0 + i * 70.0, 270.0), Vector2(120.0 + i * 70.0, 271.0), 6.0, 25.0)
		r.sync(ground)
	_check(r, ground, "5 笔内部擦除")
	# 跨块边界的一笔（脏矩形横跨两个 64 块）
	Editor.erase(pw.world, Vector2(448.0, 270.0), Vector2(448.0, 271.0), 6.0, 25.0)
	r.sync(ground)
	_check(r, ground, "跨块边界")
	# 绘制（补回）
	s.fill_rect(Rect2i(100, 20, 20, 10), 1)
	s.touch()
	r.sync(ground)
	_check(r, ground, "fill_rect + touch")
	# 原生伤害
	Destruction.apply_damage(s, Destruction.Damage.circle(Vector2(200.0, 40.0), 9.0))
	s.mark_dirty_range(Rect2i(191, 31, 19, 19))
	r.sync(ground)
	_check(r, ground, "apply_damage + mark_dirty_range")
	# 边缘擦除 -> AABB 变 -> 必须走全量
	for i in 6:
		Editor.erase(pw.world, Vector2(30.0 + i * 120.0, 220.0), Vector2(30.0 + i * 120.0, 221.0), 8.0, 25.0)
		r.sync(ground)
	_check(r, ground, "边缘擦除（AABB 变）")
	# 只 touch()、不标脏（未记录改动 -> 必须全量）
	s.fill_rect(Rect2i(300, 30, 12, 8), 0)
	s.touch()
	r.sync(ground)
	_check(r, ground, "只 touch（未记录改动）")
	# 连续 12 笔不打断（模拟连挖）
	for i in 12:
		Editor.erase(pw.world, Vector2(500.0 + i * 18.0, 260.0), Vector2(500.0 + i * 18.0, 261.0), 5.0, 25.0)
		r.sync(ground)
	_check(r, ground, "连续 12 笔")
	print("---")
	print("最后块数 %d，矩形 %d" % [(_snapshot(r, ground.id) as Dictionary).size(), ground.rects.size()])
	if failed == 0:
		print("全部通过：%d 项断言" % passed)
	else:
		print("失败 %d / %d 项" % [failed, passed + failed])
	quit(0 if failed == 0 else 1)
