# 分支策略

| 分支 | 角色 | 保证 |
|---|---|---|
| `main` | **开发 / 测试** —— 日常提交都在这 | 尽力保持全绿，但不做承诺 |
| `stable` | **稳定** —— 只有全绿才推进 | **一定是可用的** |

## 推进规则

`stable` 只接受 **fast-forward**，且推进前必须跑完全部测试：

```bash
python tools/promote.py            # 跑全部测试，全绿才推进 stable
python tools/promote.py --dry-run  # 只检查，不推
python tools/promote.py --force    # 跳过测试（仅在你已手工验证过时）
```

**为什么做成脚本而不是让人敲 `git push`**：两个分支的价值全在「stable 一定是可用的」
这一条保证上。靠人记的话，某次「就改一行」忘了跑测试，stable 就脏了，
之后没人敢信它 —— 那这个分支就白建了。

脚本会**拒绝**推进的情况：

- 工作区有未提交改动（推的会是上一个提交，容易推错东西）
- 任何一个测试不通过（会打印失败项）
- `stable` 有 `main` 没有的提交（**分叉** —— 必须人来看，不自动合并）

## 用哪个

| 你在做什么 | 用哪个 |
|---|---|
| 做实验 / 加新功能 | `main` |
| 发布 / 交付 / 给别人用 | `stable` |
| **基于本引擎做游戏** | **盯 `stable`** —— 它保证测试全绿 |

## 发布

打 tag 一律从 `stable` 打，不从 `main`：

```bash
git checkout stable && git pull
git tag -a v0.2.0 -m "..." && git push origin v0.2.0
```

## 当前

`stable` 建于节点层改造完成、260 项断言全绿的状态。
