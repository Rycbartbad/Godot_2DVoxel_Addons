#!/usr/bin/env python3
"""构建两个原生动态库，并在构建前检查"编辑器是否开着"。

## 为什么需要这个脚本

`fastphys.dll` 和 `rapier_bridge.dll` 只要被一个运行中的 Godot 打开着，
`Copy-Item` / `g++` 就会**静默失败**（不报错、不留新文件），
而症状是"物理完全不动""所有刚体停在原点"—— 完全指不到构建问题。

这个坑踩过两次。所以把它做成一个**会吵闹地失败**的前置检查，
而不是靠人记得先关编辑器。

## 用法

    python tools/build_native.py

退出码非 0 表示没构建成（或者根本没开始构建）。
"""
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GDEXT = ROOT / "gdext"
BRIDGE = GDEXT / "rapier_bridge"
# 构建产物放到仓库外：cargo 的 target/ 有几百 MB，不该进仓库
TARGET_DIR = Path(os.environ.get("RB_TARGET_DIR", r"D:\AI\tmp\rb_target"))

DLLS = ["fastphys.dll", "rapier_bridge.dll"]


def running_godot() -> list:
    """列出正在运行的 Godot 进程（任何变体）。"""
    try:
        out = subprocess.run(
            ["powershell", "-NoProfile", "-Command",
             "Get-Process -Name 'Godot*' -ErrorAction SilentlyContinue | "
             "ForEach-Object { \"$($_.ProcessName) $($_.Id) $($_.MainWindowTitle)\" }"],
            capture_output=True, text=True, timeout=30,
        )
        return [l.strip() for l in out.stdout.splitlines() if l.strip()]
    except Exception as e:  # noqa: BLE001 - 查不到就当没有，不阻塞构建
        print("  (进程查询失败: %s，按没有处理)" % e)
        return []


def build(label: str, cmd: list, cwd: Path, out: Path) -> bool:
    """跑一条构建命令，并**用命令自己的退出码**判断成败。

    ⚠️ 不要在 PowerShell 里写成 `& cmd | Select-Object` 再读 $LASTEXITCODE ——
       那取到的是管道最后一个命令的退出码，不是构建命令的。
       曾经因此"编译成功"了一整轮，实际跑的是旧 DLL。
    """
    print("  [%s] %s" % (label, " ".join(cmd)))
    r = subprocess.run(cmd, cwd=str(cwd), capture_output=True, text=True)
    if r.returncode != 0:
        print("  **%s 失败（退出码 %d）**" % (label, r.returncode))
        for line in (r.stdout + r.stderr).splitlines()[:12]:
            print("    " + line)
        return False
    if not out.is_file():
        print("  **%s 报告成功，但 %s 没生成**" % (label, out.name))
        return False
    return True


def main() -> int:
    print("=== 构建原生库 ===")

    procs = running_godot()
    if procs:
        print("")
        print("  **Godot 正在运行，构建会静默失败 —— 已中止。**")
        for p in procs:
            print("    " + p)
        print("")
        print("  原因：运行中的 Godot 会锁住 fastphys.dll / rapier_bridge.dll，")
        print("        于是 Copy-Item / g++ 不报错但也不产出新文件。")
        print("        而症状是「物理完全不动」「所有刚体停在原点」，很难查。")
        print("")
        print("  请先关掉编辑器（或让我关），再重跑。")
        return 2

    before = {d: (GDEXT / d).stat().st_mtime if (GDEXT / d).is_file() else 0 for d in DLLS}

    # 1) Rust 桥接层
    print("[1/2] rapier_bridge（Rust + Rapier）")
    env = dict(os.environ, CARGO_TARGET_DIR=str(TARGET_DIR))
    r = subprocess.run(["cargo", "build", "--release"], cwd=str(BRIDGE),
                       capture_output=True, text=True, env=env)
    if r.returncode != 0:
        print("  **cargo build 失败**")
        for line in (r.stdout + r.stderr).splitlines():
            if "error" in line.lower():
                print("    " + line)
        return 1
    built = TARGET_DIR / "release" / "rapier_bridge.dll"
    if not built.is_file():
        print("  **找不到 %s**" % built)
        return 1
    shutil.copyfile(built, GDEXT / "rapier_bridge.dll")
    print("  -> gdext/rapier_bridge.dll  %d bytes" % (GDEXT / "rapier_bridge.dll").stat().st_size)

    # 2) GDExtension 入口
    print("[2/2] fastphys（GDExtension 入口）")
    ok = build("g++", [
        "g++", "-O2", "-std=c++17", "-ffp-contract=off", "-shared",
        # 仅静态链接 gcc/stdcpp 会漏掉 winpthread，部署到 Godot 后触发加载错误126。
        "-static", "-I..",
        "-o", "fastphys.dll", "fastphys.cpp",
    ], GDEXT, GDEXT / "fastphys.dll")
    if not ok:
        return 1

    # 3) 核对：两个文件都必须是**这次**写出来的
    print("")
    print("=== 结果 ===")
    bad = 0
    for d in DLLS:
        f = GDEXT / d
        st = f.stat()
        fresh = st.st_mtime > before[d]
        if not fresh:
            bad += 1
        print("  %-22s %10d bytes  %s  %s" % (
            d, st.st_size, time.strftime("%H:%M:%S", time.localtime(st.st_mtime)),
            "新" if fresh else "**没更新**"))
    if bad:
        print("  **有 %d 个文件没更新 —— 构建没有真正生效**" % bad)
        return 1
    print("  两个都是最新的。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
