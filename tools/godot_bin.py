#!/usr/bin/env python3
"""找 Godot 可执行文件 —— **唯一真源**。

## 为什么要抽出来

promote.py / gen_api_docs.py / doctor.py 各写了一份"先看环境变量、再看 PATH、
再扫硬编码目录"的复制品，而且**环境变量名还不一样**（GODOT_BIN vs GODOT_EXE）——
同一个项目教人记两个变量名，等于两个都不记。

## 查找顺序

  1. 环境变量 GODOT_BIN（CI 里就是 ./godot）
  2. PATH 里的 godot / godot4
  3. 本机常见安装目录。Windows 下优先挑 *console* 版 —— 非 console 版在
     Windows 上不打印 stdout，测试输出会整批丢掉（只看到退出码）。
"""
import os
import shutil

BASES = (r"D:\Godot_v4.7.2", os.path.expanduser("~/godot"))


def find_godot() -> str:
    """返回可执行文件路径 / 命令名；找不到返回空串。"""
    for cand in (os.environ.get("GODOT_BIN", ""), "godot", "godot4"):
        if cand and shutil.which(cand):
            return cand
    for base in BASES:
        if os.path.isdir(base):
            for f in sorted(os.listdir(base)):
                if f.endswith(".exe") and "console" in f:
                    return os.path.join(base, f)
    return ""


if __name__ == "__main__":
    print(find_godot())
