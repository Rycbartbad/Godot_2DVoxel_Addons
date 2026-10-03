# 性能手册

**本页所有数字都是实测的**，不是估计。测法见文末。

---

## 1. 一个时间步花在哪

场景：503 个刚体（碎片）、1142 个流形、每步 1 个子步。

| 阶段 | 时间 | 占比 | 在哪 |
|---|---|---|---|
| **宽相** | 1.885 ms | 42.2% | 其中 93% 是 GDScript 侧准备 |
| 求解 | 1.201 ms | 26.9% | C++（原生求解器） |
| update_aabb | 0.487 ms | 10.9% | GDScript |
| integrate_transforms | 0.377 ms | 8.4% | GDScript |
| integrate_forces | 0.229 ms | 5.1% | GDScript |
| wake_pass | 0.225 ms | 5.0% | GDScript |
| clear_pseudo | 0.068 ms | 1.5% | GDScript |
| **合计** | **4.472 ms** | | |

### 宽相那 1.885 ms 里到底是什么

```
GDScript 侧准备  1.814 ms   (93%)
    ├─ 扫掠 AABB   0.268 ms
    ├─ 排序        0.943 ms   <- 最大单项
    └─ 编码打包表  0.603 ms
纯 C++ 调用      0.125 ms   ( 7%)
```

> **结论反直觉**：C++ 宽相只占 7%，优化它没意义。
> 真正的瓶颈是**过边界之前的 GDScript 准备** —— 尤其是排序（`sort_custom` + lambda 比较器，
> 503 个物体 ~0.94 ms）。

---

## 2. 单次操作的实测开销

| 操作 | 开销 | 说明 |
|---|---|---|
| `shape.set_pixel()` | **1289 ns** | 含 chunk 查找+创建+标脏，多层函数调用 |
| 直改 `chunk.mat[i]` | **527 ns** | 批量路径，比上面快 2.4x |
| `shape.mark_dirty()` | 327 ns | 已脏时早退，一次查表 |
| `PackedByteArray.encode_double` | 32.4 ns | |
| `PackedFloat64Array` 下标写 | 23.5 ns | 比 encode 快 1.38x |
| `PackedFloat64Array` 下标读 | 20.1 ns | |

**GDScript 的函数调用开销主导一切。** 所以热循环里的原则是：
**减少调用次数，而不是减少工作量。**

---

## 3. 选路指南

### 体素编辑：永远走批量路径

```gdscript
# ✗ 每像素 1289 ns —— 240 个碎片 x 16 像素就是 5 ms
shape.set_pixel(x, y, mat)

# ✓ 每像素 527 ns，且标脏只要每个 chunk 一次
var c: PixelChunk = shape.chunks[key]
c.mat[i] = mat
shape.mark_dirty(cx, cy)        # 一个 chunk 一次，不是一像素一次
```

### 原生加速：装了就别关

| | 收益 |
|---|---|
| 求解器（含数据搬运） | **16 ~ 28x** |
| 宽相（含数据搬运） | 1.9 ~ 2.5x |
| 拖动时的 step | 从慢 8.00x 到 1.06x |

⚠️ 这条的原始理由（"原生与 GDScript 逐位一致，所以开了不改变行为"）**已作废**：
GDScript 那一份实现已经删除，native 就是唯一实现。

### 子步：默认就好

子步按「最快物体每步走多远」自动切，目标每子步位移 <= 2 像素。
实测调好的配置下绝大多数场景是 **1 个子步**。

> 手动调 `ccd_max_substeps` 要小心：子步数会改变接触时序，进而改变物理结果。
> 而且它和 `max_speculative_margin` 是**耦合**的 —— 见 pitfalls.md。

### 休眠：大规模场景必须开

```gdscript
px.world.sleeping_enabled = true        # 默认就是 true
```

关掉的话 240 个静置碎片会一直烧 CPU。实测开着时静置场景稳定在 **0/12 清醒**。

### GPU：只对体素有用，对刚体没用

| 该上 GPU 的 | 不该上 GPU 的 |
|---|---|
| 体素元胞自动机（游戏层） | 刚体物理（几百个物体，传输开销大于收益） |
| 破坏的连通性标注（已实现） | 宽相/求解（C++ 单线程就够了） |

破坏管线已经有 GPU 路径（`Destruction.apply_damage_and_split_gpu`，用 RenderingDevice），
无 GPU 时自动退回 CPU ✓。

---

## 4. 规模上限（实测）

| 场景 | 物体 | 每步 | 说明 |
|---|---|---|---|
| 堆叠 | 241 | 2.19 ms | |
| 碎片 | 503 | 4.42 ms | 60 FPS 的预算是 16.7 ms，还有余量 |

**瓶颈不在物理，在体素。** 240 个碎片 = 3840 个体素；如果每 tick 全扫一遍，
光遍历就吃掉整个预算。这就是脏区域跟踪存在的理由。

---

## 5. 怎么自己测

```bash
# 分阶段耗时（最有用）
godot --headless --path . --script res://tests/bench_phase.gd

# 单个操作的微基准
godot --headless --path . --script res://tests/bench_encode.gd      # 打包缓冲读写
godot --headless --path . --script res://tests/bench_brush.gd       # 画笔光栅化
godot --headless --path . --script res://tests/bench_grab_cost.gd   # 拖动开销

# 分阶段剖析（更多计数器）
godot --headless --path . --script res://tests/profile_stages.gd
```

### 剖析的三个纪律

1. **取多次最小值**，不要取平均 —— 平均会被 GC/调度噪声污染。
2. **先量再改。** 这次剖析就推翻了我的假设：我以为 `encode_double` 是主因，
   实测只占 13%；真正的瓶颈是排序。
3. **小心把被测对象优化掉。** 累加一个校验和再打印，否则循环可能被消掉。

---

## 6. 已知的优化空间（按实测收益排序）

| 项 | 预期收益 | 代价 |
|---|---|---|
| 排序搬进 C++ | ~0.9 ms（20%） | 需先把排序键做成**全序**，会改基准 |
| 扫掠 AABB 搬进 C++ | ~0.27 ms（6%） | 低 |
| 编码换 packed 数值数组 | ~0.28 ms（6%） | 低 |
| update_aabb 搬进 C++ | ~0.49 ms（11%） | 中 |

> **排序为什么不能直接搬**：现在用 `sort_custom`（不稳定排序），并列元素的次序取决于
> Godot 内部实现 —— 换个引擎版本就可能变。要搬进 C++ 必须先把排序键做成全序
> （key + index 字典序），那样任何正确排序算法都给同一结果，
> 代价是并列元素的次序变了（基准要重记），换来的是**跨引擎版本稳定**。
