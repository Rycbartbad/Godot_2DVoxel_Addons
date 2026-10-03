# API 对照与缺口清单

参考 API 来自 Teardown 官方文档（609 个函数，按 26 个分类组织）。

> ⚠️ 那些文档是**第三方材料**，不随本仓库分发（见 `.gitignore`）——
> 本文只做**对照与缺口分析**，不复制原文。要查原始定义请到官方渠道获取。
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
| `IsBodyJointedToStatic` | `PWorld.is_jointed_to_static(body)` | + 走关节图（直接或间接连到静态世界） |
| `GetBodyClosestPoint(body, origin)` | `PixelPhysics.raycast` / `closest_point` | ✓ |
| `GetBodyVehicle / GetBodyAnimator / GetBodyPlayer` | — | — 无对应子系统 |
| `IsBodyVisible / DrawBodyOutline / DrawBodyHighlight` | — | — 属渲染层，不在引擎内 |
| `ConstrainVelocity / ConstrainAngularVelocity / ConstrainPosition / ConstrainOrientation` | — | ✗ 见文末（**关节**已做，见 Joint 一节；这里缺的是「任意自由度 + 目标值 + 限幅」的通用形式） |

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
| `SetShapeCollisionFilter / GetShapeCollisionFilter` | `PBody.collision_layer / collision_mask` | + **刚体级**（形状级仍缺，见文末） |
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
| `QueryRequire / QueryInclude / QueryCollisionMask` | `Query.require(mask) / include(mask)` | + 位掩码版（参考 API 的字符串层名是它自己的分层，本引擎用位） |
| `QueryRejectShape / QueryRejectShapes / QueryRejectAnimator / QueryRejectVehicle / QueryRejectPlayer` | — | — 无对应子系统 |
| `QueryShot` | `Query.raycast` 自己组合伤害即可 | ✓ 部分 |
| `QueryRaycastRope / QueryRaycastWater` | — | — 无绳索/水 |
| `QueryPath / CreatePathPlanner / ...` | — | ✗ 寻路，不在物理引擎范围 |
| `GetLastSound / IsPointInWater / GetWindVelocity` | — | — 无对应子系统 |

## Joint（16）

**本轮补齐。** 五种关节，求解在 Rapier 的**冲量关节**（ImpulseJoint）里：

| 参考 API | 本引擎 | |
|---|---|---|
| （ball / hinge joint） | `PWorld.add_hinge(a, b, anchor)` | + 只剩一个转动自由度 |
| （prismatic joint） | `PWorld.add_slider(a, b, anchor, axis)` | + 只剩沿轴平移 |
| （stiff joint） | `PWorld.add_weld(a, b, anchor)` | + 完全锁死 |
| （rope） | `PWorld.add_rope(a, b, anchor_a, anchor_b, max_len)` | + 只限制**最大**距离 |
| （spring joint） | `PWorld.add_spring(a, b, anchor_a, anchor_b, rest, k, c)` | + 拉向静止长度 |
| `SetJointMotor(joint, velocity, strength)` | `PJoint.set_motor_velocity(v, max_force)` | + strength 0 = 禁用 |
| `SetJointMotorTarget(joint, target, maxVel, strength)` | `PJoint.set_motor_target(t, max_force)` | + 位置/角度伺服 |
| `GetJointLimits(joint)` | `PJoint.min_limit / max_limit` | + |
| （限位设置） | `PJoint.set_limits / clear_limits` | + 铰链是角度，滑轨是距离 |
| `GetJointMovement(joint)` | `PJoint.movement()` | + 角度 / 距离 |
| （运动速率） | `PJoint.speed()` | + 角速度 / 沿轴速度 |
| `IsJointBroken(joint)` | `PJoint.is_broken()` + `break_impulse` | + **自己判**：约束冲量超阈值就断（Rapier 没有断裂概念） |
| `DetachJointFromShape(joint, shape)` | `PWorld.remove_joint(j)` / `PJoint.remove()` | ✓ 整条关节（没有「从某一侧解绑」的半边形式） |
| `GetJointedBodies(joint)` | `PJoint.body_a / body_b`；`PWorld.joints_of(body)` | + |
| `Body:SetMass` / `Body:SetDensity` | `PWorld.set_material_density(material, d)` -> `PBody.density`（平均密度）-> op 34 `rb_body_set_density` | + 按材质给密度，质量自动随破坏增减 |
| （参考 API 没有这一项） | `PJoint.contacts_enabled` | + **默认 false**：被关节连着的两个刚体之间不生成接触（否则体素重合时会一直抽搐） |
| `GetRopeNumberOfPoints / GetRopePointPosition / BreakRope` | — | ✗ 绳索**解算**（多段绳）没做：`add_rope` 是两点距离约束 |

`Grab` 仍然在，但它已经**不是求解器约束** —— 它是每子步算一个限力的策略层
（见 `src/physics/grab.gd` 的说明）。

**设计要点**（三条都是实测踩出来的，细节见 `docs/development_log.md`）：

- **关节帧按创建时的相对位姿设零**：否则铰链的角度不从 0 起算，焊接会把两个
  各自转过的刚体硬拧到同一个朝向。
  （Rapier 的 builder 默认给的是单位旋转。）
- **滑轨的轴按世界系传**，两端各自转到自己的局部系；照抄 `PrismaticJoint::new(axis)`
  会给两边同一个局部轴，朝向不同时求解器当场把它们拧平行。
- **断裂判据取线性冲量**：挂着东西的铰链，载荷几乎全在「锁住锚点」的那两根
  线性自由度上，而自由转动的那一行恒为 0。

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
| **关节（5 种 + 限位 + 马达 + 断裂）** | `src/physics/joint.gd` + `PWorld.add_*` | 铰链/滑轨/焊接/绳/弹簧；求解在 Rapier 的 ImpulseJoint 里 |
| **静态锚定判定** | `PWorld.is_jointed_to_static(body)` | 沿关节图走（直接或间接连到静态世界） |
| **碰撞层与掩码** | `PBody.collision_layer / collision_mask` | 映射到 Rapier 的 InteractionGroups；**双向判据**（双方都得同意） |
| **查询层过滤** | `Query.require / include` | 单向判据：刚体的层与要求的层有交集才被看见 |

补的过程中**测试抓出两个真 bug**（都已修，见开发日志坑 38）：
`PixelShape.translate_pixels` 把像素位移加在了 chunk 坐标上（差 8 倍）；
`ShapeOps.merge` 用了替换语义的 `copy_content` 导致合并后原像素全丢。

---

## 仍然缺的（按建议优先级）

1. **通用约束**（`ConstrainPosition / ConstrainVelocity / ConstrainOrientation / ConstrainAngularVelocity`）
   影响：这是"可编程关节"的通用形式 —— 任意自由度 + 目标值 + 限幅（maxVel / maxImpulse）。
   关节已经是它的**特例化**版本（五种固定拓扑），缺的是"自己拼约束"的能力。
   代价：要在求解器里加一类约束通道。
2. **形状级碰撞过滤**（`SetShapeCollisionFilter` 的**形状级**语义）
   影响：一个刚体内部"这一半碰、那一半不碰"。本引擎的碰撞体是全部形状的贪心矩形分解，
   要做到形状级就得给每个矩形带上"来自哪个形状"并按形状给分组。
   代价：中等；现在的**刚体级**已经覆盖了绝大多数需求（碎块/子弹/阵营）。
3. **绳索解算**（多段绳：`GetRopeNumberOfPoints` 那一组）
   影响：绳索/吊桥的"软"表现。`add_rope` 只是两点距离约束（不可伸长）。
   代价：要自己写分段约束或上 Rapier 的 multibody。
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
