#!/usr/bin/env python3
"""校验生成出来的 addon 是否自洽。CI 的守门人。

为什么需要它：生成器"跑成功"不等于"产物能用"。最典型的失败是
**路径改写漏了**（模块里还留着 res://src/...）或者 **preload 指向不存在的文件**
—— 两者都不会让生成器报错，只会在 Godot 里变成一堆 Parse Error。

检查项：
  1. 必须存在的文件都在；
  2. 生成的模块里不残留 res://src/ 路径；
  3. addon 内所有引用的 res://addons/pixel_destruction/... 目标都真实存在；
  4. 没有空文件（生成中断会留下 0 字节文件）。
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "addons", "pixel_destruction")
SRC = os.path.join(ROOT, "src")

MODULES = ["physics", "core", "render", "gpu"]
REQUIRED = [
    "physics/pworld.gd",
    "physics/pbody.gd",
    "physics/collide.gd",
    "physics/sweep.gd",
    "physics/query.gd",
    "physics/solver.gd",
    "physics/grab.gd",
    "native/fastphys.cpp",
    "native/rapier_bridge/Cargo.toml",
    "native/rapier_bridge/src/lib.rs",
]
PREFIX = "res://addons/pixel_destruction/"
REF = re.compile(r'res://addons/pixel_destruction/[A-Za-z0-9_./-]+\.(?:gd|tscn|tres)')


def main() -> int:
    errors = []
    if not os.path.isdir(OUT):
        print("找不到生成目录 %s" % OUT)
        print("")
        print("这是**正常状态**，不是错误：addon 是构建产物，它的 class_name 与 src/ 必然重名，")
        print("住在项目树里会让编辑器报 Class X hides a global script class 并级联到编译失败。")
        print("")
        print("要构建并自检，用一条命令（构建 -> 校验 -> 自动移出）：")
        print("    python tools/build_addon.py --verify")
        return 1

    # 1) 必需文件
    for rel in REQUIRED:
        if not os.path.isfile(os.path.join(OUT, rel)):
            errors.append("缺少文件: %s" % rel)

    # 2) 模块里不能残留 src 路径 / 不能有空文件
    for mod in MODULES:
        d = os.path.join(OUT, mod)
        if not os.path.isdir(d):
            errors.append("缺少模块目录: %s" % mod)
            continue
        for name in sorted(os.listdir(d)):
            if not name.endswith(".gd"):
                continue
            with open(os.path.join(d, name), encoding="utf-8") as f:
                body = f.read()
            if "res://src/" in body:
                errors.append("%s/%s 里残留 res://src/ 路径（路径改写漏了）" % (mod, name))
            if len(body.strip()) == 0:
                errors.append("%s/%s 是空文件" % (mod, name))

    # 2b) 不许有重复 UID。
    #
    # addons/pixel_destruction/ 和 src/ 是同一棵 Godot 项目树下的两份拷贝，
    # 一旦把 src/ 的 .uid 复制过来，Godot 4.4+ 会报
    #   "UID duplicate detected between res://src/... and res://addons/..."
    # 并且**编辑器直接打不开**。这条闸门就是防它复发的。
    src_uids = {}
    for root, _dirs, files in os.walk(SRC):
        for name in files:
            if name.endswith(".uid"):
                with open(os.path.join(root, name), encoding="utf-8") as f:
                    src_uids[f.read().strip()] = name
    dup = []
    for root, _dirs, files in os.walk(OUT):
        for name in files:
            if name.endswith(".uid"):
                with open(os.path.join(root, name), encoding="utf-8") as f:
                    v = f.read().strip()
                if v in src_uids:
                    dup.append("%s 与 src/ 的 %s 重复" % (name, src_uids[v]))
    if dup:
        errors.append("有 %d 个重复 UID（Godot 会拒绝打开项目）: %s"
                      % (len(dup), "; ".join(dup[:3])))

    # 2c) 源码里不许有 preload 环。
    #
    # ⚠️ 这不是洁癖：GDScript 运行时能容忍 preload 环，但**编辑器的脚本扫描器会
    #    无限递归然后无声段错误** —— 实测编辑器启动 17 秒后消失、退出码 0xC0000005、
    #    没有任何报错。而且 headless 跑测试完全正常，非常难查。
    #    （真实案例：pixel_shape.gd 为了 component_map 反向 preload 了 destruction.gd。）
    graph = {}
    for root, _dirs, files in os.walk(SRC):
        for name in files:
            if not name.endswith(".gd"):
                continue
            fp = os.path.join(root, name)
            with open(fp, encoding="utf-8") as f:
                body = f.read()
            deps = set(re.findall(r'preload\("res://([^"]+\.gd)"\)', body))
            graph[os.path.relpath(fp, ROOT).replace(os.sep, "/")] = deps
    seen, stack, cycles = set(), [], []

    def visit(node):
        if node in stack:
            cycles.append(" -> ".join(stack[stack.index(node):] + [node]))
            return
        if node in seen:
            return
        seen.add(node)
        stack.append(node)
        for dep in sorted(graph.get(node, ())):
            if dep in graph:
                visit(dep)
        stack.pop()

    for node in sorted(graph):
        visit(node)
    if cycles:
        errors.append("有 %d 个 preload 环（编辑器会无声段错误）: %s"
                      % (len(cycles), cycles[0]))

    # 2d) @tool 脚本的每帧入口必须有编辑器守卫。
    #
    # ⚠️ 这类 bug 只会在**编辑器里**表现（物体自己在动、编辑器卡顿），
    #    无头测试全绿也发现不了 —— 必须靠静态检查兜。
    #    真实案例：PixelWorld._physics_process 没守卫，编辑器每帧都在 world.step()。
    #    注意"定义 _physics_process 本身就会启用它"，_ready 里的守卫挡不住。
    for root, _dirs, files in os.walk(SRC):
        for name in sorted(files):
            if not name.endswith(".gd"):
                continue
            fp = os.path.join(root, name)
            with open(fp, encoding="utf-8") as f:
                lines = f.read().split("\n")
            if not lines or "@tool" not in lines[0]:
                continue
            for i, line in enumerate(lines):
                if re.match(r"\s*func\s+(_process|_physics_process)\s*\(", line):
                    body = "\n".join(lines[i:i + 10])
                    if "is_editor_hint" not in body:
                        errors.append(
                            "%s:%d 的 %s 没有编辑器守卫（@tool 脚本会在编辑器里跑，"
                            "必须用 Engine.is_editor_hint() 挡住）"
                            % (os.path.relpath(fp, ROOT).replace(os.sep, "/"),
                               i + 1, line.strip()))

    # 2e) 引用了 @tool 才该有的 API 的脚本，自己必须是 @tool。
    #
    # ⚠️ 真实案例：debug_overlay.gd 定义了 set_world() / refresh()，
    #    并被 PixelWorld（@tool）在编辑器里调用，但它自己没有 @tool。
    #    编辑器里它是个 **placeholder instance** —— 脚本根本不跑，
    #    调用会报 "Attempt to call a method on a placeholder instance"。
    #    症状还包括"节点在场景里但什么都不画"，很难联想到是缺 @tool。
    for root, _dirs, files in os.walk(SRC):
        for name in sorted(files):
            if not name.endswith(".gd"):
                continue
            fp = os.path.join(root, name)
            with open(fp, encoding="utf-8") as f:
                lines = f.read().split("\n")
            if lines and "@tool" in lines[0]:
                continue
            body = "\n".join(lines)
            # 用 is_editor_hint 说明作者本意就是"要在编辑器里跑"
            if "is_editor_hint" in body:
                errors.append(
                    "%s 用了 Engine.is_editor_hint() 但没有 @tool —— "
                    "编辑器里它是 placeholder instance，脚本不会跑"
                    % os.path.relpath(fp, ROOT).replace(os.sep, "/"))

    # 3) 所有内部引用都要能解析
    refs = 0
    for dirpath, _dirs, files in os.walk(OUT):
        for name in files:
            if not name.endswith(".gd"):
                continue
            p = os.path.join(dirpath, name)
            with open(p, encoding="utf-8") as f:
                body = f.read()
            for m in REF.finditer(body):
                refs += 1
                target = os.path.join(OUT, m.group(0)[len(PREFIX):])
                if not os.path.isfile(target):
                    errors.append("%s 引用了不存在的 %s" % (os.path.relpath(p, OUT), m.group(0)))

    n_gd = sum(1 for dp, _d, fs in os.walk(OUT) for f in fs if f.endswith(".gd"))
    if n_gd < 20:
        errors.append("生成的 .gd 只有 %d 个，明显不完整" % n_gd)

    for e in errors:
        print("  ERROR %s" % e)
    if errors:
        print("=== 校验失败：%d 项 ===" % len(errors))
        return 1
    print("=== addon 自洽（%d 个 .gd，%d 条内部引用全部可解析）===" % (n_gd, refs))
    return 0


if __name__ == "__main__":
    sys.exit(main())
