# 开发者手册

## 这份手册 vs 自动生成的 API 参考

| | 组织方式 | 回答的问题 |
|---|---|---|
| `docs/api/`（生成） | 按**类** | `PWorld` 有哪些方法？参数是什么？ |
| **本手册**（手写） | 按**任务** | 我想做 X，该用哪个 API？怎么组合？ |

参考是查的，手册是读的。先读手册建立模型，之后查参考。

---

## 心智模型

```
Body（刚体）    位置/旋转/速度/质量。物理只认识它。
  └─ Shape[]   一组形状。一个刚体可以有好几块。
       └─ PixelChunk[]   8x8 的像素块（稀疏表）。
            ├─ occ : int64        占用位掩码（哪些像素是实心的）
            ├─ mat : byte[64]     材质 id（1..255，0 = 空）
            └─ aux : byte[64]     辅助表，引擎不解释语义（损伤/引信/信号…）
```

三个关键点：

1. **物理只看见 OBB。** 像素团会被贪心分解成矩形，物理层拿到的是一堆 OBB。
   所以你不需要为碰撞单独建形状 —— 画什么就是什么。
   （"包围体"是另一回事，它有两个：轴对齐的 AABB 和跟着刚体转的凸包，见下面的决策表。）
2. **材质只是一个整数 id。** 颜色、密度、强度、混合规则**全部由游戏层持有**，
   引擎只在需要时问你要密度（`PWorld.material_density`）。
3. **`aux` 是给你用的。** 引擎不解释它，只保证它跟 `mat` 一起被复制、切分、保留。
   损伤、引信计时、信号强度、温度都放这里 —— **不要编码进材质 id 的高位**。

---

## 坐标空间（最容易搞混的地方）

| 空间 | 单位 | 怎么转 |
|---|---|---|
| **世界** | 像素 | 绝大多数 API 都用它：破坏、查询、施力、标签 |
| **刚体局部** | 像素 | `body.to_local(p)` / `body.to_world(p)` |
| **形状局部像素** | 整数格 | **和刚体局部是同一个空间** —— 形状没有独立变换 |

> ⚠️ **形状没有自己的局部变换**（引擎的刻意简化）。像素直接活在刚体局部空间里，
> 所以 `shape.get_pixel(x, y)` 的 `(x, y)` 就是刚体局部坐标取整。
> 这也意味着 `ShapeOps.world_transform(shape)` 返回的就是刚体变换。

**唯一的例外**是 `Destruction.Damage` —— 它的坐标是**形状局部像素空间**。
世界坐标的破坏请用 `PixelPhysics.carve_circle` 那一组（内部帮你换算）。

---

## 一帧里发生什么

```
world.step(dt)
  ├─ 按最快物体决定切几个子步（默认每子步位移 <= 2 像素）
  └─ 每个子步：
       清伪速度 -> 积分受力 -> 宽相+窄相 -> [采集接触事件] -> 唤醒 -> 求解
       -> 积分变换 -> 更新 AABB -> 休眠
```

游戏层通常这样编排：

```gdscript
func _physics_process(delta):
    # 1) 物理步进之前：跑你自己的体素模拟（元胞自动机），改 mat/aux
    for body in px.bodies():
        for shape in body.shapes:
            voxel_tick(shape)          # 只处理 shape.dirty_chunks()
    px.step(delta)                     # 2) 物理
    for c in px.world.contacts:        # 3) 步进之后：读接触事件做反应
        handle_contact(c)
```

---

## 决策表：我要做 X，用哪个 API

### 造东西

| 我要 | 用 |
|---|---|
| 一块地面/墙 | `px.add_ground(rect, material)` |
| 一个方块 | `px.spawn_rect(pos, size, material)` |
| 一个圆盘 | `px.spawn_circle(pos, radius, material)` |
| 任意像素团 | `px.spawn_shape(pos, shape)` |
| 程序化生成（人形、房子） | `px.spawn_from_grid(pos, w, h, solid_fn, material)` |
| 删掉一个物体 | `px.despawn(body)` |

### 材质与颜色

| 我要 | 用 |
|---|---|
| 定义一种材质（颜色+密度） | `px.define_material(id, color, density)` |
| 查世界某点的材质 | `px.material_at(world_point)` |
| 查形状上某点的材质 | `px.shape_material_at(shape, world_point)` |
| 涂色（不破坏） | `px.paint_circle(center, radius, material)` |
| 整块换材质 | `px.set_body_material(body, from, to)` |
| 逐像素读写 | `shape.get_pixel / set_pixel / get_aux / set_aux` |

### 动力学量（甲方要的：力矩 / 角速度 / 动量 / 角动量）

| 我要 | 用 |
|---|---|
| 施加**持续力矩**（每帧调） | `px.spin(body, torque)` |
| 施加**力矩冲量**（一次性） | `px.torque_impulse(body, j)` |
| 读角速度 | `px.angular_velocity_of(body)` |
| 读线动量 | `px.momentum(body)` |
| 读角动量（关于质心） | `px.angular_momentum(body)` |
| 读角动量（关于任意点） | `px.angular_momentum_about(body, p)` |
| 读动能 | `px.kinetic_energy(body)` |
| 读质量 / 转动惯量 | `px.mass_of(body)` / `px.inertia_of(body)` |
| **守恒检查**（总动量/总角动量/总动能） | `px.total_momentum()` / `px.total_angular_momentum()` |

**符号约定**（2D，Godot 的 y 轴向下）：

- 角速度为正 = 屏幕上**顺时针**转
- 二维叉积 `a.cross(b) = a.x*b.y - a.y*b.x` 在这个坐标系下同样顺时针为正
- 所以角动量的符号与角速度一致，不需要额外取负

**两个必须知道的坑**：

1. **`add_torque` 是持久累加器，引擎不会自动清** —— 忘了 `clear_forces()` 力矩会越加越大、
   角速度呈二次增长。走 `px.step()` 由它代劳；直接调 `world.step()` 就得自己清。
2. **线阻尼是 `0.35`，角阻尼是 `0.6`** —— 两个不一样，拿错会得到 ~12% 的偏差，
   而且看起来「差不多对」，很能骗人。

**关于任意点的角动量**：L = I·ω + r × m·v。`px.angular_momentum(body)` 是**关于质心**的，
判断「绕某个轴转不转」要用 `angular_momentum_about` —— 比如绕钉子摆动的木板。

**守恒检查**只有**无外力**时才成立。本引擎有阻尼，所以短窗口内检查才准：

```gdscript
var p0 := px.total_momentum()
# ... 跑几步 ...
var p1 := px.total_momentum()
# 有阻尼时按 damp^steps 衰减，别期望严格相等
```

### 让东西动

| 我要 | 用 |
|---|---|
| 持续推（每帧调） | `px.push(body, force)` |
| 在某点推（产生力矩） | `px.push_at(body, force, world_point)` |
| 转 | `px.spin(body, torque)` |
| 瞬间踢一脚 | `px.impulse(body, j, world_point?)` |
| 失重 / 反重力 | `px.set_gravity_scale(body, 0.0)` |
| 直接设速度 | `px.set_velocity(body, v)` |
| 让一个物体不被物理推走 | `body.make_static()` |

### 破坏

| 我要 | 用 |
|---|---|
| 挖圆洞 | `px.carve_circle(center, radius)` |
| 挖方洞 | `px.carve_rect(center, half_size)` |
| 激光切割 | `px.cut(from, to, radius)` |
| 爆炸（推开+破坏） | `px.explode(center, radius, power)` |
| 只切分不破坏 | `px.split_shape(shape)` |
| 合并相邻形状 | `px.merge_shape(shape)` |
| 判断是否被打碎 | `px.is_broken(body)` |

### 查询（射击、视线、范围）

| 我要 | 用 |
|---|---|
| 打一条**像素级精确**的射线 | `px.raycast(origin, dir, max_dist, radius?)` |
| 找最近的实心像素 | `px.closest_point(origin, max_dist)` |
| 范围内的物体 | `px.bodies_in(bounds)` |
| 查询时排除某些物体 | `px.query_reject_body(body)` |

### 包围体（AABB 与**凸包**并列）

| 我要 | 用 |
|---|---|
| 粗包围盒（轴对齐，最便宜） | `px.bounds(body)` / `body.aabb` |
| **紧**的包围体（跟着刚体一起转） | `px.hull(body)` / `body.world_hull()` |
| 形状自己的凸包（形状局部像素坐标） | `px.shape_hull(shape)` / `shape.local_hull()` |
| 点是否落在包围体里 | `body.aabb.has_point(p)` / `px.hull_contains(body, p)` |
| 在编辑器 / 调试里看它们 | 调试叠加层的 `show_aabbs` / `show_hulls` 开关 |

**为什么两个都要**：AABB 的判定是两次区间比较（最便宜），但它是**轴对齐**的 ——
刚体一转就按外接半径膨胀（100x8 的木板转 45 度，AABB 变成 76x76 的方框，面积 x7，
而凸包只有 x1.4）。所以选路是：**先用 AABB 粗筛，再用凸包细筛**。

### 碰撞体（第三种，和上面两种**不是**一回事）

| 你想要 | 用它 |
|---|---|
| 物理**真的在用**的形状（凸多边形，世界坐标） | `px.colliders(body)` / `world.fetch_polys(body)` |

引擎默认把像素**拟合成凸多边形**再交给 Rapier（Noita 式）：斜边是**直的**
（40 级锯齿楼梯 = 1 个多边形，斜边一条线），块数远少于矩形。

⚠️ **斜边取"中间"，不是把像素整个包住**：轴对齐的边是真实像素边界（原样保留），
**斜边是拟合出来的**，它被往里挪半个像素 —— 台阶尖露在碰撞体外面、凹口被盖住。
所以"碰撞体比像素大"和"碰撞体比像素小"**同时**存在，两个方向都受 `poly_dev_tol` 约束。
实心块不受影响（它没有斜边，四个边都是真实边界）。
```gdscript
world.poly_colliders = false   # 回到逐像素精确的轴对齐矩形（拟合的对照组）
world.poly_dev_tol = 1.0       # 偏离容差（像素）：碰撞体允许比像素表面厚多少
world.poly_max_rects = 256     # 矩形数超过它就不拟合（高频锯齿地形拟合不划算）
```

⚠️ `px.colliders(body)` 读的是 **Rapier 里真的在用的形状**（op 44 读回），
不是 GDScript 侧另算一份 —— 所以走矩形那条路时它返回的就是矩形。
**可视化必须用它**：照 `body.rects` 画会在拟合模式下画出一套**不存在**的矩形。

⚠️ **凸包是包围体，不是碰撞形状。** 凹形状（L 形墙、楼梯）的凹角会被它填平 ——
拿去碰撞会多出看不见的体积。物理真正用的是贪心分解出的碰撞矩形（`body.rects`），
理由见框架文档 5.3 与 pitfalls 第 24 条。

⚠️ `px.hull()` 是**惰性**的：第一次问才现算（768x100 的地面实测 5.05 ms），之后按形状
版本号复用；形状一改就作废。别在"每帧对几百个刚体"的热循环里第一次问它。
射线查询内部也只在凸包**已经算过**时才拿它做剔除（见 performance.md 的「凸包」一节）。

### 反应（事件）

| 我要 | 用 |
|---|---|
| 知道这一步撞了什么、多猛 | `world.contact_events_enabled = true` 然后读 `world.contacts` |
| 只处理「首次撞击」 | `c.is_new` |

### 体素级模拟（元胞自动机 / 信号 / 生长）

| 我要 | 用 |
|---|---|
| 只处理变过的区域 | `shape.dirty_chunks()` / `shape.has_dirty()` / `clear_dirty()` |
| 沿连通体素走一遍 | `shape.flood(from, matches, visit)` |
| 知道某像素属于哪个连通体 | `ShapeOps.component_map(shape)`（原生，见 performance.md）|
| 邻域 | `PixelShape.OFFSETS_4 / OFFSETS_8`（热循环里直接内联，别调 `neighbors()`） |
| 手动标脏（批量写入后） | `shape.mark_dirty(cx, cy)` |

### 液体（纯视觉的粒子流体）

| 我要 | 用 |
|---|---|
| 一瓶会跟着容器转的液体 | `FluidPBF`（`src/fluid/fluid_pbf.gd`，见 cookbook 第 16 节） |
| 液体量跟着血量 / 燃料走 | `fluid.set_fill_ratio(r)` + `fluid.fill_rate`（**连续**掉，不是一下删完） |
| 一步到位（初始化 / 测试） | `fluid.snap_fill()` |
| 知道哪里是液体 | `fluid.ink`（`x*num_y + y`，x 主序） |

> ⚠️ 这是**表现层**的东西：它不进物理像素、不做碰撞。要"液体能被踩"是另一件事。

### 查找与组织

| 我要 | 用 |
|---|---|
| 按名字找物体 | `px.set_tag(body, "crate")` + `px.find_body("crate")` |
| 找一批 | `px.find_bodies(tag)` / `px.find_shapes(tag)` |
| 拖动物体 | `px.grab_at(world_point)` / `px.drag_to(p)` / `px.release()` |

---

## 阅读路径

| 你是 | 读这些 |
|---|---|
| **第一次用** | 本页 → `addons/pixel_destruction/examples/minimal.gd`（8 个断言的活文档） |
| **要做玩法** | [cookbook.md](cookbook.md) —— 按任务的配方 |
| **关心性能** | [performance.md](performance.md) —— 实测数字与选路 |
| **踩坑了** | [pitfalls.md](pitfalls.md) —— API 误用清单 |
| **要移植/改引擎** | `addons/pixel_destruction/docs/PRECISION.md` —— 浮点与移植纪律 |
| **想懂管线** | `addons/pixel_destruction/docs/ARCHITECTURE.md` |

---

## 三十秒上手

```gdscript
var px := PixelPhysics.new()
add_child(px)                                     # 加进树里就自动 _physics_process

px.define_material(1, Color.SLATE_GRAY, 2.5)      # 石头
px.define_material(2, Color.SANDY_BROWN, 0.6)     # 木头
px.add_ground(Rect2(-400, 300, 800, 40), 1)

var crate := px.spawn_rect(Vector2(0, 0), Vector2(20, 20), 2)
px.set_tag(crate, "crate")

# 射击：像素级精确，能穿过像素画里的空洞
var hit := px.raycast(px.center_of_mass(crate) + Vector2(-100, 0), Vector2(1, 0), 300.0)
if hit.hit:
    px.explode(hit.point, 30.0, 400.0)            # 爆心/半径/速度增量
```