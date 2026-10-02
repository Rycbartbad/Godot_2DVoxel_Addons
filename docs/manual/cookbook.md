# 配方手册

按任务组织。每段都是可以直接抄的。

---

## 1. 建一个可玩场景

```gdscript
var px := PixelPhysics.new()
add_child(px)                                  # 加进树里就自动 _physics_process
px.configure({"gravity": Vector2(0, 900)})     # 想改默认值才需要

px.define_material(1, Color.SLATE_GRAY, 2.5)
px.define_material(2, Color.SANDY_BROWN, 0.6)
px.add_ground(Rect2(-800, 300, 1600, 60), 1)
```

> `add_ground` 的 `rect.position` 是**左上角**（像素坐标）。
> 不想加进树（无头测试、自己控节奏）就不 `add_child`，手动 `px.step(dt)`。

---

## 2. 程序化生成像素图形

任意像素团都能当碰撞体 —— 不需要为碰撞单独建形状。

```gdscript
# 人形：solid(x, y) 决定每个像素是否实心
var man := px.spawn_from_grid(Vector2(0, 0), 12, 20, func(x, y):
    var head := y < 6 and x >= 3 and x <= 8
    var body := y >= 6 and y < 15 and x >= 2 and x <= 9
    var legs := y >= 15 and (x < 5 or x > 6)
    return head or body or legs, 1)
```

或者先造形状再挂上去（想复用/想改的时候更方便）：

```gdscript
var s := PixelShape.new()
s.fill_rect(Rect2i(0, 0, 16, 16), 2)
s.fill_rect(Rect2i(4, 4, 8, 8), 0)              # material 0 = 挖空
var body := px.spawn_shape(Vector2(100, -50), s)
```

---

## 3. 材质与颜色

**颜色按材质表达，不逐像素存颜色。** 像素数据只占 1 字节材质 id。

```gdscript
px.define_material(3, Color.CRIMSON, 7.8)        # 定义/改一种材质（颜色+密度一次设好）

px.material_color(3)                             # -> Color
px.material_density(3)                           # -> float
px.material_at(Vector2(100, 320))                # 世界坐标处是什么材质（0 = 空）

px.paint_circle(Vector2(0, 0), 20, 3)            # 世界坐标涂色（不破坏、不分裂）
px.set_body_material(body, 2, 3)                 # 整个刚体换材质，并自动重算质量

# 逐像素（热循环里别这么写，见 performance.md）
var sh: PixelShape = body.shapes[0]
sh.get_pixel(4, 4)                               # -> 材质 id
sh.fill_rect(Rect2i(0, 0, 4, 4), 3)
sh.count_by_material()                           # -> {1: 84, 3: 16}
```

---

## 4. 射击（像素级射线）

射线走**体素 DDA**，所以能精确穿过像素画里的空洞 —— 拿 OBB 近似的话，
一个 24x24 的像素人形会被当成一个实心方块。

```gdscript
var hit := px.raycast(muzzle, aim_dir, 600.0)    # radius 省略 = 细射线
if hit.hit:
    print(hit.distance, hit.point, hit.normal, hit.material)
    print(hit.body, hit.shape)
    px.explode(hit.point, 24.0, 500.0)
```

加粗射线（霰弹、碰撞体大小的弹丸）：

```gdscript
var h := px.raycast(muzzle, aim_dir, 600.0, 6.0)   # radius = 6
```

排除自己（枪管不要打到自己）：

```gdscript
px.query_reject_body(gun_body)
var h2 := px.raycast(muzzle, aim_dir, 600.0)
px.query_clear_filters()
```

---

## 5. 爆炸与连锁

```gdscript
# power 是**速度增量**语义（紧贴爆心的物体大约获得 power 的速度），
# 与物体轻重无关 —— 内部按 impulse *= mass 抵消了质量项。
var frags := px.explode(Vector2(100, 100), 120.0, 400.0)
# 可选：把破坏边缘烧成材质 4
px.explode(center, 80.0, 300.0, 4)
```

返回的是**新产生的碎片刚体**数组，渲染层会自动跟上，不用手动 prune。

---

## 6. 高速碰撞触发

```gdscript
px.world.contact_events_enabled = true        # 默认关（有分配开销）

func _physics_process(delta):
    px.step(delta)
    for c in px.world.contacts:               # 每步清空后重填
        if not c.is_new:                      # 只要首次撞击
            continue
        if absf(c.approach) > 400.0:          # 撞得够狠
            on_hard_hit(c.a, c.b, c.point, c.approach)
```

> `c.approach` 是**接触点处**的接近速度（含转动贡献），不是质心速度。
> 一个高速旋转的物体质心可能几乎不动，但边缘撞得很狠。
> 有子步时同一个配对可能在一步里出现多次 —— 要「每步一次」请自己按 `is_new` 过滤。

---

## 7. 元胞自动机：红色蔓延（完整例子）

这是`aux` + 脏区域 + `flood` + 接触事件四样东西合起来能做的事。

```gdscript
const MAT_BLACK := 1
const MAT_RED   := 2
const MAT_ASH   := 3

## 每 tick 只处理变过的地方 —— 这是能跑得动的关键。
## 240 个碎片 x 16 像素 = 3840 个体素，全扫必崩。
func fuse_tick() -> void:
    for body in px.bodies():
        for shape in body.shapes:
            var s := shape as PixelShape
            if not s.has_dirty():
                continue
            var ignite: Array[Vector2i] = []
            var keys := s.dirty_chunks()
            for key in keys:
                var cx := PixelShape.key_x(key)
                var cy := PixelShape.key_y(key)
                var c: PixelChunk = s.chunks[key]
                var occ := c.occ
                var i := 0
                while occ != 0:
                    if occ & 1:
                        if c.mat[i] == MAT_RED and c.aux[i] > 0:
                            c.aux[i] -= 1                  # 引信倒计时
                            if c.aux[i] == 0:
                                ignite.append(Vector2i(cx * 8 + (i & 7), cy * 8 + (i >> 3)))
                    occ >>= 1
                    i += 1
                s.mark_dirty(cx, cy)        # 直改数组不会自动标脏
            s.clear_dirty()                 # 处理完就清，下一 tick 只看新的变化
            for at in ignite:
                _detonate(body, s, at)

## 引爆一个红色像素：沿连通体素把火传出去，然后把这一片炸掉
func _detonate(body, s: PixelShape, at: Vector2i) -> void:
    var spread: Array[Vector2i] = []
    s.flood(at,
        func(x, y, m, dist):
            # 谓词：只沿红色走，最多传 3 格
            return m == MAT_RED and dist <= 3,
        func(x, y, m, dist):
            # 访问者：把引信设上（注意 lambda 按值捕获，累积要用引用类型）
            spread.append(Vector2i(x, y))
            return true)
    for p in spread:
        s.set_aux(p.x, p.y, 12)                 # 12 tick 后引爆
        s.set_pixel(p.x, p.y, MAT_RED)
    # 把这一片挖掉并给出冲量
    var world_at := body.to_world(Vector2(at) + Vector2(0.5, 0.5))
    px.explode(world_at, 20.0, 350.0)
    # 烧成灰
    for p in spread:
        s.set_pixel(p.x, p.y, MAT_ASH)
```

> ⚠️ 三个必须注意的点：
> 1. **`flood` 的 lambda 按值捕获局部变量** —— 累积结果要用 Array/Dictionary/对象成员，
>    改一个局部 `var count := 0` 是改副本，外面永远是 0。
> 2. **直改 `chunk.mat/aux` 不会自动标脏**，要自己 `mark_dirty`。
> 3. **处理完要 `clear_dirty()`**，否则脏集合只增不减，下一 tick 又要全扫一遍。

---

## 8. 蓝线信号传播

```gdscript
## 从信号源沿蓝色体素传播，按距离衰减
func propagate(shape: PixelShape, source: Vector2i, power: int) -> void:
    var reached := {}                       # 引用类型，lambda 里能累积
    shape.flood(source,
        func(x, y, m, dist): return m == MAT_BLUE and dist <= power,
        func(x, y, m, dist):
            reached[Vector2i(x, y)] = power - dist
            return true)
    for p in reached:
        shape.set_aux(p.x, p.y, reached[p])   # 信号强度写进 aux
```

要知道「这条蓝线是哪一条」用 `component_map()`：

```gdscript
var cm := ShapeOps.component_map(shape)             # { count, chunks: { key: PackedInt32Array(64) } }
var arr: PackedInt32Array = cm["chunks"][PixelShape.make_key(0, 0)]
var which_line: int = arr[3 * 8 + 5]        # 局部像素 (5, 3) 属于哪条线（-1 = 空）
```

---

## 9. 抓取拖动

```gdscript
func _unhandled_input(e):
    if e is InputEventMouseButton and e.pressed:
        px.grab_at(world_pos)               # 抓住鼠标下的刚体（找不到返回 false）
    elif e is InputEventMouseMotion and px.has_grab():
        px.drag_to(world_pos)
    elif e is InputEventMouseButton and not e.pressed:
        px.release()
```

它和接触约束在**同一层迭代**，所以拖着物体撞墙时会自然互相制衡。

---

## 10. 标签与查找

```gdscript
px.set_tag(crate, "crate", 7)                # 值可以是任意东西
px.set_tag(enemy, "enemy")

px.find_body("crate")                        # 第一个
px.find_bodies("crate")                      # 全部
px.find_shapes("crate")                      # 它们的形状
px.tag_value(crate, "crate")                 # -> 7
px.has_tag(crate, "crate")
px.remove_tag(crate, "crate")
```

> 用标签而不是自己维护一张 id -> 刚体 的表：那张表一旦漏掉删除分支就会变成悬空引用。

---

## 11. 大批量体素编辑（性能写法）

逐像素 `set_pixel` 在 GDScript 里约 **1289 ns/像素**，直改数组约 **527 ns**。
元胞自动机这类热循环必须走批量路径：

```gdscript
for key in shape.dirty_chunks():
    var cx := PixelShape.key_x(key)
    var cy := PixelShape.key_y(key)
    var c: PixelChunk = shape.chunks[key]
    # 直接改 c.occ / c.mat / c.aux —— 一次都不进函数调用
    var occ := c.occ
    var i := 0
    while occ != 0:
        if occ & 1:
            c.mat[i] = MAT_ASH
        occ >>= 1
        i += 1
    shape.mark_dirty(cx, cy)          # 别忘了这一句
```

---

## 12. 手动做一个「铰接」（约束系统还没做时的临时办法）

引擎目前只有 `grab` 一种约束。要做机械结构，可以先用每帧施力近似：

```gdscript
## 每帧把 B 上的锚点拉向 A 上的锚点（软约束）
func hinge_step(a, b, local_anchor_a: Vector2, local_anchor_b: Vector2, k: float) -> void:
    var pa := a.to_world(local_anchor_a)
    var pb := b.to_world(local_anchor_b)
    var err := pa - pb
    var rel := b.velocity_at(pb) - a.velocity_at(pa)
    var f := err * k - rel * (k * 0.1)      # 弹簧 + 阻尼
    px.push_at(b, f, pb)
    px.push_at(a, -f, pa)
```

> 这是权宜之计。真正的通用约束（铰接/栓接/连杆/马达）还在计划里，
> 见 `docs/api_alignment.md` 的缺口清单。