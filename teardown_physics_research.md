# Teardown 物理实现调研

> 调研日期：2026-10-01
> 调研对象：① 游戏《Teardown》(Tuxedo Labs) 的官方可考证物理架构；② 参考仓库 [Vac2H2/VoxelEngineExperiments](https://github.com/Vac2H2/VoxelEngineExperiments)（Unity + C# 的 Teardown-like 体素引擎）的实际代码实现。
> 可信度分级：**[官方]** = 厂商一手文档/API；**[代码]** = 已逐行读过该仓库源码；**[二手]** = 第三方媒体/社区；**[未核实]** = 无法取得一手来源。

---

## 0. 结论速览

1. **Teardown 不是"多边形模型 + 预破碎网格"**，而是**体素即物理实体**：世界与可动物体共用同一套体素网格表示，破坏 = 删体素，然后做**连通性分割**，脱离的部分就地变成新的刚体。
2. 引擎的实体层次是 **Entity → Body（刚体）→ Shape（体素块）**。一个 Body 可以挂多个 Shape；Shape 之间用 Joint 连接。**[官方]**
3. 刚体质量不是预先烘死的：官方 API 有 `SetShapeDensity(shape, density)`、`GetShapeVoxelCount(shape)`，即**质量 = 体素数 × 密度**，因此破坏后质量/惯性自动变化。**[官方]**
4. "还连着静态世界吗"是一个显式查询：`IsBodyJointedToStatic(body)` 返回 "body 是否以任何方式连接到一个静态体" —— 这是判断"该不该继续参与模拟/进入休眠"的依据。**[官方]**
5. Teardown 的体素连接判据只有**共面（6 邻域）**：官方 modding 文档明确写"只靠棱或角接触的体素不会粘在一起，物体受损或转为动态时会立刻散架"。**[官方]**
6. 约束求解走的是**冲量层面、可限幅**的接口（`ConstrainPosition(... maxVel, maxImpulse)`、`ConstrainVelocity(..., min, max)`），配合 `SetBodyActive/IsBodyActive` 的激活(休眠)机制。**[官方]**
7. Dennis 2025 年公开的"新引擎"用 **sub-stepping 取代 solver iteration（Temporal Gauss-Seidel）+ 并行求解器**，但**那是 Teardown 之后的新项目，不能当作 Teardown 本体的实现**。**[二手]**
8. 参考仓库是一套**结构上高度对齐 Teardown 概念**的复刻（Shape/Body/8³ chunk 位平面/fragment 连通性），**破坏管线（生产端）已经很完整**，但**窄相接触、质量属性、关节、休眠、CCD、宽相 BVH 都还是占位或未接入状态**。

---

## 1. Teardown 官方可考证的物理架构

### 1.1 实体模型（Entity / Body / Shape）

官方脚本 API 首页给出了引擎的对象分类：**Body、Shape、Joint、Location、Light、Trigger、Screen、Vehicle、Rig、Player、Tool、Animator、Rope、Fire、Particle、Water**。**[官方]**

原文（[api.html](https://www.teardowngame.com/modding/api.html)）：

> **Body** — "A body represents a rigid body in the scene. It can be either static or dynamic. Only dynamic bodies are affected by physics."
>
> **Shape** — "A shape is a voxel object and always owned by a body. A single body may contain multiple shapes. The transform of shape is expressed in the parent body coordinate system."
>
> **Joint** — "Joints are used to physically connect two shapes. There are several types of joints and they are typically placed in the editor. When destruction occurs, joints may be transferred to new shapes, detached or completely disabled."

**这三点基本定义了整个引擎的物理数据模型：**

| 概念 | 含义 | 对应物理量 |
|---|---|---|
| Entity | 一切对象的基类（带 tag / description / 层级） | 无 |
| **Body** | 刚体（static / dynamic），物理求解单位 | 质量、惯性、速度、质心 |
| **Shape** | 体素块，永远属于某个 Body | 体素几何、密度 |
| Joint | 连接**两个 Shape** 的约束 | 类型、限位、马达 |

**关键推论：约束是挂在 Shape 上而不是 Body 上的。** 这也解释了为什么破坏发生时官方要说 "joints may be transferred to new shapes" —— 形状被切开后，关节要重新绑定到新的 Shape 句柄上。**[官方]**

### 1.2 质量、密度与质心

| 函数 | 说明（官方 desc 原文） |
|---|---|
| `GetBodyMass(body)` | "Body mass. **Static bodies always return zero mass.**" |
| `SetShapeDensity(shape, density)` | "New density for the shape" |
| `GetShapeVoxelCount(shape)` | "Number of voxels in shape" |
| `GetBodyCenterOfMass(body)` | "Vector representing **local** center of mass in body space" |
| `ApplyBodyImpulse(body, position, impulse)` | 在世界坐标点施加世界坐标冲量 |
| `SetBodyGravityScale(body, scale)` | 逐刚体重力缩放 |

**结论**：质量由 Shape 的体素数 × 密度决定；质心由体素分布决定；静态体质量为 0（即逆质量为 0，参与求解但不受冲量影响）。破坏-质量联动是引擎内建的，不需要脚本干预。**[官方]**

### 1.3 破坏的语义

| 函数 | 说明 |
|---|---|
| `IsBodyBroken(body)` / `IsShapeBroken(shape)` | 是否已破坏 |
| `IsShapeDisconnected(shape)` | "**True if shape disconnected (has detached parts)**" |
| `IsStaticShapeDetached(shape)` | "True if **static** shape has detached parts" |
| `SplitShape(shape, removeResidual)` | 返回 "List of shape handles created" —— 引擎级的分裂原语 |
| `MergeShape(shape)` | 合并，返回合并后的 shape 句柄 |
| `IsShapeTouching(a, b)` | 两个 shape 是否接触 |
| `GetShapeClosestPoint` / `GetBodyClosestPoint` | 最近点查询 |

**`IsShapeDisconnected` / `IsStaticShapeDetached` 的存在说明引擎内部维护"这个形状是否还有未分离的碎片"这个状态**，即连通性检查是引擎内核的一部分，而不是脚本层的事。静态形状（墙体、地面）被炸开后产生的脱离部分会被转成动态体。**[官方]**

### 1.4 体素连接判据（官方明确规则）

[官方 modding 文档](https://www.teardowngame.com/modding/) "Voxel Connectivity" 一节原文：

> "For voxels to correctly **"stick"** together in the game, they need to **connect on their sides**. Voxels touching only through their **edges or corners** will not stay together in the game. Such constructions **will fall apart the moment they are damaged or otherwise become dynamic** in the game."

- 只查 **6 邻域（共面）**，不查 18/26 邻域。
- 边缘/角接触的体素在"转为动态"时立即分离 —— 说明连通性不是加载时算一次，而是**每次拓扑变化后重算**。

其他官方约束（同页）：
- MagicaVoxel 的 **255 色调色板索引 → 体素材质**（材质决定硬度/易燃性/摩擦等）。
- 单个 vox object 最大 **256³**，官方建议 **128³** 以内，"最大尺寸可能在游戏里造成卡顿"。
- 世界单位 = **米**（"a body which should move 1 meter per frame should have its movement set to 1 * dt"）；阴影模糊参数 `sunSpread="0.05"` 描述为"每米 5 厘米"。

> **[未核实]** Teardown 单体素边长（社区普遍引用 0.1 m）——本次调研网络无法访问 `tuxedolabs.blogspot.com` 与 `web.archive.org`，未能从一手来源确认。

### 1.5 约束、关节与激活（休眠）

**关节类型**：编辑器教程里明确有 ball joint、hinge joint、prismatic joint、spring joint、stiff joint。**[官方]**

| 函数 | 参数要点 |
|---|---|
| `GetJointType(joint)` | 返回类型字符串 |
| `GetJointLimits(joint)` | "Minimum/Maximum joint limit (**angle or distance**)" |
| `GetJointMovement(joint)` | "Current joint **position or angle**" |
| `SetJointMotor(joint, velocity, strength)` | strength 默认无穷大，**0 = 禁用** |
| `SetJointMotorTarget(joint, target, maxVel, strength)` | 位置/角度伺服 |
| `IsJointBroken(joint)` | 关节是否断 |
| `DetachJointFromShape(joint, shape)` | 从某一侧解绑 |

**通用约束 API（非常重要，暴露了求解器风格）**：

| 函数 | 参数 |
|---|---|
| `ConstrainVelocity(bodyA, bodyB, point, dir, relVel, min, max)` | 目标相对速度 + **冲量上下限** |
| `ConstrainPosition(bodyA, bodyB, pointA, pointB, maxVel, maxImpulse)` | 位置约束 + **最大相对速度 + 最大冲量** |
| `ConstrainAngularVelocity` / `ConstrainOrientation` | 角速度/朝向版本 |

`bodyA/bodyB` 传 **0 表示静态**。这种"目标值 + 限幅(maxVel/maxImpulse)"的接口是典型的**速度/冲量层约束求解器**（与 PBD/XPBD 的 impulse clamping、以及 Box2D 的 soft constraint 同族），而不是纯位置投影。**[官方 + 推断]**

**激活与休眠**：
- `IsBodyActive(body)` / `SetBodyActive(body, active)`：`SetBodyActive` 描述为 "Set to tru[e] if body should be **active (simulated)**"。
- `IsBodyJointedToStatic(body)`：**"Return true if body is in any way connected to a static body"** —— 这是"锚定检测"的公开形式：一堆碎块通过关节连着静态墙时不必各自模拟。

### 1.6 其他物理子系统

| 子系统 | 关键 API | 备注 |
|---|---|---|
| 载具 | `DriveVehicle(vehicle, drive, steering, handbrake)`、`GetVehicleParams/SetVehicleParam`、`GetVehicleSteering/Drive`、`GetVehicleBodies/GetVehicleBody` | 编辑器搭建的多部件组合，非脚本拼装 |
| 玩家 | `GetPlayerGrabShape/Body`、`GetPlayerPickShape/Body`、`IsPlayerGrounded`、`GetPlayerGroundContact`、`SetPlayerVehicle` | 玩家是特殊 Body + 抓取约束 |
| 绳索 | `GetRopeNumberOfPoints`、`GetRopePointPosition`、`GetRopeBounds`、`BreakRope`、`QueryRaycastRope` | 独立于刚体的 rope 解算 |
| 水 | `IsPointInWater`、`QueryRaycastWater`、`GetWindVelocity` | 浮力/阻力内建 |
| 火 | `SpawnFire`、`GetFireCount`、`QueryClosestFire`、`QueryAabbFireCount`、`RemoveAabbFires` | 独立火焰蔓延系统，与体素材质耦合 |
| 粒子 | `SpawnParticle`、`ParticleGravity/Drag/Sticky/Collide/Flags` | 粒子可参与碰撞 |
| 场景查询 | `QueryRaycast`、`QueryShot`、`QueryAabbShapes/Bodies`、`QueryReject*`、`QueryPath` | 独立的空间查询体系（不是 Unity 那套） |
| 动画/布娃娃 | `MakeRagdoll` / `UnRagdoll` / `GetBoneBody` / `SetAnimatorPositionIK` | 骨骼可绑定到 Body |

### 1.7 重要区隔：Teardown 本体 ≠ Dennis 的新引擎

80.lv（2025-01）报道 Dennis Gustafsson 的新自研引擎：**[二手]**

> "This new engine utilizes **sub-stepping instead of solver iteration**, a method sometimes referred to as **"Temporal Gauss-Seidel"**, and features a **parallel solver** capable of handling large piles of objects across multiple threads. Also, improvements have been made to **contact generation and the broad phase**." … "32 threads and simulates in approximately **5 ms**."

**这是 Teardown 之后的新项目，不能当作 Teardown 本体的实现细节。** 网上大量"Teardown 用 small steps / XPBD"的说法，其实际来源是这篇报道所描述的新引擎，属于**张冠李戴**。

同时注意：`devops-geek.net` 那篇《Dissecting the Teardown Engine》页面自带 `AI Mode: tech` 标记，是 **AI 生成内容**，文中"disjoint-set/flood-fill 岛屿分离""确定性求解器"等描述属于合理猜测而非证据，**不应引用**。

---

## 2. 参考仓库 VoxelEngineExperiments 的实现拆解

仓库信息：`Vac2H2/VoxelEngineExperiments`，语言 C#/HLSL，22 stars，2026-04 创建，2026-06 最后推送，无 README。结构上分为三块：

| 目录 | 作用 |
|---|---|
| `Assets/VoxelEngine/` | Mini 物理引擎 + 体素数据 + 自研渲染管线（DXR 光追 G-buffer、NRD 降噪） |
| `Assets/VoxelEngineModules/` | Shape 存储、**破坏管线（Burst Job）**、ShapeManagement |
| `Assets/VoxelEngineDOTS/` | **设计中的** ECS/DOTS 物理后端 + Morton TLAS BVH 演示（尚未接入主流程） |

### 2.1 体素与 Shape 数据布局 **[代码]**

来自 `Assets/VoxelEngineModules/Shape/README.md`：

~~~
chunkSize                 = 8
chunksPerShape            = 8
voxelsPerChunk            = 8 * 8 * 8 = 512
bitPlaneBytesPerChunk     = 8 * 8 = 64        // 512 bit = 64 B
bitPlaneBytesPerShape     = 8 * 64 = 512
currentBitPlaneCount      = 4
currentDataBytesPerShape  = 4 * 512 = 2048 B
~~~

索引方式（**位平面 bitplane**，不是 byte-per-voxel）：

~~~
chunkBase = shapeBase + chunkIndex * 64
byteIndex = chunkBase + y + 8 * z
bitMask   = 1 << x
~~~

四个位平面：`IsOccupied` / `IsFace` / `IsEdge` / `IsCorner`。

- **一个 Shape 固定 8 个 chunk，容量不可变**；`ShapeDataStorage.Acquire()` 返回 `int` handle（即 slot index），用尽返回 `InvalidHandle`，**不扩容**。这与 Teardown 固定的 Shape 槽位模型一致。
- 硬性不变量："**Shape 内部必须连通，不能有孤岛；出现孤岛时上层构建流程应该拆成两个或多个 Shape**"。
- Shape 不保存 chunk 聚合包围盒/连接性缓存，"需要时扫描最多 8 个 chunk slot 计算"。
- `ShapeMetadata { int BodyHandle; byte IsUsed; }` —— **Shape→Body 的归属关系只有一个 int**。
- 默认体素边长 `VoxelEngineSettings.DefaultVoxelSize = 1.0f`（可通过渲染管线资产全局配置）。相对 Teardown 的 0.1 m 只差一个缩放常数。

**表面分类（与 `IsFace/IsEdge/IsCorner` 位平面同构）**，见 `MiniVoxelContactGenerator.Classify`：

~~~csharp
exposedNeighborCount == 0 -> Inside   // 完全不参与碰撞
                       1 -> Face
                       2 -> Edge
                     >=3 -> Corner
~~~

即**只有表面体素参与碰撞检测**，内部体素被排除（`Inside` 直接跳过）。

### 2.2 物理管线（Mini*，单线程、非 Job 化）**[代码]**

`Assets/VoxelEngine/Physics/Simulation/MiniPhysicsEngine.cs`：

~~~csharp
public void Tick(MiniPhysicsWorld world, float deltaTime)
{
    Collect(world);          // 收集 body / collider 快照
    ApplyForces(deltaTime);  // 重力 + 累积力 → 速度
    Broadphase();            // AABB 对 → OBB SAT 复核
    Narrowphase();           // 体素球体近似 → 接触点
    Solve(deltaTime);        // 顺序冲量
    Integrate(deltaTime);    // 半隐式欧拉 + 阻尼
}
~~~

驱动方式：`MiniPhysicsBroadphaseDebugRunner.FixedUpdate()` → `Time.fixedDeltaTime`（也支持手动 `Tick(dt)`）。骨架是标准 6 段管线，和 Teardown 概念一致但完全没有用到 Job/Burst。

#### (a) Broadphase — 朴素 O(n²) + SAT

`MiniObjectBroadphase`：双层 `for` 遍历所有 collider 对的 AABB 相交测试；静态-静态对直接跳过、同一 body 内的 collider 对跳过。`MiniColliderPairRefinement` 再用 `MiniObbSat.Overlaps`（完整 15 轴 OBB SAT，带 epsilon）复核。**没有 BVH、没有排序扫描、没有网格哈希。**

仓库里确实有 Morton 排序的 TLAS BVH（`VoxelEngineDOTS/BVH/`），但**只在独立 Demo 里用，未接入 Mini 物理**。

#### (b) Narrowphase — 逐表面体素做"球体近似"

`MiniVoxelContactGenerator` 的实际做法：

1. 取两个 collider，遍历**表面体素较少**的一方（`SurfaceVoxelCount <=`）。
2. 每个源表面体素，把世界坐标变换到目标形状局部空间，用 `FloorToVoxelKey` 定位目标体素。
3. 在以目标体素为中心、半径 `candidateRange = ceil((rA+rB)/voxelSize) + 1` 的立方体邻域里搜索目标表面体素（体素边长 1.0 时即 5×5×5 = 125 格）。
4. 每个候选对用 **球-球相交**（体素当作半径 = voxelSize/2 的球）判定穿透。
5. **只保留穿透最深的一个接触点**。

~~~csharp
// 半径 = 体素半边长
private static float GetWorldVoxelRadius(MiniCollider collider) => collider.Data.VoxelSize * 0.5f;
~~~

代价分析：单次接触生成复杂度 ≈ `O(|surface(A)| × (2r/d)³)`，其中 r 是体素半径、d 是体素边长，约 125 倍常数。**这是明确的占位实现** —— 真正的体素碰撞应当做体素-体素 AABB/OBB 穿透、多接触点流形与特征（face/edge/corner）区分。

值得注意的是 `MiniVoxelContactFeature`（Face/Edge/Corner）**已经被算出来并塞进接触点了**，但 `MiniPhysicsNarrowphaseStage` 只用了 position/normal/penetration，特征信息被丢弃 —— **留了接口没接**。

另外：`MiniObbContactPointGenerator.cs`（22 KB，完整 OBB-OBB 接触流形生成）和 `MiniContactReducer.cs`（7.7 KB，接触点约简到 ≤4 点）**都已经写好，但全仓库没有任何地方引用它们**（逐文件 grep 确认：只在自身文件内出现）。

#### (c) 窄相输出粒度

每次接触生成一个**只有 1 个接触点**的 manifold；`MiniContactManifoldFrame` 结构支持 4 点（`MaxPointCount = 4`）：

~~~csharp
frameData.AddContactManifold(new MiniContactManifoldFrame(
    pair.ColliderAIndex, pair.ColliderBIndex,
    colliderA.BodyIndex, colliderB.BodyIndex,
    contact.Normal, contact.Penetration,
    new MiniContactPointFrame(contact.Position, contact.Penetration),
    default, default, default, 1));   // pointCount = 1
~~~

即：**一个体素对一个接触点、一个 manifold**。这会导致堆叠体（大量面接触）产生远超必要数量的约束，是当前最主要的性能与稳定性隐患。

#### (d) Solver — 顺序冲量（Sequential Impulse）

`MiniPhysicsSolverStage` 的完整参数与算法：

| 参数 | 值 | 说明 |
|---|---|---|
| `IterationCount` | 10 | 每帧约束迭代次数 |
| `Restitution` | 0.05 | 恢复系数（debug runner 里设为 0） |
| `Friction` | 0.6 | 库仑摩擦系数 |
| `Baumgarte` | 0.2（runner 用 0.08） | 穿透修正比例 |
| `PenetrationSlop` | 0.01 | 允许穿透容差 |
| `MaxDepenetrationVelocity` | 3.0 | 分离速度上限 |
| `RestitutionVelocityThreshold` | 1.0 | 低于该法向速度不产生弹性 |

算法特征：

- **累积冲量** `NormalImpulse`、`Tangent1Impulse`、`Tangent2Impulse`，法向冲量 clamp 到 `>= 0`（不允许吸附）。
- 摩擦：**双切向**（`tangent1` 由相对速度正交化得到，`tangent2 = cross(normal, tangent1)`），各自 clamp 到 `±Friction * NormalImpulse`。
- **Baumgarte 走速度层**：`penetrationBias = max(0, penetration - slop) * Baumgarte / dt`，并 clamp 到 `MaxDepenetrationVelocity`，然后作为 `VelocityBias` 加到法向约束上；**没有独立的位置修正 pass**。
- 恢复系数：`normalVelocity < -threshold` 时才启用。
- 有效质量：`1 / (invMassA + invMassB + dot(axis, angularA + angularB))`，其中 `angular = cross(I⁻¹·cross(r, axis), r)` —— 标准公式。
- **无 warm starting**（每帧重建约束、冲量从 0 开始）。
- **无 sleeping / island**、**无 CCD**、**无关节/约束图**（全仓库 grep `Joint|Constraint` 只命中求解器内部的 `ContactConstraint`）。

#### (e) Body 与积分

`MiniRigidBody`（MonoBehaviour）：

- 类型：`Static / Dynamic / Kinematic`；`InverseMass` 与 `WorldInverseInertiaTensor` 对非 Dynamic 直接返回 0。
- 惯性张量是**局部对角阵 + 旋转**：`WorldInverseInertiaTensor = R * diag(1/I) * Rᵀ`。
- `IntegrateForces`：`v += (ΣF + m·g·gravityScale) · invMass · dt`；`ω += I⁻¹·τ·dt`。
- `IntegrateTransform`：先套阻尼 `v *= 1/(1 + damping·dt)`，然后 `x += v·dt`，旋转用**轴角积分** `AngleAxis(|ω|·dt, ω/|ω|) * R`，并按质心偏移回写 `transform.position`。
- **质量与惯性是手工赋值/Inspector 参数**，或用 `SetSolidBoxInertiaTensor(size)` 按**实心长方体**估算：

~~~csharp
public static Vector3 ComputeSolidBoxInertiaTensor(float mass, Vector3 size)
{
    float scale = mass / 12.0f;
    return new Vector3(scale*(y2+z2), scale*(x2+z2), scale*(x2+y2));
}
~~~

**这是与 Teardown 差距最大的一环**：全仓库 grep `density|Density|VoxelCount *` **零命中**，即质量/质心/惯性张量**都还没有从体素分布推导**。而 Teardown 正是靠 `体素数 × 密度` + 体素分布质心来做到"炸掉一半，质量自动变一半"。

### 2.3 破坏管线（这块是仓库里最完整的部分）**[代码]**

管线定义在 `ShapeDestructionPipeline/README.md`，作业实现在 `Jobs/` 与 `ShapeVoxelRemoveCommandBuffer/`：

~~~
DestructionShapeChunkOverlapJob      破坏形状 chunk × 目标 chunk 重叠检测
  -> DestructionChunkOverlapPrefixSumJob   重叠计数前缀和（紧凑分配）
  -> DestructionMaskGenerationJob          生成 64B"保留掩码"
  -> ShapeVoxelRemoveBuildKeyJob           转成可排序键 (ShapeHandle, ChunkSlot, CommandIndex)
  -> 排序                                  同 shape / 同 chunk 的指令相邻
  -> ShapeVoxelRemoveBuildRangeJob         每个 shape 一个 range
  -> ShapeVoxelRemovePackJob               同 chunk 多条指令按位 AND 合并
  -> ShapeVoxelRemoveJob                   source & keepMask
  -> ShapeChunkFragmentJob                 X-run/切片泛洪，单 chunk 最多出 4 个 fragment
  -> ShapeChunkCheckMaskJob                只算"该检查哪些邻居 node"的候选位掩码
  -> ShapeChunkConnectivityJob             真正的面位检测（+X/+Y/+Z 三方向）
  -> ShapeFragmentUnionJob                 固定 32 node 的 union-find
  -> ShapePrefixSumComputeJob              local shape 数前缀和
  -> ShapeBuildJob                         组装最终 shape 缓冲
  -> CommitBuiltShapes
~~~

几个设计要点：

- **keep-mask 语义**：`bit 1 = 保留体素，bit 0 = 删除`，初始化 `0xFF`，被破坏体积命中的位清零。删除阶段统一 `target = source & removeMask`。
- **单 chunk 最多输出 4 个 fragment**（按体素数 top-4 挑选），小于 `MinimalVoxelNumber`（测试用 2）的碎块直接丢弃 —— 这与 Teardown 里小碎块会消失的观感一致。
- **连通性只查 +X/+Y/+Z 三个正方向**：避免重复计算，也避免跨线程反向写：
  - `+X`：A 的 row bit7 对 B 的 row bit0
  - `+Y`：A 的 y=7 行对 B 的 y=0 行
  - `+Z`：A 的 z=7 层对 B 的 z=0 层
- **只查 6 邻域（共面）**，与 Teardown 官方"edge/corner 不算连接"的规则**完全一致**。
- **Shape-local 连续工作集**：中间结果写在紧凑的 affected-shape 缓冲里（`affectedShapeCount * 8 * 64B`），不写回全局 Shape 存储，减少随机访问。
- 作业粒度是刻意混合的：remove 按 shape（8 槽一起处理）、fragment 按 chunk（成本方差大）、connectivity 按 fragment node（batch=32 让一个 shape 落在同一 worker）、union 按 shape。

README 自己也指出了已知瓶颈：**命令粒度是 `target shape + target chunk + destruction chunk`**，同一个目标 chunk 被多个破坏 chunk 覆盖时会产生多条命令，后面再排序 AND 合并，造成 `sum(popcount(ChunkOverlapMasks)) * 64B` 的写放大；优化方向是把合并提前到 `DestructionMaskGenerationJob`。

基准测试：`ShapeDestructionPipelinePerformanceTests` 用 `Unity.PerformanceTesting`，对 1/2/4/8/16/32/64/128/256/512/1000 个 shape 各跑 6 次预热 + 30 次测量，并**逐 job 单独计时**（`ShapeVoxelRemoveJobMs`、`ShapeChunkFragmentJobMs` …）。破坏半径 4 体素。

### 2.4 调试用破坏实现（非正式路径）**[代码]**

`MiniDestructionEngine`（`[DefaultExecutionOrder(900)]`、`LateUpdate`）用 Unity `BoxCollider` 代理做碎片，算法本身有参考价值：

1. **播种**：所有"被删体素的 6 邻居"作为种子（不遍历全物体）。
2. **多组并行 BFS + union-find 合并**：每组有自己的 frontier 和 voxel 列表，相遇即合并（按体积小的并入大的）。
3. **判定**：循环 `while (activeGroupCount > 1)`，每次取 frontier 最小的组扩展；某组 frontier 耗尽而仍有其他活跃组 → 判为**脱离部件**。最后剩下的那个组视为主干。
4. 脱离部件整体搬运到新物体（`SetVoxel` 复制 + 源清零），并给每个物体一个轴对齐 `BoxCollider`。
5. 用颜色区分 grounded / ungrounded（体素值最高位 `1 << 7` 存 grounded 标记）。

注意：**这条路径和 2.3 的 Burst Job 管线是两套东西** —— 前者是可视化调试，后者才是正式生产端。

### 2.5 DOTS 侧的设计文档（尚未实现）**[代码]**

`VoxelEngineDOTS/PHYSICS.md` 是一份质量很高的设计文档，核心主张：

- 物理核心只认一个身份 `BodyId`，不让 ECS `Entity` 进入物理热路径。
- `ChunkData` 是入口（已知 BodyId+ChunkPos → 数据），`BVH` 是出口（未知 → 空间查询）。**Broadphase 输出的是 chunk pair `(BodyIdA, ChunkPosA) + (BodyIdB, ChunkPosB)`，不是 body pair。**
- 管线固定为：`Logic → Sync In → Voxel mutation(destruction/split) → UpdateData → Broadphase → Narrowphase → Solver → Integration → Dirty → Sync Out`。
- 一帧有**两个 BVH 同步点**：突变后的"结构同步"（在 broadphase 前）和积分后的"变换同步"（只更新 body 级 TLAS proxy）。
- 用 `DirtyTransformBodyIds` 做 `O(dirty)` 的变换回写，绝不每帧写回所有 transform。

**这份文档目前是"设计"而不是"实现"**：`VoxelPhysicsEngine.cs` 只有 0.1 KB，`VoxelPhysicsBackend.cs` 6.7 KB，主流程仍走 Mini 物理。

### 2.6 与 Teardown 的能力对照

| 能力 | Teardown | 本仓库 | 差距 |
|---|---|---|---|
| Entity/Body/Shape 层次 | 有 | 有 Body + Collider/Shape | 基本对齐 |
| Joint（ball/hinge/prismatic/spring） | 5 种 + 马达 + 限位 + 断裂 | 无 | **缺失** |
| 破坏时关节转移 | 官方明确 | 无 | **缺失** |
| 质量 = 体素数 × 密度 | `SetShapeDensity` | 手填 / 实心盒近似 | **关键缺失** |
| 质心由体素分布决定 | `GetBodyCenterOfMass` | 手填 `LocalCenterOfMass` | **关键缺失** |
| 连通性分割 | 引擎内建 | Burst Job 管线完整 | **本仓库更强（更工程化）** |
| 形状级碰撞 | 体素精确 | 球体近似 + 只取最深点 | **关键缺失** |
| 接触流形 | 多点 | 1 点/manifold | 已写好 `MiniObbContactPointGenerator` 未接入 |
| 宽相 | BVH/空间结构 | O(n²) AABB | BVH 有但未接入 |
| 休眠/激活 | `SetBodyActive` / `IsBodyJointedToStatic` | 无 | **缺失** |
| CCD | `QueryShot` 等 | 无 | 缺失 |
| 水/火/绳索/载具 | 全部内建 | 无（渲染侧有 NRD/光追） | 缺失 |
| 多线程物理 | 部分（新引擎全并行） | 全单线程 | — |
| 渲染耦合 | 体素光追 | DXR 光追 + NRD | 对齐度很高 |

---

## 3. 如果要自己实现（或往 Godot 迁移）的关键结论

1. **表示层选对了**：8³ chunk + 位平面（每 chunk 64 B）是最划算的方案，一次 `AND` 就是一次批量破坏；4 个平面（Occupied/Face/Edge/Corner）让"表面体素"可以 O(1) 查询，避免每次碰撞都做邻域扫描。
2. **破坏管线的复杂度在"命令合并"而不是"泛洪"**。本仓库的实测痛点（README 自述）是同一目标 chunk 收到多条 64 B 掩码指令造成的写放大 —— 直接在设计上做"**一个目标 chunk 一条最终 keep mask**"。
3. **连通性只用 6 邻域**，且**只查 +3 个方向**，天然免锁、可并行。这和 Teardown 官方规则一致，不要用 18/26 邻域。
4. **碎块数量必须限流**：单 chunk 最多 4 个 fragment + 最小体素数过滤 + top-N 按体素数保留，是控制刚体数量的关键阀门。
5. **质量属性必须从体素推导**，否则"炸掉半边墙质量不变"会立刻露出破绽。实现上：
   - 质量 `m = Σ(voxel_i.密度) × voxelVolume`
   - 质心 `c = Σ(m_i · p_i) / m`
   - 惯性张量用体素的位置二阶矩累加（含平行轴定理），再按质心平移。
6. **接触点数量 = 性能上限**。球体近似 + 每体素一个 1 点 manifold 会产生大量冗余约束；正确方向是生成 ≤4 点的流形（本仓库 `MiniObbContactPointGenerator` + `MiniContactReducer` 已写好，接上即可）。
7. **休眠机制不是可选项**。Teardown 用 `IsBodyJointedToStatic` 判断"是否还锚定在静态世界"，本仓库完全缺失 —— 一堆碎石永远在跑 solver 是性能杀手。
8. **Godot 4 侧的现实**：
   - 内置 GodotPhysics / Jolt 都不支持"运行时高频改变质量与惯性"的高效路径，且每帧创建/销毁 `RigidBody3D` 代价很高 → 必须**对象池 + 复用**。
   - 碰撞形状建议用 **greedy box 合并**（把体素团簇合并成若干凸盒）生成 `ConvexPolygonShape3D`，而不是 `ConcavePolygonShape3D`；合并粒度需要按性能实测调。
   - 大量小刚体 + 频繁重建网格，**基本注定要 GDExtension（C++）**，纯 GDScript 无法达到 Teardown 的量级。
   - 破坏逻辑本身（掩码生成、泛洪、union-find）可以先用 Job 化思路并行；Godot 有 `WorkerThreadPool`，但没有 Burst 那种自动向量化。

---

## 4. 本次调研的局限与存疑项

| 项 | 状态 |
|---|---|
| Dennis Gustafsson 原博客 `tuxedolabs.blogspot.com` | **无法访问**（本网络下 DNS 被污染 + 超时；`web.archive.org` 同样超时）。所有关于他原文的内容均改由官方 API/官方 modding 文档/媒体转述佐证。 |
| Teardown 体素边长 = 0.1 m | **未核实**（社区广泛引用，本次未取得一手来源） |
| Teardown 求解器具体算法（子步数、迭代数、是否 warm start） | **无公开一手证据**。官方仅暴露 `Constrain*` 的限幅式约束接口，可作为"冲量层可限幅求解"的间接证据。 |
| "Teardown 使用 small steps / XPBD" 的流行说法 | **判为误传**：其来源是 2025 年 Dennis **新引擎**的报道。 |
| `devops-geek.net` 的 Teardown 引擎分析 | **AI 生成内容**（页面自带 `AI Mode: tech`），不作为证据。 |
| 参考仓库的 `MiniObbContactPointGenerator` / `MiniContactReducer` | **已实现但未接入**（grep 全仓库无引用）。 |

---

## 5. 资料来源

### 一手（官方）
- Teardown 官方脚本 API 文档（网页版，531 个函数）：https://www.teardowngame.com/modding/api.html
- Teardown 官方脚本 API 文档（结构化 XML，含逐参数说明）：https://www.teardowngame.com/modding/api.xml
- Teardown 官方 Modding 文档（编辑器、MagicaVoxel 流程、**Voxel Connectivity 规则**）：https://www.teardowngame.com/modding/
- Teardown 官方 vox-script 文档：https://www.teardowngame.com/modding/voxscript.html
- Tuxedo Labs 官网：https://www.tuxedolabs.com/
- Teardown 官网：https://www.teardowngame.com/

### 参考仓库（代码）
- 仓库主页：https://github.com/Vac2H2/VoxelEngineExperiments
- 本地已解出源码：`_research/repo/VoxelEngineExperiments-main/`

关键文件（相对仓库根目录）：
- `Assets/VoxelEngine/Physics/Simulation/MiniPhysicsEngine.cs` — 6 段管线
- `Assets/VoxelEngine/Physics/Simulation/Stages/Solver/MiniPhysicsSolverStage.cs` — 顺序冲量求解器
- `Assets/VoxelEngine/Physics/Simulation/Stages/Narrowphase/VoxelContactGeneration/MiniVoxelContactGenerator.cs` — 体素球体近似窄相
- `Assets/VoxelEngine/Physics/Body/MiniRigidBody.cs` — 刚体与惯性张量
- `Assets/VoxelEngineModules/Shape/README.md` — Shape 位平面布局
- `Assets/VoxelEngineModules/ShapeDestructionPipeline/README.md` — 破坏管线全流程
- `Assets/VoxelEngine/Physics/Destruction/MiniDestructionEngine.cs` — 调试用碎片分离（多组 BFS）
- `Assets/VoxelEngineDOTS/PHYSICS.md` — DOTS 物理设计文档（未实现）

### 二手（媒体/社区）
- 80.lv：Dennis 新引擎用 sub-stepping / Temporal Gauss-Seidel（**非 Teardown 本体**）：https://80.lv/articles/see-what-s-new-in-teardown-creator-s-custom-voxel-physics-engine
- 80.lv：Teardown 多人模式与体素破坏技术：https://80.lv/articles/teardown-developer-breaks-down-multiplayer-and-voxel-destruction-tech
- Game Developer：体素如何支撑 Teardown 的玩法框架：https://www.gamedeveloper.com/design/how-beautiful-voxels-laid-the-way-for-i-teardown-s-i-heist-y-framework
- Teardown Lua API 结构化 JSON（社区整理，版本 0.8.0，**已过时仅供参考**）：https://github.com/funlennysub/teardown-api-docs-json
- 地图格式解析工具（.tdbin → .xml/.vox）：https://github.com/TTFH/Teardown-Converter
- Teardown 关卡编辑器节点文档（俄文社区整理）：https://github.com/YaronQ/TeardownModdingGuide/blob/main/CONCEPTS.md

### 已判定不可采信
- devops-geek.net《Dissecting the Teardown Engine: A Technical Autopsy of Voxel Destruction Pipelines》（AI 生成内容）
