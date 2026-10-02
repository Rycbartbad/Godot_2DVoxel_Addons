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

## 相机与 UI

**引擎不封装这两者**，直接用内置的：

```gdscript
camera.zoom = Vector2.ONE * PixelScale.get_scale() * PixelScale.render_scale()
```

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
| `DebugOverlay` | 画 OBB / 接触点 / 速度矢量 / 角速度 / 统计 |

> ⚠️ 编辑器里**不跑物理**。物体不会自己掉下去，按 F5 运行才进物理。
