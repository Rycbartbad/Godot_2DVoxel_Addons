extends RefCounted
## 破坏管线：破坏形状 -> 掩码 -> 应用 -> 连通性分片。
##
## 与参考实现（VoxelEngineExperiments）的对应关系：
##   DestructionShapeChunkOverlapJob -> 这里直接按 AABB 逐 chunk 求交
##   DestructionMaskGenerationJob   -> make_keep_mask()
##   ShapeVoxelRemovePackJob         -> 同一目标 chunk 的掩码按位与合并（吸收上游的"未来优化"）
##   ShapeVoxelRemoveJob             -> PixelChunk.apply_keep_mask()
##   ShapeChunkFragmentJob           -> Bits.flood() 逐分量泛洪
##   ShapeChunkCheckMaskJob + ConnectivityJob -> 交界列/行按位与
##   ShapeFragmentUnionJob           -> union-find
##   ShapeBuildJob                   -> 组装新 Shape

const Bits := preload("res://src/core/pixel_bits.gd")
const PixelChunk := preload("res://src/core/pixel_chunk.gd")
const PixelShape := preload("res://src/core/pixel_shape.gd")

## 破坏源类型
enum Kind { CIRCLE, SEGMENT, RECT }

## 一个破坏源。坐标是"目标 Shape 本地像素空间"。
class Damage:
	var kind: int = Kind.CIRCLE
	var a: Vector2 = Vector2.ZERO
	var b: Vector2 = Vector2.ZERO
	var radius: float = 4.0
	var half: Vector2 = Vector2.ONE
	var material_delta: int = 0

	static func circle(center: Vector2, r: float) -> Damage:
		var d := Damage.new()
		d.kind = Kind.CIRCLE
		d.a = center
		d.radius = r
		return d

	static func segment(from: Vector2, to: Vector2, r: float) -> Damage:
		var d := Damage.new()
		d.kind = Kind.SEGMENT
		d.a = from
		d.b = to
		d.radius = r
		return d

	static func rect(center: Vector2, half_size: Vector2) -> Damage:
		var d := Damage.new()
		d.kind = Kind.RECT
		d.a = center
		d.half = half_size
		return d

	func bounds() -> Rect2:
		match kind:
			Kind.CIRCLE:
				return Rect2(a - Vector2(radius, radius), Vector2(radius, radius) * 2.0)
			Kind.SEGMENT:
				var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2(radius, radius)
				var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2(radius, radius)
				return Rect2(lo, hi - lo)
			_:
				return Rect2(a - half, half * 2.0)

	func hits(px: float, py: float) -> bool:
		## px/py 是像素中心（+.5 已在调用侧加好）。
		match kind:
			Kind.CIRCLE:
				var dx := px - a.x
				var dy := py - a.y
				return dx * dx + dy * dy <= radius * radius
			Kind.SEGMENT:
				var ab := b - a
				var len2 := ab.length_squared()
				var t := 0.0
				if len2 > 0.000001:
					t = clampf(((Vector2(px, py) - a).dot(ab)) / len2, 0.0, 1.0)
				return (Vector2(px, py) - (a + ab * t)).length_squared() <= radius * radius
			_:
				return absf(px - a.x) <= half.x and absf(py - a.y) <= half.y


## 生成一个 chunk 的 keep 掩码（bit 1 = 保留，bit 0 = 删除）。
static func make_keep_mask(chunk_key: int, damage: Damage, force_keep: int = 0) -> int:
	var keep := 0
	var bx := PixelShape.key_x(chunk_key) << 3
	var by := PixelShape.key_y(chunk_key) << 3
	for y in 8:
		for x in 8:
			var bit := 1 << (x + (y << 3))
			if (force_keep & bit) != 0:
				keep |= bit
				continue
			if not damage.hits(bx + x + 0.5, by + y + 0.5):
				keep |= bit
	return keep


## 对整个 Shape 应用一个破坏源。返回被删除的像素数。
## 采用"每个目标 chunk 只产生一条最终 keep 掩码"的合并策略。
static func apply_damage(shape: PixelShape, damage: Damage) -> int:
	var bounds := damage.bounds()
	var cx0 := int(floor(bounds.position.x / 8.0))
	var cy0 := int(floor(bounds.position.y / 8.0))
	var cx1 := int(floor((bounds.end.x - 0.0001) / 8.0))
	var cy1 := int(floor((bounds.end.y - 0.0001) / 8.0))
	var removed := 0
	for cy in range(cy0, cy1 + 1):
		for cx in range(cx0, cx1 + 1):
			var k := PixelShape.make_key(cx, cy)
			var c: PixelChunk = shape.chunks.get(k)
			if c == null or c.occ == 0:
				continue
			var keep := make_keep_mask(k, damage, ~c.occ)
			var before := c.count()
			c.apply_keep_mask(keep)
			removed += before - c.count()
			if c.is_empty():
				shape.chunks.erase(k)
	return removed


## 连通性分片：把 Shape 拆成若干 4 邻域连通的子 Shape。
## 返回 Array[PixelShape]，每个都已剔除空 chunk。
## min_pixels 以下的分量直接丢弃（Teardown 里小碎块会消失）。
## 伤害是否**碰到形状边界 ∂S**。
##
## ⚠️ 这是一个**可证明成立**的"不可能断开"判据：
##    对**凸**的伤害集 R（圆 / 线段 / 矩形都是凸的），
##    若 R 严格在形状 S 内部（R ∩ ∂S = ∅），则 S\R 必然仍连通。
##    直观：S\R 若被分成两块，R 就得是一条"割"，
##    而凸集要成为割必须触及边界。（环形管子里放一个凸块，S\R 仍连通。）
##
## ⚠️⚠️ 判据是"**碰到边界**"，**不是**"包围盒离边界有余量"。
##    后者是错的：细杆在中间被擦断时，包围盒离形状外边界很远，
##    但它确实断开了 —— 那种情况下被擦的像素**贴着杆的边界**。
##
## 为什么值得做：split 要跑全量连通分量标记（768x100 = 1248 个 chunk，
## 实测 **31 ms**），而绝大多数笔画都是内部挖洞 —— 这一条能省掉它们。
static func touches_boundary(shape: PixelShape, rect: Rect2i) -> bool:
	var y0: int = rect.position.y
	var x0: int = rect.position.x
	# ⚠️⚠️ 八邻域**内联**判断，不要调 shape.neighbors() ——
	#    那个函数每次都**分配一个 Array**（8 个 Vector2i），
	#    而这里对 40x40 的探测框要跑 1600 次，实测 **5.4 ms**。
	#    内联之后只是一串 get_pixel，没有分配。
	#
	#    这一条本身是"花 5.4 ms 去省一次 33 ms 的 split"，净赚；
	#    但 5.4 ms 太贵了 —— 它出现在**每一笔**擦除里。
	# ⚠️⚠️ **整块跳过**：一个 occ 全满、且八邻域也全满的 chunk，
	#    它里面的任何像素都不可能邻接空像素 -> 不可能是边界像素 -> 整块跳过。
	#
	#    为什么需要：上面那个逐像素版本对 28x28 的探测框要跑 784 x 9 次
	#    get_pixel，实测 **4.7 ms**，而且**每一笔擦除都要付**。
	#    实心地面的大多数 chunk 都是全满的，跳过它们之后只剩边缘那一圈。
	#
	#    判据是**可靠**的（不是启发式）：全满块 + 八邻域全满 =>
	#    块内每个像素的八邻域都在占用集合内 => 没有边界像素。
	#    反过来，任何一块不满（或邻域有缺口）就退回逐像素查 —— 宁可多查，不能漏。
	#
	#    形状最外圈的 chunk 一定不满足（邻域缺失），所以外边界照常能查到。
	var FULL := -1
	var cx0 := x0 >> 3
	var cy0 := y0 >> 3
	var cx1 := (x0 + rect.size.x - 1) >> 3
	var cy1 := (y0 + rect.size.y - 1) >> 3
	for cy in range(cy0, cy1 + 1):
		for cx in range(cx0, cx1 + 1):
			var c: PixelChunk = shape.chunks.get(PixelShape.make_key(cx, cy))
			if c == null or c.occ == 0:
				continue                       # 整块空，本块内没有占用像素
			if c.occ == FULL:
				var solid := true
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						if dx == 0 and dy == 0:
							continue
						var n: PixelChunk = shape.chunks.get(
							PixelShape.make_key(cx + dx, cy + dy))
						if n == null or n.occ != FULL:
							solid = false
							break
					if not solid:
						break
				if solid:
					continue                   # 全满且邻域全满 -> 不可能有边界像素
			# 本块内逐像素查（只查这一块，不是整个探测框）
			var px0 := maxi(x0, cx << 3)
			var py0 := maxi(y0, cy << 3)
			var px1 := mini(x0 + rect.size.x, (cx << 3) + 8)
			var py1 := mini(y0 + rect.size.y, (cy << 3) + 8)
			for y in range(py0, py1):
				for x in range(px0, px1):
					if shape.get_pixel(x, y) == 0:
						continue
					if shape.get_pixel(x - 1, y) == 0 or shape.get_pixel(x + 1, y) == 0 							or shape.get_pixel(x, y - 1) == 0 or shape.get_pixel(x, y + 1) == 0 							or shape.get_pixel(x - 1, y - 1) == 0 or shape.get_pixel(x + 1, y - 1) == 0 							or shape.get_pixel(x - 1, y + 1) == 0 or shape.get_pixel(x + 1, y + 1) == 0:
						return true
	return false


static func split(shape: PixelShape, min_pixels: int = 1) -> Array:
	var keys: Array = shape.chunks.keys()
	if keys.is_empty():
		return []
	var parts := _components_cpu(shape, keys)
	return _assemble(shape, keys, parts, min_pixels)


## ---------- GPU 加速路径 ----------
## 一次 dispatch 同时算出"破坏后的占用"和"每个 chunk 的分量掩码"，
## 回读后复用与 CPU 完全相同的接缝归并 / 组装代码。
## 返回 {"removed": int, "parts": Array}；返回空字典表示应退回 CPU
## （设备不可用 / 规模太小 / 分量溢出）。
static func apply_damage_and_split_gpu(shape: PixelShape, damage: Damage, min_pixels: int = 1, force: bool = false) -> Dictionary:
	# ⚠️⚠️ **先判开关，再取后端。**
	#
	#    gpu_backend() 第一次调用会建 RenderingDevice 后端 + 编译 compute pipeline，
	#    实测 **5.5 ms**（带窗口时是 126 ms）—— 然后才发现 GPU 破坏路径是关的
	#    （gpu_destruction.gd: const ENABLED := false），白做一场。
	#
	#    后果不只是慢：这 5.5 ms 只出现在**第一笔**上，之后每一笔只要 0.12 ms。
	#    于是第一笔和其余各笔的手感不一样 —— 用户说的"影响擦除手感"。
	#    这就是"预热"要解决的东西：**把一次性成本从热路径上挪走**。
	#
	#    force=true 是显式要求（测试会用），那种情况仍然走完整流程。
	if not force and not _gpu_enabled():
		return {}
	var keys: Array = shape.chunks.keys()
	if keys.is_empty():
		return {}
	var gpu = gpu_backend()
	if gpu == null or not gpu.available:
		return {}
	var n := keys.size()
	if not force and not gpu.should_use_gpu(n):
		return {}

	var occ_pairs := PackedInt32Array()
	var anchors := PackedInt32Array()
	occ_pairs.resize(n * 2)
	anchors.resize(n * 2)
	for i in n:
		var k: int = keys[i]
		var c: PixelChunk = shape.chunks[k]
		occ_pairs[i * 2] = c.occ & 0xFFFFFFFF
		occ_pairs[i * 2 + 1] = (c.occ >> 32) & 0xFFFFFFFF
		anchors[i * 2] = PixelShape.key_x(k) << 3
		anchors[i * 2 + 1] = PixelShape.key_y(k) << 3

	var res: Dictionary = gpu.process(occ_pairs, anchors, _pack_damage(damage))
	if not bool(res.get("ok", false)):
		return {}
	var counts: PackedInt32Array = res.get("counts", PackedInt32Array())
	var occ_out: PackedInt32Array = res.get("occ", PackedInt32Array())
	var comps: PackedInt32Array = res.get("comp", PackedInt32Array())
	if counts.size() != n or occ_out.size() != n * 2 or comps.size() != n * GpuMaxComp * 2:
		return {}
	for i2 in n:
		# count == 0 是合法的：这个 chunk 被完全炸空了。
		# 只有"分量数超过 GPU 侧上限"才需要退回 CPU，保证结果一致。
		if (counts[i2] & GpuOverflowFlag) != 0:
			return {}

	# 写回占用，并同步材质表（GPU 不管材质，材质留在 CPU）
	var removed_total := 0
	for i3 in n:
		var k3: int = keys[i3]
		var c3: PixelChunk = shape.chunks[k3]
		var old_occ := c3.occ
		var lo := occ_out[i3 * 2] & 0xFFFFFFFF
		var hi := occ_out[i3 * 2 + 1] & 0xFFFFFFFF
		var new_occ := lo | (hi << 32)
		if new_occ == old_occ:
			continue
		c3.occ = new_occ
		var gone := old_occ & ~new_occ
		while gone != 0:
			var bi := Bits.first_bit_index(gone)
			c3.mat[bi] = 0
			gone &= gone - 1
		removed_total += Bits.popcount(old_occ & ~new_occ)
		if c3.is_empty():
			shape.chunks.erase(k3)

	# 从 GPU 的分量掩码组装 node 表
	var parts := {"comp_masks": {}, "node_of": {}, "node_chunk": [], "node_mask": []}
	var node_chunk: Array = parts["node_chunk"]
	var node_mask: Array = parts["node_mask"]
	var comp_masks: Dictionary = parts["comp_masks"]
	var node_of: Dictionary = parts["node_of"]
	for i4 in n:
		var k4: int = keys[i4]
		if not shape.chunks.has(k4):
			continue
		var cnt: int = counts[i4]
		var masks: Array = []
		var nodes: Array = []
		for s in cnt:
			var lo2 := comps[(i4 * GpuMaxComp + s) * 2] & 0xFFFFFFFF
			var hi2 := comps[(i4 * GpuMaxComp + s) * 2 + 1] & 0xFFFFFFFF
			var mask := lo2 | (hi2 << 32)
			if mask == 0:
				continue
			masks.append(mask)
			nodes.append(node_chunk.size())
			node_chunk.append(k4)
			node_mask.append(mask)
		if masks.is_empty():
			return {}
		comp_masks[k4] = masks
		node_of[k4] = nodes
	if node_chunk.is_empty():
		return {"removed": removed_total, "parts": []}
	return {"removed": removed_total, "parts": _assemble(shape, keys, parts, min_pixels)}


const GpuOverflowFlag := 0x80000000
const GpuMaxComp := 16

static var _gpu_backend_cache = null

## GPU 破坏路径是否启用（缓存一次）。
##
## ⚠️ 存在的理由是**避免一次性成本落在热路径上**：
##    gpu_backend() 第一次调用会建 RenderingDevice 后端 + 编译 compute pipeline，
##    实测 5.5 ms（带窗口时 126 ms）—— 然后才发现 ENABLED 是 false，白做一场。
##    这 5.5 ms 只出现在**第一笔**上，于是第一笔和其余各笔手感不一样。
##    用这个函数在取后端**之前**判掉，一次性成本就不会落在第一笔上。
static var _gpu_enabled_cache := -1

static func _gpu_enabled() -> bool:
	if _gpu_enabled_cache < 0:
		var script = load("res://src/gpu/gpu_destruction.gd")
		_gpu_enabled_cache = 0
		if script != null and script.get("ENABLED") != null and script.ENABLED:
			_gpu_enabled_cache = 1
	return _gpu_enabled_cache == 1


static func gpu_backend():
	if _gpu_backend_cache == null:
		var script = load("res://src/gpu/gpu_destruction.gd")
		if script == null:
			return null
		_gpu_backend_cache = script.new()
		_gpu_backend_cache.setup()
	return _gpu_backend_cache


static func _pack_damage(d: Damage) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(8)
	out[0] = float(d.kind)
	out[1] = d.radius
	out[2] = d.a.x
	out[3] = d.a.y
	out[4] = d.b.x
	out[5] = d.b.y
	out[6] = d.half.x
	out[7] = d.half.y
	return out


## ---------- CPU 分量提取 ----------
## 刻意不建"每像素 -> 分量"的标签数组：576 个 chunk 各分配一个 64B PackedByteArray
## 的开销在 GDScript 里比泛洪本身还贵。接缝只需反查少量 bit，直接对掩码做位测试。
## 多线程阈值：chunk 太少时线程调度开销 > 收益
const PARALLEL_MIN_CHUNKS := 96
const MAX_COMPONENT_THREADS := 16
static var threads_enabled := true
static var last_component_threads := 1

static func _components_cpu(shape: PixelShape, keys: Array) -> Dictionary:
	var n := keys.size()
	if n == 0:
		return {"comp_masks": {}, "node_of": {}, "node_chunk": [], "node_mask": []}
	var nthreads := 1
	if threads_enabled and n >= PARALLEL_MIN_CHUNKS:
		nthreads = clampi(int(n / PARALLEL_MIN_CHUNKS), 2, MAX_COMPONENT_THREADS)
	last_component_threads = nthreads

	var slices: Array = []
	if nthreads <= 1:
		slices.append(_component_slice(shape, keys, 0, n))
	else:
		# 每个任务处理一段**连续**的 chunk，结果按段序合并 ——
		# 这样 node id 的分配顺序与串行完全一致，结果逐位可复现。
		var per := int(ceil(float(n) / float(nthreads)))
		var slots: Array = []
		slots.resize(nthreads)
		var mtx := Mutex.new()
		var worker := func(t: int) -> void:
			var lo := t * per
			var hi := mini(lo + per, n)
			if lo >= hi:
				return
			var local := _component_slice(shape, keys, lo, hi)
			mtx.lock()
			slots[t] = local
			mtx.unlock()
		# 保持低优先级（= 原始行为）。物理侧实测过高优先级反而更慢，
		# 见 pworld.parallel_high_priority 的注释；这条路径没有单独量过，不冒险改。
		var gid := WorkerThreadPool.add_group_task(worker, nthreads, -1, false, "pixel_components")
		WorkerThreadPool.wait_for_group_task_completion(gid)
		slices = slots

	# 合并（串行，但只是拼装，没有泛洪）
	var comp_masks := {}
	var node_of := {}
	var node_chunk: Array = []
	var node_mask: Array = []
	for si in slices.size():
		var local: Array = slices[si]
		if local == null:
			continue
		for ci in local.size():
			var entry: Array = local[ci]      # [chunk_key, comp_masks]
			var k: int = entry[0]
			var masks: Array = entry[1]
			var nodes: Array = []
			for m in masks:
				nodes.append(node_chunk.size())
				node_chunk.append(k)
				node_mask.append(m)
			comp_masks[k] = masks
			node_of[k] = nodes
	return {"comp_masks": comp_masks, "node_of": node_of, "node_chunk": node_chunk, "node_mask": node_mask}


## 处理 keys[lo, hi) 这一段，返回 [[chunk_key, [分量掩码...]], ...]
static func _component_slice(shape: PixelShape, keys: Array, lo: int, hi: int) -> Array:
	var out: Array = []
	for ci in range(lo, hi):
		var k: int = keys[ci]
		var c: PixelChunk = shape.chunks[k]
		var masks: Array = []
		if c.occ == -1:
			# 满 chunk：1 个分量，省掉泛洪与逐位扫描
			masks.append(-1)
		else:
			var remaining := c.occ
			while remaining != 0:
				var comp := Bits.flood(1 << Bits.first_bit_index(remaining), c.occ)
				masks.append(comp)
				remaining &= ~comp
		out.append([k, masks])
	return out


## ---------- 接缝归并 + 组装（CPU / GPU 两条路径共用） ----------
## 连通分量归组：返回 { 分组序号: { chunk_key: 掩码 } }。
##
## 这是 split() 内部用的那份计算 —— **不要另写一份**。连通性判定的细节
## （对角不算连接、跨 chunk 只查 +X/+Y 避免重复）一旦分叉，两边会给出不同的答案，
## 而这个项目在"同一规则写两处"上栽过太多次（坑 18/31/36）。
static func _group(shape: PixelShape, keys: Array, parts: Dictionary) -> Dictionary:
	var comp_masks: Dictionary = parts["comp_masks"]
	var node_of: Dictionary = parts["node_of"]
	var node_chunk: Array = parts["node_chunk"]
	var node_mask: Array = parts["node_mask"]
	var node_count := node_chunk.size()
	if node_count == 0:
		return {}

	# union-find（Array 在 GDScript 里按引用传递，PackedInt32Array 是值拷贝）
	var parent: Array = []
	parent.resize(node_count)
	for i in node_count:
		parent[i] = i

	# 只查 +X / +Y 两个正方向，避免重复与跨线程反向写
	var col0 := Bits.col_mask(0)
	var col7 := Bits.col_mask(7)
	var row0 := Bits.row_mask(0)
	var row7 := Bits.row_mask(7)
	for k: int in keys:
		if not shape.chunks.has(k):
			continue
		var c: PixelChunk = shape.chunks[k]
		var masks: Array = comp_masks[k]
		var nodes: Array = node_of[k]
		var cx := PixelShape.key_x(k)
		var cy := PixelShape.key_y(k)

		var rk := PixelShape.make_key(cx + 1, cy)
		if shape.chunks.has(rk):
			var rc: PixelChunk = shape.chunks[rk]
			var rmasks: Array = comp_masks[rk]
			var rnodes: Array = node_of[rk]
			var common := (c.occ & col7) & ((rc.occ & col0) << 7)
			while common != 0:
				var bi := Bits.first_bit_index(common)
				_union(parent, nodes[_mask_index(masks, 1 << bi)], rnodes[_mask_index(rmasks, 1 << (bi - 7))])
				common &= common - 1

		var dk := PixelShape.make_key(cx, cy + 1)
		if shape.chunks.has(dk):
			var dc: PixelChunk = shape.chunks[dk]
			var dmasks: Array = comp_masks[dk]
			var dnodes: Array = node_of[dk]
			var common2 := (c.occ & row7) & ((dc.occ & row0) << 56)
			while common2 != 0:
				var b2 := Bits.first_bit_index(common2)
				_union(parent, nodes[_mask_index(masks, 1 << b2)], dnodes[_mask_index(dmasks, 1 << (b2 - 56))])
				common2 &= common2 - 1

	# 按 root 归组并组装 Shape（同一 chunk 的多个 node 需要按位 OR）
	var groups := {}
	for i2 in node_count:
		var root := _find(parent, i2)
		var g = groups.get(root)
		if g == null:
			g = {}
			groups[root] = g
		var k2: int = node_chunk[i2]
		g[k2] = g.get(k2, 0) | int(node_mask[i2])
	return groups


## 连通分量标注（公共入口）。返回 { 分量序号: { chunk_key: 掩码 } }，序号重排为 0..n-1
## —— union-find 的 root 是内部编号，不适合外露。
##
## 游戏层拿它做"这条蓝线是哪一条""哪些体素属于同一个连通体"。
static func components(shape: PixelShape) -> Dictionary:
	var keys: Array = shape.chunks.keys()
	if keys.is_empty():
		return {}
	var groups := _group(shape, keys, _components_cpu(shape, keys))
	var out := {}
	var i := 0
	for root: int in groups:
		out[i] = groups[root]
		i += 1
	return out


static func _assemble(shape: PixelShape, keys: Array, parts: Dictionary, min_pixels: int) -> Array:
	var groups := _group(shape, keys, parts)


	# 快路径：只有一个连通分量 => 破坏没有把东西切开。
	# 直接返回原 Shape，省掉整趟逐像素拷贝（实测是最贵的一步）。
	if groups.size() == 1:
		return [shape] if shape.pixel_count() >= min_pixels else []

	var out: Array = []
	for root: int in groups:
		var g2: Dictionary = groups[root]
		var s := PixelShape.new()
		var total := 0
		for k3: int in g2:
			var mask: int = g2[k3]
			var n := Bits.popcount(mask)
			if n == 0:
				continue
			total += n
			var src_chunk: PixelChunk = shape.chunks[k3]
			s.blit_mask_from(src_chunk, k3, mask)
		if total >= min_pixels and total > 0:
			out.append(s)
	return out


## 在分量掩码列表里找出包含指定 bit 的分量序号（通常只有 1~2 个分量）。
static func _mask_index(masks: Array, bit: int) -> int:
	for i in masks.size():
		if (int(masks[i]) & bit) != 0:
			return i
	return 0


static func _find(parent: Array, i: int) -> int:
	var root := i
	while parent[root] != root:
		root = parent[root]
	while parent[i] != root:
		var next: int = parent[i]
		parent[i] = root
		i = next
	return root


static func _union(parent: Array, a: int, b: int) -> void:
	var ra := _find(parent, a)
	var rb := _find(parent, b)
	if ra == rb:
		return
	if ra < rb:
		parent[rb] = ra
	else:
		parent[ra] = rb
