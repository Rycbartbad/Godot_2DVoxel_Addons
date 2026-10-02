extends SceneTree
## 复现「变细 / 断触」：按 Demo 真实的方式**逐帧分段**落笔，然后沿笔画量每列的厚度。
##
## 之前的 validation_stroke_exact 只验了"一笔"，而 Demo 是每帧调一次
## _paint(_last_paint, mouse)，所以真正要验的是"多段拼起来是否仍然连续、等宽"。
const PBody := preload("res://src/physics/pbody.gd")
const PWorld := preload("res://src/physics/pworld.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")
const Brush := preload("res://src/core/brush.gd")
const Editor := preload("res://src/core/pixel_editor.gd")

const TILE := 64

var _fail := 0

func _world_pixels(world: PWorld) -> Dictionary:
	var d := {}
	for b: PBody in world.bodies:
		for s: PixelShape in b.shapes:
			for k: int in s.chunks:
				var c = s.chunks[k]
				var bx := (PixelShape.key_x(k) << 3) + int(floor(b.position.x))
				var by := (PixelShape.key_y(k) << 3) + int(floor(b.position.y))
				for i in 64:
					if (c.occ & (1 << i)) == 0:
						continue
					d[Vector2i(bx + (i & 7), by + (i >> 3))] = true
	return d

## 模拟一次拖动：从 (x0,y) 拖到 (x1,y)，共 frames 帧，每帧一段。
## 同时累计被瓦片阀门丢掉的瓦片数（必须为 0，否则笔画会被截断）。
var _drops := 0

func _drag(radius: float, x0: float, x1: float, y: float, frames: int) -> Dictionary:
	var world := PWorld.new()
	var tiles := {}
	var last := Vector2(x0, y)
	_drops = 0
	for f in range(1, frames + 1):
		var cur := Vector2(x0 + (x1 - x0) * float(f) / float(frames), y)
		Editor.paint_canvas(world, tiles, last, cur, radius, 1, TILE)
		_drops += Editor.last_dropped_tiles
		last = cur
	return _world_pixels(world)

## 沿 x 量每列的厚度，返回 [最小厚度(仅统计笔画应覆盖的列), 断列数, 应覆盖列数]
func _profile(pix: Dictionary, x0: int, x1: int, y: float, radius: int) -> Array:
	var min_t := 1 << 30
	var gaps := 0
	var covered := 0
	for x in range(x0 + radius, x1 - radius + 1):
		var cnt := 0
		for k: Vector2i in pix:
			if k.x == x:
				cnt += 1
		covered += 1
		if cnt == 0:
			gaps += 1
		else:
			min_t = mini(min_t, cnt)
	return [min_t if min_t < (1 << 30) else 0, gaps, covered]

func _run(label: String, radius: float, frames: int, span: float) -> void:
	var y := 100.0
	var pix := _drag(radius, 0.0, span, y, frames)
	var p := _profile(pix, 0, int(span), y, int(radius))
	var expect := int(2.0 * radius)
	var per_frame := span / float(frames)
	var gaps: int = p[1]
	var thin: int = p[0]
	var ok: bool = gaps == 0 and thin >= expect - 1 and _drops == 0
	if not ok:
		_fail += 1
	print("  %-34s 半径%-3.0f %5.1f px/帧 | 应覆盖 %4d 列 | 断列 %4d | 丢瓦片 %3d | 最薄 %3d (期望 ≥%d)  %s" % [
		label, radius, per_frame, p[2], p[1], _drops, thin, expect - 1, "OK" if ok else "<<< 有问题"])

func _initialize() -> void:
	print("=== 拖动笔触连续性（按 Demo 逐帧分段落笔复现）===")
	print("-- 正常速度（每帧 5 px）--")
	for r in [1.0, 6.0, 20.0, 40.0]:
		_run("正常拖动", r, 80, 400.0)
	print("-- 快速拖动（每帧 40 px，约 2400 px/s）--")
	for r in [1.0, 6.0, 20.0, 40.0]:
		_run("快速拖动", r, 10, 400.0)
	print("-- 掉帧时的甩动（每帧 200 px）--")
	for r in [1.0, 6.0, 20.0, 40.0]:
		_run("掉帧甩动", r, 2, 400.0)
	print("-- 极端：一整段 800 px（跨 13 块瓦片）--")
	for r in [1.0, 6.0, 20.0, 40.0]:
		_run("单帧超长段", r, 1, 800.0)
	print("=== 失败 %d 项 ===" % _fail)
	quit(1 if _fail > 0 else 0)
