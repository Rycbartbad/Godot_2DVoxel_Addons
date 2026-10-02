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
import subprocess
import os
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "src")
GDEXT = os.path.join(ROOT, "gdext")
TEMPLATE = os.path.join(ROOT, "addon_src")
DEFAULT_OUT = os.path.join(ROOT, "addons", "pixel_destruction")

## 从 src/ 打包哪些模块（顺序即生成顺序）
MODULES = ["physics", "core", "render", "gpu", "nodes"]

## ⚠️ addons/pixel_destruction/ 是 src/ 的**拷贝**，两者在同一棵 Godot 项目树里。
## 不忽略它就会出两类硬错误：
##   · 重复 UID        -> "UID duplicate detected between res://src/... and res://addons/..."
##   · 重复 class_name -> "Class "PixelBody2D" hides a global script class"
## 后者尤其致命：class_name 是**全局**的，两份同名声明直接解析失败。
## Godot 的 .gdignore 让整个目录对编辑器不可见 —— 这才是生成物该有的样子。
## 使用方把 addon 拷进自己的项目时，那里没有 src/，自然也不冲突。
GDIGNORE = """# 这是构建产物（tools/build_addon.py 从 src/ + gdext/ + addon_src/ 拼出来）。
# 它和本仓库的 src/ 是同一份代码的拷贝，同时存在会让 Godot 报
#   · UID duplicate detected
#   · Class "X" hides a global script class
# 所以让 Godot 忽略整个目录。把 addon 拷进别的项目时删掉本文件即可（那边没有 src/）。
"""
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
    # ⚠️ --verify：构建 -> 自检 -> **自动移出项目树**，一条命令走完。
    #
    # 为什么要移出：addon 的 class_name 与 src/ **必然重名**，住在项目树里会让
    # 编辑器报 "Class X hides a global script class" 并级联到编译失败。
    # .gdignore 挡不住（只要有一个文件被加载，类就全局注册了），清 filesystem_cache 也没用。
    #
    # 但 check_addon.py 又必须能看到它 —— 所以顺序只能是：
    #     在树内构建 -> 校验 -> 移出
    # 让每个调用方自己记这个顺序是不现实的（我就在这上面翻过车），所以固化成一条命令。
    ap.add_argument("--verify", action="store_true",
                    help="构建后在树内自检，然后自动移到 ../_addon_build")
    args = ap.parse_args()
    out = os.path.abspath(args.out)

    if not os.path.isdir(SRC) or not os.path.isdir(TEMPLATE):
        print("缺少 src/ 或 addon_src/")
        return 1

    # 整个输出目录重建：不留上一次的残留（残留正是"看起来对但其实没更新"的来源）
    if os.path.isdir(out):
        shutil.rmtree(out)
    os.makedirs(out)

    # 0) 让 Godot 忽略整个目录（见 GDIGNORE 的说明：重复 UID + 重复 class_name）
    with open(os.path.join(out, ".gdignore"), "w", encoding="utf-8", newline="\n") as f:
        f.write(GDIGNORE)

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
            # ⚠️ **不要**把 src/ 的 .uid 复制过来。
            #
            # 曾经复制过，理由是"场景按 UID 引用脚本"。但那个理由在本项目不成立：
            # addon 里没有任何 .tscn，全部引用都是 res:// 路径，没有一处用 UID。
            #
            # 而复制会造成**重复 UID**：addons/pixel_destruction/ 和 src/ 是同一棵
            # Godot 项目树下的两份拷贝，Godot 4.4+ 对重复 UID 是硬错误 ——
            # 编辑器直接打不开，报
            #   "UID duplicate detected between res://src/... and res://addons/..."
            # 实测 21 对重复。
            #
            # 使用方把 addon 拷进自己的项目时，Godot 会自己生成一套新的唯一 UID，
            # 不需要我们替他决定。
            n += 1
        total += n
        print("  %-8s %2d 个脚本（生成）" % (mod, n))

    # 1.5) 许可：分发的包必须带许可全文
    lic = os.path.join(ROOT, "LICENSE")
    if os.path.isfile(lic):
        shutil.copyfile(lic, os.path.join(out, "LICENSE"))
        print("  %-8s LICENSE 已拷入" % "license")

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

    if not args.verify:
        return 0

    # ---- --verify：自检，然后移出项目树 ----
    rc = subprocess.call([sys.executable, os.path.join(ROOT, "tools", "check_addon.py")])
    if rc != 0:
        print("自检失败 —— **不移出**，先把问题修掉（产物留在原地便于排查）")
        return rc

    dest = os.path.abspath(os.path.join(ROOT, "..", "_addon_build"))
    if os.path.isdir(dest):
        shutil.rmtree(dest)
    shutil.move(out, dest)
    # addons/ 如果空了就删掉，别留一个空壳在项目树里
    parent = os.path.dirname(out)
    if os.path.isdir(parent) and not os.listdir(parent):
        os.rmdir(parent)
    print("产物已移出项目树 -> %s" % dest)
    print("（住项目树里会让编辑器报 class_name 重名并级联编译失败）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
