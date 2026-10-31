#!/usr/bin/env bash
# 对上游源码打补丁。
#
# 设计要点（这是本项目能长期跟上上游的关键）：
#   1. 前置断言：目标代码必须存在且唯一，否则立刻失败并给出明确原因；
#   2. 语义化块删除：按 if 块整体删除，而不是 sed '/pattern/,+2d' 这种
#      "假设恰好 3 行"的写法 —— 上游一改行数就会静默打歪；
#   3. 后置断言：确认目标代码已消失、函数仍在、文件语法仍合法。
#   宁可构建失败，也不要静默产出一个行为不符的镜像。
set -euo pipefail

SRC="${SRC:-build_src/tailscale}"
CERT="${SRC}/cmd/derper/cert.go"

die() { echo "patch: $*" >&2; exit 1; }

[ -f "$CERT" ] || die "not found: $CERT (先运行 scripts/fetch-upstream.sh)"

# --- 1. 前置断言 -------------------------------------------------------------
MATCHES=$(grep -c 'if hi.ServerName != m.hostname' "$CERT" || true)
[ "$MATCHES" = "1" ] || die "期望 cert.go 中恰好 1 处 'hi.ServerName != m.hostname'，实际 ${MATCHES} 处；上游代码已变更，需要更新本脚本"

# --- 2. 补丁：移除 manual 模式下对 TLS SNI 与 --hostname 的严格匹配 ----------
# 原项目行为（保持一致）：自建自签证书场景下，客户端 SNI 与 --hostname 不一致时
# 不再拒绝握手，避免 derper 直接断开导致节点反复重连。
perl -0777 -pi -e '
  s/\n\tif hi\.ServerName != m\.hostname && !m\.noHostname \{\n\t\treturn nil, fmt\.Errorf\("cert mismatch with hostname: %q", hi\.ServerName\)\n\t\}\n//;
' "$CERT"

# --- 3. 后置断言 -------------------------------------------------------------
if grep -q 'cert mismatch with hostname' "$CERT"; then
  die "补丁未生效：'cert mismatch with hostname' 仍然存在"
fi
grep -q 'func (m \*manualCertManager) getCertificate' "$CERT" \
  || die "补丁后 getCertificate 缺失，删除范围可能过大"
grep -q 'return &certCopy, nil' "$CERT" \
  || die "补丁后 getCertificate 返回值缺失"

# 语法校验（有 Go 工具链时执行）
if command -v gofmt >/dev/null 2>&1; then
  gofmt -e "$CERT" >/dev/null || die "补丁后 Go 语法不合法"
fi

echo "patch applied: cmd/derper/cert.go (SNI/hostname 严格匹配已移除)"
