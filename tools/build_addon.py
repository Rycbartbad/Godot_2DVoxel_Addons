#!/usr/bin/env python3
"""把 src/ 里的引擎模块 + gdext/ 的原生加速源码打包成可直接拖进别的 Godot 项目的 addon。

为什么是"生成"而不是"手抄一份"：
    抄一份就有两个真源，迟早分叉 —— 这个项目里已经因为"同一份规则写在两个地方"
    栽过好几次（见 docs/development_log.md 坑 18/31）。所以模块目录一律从 src/ 生成，
    要改就改 src/ 再跑这个脚本。

⚠️ 脚本**只重生成模块目录**（physics/core/render/gpu/native），
   README、docs/、examples/ 是手写的，不会被覆盖。
"""
import os
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "src")
GDEXT = os.path.join(ROOT, "gdext")
DST = os.path.join(ROOT, "addons", "pixel_destruction")

## 打包哪些模块（顺序即生成顺序）
MODULES = ["physics", "core", "render", "gpu"]
## 原生加速：这些文件进 native/
NATIVE_SRC = ["fastphys.cpp", "collide_kernel.h", "bp_kernel.h", "solver_kernel.h"]
## 原生扩展的 .gdextension 模板（路径要指向 addon 里）
GDEXTENSION_TEMPLATE = """[configuration]

entry_symbol = "gdextension_init"
compatibility_minimum = 4.2
reloadable = false

[libraries]

windows.debug.x86_64 = "res://addons/pixel_destruction/native/fastphys.dll"
windows.release.x86_64 = "res://addons/pixel_destruction/native/fastphys.dll"
linux.debug.x86_64 = "res://addons/pixel_destruction/native/fastphys.so"
linux.release.x86_64 = "res://addons/pixel_destruction/native/fastphys.so"
"""


def rewrite(text: str) -> str:
    for m in MODULES:
        text = text.replace('res://src/%s/' % m, 'res://addons/pixel_destruction/%s/' % m)
    return text


def main() -> int:
    if not os.path.isdir(SRC):
        print("找不到 src/：%s" % SRC)
        return 1
    os.makedirs(DST, exist_ok=True)

    copied = 0
    for mod in MODULES:
        sd = os.path.join(SRC, mod)
        dd = os.path.join(DST, mod)
        # ⚠️ Godot 会给每个 .gd 生成一个 .uid（脚本 ID，被场景引用）。
        # 重生成模块目录时必须把它们**留下来**，否则每次构建都churn 一批删除，
        # 而且引用这些脚本的场景会短暂失联。
        keep = {}
        if os.path.isdir(dd):
            for name in os.listdir(dd):
                if name.endswith(".uid"):
                    with open(os.path.join(dd, name), "rb") as f:
                        keep[name] = f.read()
            shutil.rmtree(dd)
        if not os.path.isdir(sd):
            continue
        os.makedirs(dd)
        for name, blob in keep.items():
            with open(os.path.join(dd, name), "wb") as f:
                f.write(blob)
        n = 0
        for name in sorted(os.listdir(sd)):
            if not name.endswith(".gd"):
                continue
            with open(os.path.join(sd, name), encoding="utf-8") as f:
                body = f.read()
            with open(os.path.join(dd, name), "w", encoding="utf-8", newline="\n") as f:
                f.write(rewrite(body))
            n += 1
        copied += n
        print("  %-8s %2d 个脚本" % (mod, n))

    # 原生加速源码
    if os.path.isdir(GDEXT):
        nd = os.path.join(DST, "native")
        os.makedirs(nd, exist_ok=True)
        n = 0
        for name in NATIVE_SRC:
            s = os.path.join(GDEXT, name)
            if os.path.isfile(s):
                shutil.copyfile(s, os.path.join(nd, name))
                n += 1
        # ⚠️ 扩展名故意不是 .gdextension —— Godot **编辑器**会自动扫描并加载项目里的
        # .gdextension，而这个 addon 里没有编译好的 .dll，留着会每次导入都报
        # "GDExtension dynamic library not found"。要用原生加速就把这个文件
        # 去掉 .template 后缀，再编译 dll 放进来。
        with open(os.path.join(nd, "fastphys.gdextension.template"), "w", encoding="utf-8", newline="\n") as f:
            f.write(GDEXTENSION_TEMPLATE)
        print("  %-8s %2d 个源文件 + .gdextension.template" % ("native", n))
        copied += n

    print("已生成 %s（%d 个文件）" % (os.path.relpath(DST, ROOT), copied))
    return 0


if __name__ == "__main__":
    sys.exit(main())
