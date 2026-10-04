extends SceneTree
## 实验：feature id 里**有没有**"第几个矩形"这个信息？
## 做法：造一个由**两个分离矩形**组成的静态刚体（贪心分解会给 2 个 rect），
## 让同一个方块分别砸在左半和右半上，比较读到的 fid。
##   若 fid 不同 -> 它编码了子形状（矩形）索引 -> **精确相交面积可达**
##   若 fid 相同 -> 它只是"面/顶点"级别的特征 -> 精确面积还需要别的办法
const PWorld := preload("res://src/physics/pworld.gd")
const PBody := preload("res://src/physics/pbody.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

func _box(w: int, h: int, mat: int) -> PixelShape:
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, w, h), mat)
	return s

func _two_bars() -> PixelShape:
	var s := PixelShape.new()
	s.fill_rect(Rect2i(0, 0, 40, 8), 1)
	s.fill_rect(Rect2i(60, 0, 40, 8), 1)     # 两个分离的矩形
	return s

func _drop(x: float) -> Array:
	var w := PWorld.new()
	w.gravity = Vector2(0, 600)
	var ground := PBody.new()
	ground.position = Vector2(0, 100)
	ground.make_static()
	w.add_body(ground, [_two_bars()], Callable(), true)
	var box := PBody.new()
	box.position = Vector2(x, 84)
	w.add_body(box, [_box(16, 8, 2)], Callable(), true)
	w._rp_ensure()
	for i in 60:
		w.step(1.0 / 60.0)
		var pts: Array = w.contact_points(0)
		if not pts.is_empty():
			return [ground.rects.size(), pts[0]["fid1"], pts[0]["fid2"], pts[0]["position"].x]
	return [ground.rects.size(), -1, -1, 0.0]

func _initialize() -> void:
	var left := _drop(20.0)      # 砸在左半（x∈[0,40]）
	var right := _drop(80.0)     # 砸在右半（x∈[60,100]）
	print("地面矩形数 = %d" % left[0])
	print("砸左半：fid=(%d, %d) 接触点 x=%.2f" % [left[1], left[2], left[3]])
	print("砸右半：fid=(%d, %d) 接触点 x=%.2f" % [right[1], right[2], right[3]])
	if left[1] != right[1] or left[2] != right[2]:
		print("=> fid **随矩形变化** -> 它编码了子形状索引 -> 精确相交面积可达")
	else:
		print("=> fid 不变 -> 它只是面/顶点级特征 -> 精确面积需要另找办法")
	quit(0)
