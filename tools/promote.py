#!/usr/bin/env python3
r"""把 main 推进到 stable —— 只有**全绿**才允许。

## 为什么要有这个脚本

两个分支的价值全在「stable 一定是可用的」这一条保证上。
如果推进靠人手敲 git push origin main:stable，那条保证迟早会破 ——
某次「就改一行」忘了跑测试，stable 就脏了，之后没人敢信它。

所以推进做成**一条命令**：跑全部测试 -> 全绿才 fast-forward -> 否则拒绝并打印失败项。

## 用法
  python tools/promote.py            # 检查并推进
  python tools/promote.py --dry-run  # 只检查，不推
  python tools/promote.py --force    # 跳过测试（只在你已经手工验证过时用）
"""
import argparse
import os
import re
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STABLE = "stable"
SOURCE = "main"

TESTS = [
    "test_core", "test_physics", "test_interaction", "test_parallel",
    "validation_sweep", "validation_query", "validation_api", "validation_api2",
    "validation_voxel_layer", "validation_contacts", "validation_traversal",
    "validation_dynamics", "validation_nodes", "validation_alignment",
    "validation_shape_plugin", "validation_stress", "validation_facade_api",
]


def find_godot() -> str:
    for cand in (os.environ.get("GODOT_BIN", ""), "godot", "godot4"):
        if cand and shutil.which(cand):
            return cand
    for base in (r"D:\Godot_v4.7.2", os.path.expanduser("~/godot")):
        if os.path.isdir(base):
            for f in sorted(os.listdir(base)):
                if f.endswith(".exe") and "console" in f:
                    return os.path.join(base, f)
    return ""


def run(cmd, **kw):
    return subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, **kw)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true", help="只检查，不推送")
    ap.add_argument("--force", action="store_true", help="跳过测试")
    # ⚠️⚠️ 必须有 --yes 才真的推。
    #
    # 规则是「开发只在 main 上，**由人确认后**才往 stable 发布」。
    # 光把规则写进文档挡不住 —— 实测我自己就会顺手跑 promote.py，
    # 等于替人做了发布决定。所以把「确认」变成命令的一部分：
    # 不加 --yes 就只报告将要发生什么，然后退出。
    ap.add_argument("--yes", action="store_true",
                    help="确认发布（不加这个只做检查并报告，不推送）")
    args = ap.parse_args()

    st = run(["git", "status", "--porcelain"]).stdout.strip()
    if st:
        print("工作区有未提交改动，先提交：")
        for line in st.splitlines()[:10]:
            print("  " + line)
        return 1

    head = run(["git", "rev-parse", "--short", "HEAD"]).stdout.strip()
    print("待推进的提交：%s" % head)

    # 0.5) **文档同步闸门** —— 在测试之前跑。
    #
    # ⚠️ 「每次发布前先同步文档」这条规则，光写进文档挡不住 ——
    #    本仓库已经证明过一次（AGENTS.md 写了「开发只在 main」，助手照样自己推进）。
    #    所以做成闸门：文档不同步就不许推进。
    if not args.force:
        r = run([sys.executable, os.path.join(ROOT, "tools", "check_docs.py")])
        doc_out = (r.stdout or "") + (r.stderr or "")
        for line in doc_out.strip().splitlines():
            print("  " + line)
        if r.returncode != 0:
            print("")
            print("文档未同步 —— **拒绝推进 stable**。先把上面列的补齐。")
            return 1

    # 0.7) **在树内构建 addon** —— 有两个测试（check_manual_api、validation_facade_api）
    #      必须对着构建产物跑：它们的 preload 路径 res://addons/pixel_destruction/...
    #      只有在构建时才存在。跑完由 --verify 移出项目树。
    #
    #      不这么做的话那两个测试会「缺席即跳过」—— 看起来是绿的，实际空转。
    if not args.force:
        r = run([sys.executable, os.path.join(ROOT, "tools", "build_addon.py")])
        if r.returncode != 0:
            print("构建 addon 失败 —— 拒绝推进。")
            return 1
        print("  addon 已在树内构建（供依赖它的测试用）")

    if not args.force:
        godot = find_godot()
        if not godot:
            print("找不到 Godot。设 GODOT_BIN，或用 --force 跳过测试。")
            return 1
        total = 0
        failed = []
        for t in TESTS:
            r = subprocess.run(
                [godot, "--headless", "--path", ROOT,
                 "--script", "res://tests/%s.gd" % t],
                cwd=ROOT, capture_output=True, text=True, timeout=900)
            out = r.stdout + r.stderr
            m = re.search(r"(\d+) passed, (\d+) failed", out)
            if not m or m.group(2) != "0":
                failed.append("%s: %s" % (t, m.group(0) if m else "没有输出摘要"))
            else:
                total += int(m.group(1))
        print("测试：%d 项通过" % total)
        if failed:
            print("有 %d 个测试不通过 —— **拒绝推进 stable**：" % len(failed))
            for f in failed:
                print("  " + f)
            return 1

    if args.dry_run:
        print("--dry-run：检查通过，未推送。")
        return 0

    if not args.yes:
        # 没有 --yes：把"将要发生什么"讲清楚就停手。
        # 决策权在人，不在脚本，也不在替你跑脚本的助手。
        print("")
        print("测试全绿，**但没有推送** —— 发布是人的决定。")
        print("确认无误后重跑并加 --yes：")
        print("    python tools/promote.py --yes")
        print("（将把 stable 快进到 %s）" % head)
        return 0

    # fast-forward only：失败说明 stable 有 main 没有的提交，那是**分叉**，
    # 必须人来看，不能自动合并。
    r = run(["git", "push", "origin", "%s:%s" % (SOURCE, STABLE)])
    if r.returncode != 0:
        print("推送失败（很可能是 stable 有 main 没有的提交 = 分叉）：")
        print((r.stderr or r.stdout).strip()[:600])
        return 1
    # 本地 ref 也要跟上 —— 只推远端的话，本地 stable 会一直停在旧位置，
    # 下一次 "git checkout stable" 看到的是过期的代码，很容易误判。
    run(["git", "branch", "-f", STABLE, SOURCE])
    print("stable 已推进到 %s（本地与远端同步）" % head)
    return 0


if __name__ == "__main__":
    sys.exit(main())
