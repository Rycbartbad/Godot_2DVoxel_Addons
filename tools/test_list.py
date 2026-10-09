#!/usr/bin/env python3
"""测试闸门名单 —— **唯一真源**。

## 为什么要有这个文件

名单原本写在两个地方（.github/workflows/ci.yml 的循环与 tools/promote.py 的
TESTS），而且**已经分叉**：CI 那份引用了一个早已删除的 test_parallel
（engine-tests job 因为没设 GODOT_VERSION 一直没跑，所以没人发现），promote
那份又少了几个。两份清单必然漂移 —— 本仓库在"同一份规则写在两个地方"上
栽过不止一次（见 docs/development_log.md 坑 18/31/36）。

所以：**加测试只改这里**，CI 与 promote 都从这里读。

## 判据

进这张表的测试必须打印 "N passed, M failed" ——
CI 用 grep "0 failed" 判、promote.py 用正则取数。不打印这个格式的
（dump_state 是逐位摘要、check_manual_api 是手册引用检查）**不进表**，
它们各自有专门的步骤。

用法：
    python tools/test_list.py                    # 空格分隔（CI 的 for 循环用）
    python tools/test_list.py --lines            # 每行一个
    python tools/test_list.py --prefix test_     # 只取单元断言
"""
import sys

GATES = [
    "test_core", "test_physics", "test_interaction", "test_determinism",
    "validation_sweep", "validation_query", "validation_api", "validation_api2",
    "validation_voxel_layer", "validation_contacts", "validation_traversal",
    "validation_dynamics", "validation_nodes", "validation_alignment",
    "validation_shape_plugin", "validation_stress", "validation_facade_api",
    "validation_fluid", "validation_hull",
    ## 这两条原本零引用（「自称闸门却没人接线」）：汇总行格式统一后才进得了名单。
    "validation_facade_render", "validation_tile_incremental",
]


def main() -> int:
    args = sys.argv[1:]
    names = list(GATES)
    if "--prefix" in args:
        p = args[args.index("--prefix") + 1]
        names = [n for n in names if n.startswith(p)]
    if "--lines" in args:
        print("\n".join(names))
    else:
        print(" ".join(names))
    return 0


if __name__ == "__main__":
    sys.exit(main())
