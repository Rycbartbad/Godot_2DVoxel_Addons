extends SceneTree
## 原生连通分量标注（PixelRaster op 3）vs GDScript 参照实现的**逐位对拍**闸门。
##
## ⚠️ 为什么必须有这一条："哪些体素属于同一个连通体"这条规则现在写了**两份** ——
##    gdext/fastphys.cpp 的 op 3，与 src/core/destruction.gd 的
##    _components_cpu + _group + components。本仓库在"同一规则写两处"上栽过太多次，
##    所以原生化必须配一条**逐位**判据，不是"看起来一样"。
##
## ⚠️⚠️ **顺序也是判据**：分组的顺序（= 节点首次出现的顺序）和组内块的顺序
##    会原样进入 Rapier 的碰撞体顺序。这里逐组、逐块、逐掩码比对**下标**。
##
## 判据三条，缺一不可：
##   ① 分组数、每组的块数、每块的位置与掩码**全部逐位相同**；
##   ② 它和 split() 用的是同一份计算（这里顺带对拍 _group 的输入结构一致性）；
##   ③ **原生那条真的被走了**（native_calls / native_fallbacks 计数）——
##      否则"退回了 GDScript"会让本闸门静默变成同义反复（结果当然一样）。
const PixelShape := preload("res://src/core/pixel_shape.gd")
const ShapeOps := preload("res://src/core/shape_ops.gd")
const Destruction := preload("res://src/core/destruction.gd")
const PixelChunk := preload("res://src/core/pixel_chunk.gd")

var _pass := 0
var _fail := 0
var _cases := 0
var _pairs := 0
var _rng := RandomNumberGenerator.new()


func _c(n: String, ok: bool, d: String = "") -> void:
	if ok:
		_pass += 1
		print("  PASS  ", n, "  ", d)
	else:
		_fail += 1
		print("  FAIL  ", n, "  ", d)


## ⚠️ 0x8080808080808080 / 0xFF00000000000000 这类字面量在 GDScript 里**写不出来**
##    （超 int64 上限），只能靠移位构造 —— 见 pixel_bits.gd 文件头的同一条说明。
##    第一版闸门直接写了字面量，整个脚本 parse error，一条断言都没跑到。
func _col(x: int) -> int:
	return 0xFF << x


func _row(y: int) -> int:
	return 0xFF << (y << 3)


## 造形状：patterns = { Vector2i(cx, cy): occ }。直接写 chunk.occ，
## 这样能造出"满块 / 棋盘 / 空块 / 多分量块"这些 set_pixel 很难造的病态输入。
func _mk(patterns: Dictionary) -> PixelShape:
	var s: PixelShape = ShapeOps.create()
	for pos: Vector2i in patterns:
		var c: PixelChunk = s.chunk_or_create(pos.x, pos.y)
		c.occ = patterns[pos]
	s.revision += 1
	return s


func _total_pairs(g: Dictionary) -> int:
	var n := 0
	for gi in g:
		n += (g[gi] as Dictionary).size()
	return n


## 逐组、逐块、逐掩码比较，**下标也是判据**。返回 "" 表示相同。
func _diff_groups(a: Dictionary, b: Dictionary) -> String:
	if a.size() != b.size():
		return "分组数 %d != %d" % [a.size(), b.size()]
	for gi in a.size():
		var ga: Dictionary = a[gi]
		var gb: Dictionary = b[gi]
		if ga.size() != gb.size():
			return "第 %d 组块数 %d != %d" % [gi, ga.size(), gb.size()]
		var ka: Array = ga.keys()
		var kb: Array = gb.keys()
		for j in ka.size():
			if ka[j] != kb[j]:
				return "第 %d 组第 %d 个块 key %d != %d" % [gi, j, ka[j], kb[j]]
			if int(ga[ka[j]]) != int(gb[kb[j]]):
				return "第 %d 组块 %d 掩码 %d != %d" % [gi, ka[j], int(ga[ka[j]]), int(gb[kb[j]])]
	return ""


## 跑一个用例：原生一次、参照实现一次，逐位对拍。
func _check(name: String, s: PixelShape) -> void:
	_cases += 1
	# ① 原生（重新打开懒加载，确保 _ensure_raster 真的会去找扩展）
	Destruction._raster = null
	Destruction._raster_checked = false
	var before := Destruction.native_calls
	var nat = Destruction.components(s)
	var used := Destruction.native_calls - before
	# ② 参照实现：把原生关掉（_raster_checked = true 时 _ensure_raster 直接返回 null）
	var keep = Destruction._raster
	Destruction._raster = null
	Destruction._raster_checked = true
	var gd = Destruction.components(s)
	Destruction._raster = keep
	Destruction._raster_checked = false
	var d := _diff_groups(nat, gd)
	_pairs += _total_pairs(gd)
	_c(name, d == "", d if d != "" else "分组 %d / 块 %d" % [nat.size(), _total_pairs(nat)])
	_c(name + " · 真的走了原生", used > 0, "native_calls +%d" % used)


func _initialize() -> void:
	_rng.seed = 20261012
	print("=== 原生连通分量标注 vs GDScript 参照实现 ===")
	# ① 单块：满块 / 半块 / 空块 / 棋盘
	_check("单块·满", _mk({Vector2i(0, 0): -1}))
	_check("单块·半块", _mk({Vector2i(0, 0): 0x00000000FFFFFFFF}))
	_check("单块·空 occ=0", _mk({Vector2i(0, 0): 0}))
	var checker := 0
	for y in 8:
		for x in 8:
			if (x + y) % 2 == 0:
				checker |= 1 << (x + (y << 3))
	_check("单块·棋盘（块内 32 个分量）", _mk({Vector2i(0, 0): checker}))
	# ② 接缝：水平相邻 / 垂直相邻 / 对角（**对角不算连通**）
	_check("横接缝·两半块连上", _mk({Vector2i(0, 0): _col(7), Vector2i(1, 0): _col(0)}))
	_check("横接缝·错开不连", _mk({Vector2i(0, 0): _col(7), Vector2i(1, 0): _col(1)}))
	_check("竖接缝·连上", _mk({Vector2i(0, 0): _row(0), Vector2i(0, 1): _row(7)}))
	_check("竖接缝·错开不连", _mk({Vector2i(0, 0): _row(0), Vector2i(0, 1): _row(1)}))
	_check("对角·不算连通", _mk({Vector2i(0, 0): 1 << 7, Vector2i(1, 1): 1}))
	# ③ 多分量 + 接缝（走 _mask_index 那条慢路径）
	var two := 0
	for y in 8:
		two |= 1 << (0 + (y << 3))
		two |= 1 << (7 + (y << 3))
	_check("一块两分量 + 两侧接缝", _mk({
		Vector2i(0, 0): two, Vector2i(1, 0): _col(0), Vector2i(-1, 0): _col(7)}))
	# ④ 负坐标（key 的高 32 位是负数）
	_check("负块坐标", _mk({Vector2i(-3, -2): -1, Vector2i(-2, -2): 0x0101010101010101}))
	# ⑤ 随机形状（含空块、满块、稀疏块）
	for t in 12:
		var pat := {}
		var nx := _rng.randi_range(1, 6)
		var ny := _rng.randi_range(1, 6)
		var ox := _rng.randi_range(-4, 4)
		var oy := _rng.randi_range(-4, 4)
		for cx in nx:
			for cy in ny:
				var roll := _rng.randf()
				if roll < 0.15:
					continue                      # 整个块不建（缺块）
				if roll < 0.35:
					pat[Vector2i(ox + cx, oy + cy)] = -1
				elif roll < 0.5:
					pat[Vector2i(ox + cx, oy + cy)] = 0
				else:
					var v := 0
					for i in 64:
						if _rng.randf() < 0.45:
							v |= 1 << i
					pat[Vector2i(ox + cx, oy + cy)] = v
		if pat.is_empty():
			continue
		_check("随机 #%d（%d 块）" % [t, pat.size()], _mk(pat))
	# ⑥ 大形状：真实规模 + 计时（768x100 = 12x96 个块）
	var big := {}
	for cx in 12:
		for cy in 96:
			big[Vector2i(cx, cy)] = -1
	var bs := _mk(big)
	Destruction._raster = null
	Destruction._raster_checked = false
	var t0 := Time.get_ticks_usec()
	var bn = Destruction.components(bs)
	var t1 := Time.get_ticks_usec()
	Destruction._raster = null
	Destruction._raster_checked = true
	var t2 := Time.get_ticks_usec()
	var bg = Destruction.components(bs)
	var t3 := Time.get_ticks_usec()
	Destruction._raster = null
	Destruction._raster_checked = false
	var bd := _diff_groups(bn, bg)
	_c("768x100 满实心·逐位相同", bd == "", bd)
	print("  原生 %.3f ms   参照实现 %.3f ms（%d 块）" % [
		(t1 - t0) / 1000.0, (t3 - t2) / 1000.0, big.size()])
	# ⑦ ShapeOps.component_map 也走同一条路
	var cm := ShapeOps.component_map(bs)
	_c("component_map 一致性（块数）", (cm["chunks"] as Dictionary).size() == 12 * 96,
			"count=%d chunks=%d" % [cm["count"], (cm["chunks"] as Dictionary).size()])
	# ⑧ 回退路径真的能跑（把原生关掉时不许崩、不许静默算错）
	_c("回退计数", Destruction.native_fallbacks == 0, "fallbacks=%d" % Destruction.native_fallbacks)
	print("")
	print("=== %d passed, %d failed  （%d 个用例 / %d 个块记录 / native_calls=%d）===" % [
		_pass, _fail, _cases, _pairs, Destruction.native_calls])
	quit(1 if _fail > 0 else 0)

