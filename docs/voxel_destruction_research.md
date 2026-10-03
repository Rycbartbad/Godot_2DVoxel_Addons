# 体素破坏：别人怎么做的（对照总结）

> 起因：擦除性能。本项目的擦除路径约 12 ms/笔，其中 `decompose` 占绝大部分
> （`_build_grid` 8.7 ms + `_greedy` 3.8 ms）。写这份是因为**一直在自己的实现里
> 打转**，应该先看别人解过没有。

## 一、根本差别：碰撞建在哪里

**Teardown（及其公开的破坏管线实现）在体素网格上直接做碰撞** ——
自定义空间索引 + spatial hashing，**不是**把形状分解成多边形再交给物理引擎。

> 原文（[Dissecting the Teardown Engine](https://devops-geek.net/nerd-space/dissecting-the-teardown-engine-a-technical-autopsy-of-voxel-destruction-pipelines/)）：
> "…executing rigid body dynamics, material stress propagation, and ray-traced
> rendering directly on uniform spatial data structures… can bypass the
> computational bottlenecks of traditional CAD-style breaking mechanics."

**这对我们意味着什么**：`GreedyRects.decompose` 存在的**唯一理由**是
Rapier 需要矩形碰撞体。这个成本是"用通用物理引擎"的代价，不是破坏系统本身需要的。

换掉 Rapier 不现实（我们刚从手写内核换过来，鲁棒性收益是实测的）。
所以只能在**喂给 Rapier 的数据**上省。

## 二、Vex-2.0：和我们做同一件事，但手段不同

[qrisquinn/Vex-2.0](https://github.com/qrisquinn/Vex-2.0) ——
"High-performance voxel destruction system for Roblox with greedy meshing and
object pooling"。

它**也做 greedy meshing**（把相邻体素合并成大块），和我们的 `GreedyRects` 同源。
所以分解这条路本身没错。但它的性能手段是：

| 手段 | 说明 | 我们 |
|---|---|---|
| **Greedy meshing** | 相邻体素合并成大块 | ✅ 已有（`GreedyRects`） |
| **对象池** | 复用零件而不是反复创建/销毁 | ⚠️ 我们是 RefCounted，创建便宜，但**没池化** |
| **maxVoxels 上限** | 防止崩溃 | ⚠️ 有 `max_rects_per_shape`，但语义不同 |
| **碎块独立碰撞组** | 碎块之间不互相碰撞，省一大截 | ❌ 没做（2D 里也许可用 collision layer） |
| **大结构用更大体素** | `voxelSize = 2/3` | ⚠️ 我们的体素尺寸固定 1 |

## 三、公开破坏管线的实现要点（工作区 teardown_physics_research.md §2.3）

那是**作业化、多线程、全位掩码**的管线：

~~~
DestructionShapeChunkOverlapJob      破坏形状 chunk × 目标 chunk 重叠检测
  -> DestructionMaskGenerationJob    生成 64B"保留掩码"
  -> ShapeVoxelRemoveJob             source & keepMask
  -> ShapeChunkFragmentJob           X-run/切片泛洪，单 chunk 最多 4 个 fragment
  -> ShapeChunkConnectivityJob       面位检测（+X/+Y/+Z 三方向）
  -> ShapeFragmentUnionJob           固定 32 node 的 union-find
  -> ShapeBuildJob                   组装最终 shape 缓冲
~~~

**值得抄的几条：**

1. **keep-mask 语义**：`bit 1 = 保留，bit 0 = 删除`，初始化 `0xFF`，
   删除统一 `target = source & removeMask`。
   → 这正是**位网格**的思想，也是子代理在做的方向。

2. **连通性只查 +X/+Y/+Z 三个正方向** —— 避免重复计算，也避免跨线程反向写。
   → 我们 2D 里应该只查 +X/+Y。**值得核对 `_components_cpu` 有没有重复查。**

3. **单 chunk 最多输出 4 个 fragment**，小于阈值的碎块直接丢弃。
   → 我们有 `min_fragment_pixels`，但没有"每 chunk 上限"。
     碎块数是擦除路径上 `split` 成本的来源之一。

4. **只查 6 邻域（共面）**，与 Teardown 官方"edge/corner 不算连接"一致。
   → ⚠️ **要核对我们的连通性判据是 4 邻域还是 8 邻域。**
     如果是 8 邻域，我们和 Teardown 的语义**不一致** —— 那不只是性能问题，
     是行为差异（斜角相连的两块在 Teardown 里会断开，在我们这里不会）。

## 四、结论与下一步

**方向确认**：位网格是对的（三份材料都指向位掩码/word 级操作）。
子代理正在做。

**另外三条值得单独评估**（按性价比）：

1. **核对连通性邻域**（4 vs 8）—— 可能是**行为差异**而不只是性能。
   便宜、且影响正确性，应该先查。
2. **碎块上限（每 chunk 最多 N 个）** —— 直接降 `split` 与后续 `rebuild` 的成本。
3. **碎块独立碰撞层** —— 2D 里可以让碎块之间不互相碰撞，
   省掉大量接触对。但要确认手感是否可接受。

**不要做的**：把 `_build_grid` 的"逐像素写"换成"逐行原生拼接" ——
实测**完全一样快**（8.71 ms），因为地板是**迭代次数**（每次 GDScript 操作约 1 µs），
不是每次写多少字节。这条已经踩过并回退。

## 来源

- [qrisquinn/Vex-2.0](https://github.com/qrisquinn/Vex-2.0) — greedy meshing + 池化的体素破坏
- [Dissecting the Teardown Engine](https://devops-geek.net/nerd-space/dissecting-the-teardown-engine-a-technical-autopsy-of-voxel-destruction-pipelines/) — Teardown 破坏管线剖析
- [Need help properly understanding how colliders work in Teardown](https://gamedev.stackexchange.com/questions/216959/need-help-properly-understanding-how-colliders-work-in-teardown) — 碰撞体讨论
- 工作区 `teardown_physics_research.md` §2.3 破坏管线
