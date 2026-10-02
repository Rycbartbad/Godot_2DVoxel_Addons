#!/usr/bin/env python3
"""构建可迁移的引擎包 addons/pixel_destruction/。

## 为什么生成物不进仓库

    仓库里只有两样东西：
      src/ + gdext/   引擎真源
      addon_src/      手写模板（README / docs / examples / pixel_physics.gd）
    生成器把它们拼成 addons/pixel_destruction/ —— 那是**构建产物**，
    在 .gitignore 里，由 CI 构建并发布（见 .github/workflows/ci.yml）。

为什么"手抄一份 addon"是错的：抄一份就有两个真源，迟早分叉。
这个项目已经因为"同一份规则写在两个地方"栽过好几次
（见 docs/development_log.md 坑 18/31/36）—— 其中一次就是 GDScript 侧改了
而 C++ 侧没改，两条路径的接触点差出 3.88 个单位。

用法：
    python tools/build_addon.py            # 生成到 addons/pixel_destruction/
    python tools/build_addon.py --out DIR  # 生成到别处
"""
import argparse
import os
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "src")
GDEXT = os.path.join(ROOT, "gdext")
TEMPLATE = os.path.join(ROOT, "addon_src")
DEFAULT_OUT = os.path.join(ROOT, "addons", "pixel_destruction")

## 从 src/ 打包哪些模块（顺序即生成顺序）
MODULES = ["physics", "core", "render", "gpu"]
## 从 gdext/ 打包哪些原生源码
NATIVE_SRC = ["fastphys.cpp", "collide_kernel.h", "bp_kernel.h", "solver_kernel.h"]
## 扩展名故意不是 .gdextension —— Godot **编辑器**会自动扫描并加载项目里的
## .gdextension，而这个包里没有编译好的 .dll，留着会每次导入都报
## "GDExtension dynamic library not found"。要用原生加速就去掉 .template 后缀。
GDEXTENSION_TEMPLATE = """[configuration]

entry_symbol = "gdextension_init"
compatibility_minimum = "4.2"
reloadable = false

[libraries]

windows.debug.x86_64 = "res://addons/pixel_destruction/native/fastphys.dll"
windows.release.x86_64 = "res://addons/pixel_destruction/native/fastphys.dll"
linux.debug.x86_64 = "res://addons/pixel_destruction/native/fastphys.so"
linux.release.x86_64 = "res://addons/pixel_destruction/native/fastphys.so"
"""


def rewrite(text: str) -> str:
    for m in MODULES:
        text = text.replace("res://src/%s/" % m, "res://addons/pixel_destruction/%s/" % m)
    return text


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=DEFAULT_OUT, help="输出目录")
    args = ap.parse_args()
    out = os.path.abspath(args.out)

    if not os.path.isdir(SRC) or not os.path.isdir(TEMPLATE):
        print("缺少 src/ 或 addon_src/")
        return 1

    # 整个输出目录重建：不留上一次的残留（残留正是"看起来对但其实没更新"的来源）
    if os.path.isdir(out):
        shutil.rmtree(out)
    os.makedirs(out)

    # 1) 从 src/ 生成模块
    total = 0
    for mod in MODULES:
        sd = os.path.join(SRC, mod)
        if not os.path.isdir(sd):
            continue
        dd = os.path.join(out, mod)
        os.makedirs(dd)
        n = 0
        for name in sorted(os.listdir(sd)):
            if not name.endswith(".gd"):
                continue
            with open(os.path.join(sd, name), encoding="utf-8") as f:
                body = f.read()
            with open(os.path.join(dd, name), "w", encoding="utf-8", newline="\n") as f:
                f.write(rewrite(body))
            # .uid 是 Godot 给脚本分配的稳定 id（场景按 UID 引用脚本）。
            # 一起带上，免得使用方导入时各自生成不同的 UID。
            uid = os.path.join(sd, name + ".uid")
            if os.path.isfile(uid):
                shutil.copyfile(uid, os.path.join(dd, name + ".uid"))
            n += 1
        total += n
        print("  %-8s %2d 个脚本（生成）" % (mod, n))

    # 2) 原样拷贝手写模板（README / docs / examples / pixel_physics.gd）
    for name in sorted(os.listdir(TEMPLATE)):
        if name == ".gdignore":
            continue
        s = os.path.join(TEMPLATE, name)
        d = os.path.join(out, name)
        if os.path.isdir(s):
            shutil.copytree(s, d)
        else:
            shutil.copyfile(s, d)
    print("  %-8s 手写模板已拷入" % "template")

    # 3) 原生加速源码
    if os.path.isdir(GDEXT):
        nd = os.path.join(out, "native")
        os.makedirs(nd, exist_ok=True)
        n = 0
        for name in NATIVE_SRC:
            s = os.path.join(GDEXT, name)
            if os.path.isfile(s):
                shutil.copyfile(s, os.path.join(nd, name))
                n += 1
        with open(os.path.join(nd, "fastphys.gdextension.template"), "w",
                  encoding="utf-8", newline="\n") as f:
            f.write(GDEXTENSION_TEMPLATE)
        total += n
        print("  %-8s %2d 个源文件 + .gdextension.template（生成）" % ("native", n))

    print("已生成 %s" % os.path.relpath(out, ROOT))
    return 0


if __name__ == "__main__":
    sys.exit(main())
