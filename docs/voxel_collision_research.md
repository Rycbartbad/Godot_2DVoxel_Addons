# 体素破坏：碰撞建在哪一层（对照研究）

> 调研日期：2026-10-03（第二轮）
> 起因：上一份 `docs/voxel_destruction_research.md` 只回答了"破坏管线怎么快"，
> 没回答**碰撞**这一层。用户给出的参考清单是：qrisquinn/Vex-2.0、
> Zylann/godot_voxel（**看它怎么做碰撞**）、Teardown 技术演讲/逆向、以及任何
> Unity/Unreal/自研体素破坏项目。
>
> 证据分级：**[代码]** = 逐行读过源码（本机克隆在 `_research/repo/`）；
> **[官方]** = 厂商一手文档/演讲；**[二手]** = 第三方分析；**[实测]** = 本机跑出来的数字。
> 外部材料见 `_research/notes/`。

---

## 0. 结论速览

1. **我们把碰撞建在"整个形状"这一层，别人建在"块"这一层。** 一笔擦除要重跑
   整个形状的位网格（768x100 = 1248 块），实测 **_build_grid 5.6 ms / decompose 7.6 ms**，
   占一笔擦除（~11-13 ms）的绝大部分。godot_voxel 的碰撞是**逐块**的，只有脏块重建。
2. **把碰撞体推给 Rapier 不是瓶颈**（早前实测 0.17 ms/笔），**生成碰撞体才是**。
   所以优化目标是"少重算"，不是"少推送"。
3. **连通性判据我们已经是 4 邻域**（跨块只查 +X/+Y，对角不算连接），
   与 Teardown 官方的"只共面才算连接"一致 —— 上一份研究里"4 还是 8"这个待办可以销掉。
   （`touches_boundary` 里那个八邻域是**保守预筛**，只会多跑一次 split，不会错判。）
4. **Vex-2.0 的"对象池 + 碎块独立碰撞组"值得抄，"用中心距判焊接"必须避开**（见 2.3）。
5. **Noita（2D 像素，和我们最像）也不逐像素做刚体碰撞** —— 它把像素轮廓转成少量凸形状
   再交给物理。所以"用通用物理引擎 + 把像素转成凸形状"**不是我们独有的妥协**（§2.4）。
6. **按块缓存分解结果**是本文最推荐的一条：把形状切成 64x64（或 32x32）的**分解块**，
   缓存每块的矩形；一笔只重算脏块。按今天量到的 4.5 µs/8x8 块算，
   一笔从 **5.6 ms 降到 0.1~0.6 ms**（预估，需复测，见 §5）。

---

## 1. 我们现在的碰撞路径（实测）

### 1.1 数据流

```
PixelShape（8x8 像素 = 1 个 uint64 的 chunk 字典）
  -> GreedyRects.decompose(shape)      全形状位网格 + 双向贪心 + merge_pass
  -> PBody.rects                       Array[Rect2]（局部像素空间）
  -> PWorld 每子步 op5                 rb_body_set_rects：**清空该刚体全部碰撞体**再重建
  -> Rapier                            N 个 cuboid（friction = solver.global_friction）
```

- `GreedyRects._build_grid()`：遍历**全部** chunk，每个写 8 行（`Bits.row_bits`）。
- `GreedyRects._greedy()`：双向贪心各跑一遍（第二遍只在第一遍 > 1 个矩形时跑），
  再 `_merge_pass()` 合并同跨度相邻矩形。
- `PBody.rebuild()`（`src/physics/pbody.gd:295`）是**唯一**的"内容变了"入口：
  `rects_rev += 1` → 每形状 `mark_dirty_range()` 或 `touch()` → 重新 decompose → `update_aabb()`。
- `PWorld` 看到 `rects_rev` 变了才发 op5（`src/physics/pworld.gd:649`）。

### 1.2 一笔擦除的成本（今天在本机重跑）

`tests/diag_fracture_parts.gd`（768x100 地面，半径 6 的线段笔）：

| 笔画 | gpu | touchB | apply | **rebuild** | 合计 |
|---|---|---|---|---|---|
| 0 | 0.01 | 0.10 | 0.25 | **10.17** | 10.52 |
| 3 | 0.03 | 0.07 | 0.24 | **11.46** | 11.81 |
| 5 | 0.00 | 0.08 | 0.24 | **12.53** | 12.85 |

**rebuild 占 96~97%**，其余全是噪声。

`tests/diag_decompose_parts.gd`（有洞的 768x100）：

| 阶段 | 耗时 |
|---|---|
| `_build_grid` | 4.81 ms |
| `_greedy` 横优先 | 0.62 ms |
| `_merge_pass`（48 矩形） | 0.12 ms |
| **decompose 整体** | **7.75 ms** |
| 未解释（第二遍贪心 + 数组搬运等） | 2.83 ms |

### 1.3 规模曲线（本次新量，探针已删）

同一份 `_build_grid` / `decompose`，形状越大越线性：

| 形状 | chunk 数 | `_build_grid` | `decompose` | 矩形数 |
|---|---|---|---|---|
| 32x32 实心 | 16 | 0.078 ms | 0.084 ms | 1 |
| 64x64 实心 | 64 | 0.278 ms | 0.300 ms | 1 |
| 128x128 实心 | 256 | 1.203 ms | 1.188 ms | 1 |
| 768x100 实心 | 1248 | 5.632 ms | 5.227 ms | 1 |
| 768x100 有洞 | 1228 | 5.687 ms | 7.631 ms | 60 |
| 32x32 有洞 | 16 | 0.073 ms | 0.365 ms | 20 |

**每块约 4.5 µs（= 每 chunk-行约 0.56 µs）** —— 这条常数是后面所有推算的依据。
注意"有洞"时 `decompose` 明显大于 `_build_grid`（32x32：0.073 → 0.365），
说明碎片化之后**贪心 + merge 也开始要钱**，不只是建网格。

### 1.4 一个必须更正的旧结论

`GreedyRects._build_grid` 顶部有一条墓碑注释：**"增量路径已删除 —— 实测无效"**
（增量 9.13 ms vs 全量 9.36 ms，只快 1.0 倍）。

⚠️ **那条测量是在字节网格 + 逐像素迭代的时代做的**：注释自己写着
"增量要跑 113 x 64 = 7232 次迭代，而全量是 79872 次"（1248 块 x 64 像素）。
今天的位网格是 **8 行/块**（不是 64 像素/块），每块 4.5 µs：

| 脏集合 | 迭代数 | 估算耗时 |
|---|---|---|
| 113 块（墓碑里的数） | 113 x 8 = 904 | **0.4 ms** |
| 9 块（半径 6 的圆实际覆盖，去重后） | 72 | **0.03 ms** |
| 全量 1248 块 | 9984 | 5.6 ms |

**所以"增量无效"这个结论对位网格不成立**，值得复测（见 §5 第一步）。
这不是翻案 —— 墓碑记的是当时的事实，只是**它测的那条路径已经不是今天的代价结构了**。

### 1.5 连通性判据（销掉上一份研究的待办）

上一份研究留了一条"要核对我们的连通性是 4 邻域还是 8 邻域"，答案是：

- **分量提取是 4 邻域**：`Bits.flood` 逐块泛洪，跨块只在 `_group()` 里查
  **+X / +Y 两个正方向**（`src/core/destruction.gd:469`），对角不算连接。
  注释原文："对角不算连接、跨 chunk 只查 +X/+Y 避免重复"。
- **`touches_boundary()` 用八邻域**（`destruction.gd:141`）—— 那是**保守预筛**：
  判据是"伤害是否碰到形状边界"，八邻域是 4 邻域的超集，只会让它更常退回全量 split，
  **不会漏判**。所以行为与 Teardown 的"只共面算连接"一致。

---

## 2. 别人怎么做（外部材料）

> 完整笔记见 `_research/notes/`：`godot_voxel_collision.md`、`teardown_talks_re.md`、
> `voxel_destruction_projects.md`。本节是摘要 + 我这边逐行核对过的证据。

### 2.1 Zylann/godot_voxel：**每块一个静态体，只为"看得见的人"生成**

本地克隆：`_research/repo/godot_voxel`（`--depth 1`）。以下全部是**读过源码**的：

| 事实 | 证据 |
|---|---|
| 每个 mesh block（默认 16³ 体素）有**自己**的 `StaticBody3D`，用 **PhysicsServer3D 直连**（`DirectStaticBody`，不是场景节点） | `terrain/voxel_mesh_block.h:93` |
| 一个块**只有一个** `ConcavePolygonShape3D`；更新时 `remove_shape(0)` + `add_shape(新)` | `terrain/voxel_mesh_block.cpp:147-171` |
| 碰撞形状来自 **mesher 输出**：可以用渲染网格、网格的**一个子区间**、或专门的碰撞网格 | `voxel_mesh_block.cpp:218-260`（`is_generating_collision_surface()` / `submesh_vertex_end`） |
| **只有块附近有 viewer 时才生成碰撞**：`gen_collisions = _generate_collisions && block->collision_viewers.get() > 0`；否则 `set_collision_enabled(false)`（形状 0 关掉，但**保留**） | `terrain/fixed_lod/voxel_terrain.cpp:2067-2090` |
| `collision_layer` / `collision_mask` / `collision_margin` 是**地形级**属性，逐块套用 | `voxel_terrain.cpp:328-336, 2085-2086` |
| 碰撞随**块的重新网格化**一起更新 —— 也就是"只有脏块重建"，不是整个地形 | 同上：`update_block_from_ob()` 是唯一的块更新入口 |
| 另外提供 `VoxelBoxMover`：**"Helper to get simple AABB physics"** —— 直接在体素数据上做 AABB 扫掠 + 台阶攀爬，**完全不走物理引擎** | `terrain/fixed_lod/voxel_box_mover.h:14-45` |

**要点**：godot_voxel 的碰撞粒度 = **块**，而且**离玩家远的块干脆没有碰撞**。
这两条我们都没有：我们是"整个形状一个 body + 全量矩形"，
768x100 的地面即使只有一小块在屏幕上，也要为整块地算碰撞。

**深挖（子代理逐行核对，完整笔记 `_research/notes/godot_voxel_collision.md`）：**

- **脏块怎么算**：`post_edit_area()` → `mark_area_modified()` → 脏块 =
  `box_in_voxels.padded(1).downscaled(mesh_block_size)`（**外扩 1 格**，因为邻居块视觉上会被影响）；
  队列 `_blocks_pending_update`，用 `is_in_update_list` 去重。
  LOD 地形更狠：一次 LOD0 编辑会把**所有 LOD 层**的对应块全标脏。
- **线程模型**：改体素 + 标脏在调用方线程；**mesher 在线程池**；
  但**建 `ConcavePolygonShape3D` 必须回主线程** ——
  原文：`voxel_lod_terrain.cpp:1806` "Building collision shapes in threads efficiently is not supported."
  于是碰撞更新被摊到多帧（`process_deferred_collision_updates`，带主线程时间预算）。
- **性能注释（最有价值的一条）**：`doc/source/performance.md:131` 原文 ——
  "Creating a collider from a mesh is actually **much more expensive than meshing itself
  (about 3 to 5 times)**… Godot does not offer a reliable way to safely create these shapes
  *including their acceleration structure* from within our meshing threads.
  So instead, we had to defer it all to the main thread… **This slows down terrain loading tremendously.**"
  另有 `voxel_lod_terrain.cpp:2070`："collision meshes still take **5x** more time than building
  ALL rendering meshes"；`blocky_terrain.md:338`："The physics engine has to process arbitrary
  triangles near the player, **which can't take advantage of particular situations, such as
  everything being cubes**"。
- **没有**：Shape3D 对象池、HeightMapShape、`voxel_terrain_collision*` 文件、
  "块里没有表面就不生成碰撞"的机制。

⚠️ **但上面那条"建 shape 很贵"对我们不成立**：那是 **trimesh** 的代价
（要建 BVH、要遍历任意三角形）。Rapier 的 `cuboid` 是凸体，构造便宜一到两个数量级，
而且凸体没有隧穿问题。**我们的代价结构是反过来的：贵在"重算多少块"，不在"建多少个 shape"。**
不要照搬它的跨帧延迟队列 —— 那是为 trimesh 付的税。

### 2.2 Teardown：碰撞**建在体素网格上**，不是"体素 -> 多边形 -> 物理引擎"

（本节事实来自工作区 `teardown_physics_research.md` 与官方 API/modding 文档；
"演讲/逆向"部分由外部调研补，见 §2.4 与 `_research/notes/teardown_talks_re.md`。）

| 事实 | 依据 |
|---|---|
| 世界与可动物体**共用同一套体素网格表示**，破坏 = 删体素 + 连通性分割，脱离部分就地变刚体 | [官方] API + modding 文档 |
| 层次是 **Entity → Body（刚体）→ Shape（体素块）**；一个 Body 可挂多个 Shape | [官方] |
| **约束（Joint）挂在 Shape 上**，破坏时官方明说 "joints may be transferred to new shapes / detached / disabled" | [官方] |
| 质量 = **体素数 × 密度**（`GetShapeVoxelCount` + `SetShapeDensity`）；静态体质量恒 0；质心由体素分布决定 | [官方] |
| 连接判据只有**共面**："Voxels touching only by edge or corner will not stick together" | [官方] modding 文档 |
| 分裂是**引擎原语**：`SplitShape` / `MergeShape` / `IsShapeDisconnected` / `IsStaticShapeDetached` | [官方] |
| "还连着静态世界吗"是显式查询：`IsBodyJointedToStatic` —— 用来决定要不要继续模拟/入睡 | [官方] |
| 高速小物体走**查询**而不是求解器：`QueryShot(origin, dir, maxDist, radius)`（半径 0.5 = 扫掠球） | [官方] |
| 碰撞查询是自成一体的：`QueryRaycast` / `QueryAabbShapes` / `QueryClosestFire` / `IsShapeTouching` / `GetShapeClosestPoint` | [官方] |

**一手访谈（本次新找到，价值最高的一条证据）** ——
Dennis Gustafsson 接受 Software Engineering Daily 的访谈（EP1772，2025-01-02，
[完整文字稿](http://softwareengineeringdaily.com/wp-content/uploads/2024/12/SED1772-Teardown.txt)）。
他亲口说的三条，直接回答了"碰撞建在哪一层"：

> **[0:07:02]** "…normally when you do destruction with polygons… you have this triangle meshes.
> When you do destruction on those, there are a lot of gnarly cases with **degenerate triangles and
> floating-point precision issues**, and none of that really exists with voxels.
> Everything is nicely aligned on the grid. **It's all integer math**, and it's much more well-behaved."

> **[0:09:00]** "…from a physics perspective, a lot of physics actually turn out much nicer with voxels.
> That was something I thought was going to be challenging to do **collision detection**…
> but actually turned out **much easier than I thought**."

> **[0:22:48]** "…there was a limitation on this thing that **find connected parts**…
> even the last voxel, it would actually still stand… That's something we updated a few months later.
> It was a really challenging technical problem… to come up with an algorithm that could do that for
> **infinitely large objects**, because you may end up searching the whole level,
> which is **hundreds of millions of voxels**. So, it can be really slow."

另外两条同样有用：

- **[0:10:50] 结构强度没有做**："if you have a whole house… it is still connected.
  But in reality, it should just break." —— 连通性是**二值**的，没有应力/承重模拟。
- **[0:21:43] 用关节"假装"结构断裂**："You could also fake it a little bit by making the house
  in multiple parts and join them together with like **physical joints** instead.
  We do that for some parts of the buildings." —— 印证了官方 API 里 Joint 挂 Shape 的设计。
- **[0:07:02] 体素边长**："1 voxel is **10 centimeters**" —— 工作区
  `teardown_physics_research.md` 里"0.1 m 未核实"这一条**现在有一手来源了**。

**⚠️ 两条必须避开的误传**（工作区文档已判定，这里再强调一次）：

1. **"Teardown 用 small steps / Temporal Gauss-Seidel"是张冠李戴。**
   那是 Dennis 2025 年**新引擎**（新项目）的做法，不是 Teardown 本体。
2. **`devops-geek.net` 那篇《Dissecting the Teardown Engine》是 AI 生成内容**
   （页面自带 `AI Mode: tech` 标记）。上一份 `docs/voxel_destruction_research.md`
   引用了它 —— 那一条**应当撤掉**（见 §6 的文档订正）。

### 2.3 Vex-2.0（qrisquinn）：精读源码后的更正

上一份研究把它概括为"greedy meshing + 对象池"，读完之后要**更正两点**：

**它其实是一次性转化，不是渐进破坏。** `VoxelStructure:Destroy()`（`src/Vex:129-158`）
把整个 Model 体素化、生成全部 Part、然后 `source:Destroy()`。
**没有"擦一笔 -> 只改局部"的路径**，也没有连通性分割 ——
所以它的"性能手段"清单里那几条（池化、上限）**都是在"一次性生成几千个 Part"这个语境下的**，
不能直接类比我们的"每笔擦除"。

**焊接判据是错的（这条要避开）：**

```lua
-- src/Vex:99-115
local WELD_DISTANCE = self.config.voxelSize * 1.5
if (part1.Position - part2.Position).Magnitude <= WELD_DISTANCE then
    -- WeldConstraint
```

贪心合并之后，两个相邻大块的中心距 = (sizeA + sizeB)/2 个体素，**必然大于 1.5**，
于是"该焊的没焊"—— 物体受冲击时会从合并块之间散开。
正确的判据是**面相邻**（两个盒子共享一个面且重叠面积为正），
这也正是我们 `_group()` 已经在做的（+X/+Y 共面）。

**值得抄的**：

| 做法 | 证据 | 我们的状态 |
|---|---|---|
| 碎块碰撞组 `Debris`，**设成不与自身碰撞**（文档原话："This dramatically improves physics performance"） | `DOCUMENTATION.md:33-38`、`src/Config:16` | ❌ 桥接层没有 `collision_groups` |
| 对象池：按 `size_material_color` 作键复用 Part，单键上限 1000；释放时清焊接、`Anchored=true`、`CanCollide=false`、挪到 y=-10000 | `src/VoxelPool:35-112` | ⚠️ 我们是 RefCounted，创建便宜；但 `rects` 数组每次重建，可复用 |
| 上限保护：`maxVoxels`（默认 10000 / 上限 50000）、`voxelSize` 可调（0.1~10） | `src/Config:10-26` | ⚠️ 有 `min_fragment_pixels`、`max_rects_per_shape`，语义不同 |
| 力按**到爆心距离线性衰减**施加（半径 20 studs），走 `AssemblyLinearVelocity` 而不是 `ApplyImpulse` | `src/Vex:161-182` | ⚠️ 我们有 `apply_impulse`，衰减规则在游戏层 |

### 2.4 Unity / Unreal / 自研

**Unity：VoxelEngineExperiments（Vac2H2，本地已克隆）** —— 目前读到的最完整的一份"Teardown-like"实现，
但**它的物理是占位实现**，要看清哪部分能抄：

| 维度 | 它的做法 | 对我们的意义 |
|---|---|---|
| 体素布局 | Shape = 固定 8 个 chunk × 8³，**位平面**（Occupied/Face/Edge/Corner），每 chunk 64 B | 与我们的 8x8 uint64 同源；"表面体素"用位平面 O(1) 查 |
| 表面分类 | `exposedNeighborCount` 0/1/2/≥3 → Inside/Face/Edge/Corner，**Inside 不参与碰撞** | 2D 里等价于"只把边界像素交给碰撞"—— 我们用矩形覆盖已经隐含了这点 |
| 宽相 | 朴素 O(n²) + OBB SAT 复核；仓库里有 Morton TLSA BVH 但**未接入** | 反面教材 |
| 窄相 | 体素当球（半径 = 体素半边长），邻域 5³=125 格搜索，**只保留最深的一个接触点** | 反面教材：一个体素一个接触点会淹没求解器 |
| 求解 | 顺序冲量 10 迭代，无 warm start、无休眠、无 CCD、无关节 | 我们已经把这些交给 Rapier |
| 质量/惯性 | **手填 / 实心盒近似**（全仓库 grep `density` 零命中） | 我们**已经**做到了"体素推导"，这是我们的优势 |
| 破坏管线 | Burst Job 化、keep-mask、单 chunk 最多 4 个 fragment、只查 +X/+Y/+Z | 见 `docs/voxel_destruction_research.md` |
| DOTS 设计文档 | 宽相输出**chunk pair** 而不是 body pair；每帧两个 BVH 同步点；`DirtyTransformBodyIds` 做 O(dirty) 回写 | **"只处理脏的"这条思路在每一层都出现** |

**Noita（Nolla Games，2D 像素 —— 和我们最像的一个）** ——
完整笔记 `_research/notes/voxel_destruction_projects.md`（481 行）。

| 维度 | Noita 的做法 | 证据等级 |
|---|---|---|
| 世界模拟 | 逐像素落沙，世界切成 **64x64 chunk**，每 chunk 维护 **dirty rectangle**，只模拟脏像素 | GDC 2019 "Exploring the Tech and Design of Noita" 第三方笔记 |
| 刚体 | 实体的刚体用 `collision_shape = "box" / "circle"` + `collision_box_size` / `collision_radius`（**常规凸形状**） | [官方] modding 文档 |
| 刚体形状从哪来 | 第三方笔记只有一句 "Rigid bodies use a **marching square** algorithm"（把像素轮廓转成多边形），**未取得一手来源** | [未核实] |

**⚠️ 这条很关键**：Noita **不是**逐像素做刚体碰撞 —— 它把像素轮廓**转成少量凸形状**再交给物理。
这和我们"像素 -> 贪心矩形 -> Rapier"是**同一个精神**，只是转换算法不同
（marching squares 是轮廓近似，贪心矩形是**精确覆盖**）。
所以"用通用物理引擎 + 把体素转成凸形状"这条路**不是我们独有的妥协**，
Noita 这个量级的作品也这么做。

**Unreal：Voxel Plugin**（`_research/notes/voxel_destruction_projects.md`）

- Legacy 版：**complex collision = trimesh，只给静态查询；simple collision = 凸包**（`Num Convex Hulls Per Axis`）才能参与模拟。
  官方原文："Decomposing a mesh into convex hulls is a very complex & expensive problem"。
- 源码 `VoxelAsyncPhysicsCooker_Chaos.cpp` 里建了 Chaos trimesh，但 **`TriMesh->SetDoCollide(false)`** ——
  即**根本不让它参与碰撞**，只做查询。
- **VP2 直接砍掉了 Voxel Physics**（浮空碎块检测）。
- **UE 的 Chaos Destruction 是预破碎**（geometry collection，碎块形状预先烘死），**不是体素** ——
  别把它当成同类。

**其他（都是"凸体近似"这一派）**：Space Engineers 的方块用**离线烘好的 Havok 凸体**；
Voxlap（Ken Silverman）用**包围球**，作者原话 "I have not studied voxel-accurate collision"；
Claybook 是 SDF + GPU 物理。

**一个必须避开的坑（Space Engineers 官方博文自述）**：动态热插拔/焊接刚体
会导致**卡顿、刚体互相穿透、随机断连** —— 这正好从反面印证了 Vex-2.0 那条
"按中心距焊接"为什么危险。

---

## 3. 对照表：碰撞到底建在哪一层

| 维度 | Teardown | godot_voxel | Vex-2.0 (Roblox) | VoxelEngineExperiments (Unity) | **我们** |
|---|---|---|---|---|---|
| 碰撞粒度 | **体素**（Shape 内） | **块**（16³ 一块） | 贪心块（一盒一 Part） | 体素（球近似） | **整个形状** |
| 碰撞体类型 | 体素网格上的自定义空间索引 + 查询 | 每块一个 `ConcavePolygonShape3D` + 独立 StaticBody | 盒（Roblox Part） | 球（体素近似） | N 个 Rapier cuboid（一个 body） |
| 谁生成碰撞 | 引擎内核（`SplitShape` 等原语） | mesher 输出（可复用渲染网格/子区间/专用碰撞网格） | GreedyMesher | 逐对体素搜索 | `GreedyRects.decompose` **全量** |
| 更新触发 | 破坏时内建 | **脏块重新网格化** | 一次性转化 | 每帧全量 | **每笔擦除全量** |
| 只给近处生成 | — | ✅ `collision_viewers` | ✗ | ✗ | ✗ |
| 碰撞层/组 | 官方 API 有 | `collision_layer/mask`（地形级） | ✅ `Debris` 组不与自身碰撞 | ✗ | ❌ 未实现 |
| 高速物体 | `QueryShot`（查询） | `VoxelBoxMover`（自定义 AABB 扫掠） | — | ✗ | 自适应子步 + 扫掠 CCD |
| 质量/惯性 | 体素数 × 密度 | 不适用（静态） | Roblox 自动 | ❌ 手填 | ✅ 体素推导 |

**一句话**：四个参考实现里，**没有一个把碰撞建在"整个物体"这一层**。
Teardown 建在体素上，godot_voxel 建在块上，Vex-2.0 建在贪心盒上，
Unity 那个建在体素对上 —— 只有我们是"整个形状一次全量分解"。
我们**不能**照搬 Teardown（碰撞直接进体素网格）或 Unity 那个（逐体素接触），
因为那等于放弃 Rapier；但**"按块"这一层是可以搬过来的**（§4.2）。

---

## 4. 可以抄的 / 不能抄的

按**性价比**排序（"改动量 → 收益 → 风险"）：

### ★★★ 1. 擦除时**不要**让 `local_aabb()` 失效（行为不变，零基准风险）

**实测**：`local_aabb()` 要遍历全部 1248 块，**3.85 ms/次**（`_build_grid` 是 5.6 ms，
两者同一量级）。而 `PBody.rebuild()` → `mark_dirty_range()` 会 bump `revision`
→ AABB 缓存失效 → `decompose()` 第一件事就是 `shape.local_aabb()` → **白扫 1248 块**。

实测差值：`decompose`（AABB 冷）**8.66 ms** vs（AABB 热）**5.34 ms**
→ **每笔多付 3.3 ms**，占一笔擦除（~11-13 ms）的 **~27%**。

**修法**：删除只会**移除**像素，而移除**严格位于当前 AABB 内部**的矩形不可能改变 AABB
（AABB 的四条边由边上的像素定义）。所以：

```gdscript
# PixelShape：移除类改动专用（destruction 路径）
func note_removal(rect: Rect2i) -> void:
    mark_dirty_range(rect)          # 版本号照常 +1（渲染器要用）
    if _aabb_cache.encloses(rect):  # 严格在内 -> AABB 不可能变
        _aabb_rev = revision        # 把缓存重新"认证"到新版本号
```

**为什么这条排第一**：它**不改变任何数值**（AABB 结果逐位相同、矩形集合不变、
物理轨迹不变），所以**不会动 8 条基准** —— 而下面几条都会。

⚠️ 前提：只有"纯移除"能这么干。加像素（绘制 / 生长）必须走原来的全量重算，
或者用 `_aabb_cache.merge(rect)` 显式扩大。

### ★★★ 2. 把分解**按块缓存**（收益最大，但会动基准）

godot_voxel 的碰撞就是**逐块**的（脏块重建），我们却是"整个形状"的。
按今天的常数（**4.5 µs / 8x8 块**）：

| 方案 | 一笔（1~2 个脏块） | 768x100 实心地面的矩形数 |
|---|---|---|
| 现状：全形状 decompose | 5.3~7.6 ms（+ AABB 3.3） | 1 |
| 按 64x64 分解块缓存 | **0.3~0.6 ms** | 24（`_merge_pass` 后约 6~12） |
| 按 32x32 分解块缓存 | **0.1~0.2 ms** | 96（`_merge_pass` 后约 12~24） |

- 缓存的是**每块的矩形列表**（不是位网格）—— 这正是上一轮墓碑里那条"增量网格"
  失败的地方：它缓存的还是整张网格，只是跳过写入。
- 跨块的贪心不再可能（矩形不跨界），但 `_merge_pass` 能把同跨度的相邻矩形再合回去，
  代价可接受（48 矩形时 0.12 ms）。
- **脏区域必须先外扩 1 格再折算成块**（godot_voxel 的原话：
  "We pad by 1 because neighbor blocks might be affected visually"，
  `voxel_terrain.cpp:823-839`）。我们的伤害包围盒同样要 `grow(1)` ——
  擦掉一个像素会改变**邻居块**的贪心结果（一个矩形可能因此能跨过原边界）。
- **⚠️ 代价：矩形集合会变 → 接触流形会变 → 8 条基准会移动。**
  和"角接触修复"那次一样，必须**单独一个提交 + 明确重设基准**，
  不能混在别的改动里（否则分不清是谁动的）。

### ⚠️⚠️ 实测回滚：接缝会毁掉接触 —— 这条**不要做**

按上面的设计实现了一版（64x64 块 + 每块双向贪心 + 全局 `_merge_pass`，
缓存做成**自校验**：每次比对该块 64 个 chunk 的占用字，不依赖任何"谁改了要通知我"
的脏标记）。它确实快：`decompose` 20.4 -> 3.3 ms（374 矩形），
擦除路径 **14.2 -> 7.65 ms/笔**，`validation_block_cache` 156 项断言全过
（含"直接改 `chunk.occ` 绕过所有标记"那条）。
**但它被 8 条基准拦下来了，已回滚。**

**症状**：`tests/dump_state.gd` 的 `stack:6:5` 里，c=4 那列箱子
（局部 2040，右沿 2047）**离接缝（局部 2048）1 像素** —— 两个箱子**翻了 90°、
滑走 47 像素**；旧版 30 个箱子的 rotation 全是 0。

**机制是定死的（不是混沌，也不是矩形数或顺序）**：同一个代码路径下，

| 地面宽 | 矩形数 | 结果 |
|---|---|---|
| **4096**（64 的整数倍 → 进位合并成 **1 个**） | 1 | 30 个箱子**纹丝不动** |
| **4000 / 4032**（接缝在 2048） | 6 | **倒塌**（2 个箱子翻 90°） |

再按"箱子右沿到接缝的距离"扫描：**1 像素 → 倒塌；4 像素（箱子跨接缝）→ 滑 6.5 像素；
15 像素 → 完全静止**。旧版（1 个矩形，无接缝）在任何偏移下都完美静止。

**这条错在哪**：上面的成本/收益表只算了"重算多少块"和"矩形数膨胀"
（后者实测很准：带洞形状 483 -> 517，只 +7%），
**没有算"接缝会不会毁掉接触"** —— 而这是会毁掉整个方案的量。
矩形不再跨块 = 实心表面上凭空多出接缝，而箱子**恰恰就停在表面上**。

### 接缝的机制：查清了（试验台 `tests/diag_seam_matrix.gd`）

**做法**：地面先建好，再**直接注入**想测的矩形布局
（`body.rects` + `rects_rev` → op5），箱子位置、物理参数、步数全不变 ——
唯一的变量就是地面被切成了什么形状。30 秒验一个布局假设。

| 地面布局 | 矩形 | 结果 |
|---|---|---|
| `[0,4000]` 整块 | 1 | 完全静止 |
| 按块那 6 个（接缝 2048…） | 6 | **倒塌**（2 个翻 90°、滑 47 像素）|
| 同上、顺序倒过来 | 6 | 倒塌（dx 45.4）→ **与顺序无关** |
| 6 个但互相**重叠 1 像素** | 6 | 倒塌（dx 44.8）→ **裂缝/重叠不是原因** |
| 2 个（`[0,3968]`+`[3968,4000]`） | 2 | **完全静止** |
| 6 个但接缝全在箱子左边（x<1760） | 6 | **完全静止** |
| 6 个但接缝处留 1 像素**真空隙** | 6 | 倒塌（dx 32.2）|
| 3 个（接缝 2048 与 2049 都贴着箱子） | 3 | 倒塌 |

**四个猜测全被否掉**：不是矩形数（6 个也能稳）、不是顺序、不是裂缝/重叠、
不是碰撞体数量。**触发条件是"矩形边界落在离静止物体边缘 ~1 像素处"**。

**所以"能否解决"要分两层**：

- ✅ **人造接缝这一类能解决**：把实心区域并成**最大行程**（而不是
  `_merge_pass` 现在那种"进位"语义 —— 3 个等尺寸连排停在 2 个），
  4000 宽的地面就只留 1 个接缝、且落在区域末端 —— 表里 ⑤ 已证明这种布局是稳的。
  再进一步"同行不同宽也并"，实心矩形区会并成 **1 个矩形、零接缝**
  （等于旧全局贪心的结果）。
- ❌ **类别本身消不掉**：任何**残留**边界，只要有物体停在它 1 像素内，照样掀翻。
  所以这条路必须**自带一个"停在边界 1 像素处"的基准**守住它，
  否则下次改合并规则时会静默退化。

**⚠️ 但收益要先重算**：位网格改成自校验增量重建之后（见 §5 第 1 条），
768x100 的擦除已经是 **10.83 ms/笔**，其中分解只占 ~3 ms ——
剩下的大头是 `renderer.sync`（~6.8 ms）。
所以"按块分解 + 最大行程合并"值得做的**前提**是把 `renderer.sync` 一起算账，
而不是只看分解那一段（它现在只占 28%）。

### ★★ 3. 碎块独立碰撞组（抄 Vex-2.0 的 "Debris"）

Vex-2.0 的官方文档第 33-38 行直接写：建一个 `Debris` 碰撞组、
**设成不与自身碰撞**，"这能极大改善物理性能"。

我们**现在做不到**：`rapier_bridge` 里 `ColliderBuilder` 只设了
`friction`（`lib.rs:124`），没有 `collision_groups`，命令流也没有对应 op。
Rapier 0.36 本身支持 `InteractionGroups`，所以要加的是**桥接层的一个字段**，不是算法。

⚠️ 风险：这条会**改变手感**（碎块会互相穿透堆叠），必须先量"接触对少了多少"
再决定，不能只因为"别人这么做"就上。

### ★ 4. 每块一个碰撞体槽位（op5 的部分替换）

现在 `rb_body_set_rects`（`lib.rs:112`）是**清空该刚体全部碰撞体再重建**。
好处是简单、且 Rapier 的 compound pseudo-normals 依赖"兄弟碰撞体"关系；
坏处是每次改动都要 churn 全部 N 个碰撞体。

不过**实测推送只要 0.17 ms/笔**，所以这条**优先级低** ——
在分解还是 5~8 ms 的时候优化推送是打错目标（这个项目在
"优化错了目标"上已经栽过一次，见开发日志第 6 轮）。

### ★ 5. 只把"外壳矩形"送进 Rapier（候选，先量再上）

Teardown / VoxelEngineExperiments 都显式区分 `Inside` 与表面体素，**内部体素不参与碰撞**
（`exposedNeighborCount == 0 -> Inside`，直接跳过）。我们的贪心矩形覆盖的是**全部占用像素**，
包括被完全包住的内部矩形。

- 安全前提：内部矩形被其它矩形完全围住 —— 刚体要进到那里，**必须穿过外壳**，
  而我们有自适应子步，所以几何上成立；且 body 的 AABB 是全部 collider 的并集，
  丢掉内部矩形**不会**缩小 AABB。
- ⚠️ 但**预期收益小**：贪心本来就把实心区域合成 1 个矩形（768x100 实心 = 1 个），
  真正碎的形状（有洞）产出的 60 个矩形**几乎都贴着边界**。
- 所以这条要**先量"有多少矩形是严格内部的"**再决定，别凭直觉做。

### ★ 6. 增量更新的顺序纪律（godot_voxel 的教训）

1. **一次分解，两份输出** —— 绝不为了"再来一份碰撞数据"重跑贪心。
2. **脏区外扩 1 格再折算成块**（见 §4.2）。
3. **enable/disable 优先于 remove/insert**（但要先 profile：Rapier 里被禁用的 collider
   是否仍占宽相）。
4. **连续擦除要节流**：godot_voxel 的 `process_deferred_collision_updates` 用
   "至少处理一个，再查超时"的主线程时间预算 —— 连挖连炸时不要每笔都全量重建。

### ✗ 不要抄的

- **Vex-2.0 的"按中心距焊接"**：`distance(part1.Position, part2.Position) <= voxelSize * 1.5`
  （`src/Vex:99-115`）—— 贪心合并出的大块之间中心距必然大于 1.5 个体素，
  **该焊的焊不上**，物体会在受力时散开。判据应该是**盒子的面相邻**（AABB 共面接触），
  不是中心距。我们已经有精确的 4 邻域连通性，不需要退化成距离启发式。
- **动态焊接 / 热插拔刚体**：Space Engineers 官方博文自述会导致卡顿、**刚体互相穿透**、
  随机断连；Vex-2.0 的按中心距焊接是同一个坑的另一个版本。
  我们的"一个形状一个 body + N 个 collider"反而是稳的那一侧，别改成"每块一个 body"。
- **把碰撞交给"每个体素一个碰撞体"**：Vex-2.0 的非贪心路径就是一体素一 Part
  （`GreedyMesher.createNaiveMeshes`），Roblox 侧靠引擎扛；
  我们在 Rapier 上这么做会直接把宽相打爆。

---

## 5. 下一步（按顺序，都可测）

1. ~~**复测"按块增量"到底值多少**~~ —— **已复测，两条路都走了，结论相反**：
   · ✅ **位网格改成"自校验增量重建"**（比 §4.2 更小的一步，已落地）：
     网格缓存在 PixelShape 上，每次只重写**指纹变了的块**（比对每块 64 个 chunk
     的占用字，**不依赖任何脏标记**）。实测 `build_grid` **5 倍**
     （2048x128：17.35 -> 3.44 ms），整笔擦除 **-25% ~ -29%**，
     而**8 条基准逐位不变**（矩形集合没变）—— 这是它最大的优点。
     ⚠️ 墓碑里"增量无效"的结论确实是**字节网格 + 逐像素脏集合**时代量的
     （一个半径 6 的圆标 113 个 chunk），今天两个前提都不成立；
     墓碑已改写，把"为什么当年失败"和"为什么现在成立"都留下。
   · ❌ **§4.2 的按块分解实测回滚**（见上面"实测回滚"一节）：它更快
     （擦除 14.2 -> 7.65 ms/笔），但接缝会把停在 1 像素外的箱子掀翻。
     要再走那条路，先解决接缝（最大行程合并）+ 专门的接缝基准场景。
2. ~~**AABB 那条（§4.1）单独一个提交**~~ —— **已完成（`ea72019`）**：
   内部擦除 23.5 -> 14.9 ms/笔，8 条基准逐位不变。
3. 再决定 §4.2 的分解块尺寸（32 / 64 / 128）—— 现在被第 1 条挡着：
   块尺寸只在"按块分解"这条路上才有意义，而那条路要先解决接缝。
4. §4.3 的碰撞组要先量接触对数，再谈手感。

**不要做**：在分解还是 5~8 ms 的时候去优化 Rapier 侧的推送（0.17 ms）。