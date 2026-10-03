# 交接提示词

> 把这份内容作为**新会话的第一条消息**发给助手。它包含：项目是什么、
> 硬性规则、当前状态、**未完成的事（带测量数据）**、以及**上一个助手踩过的坑**。

---

## 项目

`D:\Godot_v4.7.2\TapTap2026` —— Godot 4.7.2 + GDScript 的 **2D 像素破坏物理引擎**
（参考 Teardown 的能力集，但**不要用 teardown 命名**任何东西）。MIT。

引擎是**可迁移的 addon**：真源在 `src/`，`tools/build_addon.py` 生成构建产物。
**构建产物绝不进项目树**（见下）。`gdext/` 有一个 C++ 原生加速层，
与 GDScript 路径**必须逐位一致**。

**引擎只提供机制，规则在游戏层。** 节点层尽量像 Godot 内置（有 body / mesh / camera / UI 图层，
可拖动、可继承、有子节点组合）。

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

# 依赖 addon 产物的测试（两个）
python tools/build_addon.py            # 先在树内构建
& $exe --headless --path . --script res://tests/validation_facade_api.gd
& $exe --headless --path . --script res://tests/check_manual_api.gd
python tools/build_addon.py --verify   # 再移出去

# 文档闸门
python tools/check_docs.py -v

# 基准（发布前必须逐位不变）
& $exe --headless --path . --script res://tests/dump_state.gd
```

## 当前状态（交接时）

- `main = stable` 附近，最后一次提交是 `e463164` 之后。
- **常规 16 个测试脚本 290 项** + `validation_facade_api` **25 项**，全绿。
- **基准（不许动）**：`sleep_box -4.414969665068 (0/12)`、`sleep_frag -40.915225196828 (0/120)`。
- Tag：`v0.1.0 v0.2.0 v0.2.1 v0.2.2`；发布说明在 `docs/release_notes/`。
- **项目树里不能有 `addons/`** —— 住在树里会让编辑器报
  `Class X hides a global script class` 并**级联到编译失败**（`.gdignore` 挡不住，
  清 `filesystem_cache` 也没用，headless 同样受影响）。

---

# 未完成的事

## ★★★ 一、角接触不产生倾倒力矩（最重，未动）

**现象**：把一个 24×24 的方块转 **40°** 放在地上，**只有一个角接触** ——
它**不倒** ✗，速度恒为 0，1.1 秒后**睡着**。

**测量数据**（`tests/_tiltcheck.gd` 那种探针，已删，可重建）：

```
--- 45.0 度 ---  第一次明显转动: 第 -1 步（从没转动）  叫醒后 0.0 度
--- 44.0 度 ---  第一次明显转动: 第 -1 步             叫醒后 0.0 度
--- 40.0 度 ---  第一次明显转动: 第 -1 步             叫醒后 0.0 度
```

**几何算过了：40° 时它必须倒** ——
局部 (24,24) 是接触角，旋转后 `x = 24·(cos40° − sin40°) = 2.95`；
质心局部 (12,12)，旋转后 `x = 1.48`。
**质心比接触点偏左 1.47 px → 力臂不为 0 → 有力矩** ✗ 而它不动 ✗。

**所以这不是睡眠的问题**（45° 那个恰好是零力矩的平衡态，但 40/44 不是）。

**最怀疑**：`PWorld._contact_width()` 沿切线**采样**找接触宽度，
很可能把**点支撑摊成了面支撑** → 法向冲量分散在一个宽度上 → 两侧力矩抵消 → 不倒。

**旁证**：`src/physics/collide.gd` 122 行附近的墓碑注释写着 ——
接触点改成推测接触之后，静止堆叠会残留 **0.43~0.48 rad/s** 的角速度，
20×20 方块对角半径约 14，表面速度 ≈ 6.7。而 `sleep_surface` 当时被从 6.0
**提到 12.0** 来容下它 —— **那其实是把症状盖住了**。

**下一步（只读，不动公式，不影响基准）**：
量**角接触的法向冲量分布** —— 在一个 40° 方块的单一角接触上，打印
`Contact.point` / `Contact.contact_width` / 每个接触的 `impulse` 与**作用点 x 坐标**。
如果冲量分布在**几像素宽**的区间上（而不是集中在角上），就确认了上面的判断。

**⚠️ 改这里会动基准** ✗ —— 必须**先问**。而且 `sleep_surface = 12.0` 是**配着当前接触点公式**
调的，**改接触公式就必须重新调它**（`pworld.gd:41-49` 的注释写明了）。

## 二、睡眠阈值（优先级已降低）

`pworld.gd:32-50`：

```gdscript
var sleeping_enabled := true
var sleep_linear  := 6.0      # 线速度阈值（px/s）
var sleep_surface := 12.0     # **表面速度**阈值 = |ω| * bounding_radius()
var sleep_delay   := 0.4
```

判据 `PBody.is_slow()`：线速度 + **最快点表面速度**（和尺寸无关）。
岛屿级：岛内 awake 成员 `sleep_timer` 的**最小值** ≥ 0.4 就整岛入睡；
被抓着/有外力的岛**永不睡**；入睡时**速度清零**。

**待定**：曾怀疑"没稳定就睡" ✗ —— 但**实测单个方块落地是睡在完全静止状态的**
（叫醒也不动）✗ —— 所以**暂不需要改** ✓。若之后仍遇到，考虑加一条
**位置稳定性判据**（计时窗口内累计位移超阈值就清零计时），而不是调小速度阈值
（那会扰动基准）。

## 三、编辑器画笔（③）—— 节点侧已完成，插件侧未做

- ✅ `PixelShape2D` 已有 `Source.PAINT` + `@export var paint: Image`（**R 通道 = 材质 id**，0 = 空）
  + `paint_brush(cx, cy, material, radius)`（按需新建/扩容图层）。
- ✅ `px.bake_image(image, pos, material_of)` —— **图片 → 多材质实体**（规则由游戏层用回调给）。
- ✅ `px.solidify(id, shape, pos)` —— **蓝图固化**（蓝图只是画面，这一步才进物理）。
- ❌ **插件侧没做**：工具栏选模式、`_forward_canvas_gui_input` 拦截鼠标、落笔写 `paint`、
  预览圈、`EditorUndoRedoManager` 撤销。

**插件当前是停用状态** —— `project.godot` 的 `[editor_plugins] enabled=PackedStringArray()`。
原因：插件原来的唯一功能是注册节点图标，而**图标（`src/editor/icons/*.svg`）已经被用户删掉**。
文件还在 `src/editor/`，③ 做出来之后再启用。

## 四、停靠面板（④）—— 用户说不急

## 五、待核实

- **原生求解路径下的冲量回填**：`_fill_contact_impulses()` 在
  `_packed_manifolds = true`（默认）时遍历的是**空数组**。
  v0.2.1 声称改用"动量变化"算过 —— 但**没有当场验证**，请先量再信。
- `frags:240` 回退路径在第 142 步起有 `1.92e-5` 偏差（疑似 warm-start 缓存键序）。
- API 文档覆盖率约 159/442 公开成员。
- 图层 ④（碰撞层/掩码）、通用约束/关节、通用 `GetProperty/SetProperty` 未实现。

---

# ⚠️ 上一个助手踩过的坑（务必避免）

**这些全部真实发生过，而且大部分是我"以为对"然后被打脸。**

## 代码层面

1. **两条路径（原生 C++ / GDScript）之间的状态不同步** —— 同一个模式出现了**三次**：
   - 冲量回填在原生路径下遍历空数组 → 静默空转
   - 缩放：注释写了"只有 scale 会"让形状失效，**那一支从来没实现**
   - 破坏擦除：C++ 直接改块位图，**不经过 `set_pixel`** → `revision` 不变 →
     渲染器判定"没变"跳过贴图重建 → **擦掉了但画面上还在**
   
   **教训**：改内容之后**必须**让 GDScript 侧知道。最终修法是放在
   `PBody.rebuild()` —— **所有内容变化的必经之路**，而不是在每个调用方补。

2. **在症状处打补丁 vs 在源头修** —— 我第一版在 `_damage_world` 补，
   **当场就漏掉了 `PixelEditor` 那条路**，用户第二次报同一个 bug 才找到。
   **找"谁还会走到这段代码"**，别只修眼前这一条。

3. **`:=  ` 在无类型值上推不出类型** —— `var x := px.some_method()`（px 无类型）会
   **解析失败**。这个会话里我犯了 **4 次**。用普通 `var`。

4. **GDScript 的 `const` 要求编译期常量** —— `const DIR := get_script().resource_path` 直接解析失败。

5. **`Vector2`/`Rect2` 是 float32，GDScript 标量是 float64**；
   `Vector2 * real_t` 会先把标量截断成 float32。
   编译必须 `-ffp-contract=off`（否则 FMA 让两条路径分叉）。
   **绝不从 C++ 侧 resize PackedByteArray**。
6. **改 `.tscn` 一定要保住 header 的 `uid=`** —— 丢了会刷 `Unrecognized UID`。
7. **`.tscn` 里的 `;` 注释在编辑器保存时会被丢掉** —— 别指望它们留着。
8. **隐藏 canvas item 才不被 2D 编辑器拾取** —— 形状子节点默认 `hide_in_editor = true`，
   因为它和刚体原点必然重合，拾取时永远抢走点击。

## 流程层面（更痛）

9. **说了一件事，但没验证它真的成立** —— 出现了**三次**：
   - 脚本里 `git commit` **没检查前面的语法检查结果**，于是**提交了跑不起来的插件**
     （用户编辑器因此打不开）
   - 注释写"只有 scale 会失效"，实现没写
   - PowerShell `-replace` 写错参数导致没生效，我却报告"已停用"
   
   **每次多步操作都要检查退出码，写完文件要读一遍。**

10. **凭 grep 片段 / 记忆就下判断** —— 断言过不存在的 `_draw`、
    不存在的渲染器泄漏、**编造过 `PixelShape.clear_all()` 和 `get_bounds()`**。
    **改任何函数前，先 `read` 那个完整函数。** 几秒钟的事，省它的代价是六轮。

11. **测试是绿的，但它什么都没测** —— 写过 `(not before) or after` 这种**恒真**断言；
    写过"只检查返回类型是 Array"；测 `split_shape` 时只累加返回值却漏了
    "原形状剩下的那块"，把一个**正确实现**判成丢数据。
    **看结果里的数字，别只看 passed/failed。**

12. **会误报的闸门比没有闸门更糟** —— `check_docs.py` 第一版规则误报，
    我改成可度量的判据（长度）并用探针反证过。**闸门自己也要被验证。**

13. **PowerShell 陷阱**：反引号和 ASCII 引号会**截断 JS 模板字符串**；
    内联 Python 单行会炸掉解析器；`-replace` 只吃两个参数；
    here-string 里的 `$` 会被展开。**优先用 `edit`/`write` 工具改文件。**

14. **网络**：这台机器上 **Python 的 urllib 连不上 `api.github.com`**
    （`WinError 10054`），但 `curl` 是 200、SSH 正常。用 curl 绕。

---

# 建议的第一件事

**做第一条的测量**（角接触的冲量分布）—— 只读、不动公式、不影响基准。
把数拿出来之后再决定要不要碰接触点公式。
