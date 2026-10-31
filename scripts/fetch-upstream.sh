#!/usr/bin/env bash
# 下载指定版本的 tailscale 源码到 build_src/tailscale（Docker 构建上下文）。
#
# 用 tarball 而不是 git clone：
#   - 体积从 ~200MB 降到 ~30MB，CI 与本地都快；
#   - 源码树里没有 .git，版本信息改由 TS_VERSION_LONG / TS_VERSION_GIT_HASH
#     注入（cmd/mkversion 原生支持，见其文件头注释）。
set -euo pipefail

VERSION="${1:?usage: fetch-upstream.sh <version>  # e.g. v1.104.4}"
DEST="${DEST:-build_src/tailscale}"

rm -rf "$DEST"
mkdir -p "$DEST"

curl --retry 5 -fsSL \
  "https://github.com/tailscale/tailscale/archive/refs/tags/${VERSION}.tar.gz" \
  -o /tmp/tailscale.tar.gz

tar -xzf /tmp/tailscale.tar.gz -C "$DEST" --strip-components=1
rm -f /tmp/tailscale.tar.gz

# 记录版本元信息，供 Dockerfile / Makefile 复用
SHA=$(curl --retry 5 -fsSL \
  "https://api.github.com/repos/tailscale/tailscale/commits/${VERSION}" \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["sha"])')

printf '%s\n%s\n' "$VERSION" "$SHA" > build_src/VERSION
echo "fetched ${VERSION} (${SHA}) -> ${DEST}"
