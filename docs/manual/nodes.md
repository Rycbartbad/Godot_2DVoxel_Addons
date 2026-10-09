# 节点层：像用 Godot 内置引擎一样用本引擎

引擎有**两套用法**，可以先只用一套：

| 用法 | 适合 | 入口 |
|---|---|---|
| **纯代码** | 程序化生成、无头测试、批量模拟 | `PixelPhysics` 门面 / `PWorld` |
| **节点层** | 手搭关卡、美术参与、要 Inspector 可视化 | `PixelWorld` + 子节点 |

两套共用同一个物理内核，**可以混用**。

## 结构

```
PixelWorld                     世界容器（一帧推进一次物理）
 ├─ PixelBody2D                刚体：可拖动、可继承、可组合
 │   ├─ PixelShape2D           形状子节点（对标 CollisionShape2D）
 │   ├─ PixelShape2D           一个刚体可以挂多个
 │   └─ PixelSprite2D          渲染子节点（对标 Sprite2D，继承自它）
 ├─ PixelBody2D
 ├─ PixelJoint2D               关节：连两个 PixelBody2D（节点位置 = 锚点 A）
 ├─ Camera2D                   ← 用内置的，引擎不封装
 └─ CanvasLayer                ← 用内置的，引擎不封装
```

### 三条不变量（任何一条破了都会「碰撞箱与精灵图对不上」）

1. 局部像素 `(0,0)` 是形状的**左上角**
2. `PixelBody2D.position` 指向局部 `(0,0)` —— **不是中心**
3. `PixelSprite2D` 的贴图左上角也贴在同一个点上

想在游戏里做「以中心对齐」，**把 position 减去半个外接尺寸**，
不要改引擎 —— 贪心分解、质量属性、破坏、渲染全部建立在「原点=左上角」之上。

## 形状是子节点，不是属性

一个刚体可以挂多个形状子节点，每个有自己的 `position` / `scale`，
在编辑器里能单独选中、拖动。

**接口约定**：`PixelBody2D.collect_shapes()` 只认 `build_shape()` **这个方法**，
**不检查节点类型**。所以：

```gdscript
@tool
class_name MyShape2D
extends "res://src/nodes/pixel_shape_2d.gd"   # 注意用路径式 extends

func build_shape() -> PixelShape:
    var s := PixelShape.new()
    # ... 你的生成逻辑，坐标用局部像素 ...
    return s
```

挂到 `PixelBody2D` 下面就能用 —— **不用改 PixelBody2D 一行代码**。
碰撞、渲染、编辑器抓手、质量/惯量/破坏/查询全都自动生效。

仓库里的 `PixelShapePolygon2D` 就是这样一个例子（扫描线填任意多边形，
像素游戏里的斜坡直接可用）。

> ⚠️ `extends` 必须写**路径式**（`extends "res://..."`）而不是 `extends PixelShape2D`：
> addon 里也有一份同名脚本，靠全局 `class_name` 解析会失败。

## 关节也是节点（PixelJoint2D）

五种关节（铰链 / 滑轨 / 焊接 / 绳 / 弹簧）都有节点形态，放在 `PixelWorld` 下面、
和 `PixelBody2D` 同级。这样"吊桥挂在哪个点、限位多少度、马达多快"全在 Inspector 里，
改完在编辑器里就能看到，不用改一次代码跑一次游戏。

| 属性 | 说明 |
|---|---|
| **`position`** | **锚点 A**（世界坐标）—— 拖节点就是拖支点 |
| `body_a` / `body_b` | `NodePath` 指向两个 `PixelBody2D`。**留空 = 接静态世界** |
| `anchor_b_offset` | 锚点 B 相对节点位置的偏移。**只有绳/弹簧用得到**（两端锚点不同） |
| `kind` | `HINGE` / `SLIDER` / `WELD` / `ROPE` / `SPRING` |
| `axis` | 滑轨的轴（**世界方向**） |
| `limits_enabled` / `min_limit` / `max_limit` | 限位（铰链是角度，滑轨是距离） |
| `motor` / `motor_target` / `motor_max_force` | 马达：`OFF` / `VELOCITY` / `POSITION`；`max_force = 0` 即关闭 |
| `rest_length` / `stiffness` / `damping` | 绳的最大长度 / 弹簧的静止长度与刚度阻尼 |
| `break_impulse` | 约束冲量（力 x 时间步）超过它就断；**0 = 不断** |
| `contacts_enabled` | 两个被连着的刚体之间**要不要生成接触**。默认 **关**（见下） |

关节在物理里没有形状，所以节点**自己把两端锚点连成一条线**：
**青=铰链，白=滑轨，粉=焊接，黄=绳，绿=弹簧**。

> ⚠️ **运行时只在 `DebugOverlay` 可见时才画**（甲方要求：约束的调试画法不能出现在
> 游戏画面里）—— Demo 里按 **D** 开关叠加层，约束线跟着一起出现/消失。
> **编辑器里始终画**（`Engine.is_editor_hint()`），否则摆关节时"有约束/没约束"看起来
> 一模一样。`debug_draw = false` 可以彻底关掉。

烘焙顺序由 `PixelWorld` 保证：**先所有刚体，再关节** —— 关节两端要的是已经进世界的 `PBody`。

> ⚠️ **默认不生成接触**（`contacts_enabled = false`，与 Box2D 的 `collideConnected = false` 同款）。
> 关节和接触是**两个求解器**，目标相反：关节按创建时的相对位姿把两端按住，接触要把重叠的
> 体素推开。两个**体素重合**的刚体焊在一起时，这两股力会一直打架 —— 实测逐帧跳变
> **0.785 px/步**、关节冲量 **121280**（不碰时是 0.0000 / 0）。只有确实需要"连在一起还互相挡"
> （比如带限位的门要挡住身体）时才把它打开。
>
> ⚠️ **弹簧的刚度要按重量选。** Rapier 的弹簧是绝对力语义，平衡点在静止长度**下方**
> `m*g/刚度` 处。Demo 里那个 16x16 木箱（m≈154、g=600）用 `stiffness=10000` 得到 9 px 垂度；
> 用 200 会直接坠到地上（垂度 462 px），再往上调则 `ω*dt > 1` 会把求解器炸掉。

### 约束误差：怎么知道"哪个关节在漂"

`PJoint` 有三个**只读**诊断量（纯 GDScript 算，**零原生调用**，每次约 5~10 µs）：

| 方法 | 量 | 用途 |
|---|---|---|
| `anchor_error()` / `anchor_error_len()` | 两个锚点的世界坐标差（px） | 约束有没有把两端按在一起 |
| `angle_error()` | 相对转角相对创建时刻的变化（弧度） | **WELD / HINGE 锁住的那一行** |
| `lateral_error()` | 滑轨**垂直于轴**的漂移（世界向量） | SLIDER 锁住的 LinY 那一行 |

```gdscript
# 按**步**采样（不是每帧 —— 一帧可能补多个 step，那样会漏掉中间的振动）
func _on_step(w) -> void:
    for j in w.joints:
        if j.anchor_error_len() > 0.25:
            print("关节 %d 锚点漂了 %.3f px，角差 %.4f rad" % [
                j.rapier_id, j.anchor_error_len(), j.angle_error()])
```

> ⚠️ 它**不是** Rapier 内部那个速度级约束误差（那个不对外暴露，只作为 rhs 活在求解器里），
> 而是**位姿级**的答案："约束到底把两个锚点 / 朝向按住了吗"。两者同源（位姿是约束的积分结果），
> 但不是同一个数学对象 —— 别拿它当求解器残差用。
> ⚠️ `angle_error()` **不能**用 `movement()` 代替：WELD 的 `movement()` 恒为 0（它没有自由度），
> 而那正是"焊接被拉歪多少"最需要看的地方。
> ⚠️ 容差里的坑：锚点走 `body.to_world()`，而 **Vector2 是 float32**（GDScript 标量才是 float64）——
> 自己算预期值时容差别小于 1e-4。
> 闸门：`tests/validation_joint_error.gd`（14 项，判据是"人为瞬移/转一个已知量，读到的误差必须等于它"）。

## 材质是资源

`PixelMaterial` 是一个 `Resource`：颜色 / 密度 / 摩擦 / 恢复系数 / 抗压 / 抗剪在**同一个资源**里。

```
materials/
  stone.tres    石头  密度 2.5   摩擦 0.5   恢复 0.0   抗压 40
  wood.tres     木头  密度 0.6   摩擦 0.5   恢复 0.0   抗压 14
  metal.tres     铁   密度 7.8   摩擦 0.5   恢复 0.0   抗压 120
  brick.tres     砖   密度 2.0   摩擦 0.5   恢复 0.0   抗压 20
```

| 属性 | 语义 | 备注 |
|---|---|---|
| `density` | 质量 = Σ 密度 | 逐像素存，混合材质取加权平均 |
| `friction` | 摩擦系数（0 = 冰面）| **两个碰撞体合成**（默认取平均）|
| `restitution` | 恢复系数（0 = 不弹，1 = 完全弹性）| 合成规则同上 |

> ⚠️ **合成规则**：Rapier 的接触系数是**两个碰撞体按 `CoefficientCombineRule` 合成**的
> （默认 `Average`）。球 0.9 + 地面 0.0 → 接触处 0.45 → 回弹速度 45%、高度约 20%。
> 想让球真的弹起来，**地面也要给恢复系数**；摩擦同理（想让某个材质说了算，两边设同值）。
> 实测：`tests/validation_materials.gd`（摩擦 0 → 滑 213.7 px，摩擦 0.9 → 124.2 px；
> 恢复 0 → 回弹 0.0 px，0.9 → 19.2 px）。

在 `PixelWorld` 的 Inspector 里把这些资源填进 `materials` 数组即可。
`rebuild()` 会把颜色播给渲染层、密度与强度播给物理层 —— **一份数据，三处同源**。

> 为什么做成 Resource：以前颜色在 `PixelRenderer.palette`、密度在 `PWorld` 里，
> 改一处忘另一处是**静默 bug**（颜色变了手感没变）。

## 破坏判据

四样工具，合起来能写「矛能破盾、盾不能破矛」：

| 工具 | API |
|---|---|
| 接触冲量（**真值**） | `Contact.impulse` / `Contact.tangent_impulse` |
| 接触宽度 | `Contact.contact_width` |
| 材质强度 | `world.set_material_strength(mat, 抗压, 抗剪)` |
| 法向厚度 | `Query.thickness_at(body, point, normal)` |

```gdscript
for c in world.contacts:
    var sigma := c.impulse / maxf(1.0, c.contact_width)   # 应力
    var s := world.strength_for(material, c.shear_ratio)  # 该加载模式下的强度
    if s > 0.0 and sigma > s:
        px.carve_circle(c.point, 6.0)
```

### 为什么这样就能区分矛与盾

同样材料、同样冲量，**接触面积差 100 倍 → 应力差 100 倍**：

- 矛尖接触 ~1 像素² → 应力极大 → 破盾
- 盾面接触 ~200 像素² → 应力小 → 不破

**抗压与抗剪分开**是另一半：矛尖正面顶盾面是**压缩**，盾缘横向切矛杆是**剪切**。
同一种材料抗压远强于抗剪 —— 所以是矛破盾，不是盾破矛。

`shear_ratio` 由 `Query.thickness_at` 算出：法向穿过的材料越薄，越是正面顶上去。

### 性能：接触宽度是惰性的，应力场可以整体关掉

`contact_width` 是**沿切向逐像素数**出来的（不能用 AABB 近似 —— 那样看不出矛是尖的），
`shear_ratio` 还要再做两次 `Query.thickness_at`。这两样是接触事件里**最贵**的部分。
实测（`tests/bench_contact_light.gd`：120 个方块落在地面上，62 接触/步）：

| 你要什么 | 怎么配 | 每接触代价 |
|---|---|---|
| 撞了什么 / 撞在哪 / 撞得多猛 | `contact_events_enabled = true` + `contact_stress_enabled = false` | **~22 µs** |
| 还要 σ = 冲量 / 宽度 | 同上，但 `contact_stress_enabled` 保持默认 `true`；宽度**读它的时候**才算 | ~185 µs（读宽度 ~77 + 两次厚度 ~108）|
| 连事件都不要 | 查询路径 `contact_pair_count()` / `contact_info(i)`（**不用开事件**）| 0 |

- **`Contact.contact_width` 是惰性的**：不读不算，第一次读之后缓存 ——
  所以"只用冲量做判据"的代码不会为它付钱（轻量模式下再读它，照样算得出来）。
- **`contact_stress_enabled = false`（轻量模式）**：点/法向/接近速度/冲量一个不少，
  但 `shear_ratio` 恒为 0 —— 上面那半条"抗压远强于抗剪"的判据会失效
  （`strength_for` 退化成纯抗压强度）。要那半个判据就别关。
- **查询路径也是"一次往返"**：`contact_info(i)` / `contact_points(i)` 取一对接触只发
  **一次**原生调用（op 35 的 cap 拿上一次的点数当猜值，猜错也只是退回两步，数据不受影响）。
  实测一次 `_rp_send` ≈ **2.8 µs**，而每对接触**每子步**都要取一次 —— 子步多的场景
  这个乘数是子步数（29 子步 x 25 对 = 725 次/步 ≈ 2 ms/步）。

## 蓝图：画完先不固化

游戏层「画一笔」不应该立刻变成物理实体。蓝图就是这个中间态：

```gdscript
renderer.sync_blueprint(id, shape, xform)   # 半透明显示，不参与物理
renderer.forget_blueprint(id)
renderer.clear_blueprints()

# 玩家按下"固化"
world.add_body(body, shape)
renderer.forget_blueprint(id)
```

蓝图**不在 `world.bodies` 里** —— 宽相扫不到、不受重力、不被破坏。
所以画 100 笔不固化的成本 = 100 次形状编辑；固化才建刚体。

## 体素尺寸（`PixelWorld.voxel_size`）

**编辑器里就能调**（Inspector 的"观感"组，1~32，默认 3）—— 运行时改也立刻生效
（Demo 里 `-` / `=` / `0`）。它**只影响"一个体素画多大"**：物理、破坏、笔刷、质量
全部以**体素**为单位，改它不会牵动重力、速度、质量。

节点是**唯一真相源**：改它会同时播到相机取景和渲染贴图（[`pixel_world.gd`](../../src/nodes/pixel_world.gd)）。

## 物理与破坏旋钮（Inspector 里可调）

`PixelWorld` 把这些旋钮**导出**了，编辑器里就能改（"物理"/"破坏"两个组）；
`rebuild()` 与 `push_physics_settings()` 会播到 `PWorld`。

| 导出 | 作用 | 默认 |
|---|---|---|
| `gravity` / `fixed_dt` / `max_substeps` / `sleeping` | 基本物理 | |
| `terminal_speed` | 终端速度（只钳下落分量）| 650 |
| `max_linear_velocity` | 线速度上限（0 = 不钳）| 40000 |
| `max_angular_velocity` | 角速度上限 rad/s（0 = 不钳）| 1000 |
| `ccd_ignore_mass` | 轻碎片豁免子步估计（0 = 关）| 0 |
| `min_fragment_pixels` | 碎片小于这么多像素就丢掉 | 4 |
| `debris_max_mass` | 灰尘清理**总开关**（质量 <= 它）| 0（关）|
| `debris_min_speed` | > 0 = 只清"正在飞的"；**0 = 不限速度** | 0 |

⚠️ **改了就生效**：每个导出的 setter 会**立刻播到 `world`**（不需要手动 push）。
`push_physics_settings()` 只在两种情况下需要：① `rebuild()` 之后；② 你自己把 `world` 换掉之后。
**别为改一个阈值去调 `rebuild()`** —— 那会重建世界、把破坏状态全丢掉。

⚠️ 灰尘策略（`debris_*` / `ccd_ignore_mass`）会**改变内容**（碎片凭空消失 / 穿墙），
所以默认全关 —— 开之前先读[性能手册](performance.md)的"灰尘策略"那一节。

⚠️ **质量 = 像素数 x 材质密度**（4x4 的碎片在密度 2.5 下是 **40**）—— 阈值要比你实际的碎片质量
大才清得掉；**静止的碎片运动恒为 0**，所以想清躺着的必须把 `debris_min_speed` 设成 0。

## 相机与 UI

**引擎不封装这两者**，直接用内置的：

```gdscript
# 相机取景 = 体素尺寸 x 分辨率补偿（相机所在视口高度 / 540）
camera.zoom = Vector2.ONE * PixelScale.get_scale() * PixelScale.render_scale(camera)
```

> ⚠️ `render_scale()` 取的是**相机所在视口**的高度，不是窗口高度。
> 像素风常见做法是"小视口渲染 -> 放大贴屏"（相机挂在 SubViewport 里）——
> 那时窗口 1080p、相机视口 540p，拿窗口算会让取景差一倍。

### 游戏取景范围（和分辨率无关）

```text
zoom     = voxel_size * render_scale = voxel_size * (视口高 / 540)
可见高度 = 视口高 / zoom = 540 / voxel_size
可见宽度 = 可见高度 x 项目宽高比
```

所以 **1080p 和 720p 看到的范围完全一样**（只是每体素占的屏幕像素不同）。
体素 3、项目 1920x1080 时：**320 x 180 世界单位**。

> ⚠️ Godot 编辑器自带的相机框按**编辑器面板**的大小画：面板一拉，框的世界范围就变，
> 面板不是 16:9 时形状也不对 —— 所以别拿它当"游戏里能看到多少"的依据。
> `PixelWorld` 在**编辑器里**会画一个青色"游戏取景框"（按项目分辨率算，和实际游戏一致；
> 游戏里不画）。

UI 用原生 `Control` + `Theme`。引擎只暴露**数据**
（`px.momentum(body)`、`px.total_kinetic_energy()` 等），UI 去读。

## 预引用：`@onready` 直接拿 PBody

```gdscript
@onready var body = $Placed.body        # 就这一句，不用等帧、不用 find
```

⚠️ 以前不行：`body` 只是"运行时才有值的普通字段"，而 Godot 的 `_ready` 是**子节点先、
父节点后**，`PixelWorld` 又是在自己的 `_ready` 里才烘焙 —— 子脚本里读到的是 `null`，
只能 `await get_tree().process_frame` 或者自己 `find_children` 找一遍。

现在 `body` 是**访问时按需烘焙**（幂等，走 `PixelWorld.add_body_node`）：
不管 `_ready` 顺序、不管世界建没建好，第一次读就能拿到东西；编辑器里读也会烘。

想在 Inspector 里"拖一个刚体进来"，导出**节点**（`PBody` 是 RefCounted，`@export` 不支持）：

```gdscript
@export var body_node: PixelBody2D

func _ready() -> void:
    var body = body_node.body          # 拖节点 -> 拿 PBody
```

契约由 [`tests/validation_preref.gd`](../../tests/validation_preref.gd) 钉住：探针挂在
`PixelWorld` 下面（它的 `_ready` 一定早于世界的烘焙），在里面读 `.body` 必须拿到
**世界里的那个刚体**，而且世界不会被二次重建把引用作废。


## 节点摆的 + 代码生成的，可以共存

两条路落在**同一个 world** 上，互不打扰：

```gdscript
# ① 编辑器里摆的：PixelBody2D 挂在 PixelWorld 下面，rebuild() 时烘焙（只烘一次）

# ② 运行时用代码加一个（增量，不重建世界）
var node := PixelBody2D.new()
node.position = Vector2(160, 40)
node.rect_size = Vector2i(16, 16)
pw.add_child(node)              # 必须是 PixelWorld 的子节点
var body = pw.add_body_node(node)
```

> ⚠️ **加完运行时刚体后不要调 `rebuild()`** —— 它会 `PWorld.new()` 造一个**全新的世界**：
> 运行时加的全没了、破坏状态（碎块/擦除）也全没了。`add_body_node()` /
> `remove_body_node()` 这两个增量 API 就是为这件事存在的。

契约由 [`tests/validation_mixed_bodies.gd`](../../tests/validation_mixed_bodies.gd) 钉住：
代码加进去时**节点那个 body 对象必须还是同一个**（= 没重建世界）、两者质量一致、
一起落地一起睡、运行时加的不会被清掉。

（门面版 `PixelPhysics`（`spawn_box` 等）在 **addon** 里：`tools/build_addon.py` 生成到
`addons/pixel_destruction/`，刻意不常驻项目树 —— 否则编辑器会报 class_name 重名。）


## 编辑器里能做什么

| 操作 | 结果 |
|---|---|
| 拖动 `PixelBody2D` | 实时重烘焙，像素与碰撞箱一起动 |
| 缩放手柄 | **按比例重新生成形状**（不是把贴图拉大 —— 物理要整数体素） |
| 旋转 | 形状随刚体旋转（像素格相对刚体倾斜） |
| 改 `PixelShape2D` 的属性 | 立即生效 |
| 加/删形状子节点 | 立即生效，可组合 |
| `PixelJoint2D` | 拖节点 = 拖支点；改参数立即生效（见上一节） |；拖动会**增量重烘焙这一个关节**（摘掉旧的、按新位置重建，不重建整个世界）
| `DebugOverlay` | 画 OBB / 接触点 / 速度矢量 / 角速度 / 统计（见下一节） |

> ⚠️ 编辑器里**不跑物理**。物体不会自己掉下去，按 F5 运行才进物理。

## 调试可视化：两套颜色，别搞混

### 1) 编辑器抓手（只在编辑器里画，运行时看不到）

| 看到什么 | 是什么 |
|---|---|
| **蓝色框** | `is_static = true` 的刚体（地面、墙、锚点柱） |
| **绿色框** | **动态**刚体（箱子、桥板、碎块） |
| 框本身 | 形状的**凸包**（多边形碰撞箱拟合）—— 所有形状子节点的并集，**不是碰撞体**。规则轮廓（RECT）下它就是那个矩形；不规则轮廓（TEXTURE/PAINT）下比外接矩形紧得多 |
| 左上角小圆点 | 形状原点（局部 `(0,0)`，全项目约定"原点=左上角"） |
| 圆盘形状 | 画的是**圆**（画外接矩形会让人以为"球变成了四边形"） |

### 2) 运行时调试叠加层 `DebugOverlay`（Demo 里 **D** 键开关）

画的全是**世界坐标**，跟着相机走：

| 画的东西 | 颜色 | 表示什么 | 开关 |
|---|---|---|---|
| **碰撞矩形（OBB）** | 青 = **清醒**，灰 = **休眠** | 物理真正用的形状（贪心矩形分解结果），四边形所以跟着刚体转 | `show_obbs` |
| AABB | 半透明灰 | 宽相用的粗包围盒，**不随旋转** | `show_aabbs` |
| **凸包** | 黄 | **与 AABB 并列**的另一种包围体：跟着刚体转，所以紧（凹角会被填平 —— 它是包围体，不是碰撞体） | `show_hulls` |
| 扫掠 AABB | 半透明橙 | 含**本步位移**（CCD / 推测接触用） | `show_swept_aabbs` |
| 接触点 + 法向 | 红 | 点 = 接触位置；线 = 法向（由 A 指向 B） | `show_contacts` |
| 线速度矢量 | 绿 | 从质心出发，长度 = 速度 x `velocity_scale` | `show_velocity` |
| 角速度弧线 | 黄 | 半径随角速度大小，绕向 = 转向 | `show_angular` |
| 质心 | 白十字 | 只画动态体 | `show_com` |
| 刚体 id | 同 OBB 色 | 数字，画在刚体原点 | `show_ids` |
| 左上角统计 | 白 | 刚体数（动态/清醒/休眠）、流形数、接触点数、子步数、总动量/总角动量/总动能 | `show_stats` |

> ⚠️ 叠加层的线宽按**相机 zoom 反算成"屏幕 1 像素"**（`_screen_unit()`）。
> 不反算的话 1.0 世界单位在 zoom 6 下是 6 屏幕像素，而线是**以边界为中心**画的 ——
> 看起来就是"碰撞框比像素图大一圈"（实测：墙的像素在 x=948..1667、叠加层外沿在 x=945..1670，
> 正好各多 3 px = 半个线宽）。改细之后还必须画在**像素精灵之上**（`z_index`），
> 否则 1 px 的线有一半被精灵盖掉，看起来像"叠加层消失了"。

## 渲染归属：谁画这个刚体

内部渲染器（`PixelRenderer`）只画**该由它画**的刚体。判据只有一个：
`PixelWorld.uses_internal_render(node)`，四条同步路径共用（`rebuild` / `bake_node` /
每帧的 `_physics_process` / 破坏后的 `sync_world_bodies`）。

| 刚体 | 谁画 | 怎么配 |
|---|---|---|
| 普通刚体 | 内部渲染器 | 默认 |
| 有自定义视觉（子节点 `PixelSprite2D`、自绘 `Polygon2D`） | **它自己** | 挂 `PixelSprite2D` 即可（引擎自动让位）|
| 不该被看见（玩家内部的"手/臂"：只有碰撞和骨骼） | **谁也不画** | `PixelBody2D.internal_render = false` |
| 破坏产生的碎片 | 内部渲染器 | 它们没有节点，自动归内部渲染器 |

两条"不要画"的理由**任一成立**就不画；刚体**后来**才拿到自有视觉（或改成 `internal_render=false`）时，
**下一次同步就会把旧贴图回收**（`renderer.forget`）—— 所以"破坏之后调一次 `sync_world_bodies()`"
不会给它补出一张矩形残影。

> ⚠️ 为什么这条要单独写：以前只有 `rebuild` / `add_body_node` 过滤，**每帧同步**和**破坏后的同步**
> 不过滤 —— 症状是破坏瞬间多出一张**矩形手**，而且它**停在旧位置**（游戏层跳过自有视觉的同步，
> 那张矩形就永远留在原地）。闸门：`tests/validation_node_render_policy.gd`（18 项）。
>
> ⚠️ `internal_render = false` 只影响**画**：像素照样参与物理、破坏、质量、连通性，
> 刚体也不会被摘出世界。它的用途是"不可见的臂/手"，**不是**"隐藏物体"（要隐藏用 `visible` 或层级）。

## 破坏之后：节点层怎么跟世界对齐

破坏（`fracture` / `detach` / `fracture_pixels`）会**增删刚体**：碎片是新刚体、被全删的刚体消失。
节点层有两件事必须跟着做，否则症状是"碎片没有贴图""消失的刚体留下悬空引用""关节指向不存在的刚体"。

### `physics_step_finished(world)`

**每个固定步**走完时发出。信号发在 `_physics_process` 的 while 循环**内部**，所以三条契约是
**按构造成立**的，不靠调用方自觉：

1. **恰好一次** —— 一帧补多个 step 就发多次，不漏不重；
2. **零 step 帧不发**；
3. **同步回调** —— 这里读到的 `world.contacts` 是**本次 step 的完整结果**，可以当场提交破坏。

```gdscript
func _ready() -> void:
    $PixelWorld.physics_step_finished.connect(_on_step)

func _on_step(w) -> void:
    # 游戏规则在这里读接触数据、算删除计划、提交破坏
    for i in w.contact_pair_count():
        var info: Dictionary = w.contact_info(i)
        # ...
```

⚠️ 一帧可能补多个 step，所以**不要**在 `_process` 里读接触 —— 那样会漏掉中间的步。

### `sync_world_bodies()`

破坏之后把节点层与 `world.bodies` 对齐：

- **按下标重建 `_body_nodes`**，碎片/未节点化的刚体用 **null 占位**（**不删项** —— 删了会让下标整体错位，
  症状是"节点索引串位"）；
- **全量 `renderer.sync`（含静态地形）** —— 每帧的自动同步只同步动态体（静态体像素不变、sync 又贵），
  但破坏之后静态地形的像素**真的变了**。⚠️ **自带视觉 / `internal_render=false` 的刚体除外**：
  它们不画，而且会在这里把**以前画出来的**旧贴图回收（见下"渲染归属"）；
- `renderer.prune(...)` 清掉已经不存在的刚体；
- **清掉锚点已不存在的关节** —— ⚠️ `body_a`/`body_b` 为 `null` 表示"锚在静态世界"，
  那是**合法**的，必须保留。

### `sync_body_nodes() -> bool`

**按版本号**检查并对齐 `_body_nodes`（返回是否真的对齐了）—— 只在刚体增删过时才付 O(n)，
平时只是一次整数比较。

⚠️ `PixelWorld._physics_process` 每帧会调它，所以**正常项目不用管**。
但**自己驱动步进的项目必须自己每帧调一次**：那种项目通常会 `set_physics_process(false)`
（避免同一帧推进两次），于是节点自己的每帧钩子**不会跑**，自动对齐也就失效了。

```gdscript
func _physics_process(delta):
    _main.sync_body_nodes()      # 放在渲染同步之前
    # ... 你自己的子步循环 + 渲染同步
```

⚠️ 为什么需要它：`_body_nodes` 与 `world.bodies` 有一条**硬不变量**（按下标一一对应），
而任何**绕过节点层**增删刚体的路径都会破坏它（直接 `fracture_pixels`、门面 `spawn_*`、
灰尘策略的 `remove_body`、调试脚本的 `add_body`）。破坏后的症状**不是报错**：
数组**变短**时"按下标取节点"的消费方（渲染同步循环）越界中断，那之后的刚体（通常正是
新碎片）这一帧不再被 `sync`，贴图停在旧位姿 = "碎片渲染位置偏差"；数组**变长**时静默错位，
`has_own_sprite` 会去问**别人的节点**。

### `fracture_pixels_and_sync(body, removals, burst_speed := 0.0, dynamic_fragments := false, static_anchors := {})`

`world.fracture_pixels(...)` + `sync_world_bodies()` 一步到位 —— **推荐用这个**，
忘了调同步的症状是"碎片没有贴图"。

```gdscript
# removals = {PixelShape: {Vector2i: true}}（该 shape 的局部像素坐标）
var res: Dictionary = px.fracture_pixels_and_sync(body, {body.shapes[0]: mask})
# res = {removed: int, body_alive: bool, fragments: Array}
```

#### 可破坏钉子

`static_anchors` 与 `removals` 使用相同格式：`{PixelShape: {Vector2i: true}}`。坐标指向
固定该刚体的钉子像素。传入非空字典后，钉子决定分片是否静态，像素数量只决定哪个分片
继承原 PBody：

```gdscript
var shape = body.shapes[0]
var nail := Vector2i(5, 1)
var result := px.fracture_pixels_and_sync(
    body,
    {shape: pixels_to_remove},
    0.0,
    true,
    {shape: {nail: true}},
)
```

- 分裂后含至少一个存活钉子的连通分量保持 `static`；
- 不含钉子的分量成为动态体；
- 钉子坐标也在本次删除掩码中时，钉子先被删除，该分量立即失去 `static`；
- 多个钉子可以固定多个分量；最大的含钉子分量继承原 PBody，其余含钉子分量生成新的
  static PBody；
- 不传 `static_anchors` 时完全保留旧规则，`dynamic_fragments` 仍只决定静态母体的脱落碎片
  是否转为动态。

这一步复用破坏已经得到的连通分量，只对已知钉子坐标做块查询，不会再次 flood fill。
主要开销仍是原有的分裂、碰撞矩形和质量重建。钉子破坏后若巨大地形整体动态化，质量计算
和后续刚体求解本身仍可能昂贵，应通过地图分块限制单体尺寸。
