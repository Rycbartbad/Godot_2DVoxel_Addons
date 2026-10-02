#!/usr/bin/env python3
r"""用 GitHub API 建 Release（从仓库里的发布说明读正文）。

## 为什么单独写这个脚本

tag 用 git 推就够了，但 **Release 是 GitHub 的元数据**，git 推不上去，
必须走 API。而 API 需要 token —— 这个脚本把 token 的读取、仓库地址解析、
正文装配都封起来，让"发一个版本"变成一条命令。

## token 放哪（**不要**贴进对话或写进仓库）

脚本按顺序找：

  1. 环境变量 GITHUB_TOKEN 或 GH_TOKEN
  2. 文件 ~/.gh_token（内容就是 token 本身，一行）

推荐用文件：

  # 在 GitHub 建 token： https://github.com/settings/tokens
  #   经典 token 勾 repo
  #   细粒度 token 给 Contents: Read and write
  # 然后（PowerShell，注意别让内容进 shell 历史）：
  Set-Content -Path "$env:USERPROFILE\.gh_token" -Value "ghp_xxxx" -NoNewline

脚本**从不打印 token**，出错信息里也会把它抹掉。

## ⚠️ 已知环境问题：这台机器上 Python 的 urllib 连不上 api.github.com

实测 `WinError 10054`（连接被重置），重试 4 次全失败 —— 但同一台机器上：

  curl https://api.github.com/zen        -> HTTP 200
  ssh -T git@github.com                  -> 认证成功
  [System.Net.Dns]::GetHostAddresses     -> 正常解析

所以**网络是通的**，是 Python 的 TLS/连接层被重置。urllib 路径在这台机器上不可用。

绕过办法（已验证可用）：让 curl 发请求。

  hdr=(-H "Authorization: Bearer $tok" -H "Accept: application/vnd.github+json")
  curl -s @hdr "https://api.github.com/repos/OWNER/REPO/releases/tags/TAG"
  curl -s -X PATCH @hdr -H "Content-Type: application/json" \
       --data-binary '@payload.json' "https://api.github.com/repos/OWNER/REPO/releases/ID"

payload.json 的内容是 {"name": TAG, "body": "<发布说明全文>"}。

另外：**推 tag 时 GitHub 会自己建一个 Release**（正文是自动生成的 changelog 链接），
所以 POST 几乎必然撞 already_exists —— 脚本已经处理成"改成更新正文"。

## 用法

  python tools/make_release.py v0.2.0              # 建 Release
  python tools/make_release.py v0.2.0 --dry-run    # 只显示将要提交的内容
  python tools/make_release.py v0.2.0 --draft      # 建草稿
"""
import argparse
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
API = "https://api.github.com"


def token() -> str:
    for n in ("GITHUB_TOKEN", "GH_TOKEN"):
        v = os.environ.get(n)
        if v:
            return v.strip()
    p = os.path.join(os.path.expanduser("~"), ".gh_token")
    if os.path.isfile(p):
        with open(p, encoding="utf-8") as f:
            return f.read().strip()
    return ""


def repo_slug() -> str:
    """从 origin 的 URL 解析出 owner/repo（SSH 与 HTTPS 两种都支持）。"""
    url = subprocess.run(["git", "remote", "get-url", "origin"], cwd=ROOT,
                         capture_output=True, text=True).stdout.strip()
    m = re.search(r"github\.com[:/]([^/]+)/(.+?)(?:\.git)?$", url)
    if not m:
        print("解析不出 GitHub 仓库地址：%s" % url)
        sys.exit(1)
    return "%s/%s" % (m.group(1), m.group(2))


def scrub(s: str, tok: str) -> str:
    """任何输出前都过一遍，确保 token 不会被打印出来。"""
    return s.replace(tok, "***") if tok else s


def call(method: str, path: str, tok: str, body=None):
    data = json.dumps(body).encode("utf-8") if body is not None else None
    req = urllib.request.Request(API + path, data=data, method=method)
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("Authorization", "Bearer " + tok)
    req.add_header("X-GitHub-Api-Version", "2022-11-28")
    if data:
        req.add_header("Content-Type", "application/json")
    # ⚠️ 网络类错误要重试，HTTP 状态码不要。
    #    这台机器到 GitHub 经常 WinError 10054 / "Remote end closed connection"，
    #    一次失败就报错很烦；但 4xx 重试多少次都一样，重试只会掩盖真问题。
    last = ""
    for attempt in range(4):
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                return json.loads(r.read().decode("utf-8")), None
        except urllib.error.HTTPError as e:
                # 请求体可能已经被读过一次，重建一个
            return None, "%s %s" % (e.code, e.read().decode("utf-8", "replace")[:400])
        except Exception as e:                  # noqa: BLE001
            last = str(e)
            if attempt < 3:
                print("  网络错误，重试 %d/3：%s" % (attempt + 1, last[:60]))
                time.sleep(2.0 * (attempt + 1))
                if data is not None:
                    req = urllib.request.Request(API + path, data=data, method=method)
                    req.add_header("Accept", "application/vnd.github+json")
                    req.add_header("Authorization", "Bearer " + tok)
                    req.add_header("X-GitHub-Api-Version", "2022-11-28")
                    req.add_header("Content-Type", "application/json")
    return None, last


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("tag")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--draft", action="store_true")
    ap.add_argument("--prerelease", action="store_true")
    args = ap.parse_args()

    tag = args.tag
    slug = repo_slug()

    # 正文优先读仓库里的发布说明 —— 让"仓库文档"和"Release 页面"同源，
    # 而不是两边各写一遍然后慢慢漂移。
    notes_path = os.path.join(ROOT, "docs", "release_notes", "%s.md" % tag)
    if os.path.isfile(notes_path):
        with open(notes_path, encoding="utf-8") as f:
            body = f.read()
        print("正文来自 %s（%d 字符）" % (
            os.path.relpath(notes_path, ROOT).replace(os.sep, "/"), len(body)))
    else:
        body = "见仓库 docs/release_notes/%s.md" % tag
        print("⚠️ 找不到 docs/release_notes/%s.md，用占位正文" % tag)

    tok = token()
    if not tok and not args.dry_run:
        print("找不到 token。请把 Personal Access Token 存到 ~/.gh_token，")
        print("或设环境变量 GITHUB_TOKEN。详见本文件开头的说明。")
        return 1

    payload = {
        "tag_name": tag,
        "name": tag,
        "body": body,
        "draft": args.draft,
        "prerelease": args.prerelease,
    }

    if args.dry_run:
        print("仓库：%s" % slug)
        print("POST %s/repos/%s/releases" % (API, slug))
        print("tag_name=%s draft=%s prerelease=%s" % (tag, args.draft, args.prerelease))
        print("正文前 300 字符：\n%s" % body[:300])
        return 0

    # 先确认 tag 在远端存在 —— 否则 API 会自己从默认分支造一个 tag，
    # 那是指向错误提交的 Release，比失败更糟。
    _, err = call("GET", "/repos/%s/git/ref/tags/%s" % (slug, tag), tok)
    if err:
        print("远端没有 tag %s，请先 git push origin %s" % (tag, tag))
        print("  " + scrub(err, tok))
        return 1

    data, err = call("POST", "/repos/%s/releases" % slug, tok, payload)
    if err and "already_exists" in err:
        # ⚠️ 推 tag 时 GitHub 会**自动建一个 Release**（正文是自动生成的 changelog 链接），
        #    所以正常流程下 POST 几乎必然撞 already_exists —— 这不是错误，是常态。
        #    撞上就改成更新，把仓库里的发布说明灌进去（两边同源）。
        print("Release 已存在（推 tag 时 GitHub 自动建的），改为更新正文")
        cur, err2 = call("GET", "/repos/%s/releases/tags/%s" % (slug, tag), tok)
        if err2:
            print("查不到已有 Release：")
            print("  " + scrub(err2, tok))
            return 1
        if (cur.get("body") or "").strip() == body.strip():
            print("正文已经一致，不用改：%s" % cur.get("html_url", ""))
            return 0
        data, err2 = call("PATCH", "/repos/%s/releases/%d" % (slug, cur["id"]), tok,
                          {"name": tag, "body": body})
        if err2:
            print("更新失败：")
            print("  " + scrub(err2, tok))
            return 1
        print("正文已更新为 %d 字符：%s" % (len(body), data.get("html_url", "")))
        return 0
    if err:
        print("建 Release 失败：")
        print("  " + scrub(err, tok))
        return 1
    print("Release 已建立：%s" % data.get("html_url", "(无 URL)"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
