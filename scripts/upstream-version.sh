#!/usr/bin/env bash
# 查询 tailscale/tailscale 的最新"正式版" tag。
#
# 原项目用 `git describe --tags $(git rev-list --tags --max-count=1)`，
# 该写法会选中 v1.105.0-pre 之类的预发布 tag，导致镜像追着 pre-release 跑。
# 这里改为：只取形如 v<major>.<minor>.<patch> 的 tag，并按语义化版本取最大值。
set -euo pipefail

exec python3 - <<'PY'
import json, re, urllib.request

req = urllib.request.Request(
    "https://api.github.com/repos/tailscale/tailscale/tags?per_page=100",
    headers={"Accept": "application/vnd.github+json", "User-Agent": "derper-build"},
)
with urllib.request.urlopen(req, timeout=30) as r:
    tags = json.load(r)

pat = re.compile(r"^v(\d+)\.(\d+)\.(\d+)$")
versions = [tuple(map(int, pat.match(t["name"]).groups())) for t in tags if pat.match(t["name"])]
if not versions:
    raise SystemExit("no stable tag found")
major, minor, patch = max(versions)
print(f"v{major}.{minor}.{patch}")
PY
