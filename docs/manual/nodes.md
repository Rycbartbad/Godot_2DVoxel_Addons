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

## 材质是资源

`PixelMaterial` 是一个 `Resource`：颜色 / 密度 / 抗压 / 抗剪在**同一个资源**里。

```
materials/
  stone.tres    石头  密度 2.5   抗压 40
  wood.tres     木头  密度 0.6   抗压 14
  metal.tres    铁    密度 7.8   抗压 120
  brick.tres    砖    密度 2.0   抗压 20
```

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

## 相机与 UI

**引擎不封装这两者**，直接用内置的：

```gdscript
# 相机取景 = 体素尺寸 x 分辨率补偿（相机所在视口高度 / 540）
camera.zoom = Vector2.ONE * PixelScale.get_scale() * PixelScale.render_scale(camera)
```

> ⚠️ `render_scale()` 取的是**相机所在视口**的高度，不是窗口高度。
> 像素风常见做法是"小视口渲染 -> 放大贴屏"（相机挂在 SubViewport 里）——
> 那时窗口 1080p、相机视口 540p，拿窗口算会让取景差一倍。

UI 用原生 `Control` + `Theme`。引擎只暴露**数据**
（`px.momentum(body)`、`px.total_kinetic_energy()` 等），UI 去读。

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
| 框本身 | 形状的**外接矩形** —— 所有形状子节点的并集，不是碰撞体 |
| 左上角小圆点 | 形状原点（局部 `(0,0)`，全项目约定"原点=左上角"） |
| 圆盘形状 | 画的是**圆**（画外接矩形会让人以为"球变成了四边形"） |

### 2) 运行时调试叠加层 `DebugOverlay`（Demo 里 **D** 键开关）

画的全是**世界坐标**，跟着相机走：

| 画的东西 | 颜色 | 表示什么 | 开关 |
|---|---|---|---|
| **碰撞矩形（OBB）** | 青 = **清醒**，灰 = **休眠** | 物理真正用的形状（贪心矩形分解结果），四边形所以跟着刚体转 | `show_obbs` |
| AABB | 半透明灰 | 宽相用的粗包围盒，**不随旋转** | `show_aabbs` |
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
