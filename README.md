2D 像素破坏物理引擎

# 本仓库是参考 Teardown 实现的 Godot 2D 体素拓展

引擎已经剥离成可迁移的 addon：`addons/pixel_destruction/`。

---

## 运行

```bash
# 演示（需要 GPU）
godot --path . -- --shot

# 无头测试
godot --headless --path . --script res://tests/test_core.gd
godot --headless --path . --script res://tests/dump_state.gd    # 逐位状态摘要
```

## 测试

| 类别 | 命令 |
| --- | --- |
| 单元断言 | `tests/test_core.gd` / `test_physics.gd` / `test_interaction.gd` / `test_parallel.gd` |
| 物理验证 | `tests/validation_*.gd`（sweep 14/14、extreme、grab、stroke…） |
| 逐位回归 | `tests/dump_state.gd` —— 8 个固定场景的 12 位小数摘要，**基准值见 `docs/development_log.md`** |
| 接口验证 | `tests/validation_api.gd`（17 项）+ `addons/pixel_destruction/examples/facade_demo.gd`（24 项） |
| 性能 | `tests/bench_phase.gd` / `bench_grab_cost.gd` / `bench_native_solve.gd` |
| GPU | 加 `--display-driver windows --rendering-driver vulkan` 再跑 `tests/test_gpu.gd` |

## 首次使用时需让编辑器先注册扩展

GDExtension 是靠**编辑器扫描** `.gdextension` 写进 `.godot/extension_list.cfg` 来注册的，
而这个缓存不进仓库。所以刚克隆下来时：

```bash
godot --headless --editor --quit --path .     # 扫描一次，注册扩展
```

在此之前直接跑 `--headless --script`，扩展**不会**加载，会落到 GDScript 回退路径。
仓库里带了预编译的 `gdext/fastphys.dll`（Windows x86_64）。

> **已知问题**：GDScript 回退路径目前与原生路径**不等价**
> （实测 `sleep_box` 场景 0/12 → 10/12 清醒）。详见
> [docs/development_log.md](docs/development_log.md) 坑 36。所以请确保 dll 可用。

## 构建原生加速

```bash
cd gdext
g++ -O2 -std=c++17 -ffp-contract=off -shared -static-libgcc -static-libstdc++ -o fastphys.dll fastphys.cpp
```

`-ffp-contract=off` 不能省：少了它编译器会把浮点乘加融合成 FMA，与 GDScript 路径立刻分叉。
构建前先关掉占用 dll 的 Godot 进程，否则链接会报 Permission denied。

## 引擎包（addon）：**生成物，不进仓库**

`addons/pixel_destruction/` 是**构建产物**，由 `tools/build_addon.py` 从三处拼出来：

```
src/ + gdext/       引擎真源
addon_src/          手写模板（README / docs / examples / pixel_physics.gd）
        |
        v  python tools/build_addon.py
addons/pixel_destruction/     <- 构建产物（.gitignore）
```

本地构建与校验：

```bash
python tools/build_addon.py     # 生成
python tools/check_addon.py     # 校验自洽：路径改写、内部引用、空文件
```

**CI**（`.github/workflows/ci.yml`）在每次推送时构建 → 校验 → 验证幂等 →
打包成 `pixel_destruction.zip` 作为 artifact；**打 `v*` tag 时自动发布 Release**。

> **为什么不把生成物提交进仓库**：那就等于有两个真源。
> 这个项目已经因为「同一份规则写在两个地方」栽过好几次
> （见 [docs/development_log.md](docs/development_log.md) 坑 18/31/36）——
> 其中一次就是 GDScript 侧改了而 C++ 侧没改，两条路径的接触点差出 3.88 个单位。

> `addon_src/` 里有 `.gdignore`，让 Godot 跳过它 ——
> 模板里的 preload 路径是**装好之后**的路径，在仓库里解析不了。
---

## API 参考（生成物，不进仓库）

用 **Godot 自带的文档工具**导出结构，再由 `tools/gen_api_docs.py` 拼成 Markdown：

```
godot --doctool <out> --gdscript-docs res://src     # 官方工具导出 XML（权威结构）
        |
        v  tools/gen_api_docs.py
docs/api/README.md        索引 + 模块分组
docs/api/<类名>.md        每个类一页
docs/api/_coverage.md     文档覆盖率（哪些公开成员没写注释）
```

本地生成：

```bash
python tools/gen_api_docs.py            # 生成到 docs/api/
python tools/gen_api_docs.py --check    # 只查覆盖率，有未文档化的公开成员就非零退出
```

**为什么是「XML + 源码」的混合方案**：Godot 的 `--gdscript-docs` 有个硬伤——
描述文本里的**换行被压平成了空格**，注释里的 `##   · xxx` 列表项会连成一整段。
所以结构（签名/类型/默认值/继承）取自 XML，**排版取自原始 `##` 注释**，两边按符号名对齐。

> 判定「文件头注释」和「符号注释」靠的是**注释与声明之间有没有空行** ——
> 不区分的话文件头会漏进第一个常量的文档里（实测踩过）。

**CI**（`.github/workflows/ci.yml` 的 `docs` 任务）生成后：
把覆盖率写进任务摘要、上传 `api-docs` artifact，并在 `main` 上部署到 **GitHub Pages**。

---

## 目录

```
src/physics/    物理核心：世界 / 刚体 / 窄相 / 求解器 / 宽相 / sweep / 抓取
src/core/       像素与破坏：chunk、形状、贪心分解、质量、破坏、画笔
src/render/     像素渲染（每个刚体一张 ImageTexture）
src/gpu/        RenderingDevice 破坏加速（可选）
src/demo/       演示场景逻辑
tests/          单元断言 + 物理验证 + 逐位回归 + 性能基准
docs/           开发日志（三十多个坑的完整记录）与框架文档
gdext/          GDExtension 原生加速源码
addon_src/      引擎包的手写模板（README / docs / examples / 门面）
addons/pixel_destruction/   **生成物**（.gitignore，由 tools/build_addon.py 产出）
```

## 文档

- **[addons/pixel_destruction/README.md](addons/pixel_destruction/README.md)** —— 引擎的对外接口，推荐从这里开始
- **[addons/pixel_destruction/docs/PRECISION.md](addons/pixel_destruction/docs/PRECISION.md)** —— 精度纪律：float32/float64 的全部边界
- **[docs/development_log.md](docs/development_log.md)** —— 开发日志，按坑编号，含被证伪的假设
- [docs/2d_pixel_physics_framework.md](docs/2d_pixel_physics_framework.md) —— 框架设计

---

## 许可

MIT，见 [LICENSE](LICENSE)。

> 仓库里**不含**第三方材料：`_research/`、`_tdres/`、`docs/teardown_api_research/`（Teardown 官方 API 文档）。
> 它们只在本地作为参考资料存在，已列入 `.gitignore` —— 用 MIT 分发一个仓库时，不该把别人的文档一起打包。
