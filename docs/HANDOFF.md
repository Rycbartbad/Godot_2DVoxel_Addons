# 交接提示词

> 把这份内容作为**新会话的第一条消息**发给助手。它包含：项目是什么、
> 硬性规则、当前状态、**未完成的事（带测量数据）**、以及**上一个助手踩过的坑**。
>
> 最近一次重写：`fac0d95`（本轮做了擦除性能 + 碰撞层对照研究）。

---

## 项目

`D:\Godot_v4.7.2\TapTap2026` —— Godot 4.7.2 + GDScript 的 **2D 像素破坏物理引擎**
（参考 Teardown 的能力集，但**不要用 teardown 命名**任何东西）。MIT。

引擎是**可迁移的 addon**：真源在 `src/`，`tools/build_addon.py` 生成构建产物。
**构建产物绝不进项目树**（见下）。

**物理已经完全交给 Rapier**（`rapier2d 0.36`，Rust cdylib + GDExtension）。
GDScript 那份自研求解器**已全部删除**，只剩 native 一条路 ——
所以**不再需要 `use_xxx` 这类开关**。

原生层只暴露**一个方法**：`RapierPhys.cmd(in, out_template) -> PackedByteArray`，
走命令流协议（`in = [i32 out_cap][i32 cmd_len][ops...]`）。
操作码 0..23 是刚体/世界，**24..31 是关节**（见 `gdext/fastphys.cpp` 顶部的文档注释）。

**引擎只提供机制，规则在游戏层。** 节点层尽量像 Godot 内置
（`PixelWorld` / `PixelBody2D` / `PixelShape2D` / `PixelMaterial` / `DebugOverlay`）。

## 硬性规则（AGENTS.md 的要点）

1. **开发只在 `main`**，不要自己跑 `promote.py --yes`（推进 stable 是人的决定）。
2. **提交前全绿**：`python tools/check_docs.py` + 全部测试。
3. **不要把凭据写进对话**。
4. **注释写"为什么"**，踩过的坑写成墓碑注释（说明当时错在哪、症状是什么）。
5. **发布前先同步文档** —— 已做成闸门，`promote.py` 会自动跑。

## 常用命令

```powershell
$exe = 'D:\Godot_v4.7.2\Godot_v4.7.2-stable_win64_console.exe'

# 构建（构建 -> 自检 -> **移出项目树**）—— 顺序是强制的，别拆开
python tools/build_addon.py --verify

# 依赖 addon 产物的测试（三个）—— 必须**先在树内构建**，跑完再移出去
python tools/build_addon.py            # 不带 --verify 才会留在树内
& $exe --headless --path . --script res://tests/validation_facade_api.gd
& $exe --headless --path . --script res://tests/validation_fusion.gd
& $exe --headless --path . --script res://tests/check_manual_api.gd
python tools/build_addon.py --verify   # 再移出去

# 文档闸门
python tools/check_docs.py -v

# 基准（发布前必须逐位不变）
& $exe --headless --path . --script res://tests/dump_state.gd
```

## ⚠️⚠️ 跑测试的正确姿势（这里踩过整整一轮）

`tests/` 下有 **134 个 .gd**，但**只有 `test_*` 和 `validation_*` 是自检测试**。
其余是探针（`diag_*` / `probe_*`）、基准（`bench_*`）、剖析（`profile_*`）。

**直接全跑会挂死** —— 探针脚本大多**没有 `quit()`**，Godot 会一直跑下去。
我因此白等了两轮。正确的筛法：

```powershell
$tests = Get-ChildItem tests -Filter '*.gd' | Where-Object {
  $_.Name -like 'test_*' -or $_.Name -like 'validation_*' -or $_.Name -eq 'check_manual_api.gd'
} | Sort-Object Name
foreach ($f in $tests) {
  $n = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
  $o = & $exe --headless --path . --script ('res://tests/' + $n + '.gd') 2>&1
  $c = $LASTEXITCODE
  $sum = ($o | Select-String -Pattern 'passed' | Select-Object -Last 1)
  '{0,-34} exit={1}  {2}' -f $n, $c, $(if ($sum) { $sum.Line.Trim() } else { '(无汇总行)' })
}
```

### 三种"看起来失败、其实正常"的情况

| 现象 | 真相 |
|---|---|
| `check_manual_api` / `validation_facade_api` / `validation_fusion` exit=1 | **设计如此**：找不到 addon 就用失败码大声报错（"教错 API 的手册比没有手册更糟"）。先在树内构建 addon。想临时放行：`DSH_ALLOW_MISSING_ADDON=1` |
| `test_gpu` exit=2 | **跳过码**（`test_gpu.gd:67`）：headless 下没有 RenderingDevice，要用 `--rendering-driver vulkan` 才真跑 |
| `validation_alignment` **卡住不返回** | **既有问题，与你的改动无关** —— 新旧两版都卡在 "B2. 精灵摆放 vs 刚体变换"。要查就单独查 |

## 当前状态（交接时）

- `main` 上最近几次提交：**`fac0d95`（碰撞层对照研究）** /
  **`ea72019`（AABB 缓存，擦除 23.5 -> 14.9 ms/笔）** /
  `56196f7`（碰撞层/掩码）/ `178cef9`（关节系统）。
- **断言测试 389 项全绿**（`test_*` 167 + `validation_*` 222），另有若干
  `validation_*` 只以退出码判定（不打印汇总行）。`validation_facade_api` 25 项需 addon。
- `test_parallel.gd` **不存在**（旧交接里写的那个已经随手写内核删掉了）。
- **基准（不许动）** —— 8 条，`tests/dump_state.gd` 的输出。
  **2026-10 在 `ea72019` 上重测，与上一份交接逐位相同**：

  ```
  stack:6:5    -14.016073139122
  pile:8:6     -30.229686689508
  frags:240    -214.586038730939
  mixed        -3.464347122832
  stack:2:3    -2.694825580758
  pile:4:4     -8.328776872784
  sleep_box    -4.705517743051   (0/12)
  sleep_frag   -35.696264844083  (0/120)
  ```

  > ⚠️ **每一次改动都要拿它当等价性判据**（关节、碰撞层、AABB 缓存三轮都过了）。
  > 更早的那组（stack:6:5 = -8.229...）是 Rapier 迁移之前的，已过期。
- Tag：`v0.1.0 v0.2.0 v0.2.1 v0.2.2 v0.3.0`；发布说明在 `docs/release_notes/`。
- **项目树里不能有 `addons/`** —— 住在树里会让编辑器报
  `Class X hides a global script class` 并**级联到编译失败**（`.gdignore` 挡不住，
  清 `filesystem_cache` 也没用，headless 同样受影响）。
- 工作区可能有**另一个会话的在途改动**。提交时**逐路径 `git add`**，
  绝不 `git add -A`；`scenes/demo.tscn` 是编辑器写的视图状态，**永远不要提交**。

---

# 本轮做完的事：AABB 缓存（`ea72019`）

**问题**：`mark_dirty_range()` 无脑 bump `revision`，而 `local_aabb()` 拿
`revision` 当缓存键 —— 于是**每一笔擦除**都把 AABB 缓存打掉，而
`decompose()` 第一件事就是调 `local_aabb()`，等于白扫 1248 个 chunk。
`pworld.gd` 里还有个 `parts[i].local_aabb()` 在循环里，也在重复付这笔钱。

**修法**：新增 `PixelShape._bounds_rev`，**只在 AABB 可能改变时才 +1**。
判据是「改动矩形是否**严格**落在当前 AABB 内部」—— 严格在内则四个极值像素
都在矩形之外，AABB 必然不变。`touch()` / `mark_dirty()` / `mark_dirty_key()`
不知道改了哪里，一律 +1（保守）。

**这个判据是可证的**（不是"看起来差不多"）：唯一调用方 `PWorld.fracture()`
传的 `dmg_rect` 是 `damage.bounds()` 向外取整 +1；而 `make_keep_mask`（CPU）
和 `destruction.glsl`（GPU）都只在 `damage.hits(像素中心)` 为真时删除，
`hits` 的范围恰好就是 `bounds()`。两条路径都逐行核过。

**等价性证据**（全部通过）：

- 8 条基准**逐位不变**；
- 擦除序列的**碰撞矩形集合摘要逐位不变**（优化前后用 `git stash` 对拍，7 步）；
- `validation_shape_vs_rects` 6/6、`validation_sprite_offset` 2/2、
  `validation_tile_consistency` 4/4、`validation_aabb_cache` **15/15（新增）**。

**实测**（768x100 地面，含 `renderer.sync`）：
内部擦除 **23.48 -> 14.87 ms/笔**；内部偏上 **23.65 -> 16.02 ms/笔**；
`fracture` 单步 **10.2~12.5 -> 7.06~9.27 ms**。

> ⚠️ 新增的 `tests/validation_aabb_cache.gd` 用**逐像素扫描**当独立参照物，
> **不拿缓存自己的值当预期值** —— 缓存判错是**不报错**的，只会让形状与碰撞箱
> 静默错位（用户报过两次）。

顺带拆了一颗雷：`translate_pixels()` 换掉整个 `chunks` 却不 bump 任何版本号
（当前无调用方，但缓存键不变会让 `local_aabb()` 返回平移**之前**的 AABB）。

---

# 未完成的事

## 一、擦除性能（**当前主线**）

一笔内部擦除现在是 ~15 ms（含 sync），拆开大致是：

| 阶段 | 成本 | 说明 |
|---|---|---|
| `rebuild` | ~7 ms | 仍占大头 |
| --- `_build_grid` | 4.5~5.7 ms | 位网格，8 行/块 |
| --- `local_aabb()` | 3.3 ms -> **0** | 本轮已消除 |
| --- 贪心 + 合并 | ~1.5 ms | `_merge_pass` 是 O(n^2)（374 个矩形时 6.57 ms） |
| `renderer.sync` | ~7 ms | 分块贴图：内部擦除只重建 **1.1/24** 块 |
| `apply_damage` | 0.27 ms | |
| 推矩形给 Rapier | 0.17 ms | **不是瓶颈，别再优化它** |

**核心事实（GDScript 的固定开销 约 1 us/次操作）**：把网格构建从 79872 次
逐像素写改成 9600 次行级 `append_array`，**耗时一模一样（8.71 ms）**。
**只有"更少的操作"有用，不是"更少的字节"。** 猜之前先量。

**按性价比排序的下一步**（来自 `docs/voxel_collision_research.md`）：

1. **★★★ 按块缓存分解结果**（64x64 或 32x32）：一笔从 5.6 ms -> 0.1~0.6 ms。
   ⚠️ 矩形集合会变 -> **基准会移动**，必须单独一个提交。
2. **★★★ 干掉 `_merge_pass` 的 O(n^2)** —— 现在唯一还没被碰过的热点了。
   **它不改矩形集合，基准应当逐位不变，风险最低。**
3. **★★ 碎块独立碰撞组**（抄 Vex-2.0 的 Debris）：省掉大量接触对。
   桥接层已有 `layer/mask`（`56196f7`），但那是**刚体级**。
4. 复测 `_build_grid` 的增量路径 —— 顶部"增量无效"的墓碑是**字节网格 +
   逐像素时代**量的（113x64 次迭代）；位网格是 8 行/块，值得用今天的常数重测。

**研究结论（一手，`docs/voxel_collision_research.md`）**：
四个参考实现**没有一个**把碰撞建在"整个物体"这一层 ——
Teardown 直接在体素网格上做（Dennis 访谈原话 "It's all integer math"）、
`godot_voxel` 每块一个 `ConcavePolygonShape3D` 且只在有 viewer 时生成、
Vex-2.0 贪心盒 -> 每个盒一个 Roblox Part（一次性转化）、
**Noita（2D，和我们最像）用 box/circle 凸形状**。
而我们的 `PBody.rebuild()` 是**全量**贪心分解 —— 这就是它占 96% 的原因。

**不要抄**：Vex-2.0 的"按中心距焊接"（贪心大块中心距必然 > 1.5 体素，该焊的焊不上）、
每体素一个碰撞体、动态热插拔刚体、trimesh、换物理引擎。

## 二、角接触不产生倾倒力矩 —— 已修（`1c89b9f`，开发日志坑 38）

真凶**不是**当初最怀疑的 `_contact_width()`，而是 `speculative_point()`
合成的接触点（力臂恒为 0）。诊断记录与实测数据见 `docs/development_log.md` 坑 38。

## 三、睡眠阈值 —— 已处理

`sleep_surface` 从 12.0 **改回 6.0**（12.0 当年是为了盖住坑 38 的症状才提上去的）。
⚠️ 它和 `_wake_pair` 耦合（那里用 `sleep_surface * 2.0`），改它会影响"谁唤醒谁"。

## 四、编辑器画笔（3）—— 节点侧已完成，插件侧未做

- 已有 `PixelShape2D.Source.PAINT` + `@export var paint: Image`（R 通道 = 材质 id）
  + `paint_brush(cx, cy, material, radius)`。
- 已有 `px.bake_image(image, pos, material_of)`、`px.solidify(id, shape, pos)`。
- **插件侧没做**：工具栏选模式、`_forward_canvas_gui_input` 拦截鼠标、
  落笔写 `paint`、预览圈、`EditorUndoRedoManager` 撤销。

**插件当前是停用状态** —— `project.godot` 的 `[editor_plugins] enabled=PackedStringArray()`。
原因：插件原来的唯一功能是注册节点图标，而**图标（`src/editor/icons/*.svg`）已被用户删掉**。

## 五、停靠面板（4）—— 用户说不急

## 六、待核实

- **原生求解路径下的冲量回填**：`_fill_contact_impulses()` 在
  `_packed_manifolds = true`（默认）时遍历的是**空数组**。请先量再信。
- `frags:240` 回退路径在第 142 步起有 `1.92e-5` 偏差（疑似 warm-start 缓存键序）。
- **`Query.raycast` 在实心地面上也返回不到命中** —— 未解释。它会挡住任何
  "直接问 Rapier 要答案"的验证手段，值得单独查。
- API 文档覆盖率约 159/442 公开成员。
- **仍未实现**：通用约束（`ConstrainPosition/Velocity/Orientation/AngularVelocity`）、
  **形状级**碰撞过滤（现在是刚体级）、多段绳索解算、通用 `GetProperty/SetProperty`、
  停靠面板 4。

---

# ⚠️ 上一个助手踩过的坑（务必避免）

**这些全部真实发生过，而且大部分是"以为对"然后被打脸。**

## 代码层面

1. **两条路径（原生 C++ / GDScript）之间的状态不同步** —— 同一个模式出现过**三次**：
   - 冲量回填在原生路径下遍历空数组 -> 静默空转
   - 缩放：注释写了"只有 scale 会让形状失效"，**那一支从来没实现**
   - 破坏擦除：C++ 直接改块位图，**不经过 `set_pixel`** -> `revision` 不变 ->
     渲染器判定"没变"跳过贴图重建 -> **擦掉了但画面上还在**

   **教训**：改内容之后**必须**让 GDScript 侧知道。最终修法是放在
   `PBody.rebuild()` —— **所有内容变化的必经之路**，而不是在每个调用方补。

2. **在症状处打补丁 vs 在源头修** —— 第一版在 `_damage_world` 补，
   **当场就漏掉了 `PixelEditor` 那条路**，用户第二次报同一个 bug 才找到。
   **找"谁还会走到这段代码"**，别只修眼前这一条。

3. **`:=` 在无类型值上推不出类型** —— `var x := px.some_method()`（px 无类型）
   会**解析失败**。用普通 `var`。

4. **GDScript 的 `const` 要求编译期常量** —— `const DIR := get_script().resource_path` 直接解析失败。

5. **`Vector2`/`Rect2` 是 float32，GDScript 标量是 float64**；
   编译必须 `-ffp-contract=off`（否则 FMA 让两条路径分叉）。
   **绝不从 C++ 侧 resize PackedByteArray**。

6. **缓存判错是不报错的** —— AABB 缓存、分块贴图的 `_rev_offset`、`_rect_grid`
   都栽过。**给缓存写测试时，参照物必须用独立算法**（逐像素扫），
   不能拿缓存自己的值当预期值。

7. **`_build_region_image` 曾经"分块实现成每块扫全局"** —— 每个 tile 遍历全部
   1248 个 chunk，24 个 tile 要 821 ms（比不分块还慢 18 倍）。
   分块的意义是**只扫自己那块**。

8. **累计版本号会让快路径永久失效** —— 一次历史 `touch()`（bake 时）就让
   `revision != range_revision` 永远成立，diff 卡在 2，24/24 个 tile 每帧重建。
   修法是 `_rev_offset`（**相对上次全量重建**算 diff）。

9. **改 `.tscn` 一定要保住 header 的 `uid=`**；`.tscn` 里的 `;` 注释
   在编辑器保存时会被丢掉。

10. **`PackedByteArray.fill()` 只有一个参数**（没有区间重载）；
    `Rect2i.intersects()` 也只有一个参数。

11. **ASCII 双引号夹在中文 GDScript 字符串里会截断它** —— 踩过 4 次。

## 流程层面（更痛）

12. **说了一件事，但没验证它真的成立** —— 出现过**三次**：
    - 脚本里 `git commit` **没检查前面的语法检查结果**，于是**提交了跑不起来的插件**
      （用户编辑器因此打不开）
    - 注释写"只有 scale 会失效"，实现没写
    - PowerShell `-replace` 写错参数导致没生效，却报告"已停用"

    **每次多步操作都要检查退出码，写完文件要读一遍。**

13. **凭 grep 片段 / 记忆就下判断** —— 断言过不存在的 `_draw`、不存在的渲染器泄漏、
    **编造过 `PixelShape.clear_all()` 和 `get_bounds()`**。
    **改任何函数前，先 `read` 那个完整函数。**

14. **测试是绿的，但它什么都没测** —— 写过 `(not before) or after` 这种**恒真**断言；
    `validation_shape_vs_rects` **从创建起就是空转的**（拿世界坐标 AABB 配形状局部
    `get_pixel()`，两边都退化成全 0，`0 == 0` 永远通过）——
    所以之前所有"形状与碰撞箱一致（6/6）"的说法**都没有依据**。
    **看结果里的数字，别只看 passed/failed。**

15. **会误报的闸门比没有闸门更糟** —— `check_docs.py` 第一版规则误报，
    改成可度量的判据（长度）并用探针反证过。**闸门自己也要被验证。**

16. **PowerShell 陷阱**：反引号和 ASCII 引号会**截断 JS 模板字符串**；
    内联 Python 单行会炸掉解析器；`-replace` 只吃两个参数；
    here-string 里的 `$` 会被展开。
    **优先用 `edit`/`write` 工具改文件；提交信息用 `git commit -F 文件`**，
    不要用 here-string（我因此丢掉过一次提交）。

17. **PowerShell 的 `& cmd | Select-Object` 之后 `$LASTEXITCODE` 是管道最后一条
    命令的退出码** —— 因此在一份**过期的 DLL** 上白查了一整轮。

18. **网络**：这台机器上 **Python 的 urllib 连不上 `api.github.com`
    （`WinError 10054`）**，但 `curl` 是 200、SSH 正常。用 curl 绕。

## 测试运行层面

19. **`tests/` 下大部分脚本不是测试** —— 见上面「跑测试的正确姿势」。
    探针没有 `quit()`，全跑会挂死。

20. **一个卡住的 Godot 进程会污染后面的结论** —— 先
    `Get-CimInstance Win32_Process -Filter "Name like '%Godot%'"` 看有没有残留。

---

# 建议的第一件事

**先跑 8 条基准确认起点没被动过**：

```powershell
& $exe --headless --path . --script res://tests/dump_state.gd
```

对不上就先查，别在漂移的基准上做优化。

然后接 **未完成的事 -> 一、擦除性能**：按性价比第 2 条
（`_merge_pass` 的 O(n^2)）动手 —— 它**不改矩形集合**，基准应当逐位不变，
是风险最低的下一个目标。第 1 条（按块缓存分解结果）收益更大但**会移动基准**，
必须单独一个提交。
