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

## 重新生成 addon

```bash
python tools/build_addon.py
```

引擎的**源码是 `src/`**；addon 是生成物 —— 脚本只重生成模块目录，

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
addons/pixel_destruction/   可迁移的引擎包（见其 README）
```

## 文档

- **[addons/pixel_destruction/README.md](addons/pixel_destruction/README.md)** —— 引擎的对外接口，推荐从这里开始
- **[addons/pixel_destruction/docs/PRECISION.md](addons/pixel_destruction/docs/PRECISION.md)** —— 精度纪律：float32/float64 的全部边界
- **[docs/development_log.md](docs/development_log.md)** —— 开发日志，按坑编号，含被证伪的假设
- [docs/2d_pixel_physics_framework.md](docs/2d_pixel_physics_framework.md) —— 框架设计

## 说明

`_research/` 与 `_tdres/` 是调研资料（第三方仓库拷贝 / 下载的参考文档），已在 `.gitignore` 中排除。
`gdext/*.bin` 是可由 `tests/dump_*_bin.gd` 重新生成的测试夹具，同样未提交。
