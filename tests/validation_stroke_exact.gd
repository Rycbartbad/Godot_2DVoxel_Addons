extends SceneTree
## 笔触形状的**精确**验证：走 Demo 真正用的那条路径（Editor.paint_canvas），
## 把画出来的世界像素集合与"无裁剪参照物"做**双向差集**。
##
## 为什么必须用差集：开发日志坑 6 的教训 —— 用"集合大小/连通块数"验证，
## 重复像素会被 Dictionary 去重，一笔被画了 4 遍也照样通过。
##
## 覆盖面：跨瓦片、瓦片边界起笔、负坐标、对角线、非整数坐标、半径 1..40。
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")
const Brush := preload("res://src/core/brush.gd")
const Editor := preload("res://src/core/pixel_editor.gd")

const TILE := 64

var _pass := 0
var _fail := 0

func _check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		_pass += 1
		print("  PASS  ", name, "  ", detail)
	else:
		_fail += 1
		print("  FAIL  ", name, "  ", detail)

## 参照物：在一块**无限大**的 Shape 上落同一笔（不裁剪）
func _reference(from: Vector2, to: Vector2, r: float) -> Dictionary:
	var s := PixelShape.new()
	Brush.stroke_circle(s, from, to, r, 1)
	return _pixels_of_shape(s, Vector2.ZERO)

func _pixels_of_shape(s: PixelShape, origin: Vector2) -> Dictionary:
	var d := {}
	for k: int in s.chunks:
		var c = s.chunks[k]
		var bx := PixelShape.key_x(k) << 3
		var by := PixelShape.key_y(k) << 3
		for i in 64:
			if (c.occ & (1 << i)) == 0:
				continue
			var px := bx + (i & 7)
			var py := by + (i >> 3)
			d[Vector2i(int(floor(origin.x)) + px, int(floor(origin.y)) + py)] = true
	return d

## 实际：走 Demo 的路径（可能横跨多块画布瓦片）
func _actual(from: Vector2, to: Vector2, r: float) -> Array:
	var world := PWorld.new()
	var tiles := {}
	var touched: Array = Editor.paint_canvas(world, tiles, from, to, r, 1, TILE)
	var d := {}
	for b: PBody in touched:
		var sub := _pixels_of_shape(b.shapes[0], b.position)
		for k in sub:
			d[k] = true
	return [d, touched.size()]

func _case(label: String, from: Vector2, to: Vector2, r: float) -> void:
	var ref := _reference(from, to, r)
	var act := _actual(from, to, r)
	var got: Dictionary = act[0]
	var missing := 0
	var extra := 0
	for k in ref:
		if not got.has(k):
			missing += 1
	for k2 in got:
		if not ref.has(k2):
			extra += 1
	_check(label, missing == 0 and extra == 0,
		"参照 %d 实际 %d | 缺 %d 多 %d | 瓦片 %d" % [ref.size(), got.size(), missing, extra, act[1]])

## 量一笔的"厚度"：沿笔画走向的垂直方向上有多少像素
func _measure_thickness(from: Vector2, to: Vector2, r: float) -> int:
	var act := _actual(from, to, r)
	var got: Dictionary = act[0]
	# 水平笔画：取若干 x 列，数该列上的像素个数
	var cols := {}
	for k: Vector2i in got:
		cols[k.x] = cols.get(k.x, 0) + 1
	var best := 0
	for x in cols:
		best = maxi(best, cols[x])
	return best

func _initialize() -> void:
	print("=== 笔触精确性（Demo 路径 Editor.paint_canvas vs 无裁剪参照）===")
	print("[A] 跨瓦片 / 边界 / 负坐标 / 对角线")
	_case("整数短笔 r=6", Vector2(10, 20), Vector2(30, 20), 6.0)
	_case("跨瓦片边界 r=6", Vector2(50, 30), Vector2(80, 30), 6.0)
	_case("正好压在边界上 r=6", Vector2(60, 30), Vector2(68, 30), 6.0)
	_case("长笔跨 3 块 r=6", Vector2(10, 30), Vector2(200, 30), 6.0)
	_case("负坐标 r=6", Vector2(-40, -30), Vector2(-10, -10), 6.0)
	_case("非整数坐标 r=6", Vector2(50.3, 30.7), Vector2(80.9, 31.2), 6.0)
	_case("对角笔 r=6", Vector2(20, 20), Vector2(140, 120), 6.0)
	_case("对角线跨瓦片 r=12", Vector2(30, 30), Vector2(150, 130), 12.0)
	_case("细笔 r=1 跨瓦片", Vector2(50, 30), Vector2(90, 30), 1.0)
	_case("大笔 r=40", Vector2(100, 100), Vector2(120, 100), 40.0)

	print("[B] 笔触厚度（应为 2r 或 2r+1）")
	for spec in [[1, 1.0], [2, 2.0], [6, 6.0], [10, 10.0], [20, 20.0], [40, 40.0]]:
		var r: float = spec[1]
		var th := _measure_thickness(Vector2(100, 100), Vector2(190, 100), r)
		var expect := int(ceil(2.0 * r))
		_check("半径 %.0f 的笔触厚度" % r, th >= expect - 1 and th <= expect + 1,
			"实测 %d, 期望约 %d" % [th, expect])

	print("=== %d passed, %d failed ===" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
