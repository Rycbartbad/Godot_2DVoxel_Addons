# API 对照与缺口清单

参考 API 来自 `docs/teardown_api_research/`（Teardown 官方 609 个函数，按 26 个分类组织）。
本引擎是 **2D**，所以只对照与物理相关的四类：**Entity / Body / Shape / Scene queries**，
外加 Joint。其余分类（Vehicle / Water / Light / Screen / Trigger / Animation / Player / UI / Sound）
不在范围内。

> **命名约定**：本引擎**不照搬参考 API 的名字**。下面左列是参考名（便于查原文档），
> 右列是本引擎的等价物，一律 snake_case、与引擎其它部分一致。
> 语义对齐、命名自持 —— 这样"对着参考文档查功能"和"读自己的代码"都顺。

图例：`✓` 已有 · `+` 本轮补齐 · `✗` 缺失（见文末优先级） · `—` 2D 不适用

---

## Entity（16）

| 参考 API | 本引擎 | |
|---|---|---|
| `FindEntity(tag, global?, type?)` | `PWorld.find_body(tag)` | + |
| `FindEntities(tag, global?, type?)` | `PWorld.find_bodies(tag)` | + |
| `GetEntityChildren / GetEntityParent` | — | ✗ 没有实体层级 |
| `SetTag(handle, tag, value?)` | `PBody.tags[tag] = value` | + |
| `RemoveTag / HasTag / GetTagValue / ListTags` | `PBody.tags` 直接读写 | + |
| `GetDescription / SetDescription` | `PBody.description` | + |
| `Delete(handle)` | `PWorld.remove_body(body)` / `PixelPhysics.despawn` | ✓ |
| `IsHandleValid(handle)` | `world.bodies.has(body)` | ✓ |
| `GetEntityType(handle)` | `is PBody` / `is PixelShape` | ✓ |
| `GetProperty / SetProperty` | `PBody.get_prop / set_prop` | ✗ 见文末 |
| `GetWorldBody()` | — | — 2D 无世界刚体 |

## Body（33）

| 参考 API | 本引擎 | |
|---|---|---|
| `FindBody / FindBodies` | `PWorld.find_body / find_bodies` | + |
| `GetBodyTransform / SetBodyTransform` | `PBody.position / rotation`（`Transform2D` 可自行组装） | ✓ |
| `GetBodyMass` | `PBody.mass` | ✓ |
| `IsBodyDynamic / SetBodyDynamic` | `PBody.is_static` / `make_static / make_dynamic` | ✓ |
| `SetBodyVelocity / GetBodyVelocity` | `PBody.linear_velocity` | ✓ |
| `GetBodyVelocityAtPos` | `PBody.velocity_at(p)` | ✓ |
| `SetBodyAngularVelocity / GetBodyAngularVelocity` | `PBody.angular_velocity` | ✓ |
| `SetBodyGravityScale` | `PBody.gravity_scale` | + |
| `IsBodyActive / SetBodyActive` | `PBody.awake` | ✓ |
| `ApplyBodyImpulse(handle, position, impulse)` | `PBody.apply_impulse(impulse, position)` | ✓ |
| `GetBodyShapes` | `PBody.shapes` | ✓ |
| `GetBodyBounds` | `PBody.aabb` | ✓ |
| `GetBodyCenterOfMass` | `PBody.com_world()` | ✓ |
| `IsBodyBroken` | `PixelPhysics.is_broken(body)` | + |
| `IsBodyJointedToStatic` | — | ✗ 无关节系统 |
| `GetBodyClosestPoint(body, origin)` | `PixelPhysics.raycast` / `closest_point` | ✓ |
| `GetBodyVehicle / GetBodyAnimator / GetBodyPlayer` | — | — 无对应子系统 |
| `IsBodyVisible / DrawBodyOutline / DrawBodyHighlight` | — | — 属渲染层，不在引擎内 |
| `ConstrainVelocity / ConstrainAngularVelocity / ConstrainPosition / ConstrainOrientation` | `PWorld.grab`（只有一种约束） | ✗ 见文末 |

## Shape（40）

| 参考 API | 本引擎 | |
|---|---|---|
| `FindShape / FindShapes` | `PWorld.find_shapes(tag)` | + |
| `GetShapeBody / SetShapeBody` | `PixelShape.owner_body` / `ShapeOps.attach_to` | + |
| `GetShapeLocalTransform / SetShapeLocalTransform` | — | — 形状没有独立局部变换（见下） |
| `GetShapeWorldTransform` | `ShapeOps.world_transform(shape)` | + |
| `GetShapeBounds / GetShapeSize / GetShapeVoxelCount` | `local_aabb() / .size / pixel_count()` | ✓ |
| `SetShapeDensity` | `ShapeOps.set_density` / `PixelShape.density_scale` | + |
| `GetShapeMaterialAtPosition(handle, pos)` | `ShapeOps.material_at_position(shape, world_point)` | + |
| `GetShapeMaterialAtIndex(handle, x, y, z)` | `PixelShape.get_pixel(x, y)` | + |
| `GetShapePalette / GetShapeMaterial` | `PixelRenderer.palette`（颜色归渲染层） | ✓ |
| `CreateShape(body, transform, refShape)` | `ShapeOps.create(body, ref)` | + |
| `ClearShape` | `ShapeOps.clear` | + |
| `CopyShapeContent / CopyShapePalette` | `ShapeOps.copy_content` / `union_into` | + |
| `SplitShape(shape, removeResidual)` | `ShapeOps.split(shape)` | + |
| `MergeShape(shape)` | `ShapeOps.merge(shape)` | + |
| `IsShapeDisconnected` | `ShapeOps.is_disconnected` | + |
| `IsShapeTouching(a, b)` | `ShapeOps.is_touching(a, b)` | + |
| `GetShapeClosestPoint(shape, origin)` | `ShapeOps.closest_point(shape, world_point)` | + |
| `DrawShapeBox` | `ShapeOps.draw_box(shape, rect, material)` | + |
| `DrawShapeLine` | `Brush.stroke_circle` / `stamp_circle` | ✓ 部分 |
| `SetBrush` | `Brush` 是无状态静态函数，没有全局笔刷 | ✗ 见文末 |
| `ResizeShape(shape, ...)` | — | ✗ |
| `TrimShape / ExtrudeShape` | — | — 3D 挤出 |
| `SetShapeCollisionFilter / GetShapeCollisionFilter` | — | ✗ 见文末 |
| `SetShapeEmissiveScale` | — | — 渲染层 |
| `IsShapeVisible / IsShapeBroken` | `PixelPhysics.is_broken(body)` | ✓ 部分 |
| `IsStaticShapeDetached` | — | ✗ |

## Scene queries（28）

| 参考 API | 本引擎 | |
|---|---|---|
| `QueryRaycast(origin, dir, maxDist, radius?)` | `Query.raycast` / `PixelPhysics.raycast` | + **像素级精确** |
| `QueryClosestPoint(origin, maxDist)` | `Query.closest_point` | + |
| `QueryAabbBodies(min, max)` | `Query.aabb_bodies` / `PWorld.bodies_in` | + |
| `QueryAabbShapes(min, max)` | `Query.aabb_shapes` | + |
| `QueryRejectBody / QueryRejectBodies` | `Query.reject_body` / `PixelPhysics.query_reject_body` | + |
| `QueryRequire / QueryInclude / QueryCollisionMask` | — | ✗ 依赖碰撞层 |
| `QueryRejectShape / QueryRejectShapes / QueryRejectAnimator / QueryRejectVehicle / QueryRejectPlayer` | — | — 无对应子系统 |
| `QueryShot` | `Query.raycast` 自己组合伤害即可 | ✓ 部分 |
| `QueryRaycastRope / QueryRaycastWater` | — | — 无绳索/水 |
| `QueryPath / CreatePathPlanner / ...` | — | ✗ 寻路，不在物理引擎范围 |
| `GetLastSound / IsPointInWater / GetWindVelocity` | — | — 无对应子系统 |

## Joint（16）

**整类缺失。** 本引擎只有一种约束：`Grab`（鼠标关节，速度层）。
参考 API 里的 `SetJointMotor / SetJointMotorTarget / GetJointLimits / GetJointMovement /
GetJointedBodies / DetachJointFromShape` 以及绳索那一组（`GetRopeNumberOfPoints /
GetRopePointPosition / BreakRope`）都没有对应实现。

---

## 本轮补的东西

| 能力 | 落点 | 说明 |
|---|---|---|
| **像素级射线** | `src/physics/query.gd` | 走体素 DDA，**能穿过像素画的空洞**；不是拿 OBB 近似。radius>0 走扫掠圆 |
| **最近点 / AABB 查询 / 查询排除** | 同上 | |
| **标签查询** | `PBody.tags` + `PWorld.find_body/find_bodies/find_shapes` | 游戏逻辑不必自己维护 id 表 |
| **重力缩放** | `PBody.gravity_scale` | 0 = 失重，负数 = 反重力 |
| **形状操作** | `src/core/shape_ops.gd` | 创建/清空/复制/并集/切分/合并/相邻/最近点/材质/密度 |
| **形状→刚体反向引用** | `PixelShape.owner_body` | |
| **形状级密度** | `PixelShape.density_scale` | 质量 = Σ 材质密度 x density_scale |
| **门面统一入口** | `pixel_physics.gd` | 上面全部都有 snake_case 的转发 |

补的过程中**测试抓出两个真 bug**（都已修，见开发日志坑 38）：
`PixelShape.translate_pixels` 把像素位移加在了 chunk 坐标上（差 8 倍）；
`ShapeOps.merge` 用了替换语义的 `copy_content` 导致合并后原像素全丢。

---

## 仍然缺的（按建议优先级）

1. **碰撞层与掩码**（`SetShapeCollisionFilter` / `QueryRequire` 那一组）
   影响：做不出"子弹不打自己人""查询只测地形"这类常见需求。
   代价：要动宽相（配对阶段过滤），有基准风险。
2. **通用约束**（`ConstrainPosition / ConstrainVelocity / ConstrainOrientation / ConstrainAngularVelocity`）
   影响：这是"可编程关节"的通用形式，`Grab` 只是它的一个特例。
   代价：要在求解器里加一类约束通道。
3. **关节系统**（Joint 整类）
   影响：铰链/滑轨/绳索。破坏类游戏很常用（吊桥、绳索、机械）。
   代价：最大的一块，且和 CCD/休眠的交互需要重新验证。
4. **`GetProperty / SetProperty` 的通用属性访问**
   影响：数据驱动的关卡逻辑（从表里读属性批量设置）。
   代价：小。
5. **`ResizeShape` / `SetBrush`（全局笔刷状态）**
   影响：小，属于编辑便利。

## 刻意不做的

- **形状的独立局部变换**：参考 API 里形状可以相对刚体偏移旋转。本引擎把像素直接放在刚体局部空间，
  简化了一大类坐标转换（也避免"形状变换 vs 刚体变换"两处真相）。要加的话是引擎级改动。
- **3D 专属**：`ExtrudeShape / TrimShape`、`Quat` 全系列、`GetShapeMaterialAtIndex` 的 z 轴。
- **渲染/表现层**：`DrawBodyOutline / SetShapeEmissiveScale / IsBodyVisible` 等 ——
  本引擎把渲染隔离在 `render/pixel_renderer.gd` 一个模块里，物理层不认识"可见"。
