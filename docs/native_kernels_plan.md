# 方案 A：把五个内核搬进原生代码（落地设计）

> 这份文档只写**已经在代码里核对过**的东西。本会话的教训：凭直觉归因每次都错
> （见 docs/perf_optimization_options.md 的方法论一节），所以每条都标了出处。

## 一、为什么是这五个内核

本会话量到的账（768x100 一刀 r=60，`world.fracture` 实测 ~36 ms）：

| 内核 | 现状 | 实测 | 数据依赖 |
|---|---|---|---|
| `make_keep_mask`（伤害命中判定） | 逐像素 | 5.9 ms / 14400 像素 | occ + mat |
| `MassProps.compute` | 逐像素（已改逐块 popcount，7 倍） | 5.1 ms | occ + mat + 材质表 |
| `_assemble` 的逐块拷贝 | 逐 chunk | 7.7 ms / 1098 chunk | occ + mat + aux |
| `_group` 并查集 | 逐 chunk | 3.8 ms / 1248 chunk | occ |
| `_decompose_block` 网格构建 + 贪心 + 合并 | 逐 chunk 行 | ~0.5 ms/块 | occ |

规律：所有热点都是**每 chunk 0.3~7 us、每像素 ~0.5 us** —— 全是 GDScript 解释器开销。
同一批数据在 Rust 里是**几十微秒**级别。

## 二、架构（已核对）

三层，**引擎真源只有 src/ + gdext/**（`tools/build_addon.py` 的文件头写明；
`addons/pixel_destruction/native/rapier_bridge/src/lib.rs` 是**构建产物副本**，不要直接改）：

    src/physics/pworld.gd            GDScript 调用方（_rp.cmd(inp, tmpl)，见 pworld.gd:652）
      -> ClassDB.instantiate("RapierPhys")            （pworld.gd:741）
    gdext/fastphys.cpp               C++ GDExtension：RapierPhys 类 + cmd 协议 + FFI
      -> g_rap.*（RapierApi 函数表）                  （fastphys.cpp:140）
    gdext/rapier_bridge/src/lib.rs   Rust cdylib：struct World（真正的物理）

构建：`python tools/build_native.py`（Rust）-> `python tools/build_addon.py`（打包）。
`gdext/fastphys.dll` 与 `gdext/rapier_bridge.dll` 已存在，`cargo 1.99` / `rustc 1.99` 在位。
⚠️ `tools/check_addon.py` 退出 1 是**正常态**（addon 是构建产物，不进仓库）。

## 三、cmd 协议（已核对 fastphys.cpp:268-306）

- `cmd(in, out)` 是一条**命令流**：`while (r.ok && r.i < r.n)` 逐个 op 执行，每个 op 以
  `u8 opcode` 开头，参数按**小端、memcpy、不要求对齐**读。
- 读取器有：`u8 / i32 / u32 / f64 / f32s(count, dst)`（批量 float）。
- 写入器**只有** `i32 / f64` —— 要输出批量字节/整数数组得先给它加一个（约 5 行）。
- 现有 op 到 **23**（23 = ccd substeps）。新 op 用下一个空号，**加之前先确认**。
- 参数里已经有 bulk float 的先例（case 5 的 collider 推送，用 `rect_scratch` 复用缓冲）。

## 四、数据怎么过去（这是方案 A 的真正成本所在）

⚠️⚠️ **绝不能变成"第二份真源"** —— 项目的原则是"材质是**一份数据**"（见
`pixel_world.gd` 的注释）。所以原生内核必须是**纯函数**：GDScript 把数据传过去、
拿结果回来，原生侧**不持有**权威状态。

- **Phase 1/2/3 的输入**：chunk 的 `occ`（int64，每 chunk 8 字节）+ 需要时 `mat`（64 字节）。
  768x100 = 1248 chunk -> occ 只有 **10 KB**，occ+mat 约 **90 KB**。
- **打包成本**：GDScript 逐 chunk 写进 `PackedByteArray` 约 1~2 us/chunk（1248 chunk ≈ 1.2~2.5 ms）
  —— ⚠️ **这是必须计入的净成本**，它吃掉一部分收益。
- **对策（按项目已有的模式）**：把打包结果**按 revision 缓存**在 shape 上（自校验指纹，
  和 `_grid_sigs`/按块矩形缓存同一个模式；**不要用脏标记**）。
  破坏/擦除会改内容 -> 那次要重打包；而**同一形状被反复分解**（渲染、AABB、质量、
  分块缓存失效重算）时打包是零成本。
- **Phase 4（拷贝，7.7 ms，最大的一项）特殊**：它是**数据结构**操作（要给分片建出各自的
  chunk 字典），不是纯计算。原生只能把"分片的网格"算出来，GDScript 仍要逐 chunk 物化
  —— 省不掉那趟循环。所以 **Phase 4 要么不做，要么走"原生持有网格 + GDScript 句柄"**，
  那是数据模型级改动，风险最高，单独评估。

## 五、分期（每期都必须能被闸门钉住）

| 期 | op | 输入 | 输出 | 预期 | 闸门 |
|---|---|---|---|---|---|
| 1 | `shape_rects`（按块贪心 + 最大行程合并） | occ | 矩形列表（i32） | 6.3 -> ~0.1 ms | `validation_merge_equiv` + `validation_fragment_cover`（逐像素 phantom/missing/overlap = 0）+ 8 条基准 |
| 2 | `shape_mass`（边际量） | occ + mat + 材质表 | 10 个 f64 | 5.1 -> ~0.05 ms | `validation_mass_props`（35 项，对冻结旧实现 1e-12）|
| 3 | `damage_keep_mask` | occ + 伤害几何 | 位掩码（字节） | 5.9 -> ~0.05 ms | `validation_damage_mask`（12000 组，逐位）|
| 4 | `shape_components`（并查集） | occ | 标签 | 5.6 -> ~0.1 ms | `validation_local_connect` + `validation_connected_body` |

**先从 Phase 1 开始**，理由：
1. **纯函数**（不产生任何状态）-> 不可能制造"第二份真源"；
2. 输入只要 **occ**（不需要 mat）-> 打包最便宜；
3. 输出小（几百个 i32）；
4. 它每笔破坏都跑，而且**已经有逐像素的等价闸门**（`validation_fragment_cover`），
   位等价是可直接验证的。

⚠️ **必须位等价**：新 op 的输出要和 GDScript 版**逐位相同**（矩形顺序、起点、尺寸都算），
否则碰撞体变了、基准就动。做法：先在探针里对同一批形状跑"两边对照"，逐矩形比对。

## 六、验证与构建循环

1. 改 `gdext/rapier_bridge/src/lib.rs`（Rust 内核）+ `gdext/fastphys.cpp`（新 op 与 FFI）
2. `python tools/build_native.py` -> `python tools/build_addon.py`
3. 对照探针（两边逐矩形比对）-> 通过后切换 GDScript 调用点
4. 全量测试 + **8 条基准逐位不变**（这是硬判据）
5. ⚠️ 保留 GDScript 实现作为**回退路径**（扩展不可用时自动降级）—— 项目已有这个模式
   （`pworld.gd:746` 的 "RapierPhys 扩展不可用" 分支）。

## 七、风险

- **三语言改动**：C++ 的 op + Rust 的内核 + GDScript 的调用点，任何一处不齐都会静默降级
  （项目栽过"两条路径的接触点差出 3.88 个单位"，见 development_log 坑 18/31/36）。
  -> 对策：op 里带**版本号/魔数**，不匹配就明确报错，不要静默走另一条路。
- **"纯 GDScript、零依赖"的卖点会打折**：扩展不可用时必须仍能跑（回退路径），
  所以两套实现都要维护 -> 每加一个原生内核，就多一份要同步的等价性负担。
- **净收益要算打包成本**（第四节）。Phase 1 的净收益 ≈ 6.3 - 2.5 ≈ **3.8 ms/笔**；
  缓存生效时 ≈ 6.2 ms。
