# syntax=docker/dockerfile:1.7
#
# 构建 tailscale/cmd/derper + 本项目补丁。
#
# 为什么不用 `FROM golang`：tailscale 的 go.mod 在每次 Go 小版本发布后会立刻
# 抬高 go directive（现在是 go 1.27.3），而官方 golang 镜像往往滞后几天，
# 构建会直接失败在 "go.mod requires go >= X"。tailscale 自己的 Dockerfile
# 对此有专门说明（issue #21072）：按仓库里的 go.toolchain.rev 下载他们维护的
# Go fork，永远和 go.mod 匹配。
#
# 兜底：若不想用 fork，传 --build-arg GO_BUILDER_IMAGE=golang:1.27 即可切回
# 官方镜像（此时依赖 GOTOOLCHAIN=auto 联网补齐小版本）。

ARG GO_BUILDER_IMAGE=tailscale-go

# ---------------------------------------------------------------- 工具链阶段
FROM alpine:3.22 AS tailscale-go
ARG TARGETARCH
RUN apk add --no-cache curl tar
COPY build_src/tailscale/go.toolchain.rev /tmp/go.toolchain.rev
RUN set -eux; \
    read -r REV < /tmp/go.toolchain.rev; \
    case "${TARGETARCH}" in \
      amd64) ARCH=amd64 ;; \
      arm64) ARCH=arm64 ;; \
      *) echo "unsupported TARGETARCH=${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    curl --retry 5 -fL -o /tmp/go.tar.gz \
      "https://github.com/tailscale/go/releases/download/build-${REV}/linux-${ARCH}.tar.gz"; \
    mkdir -p /usr/local/go; \
    tar -C /usr/local/go --strip-components=1 -xzf /tmp/go.tar.gz; \
    rm -f /tmp/go.tar.gz; \
    /usr/local/go/bin/go version
ENV PATH=/usr/local/go/bin:/go/bin:$PATH
ENV GOPATH=/go

# ---------------------------------------------------------------- 编译阶段
FROM ${GO_BUILDER_IMAGE} AS builder
ARG TARGETARCH
ARG VERSION_LONG=""
ARG VERSION_GIT_HASH=""
WORKDIR /src
COPY build_src/tailscale/ /src/

# 先只拉依赖，利用 Docker 层缓存：改补丁不会重下依赖
RUN --mount=type=cache,target=/go/pkg/mod go mod download

# 注意：VERSION_LONG/SHORT/GIT_HASH 来自 source .envrc，不是 Dockerfile 的 ARG/ENV。
# 必须写成 $${...} —— 单个 $ 会被 Docker 在启动 shell 之前就替换成空字符串
# （原项目正是这样，导致 -X 实际注入了空值，derper --version 一直是默认值）。
RUN set -eux; \
    export TS_VERSION_LONG="${VERSION_LONG}" TS_VERSION_GIT_HASH="${VERSION_GIT_HASH}"; \
    go run ./cmd/mkversion --export > /tmp/envrc; \
    . /tmp/envrc; \
    CGO_ENABLED=0 GOOS=linux GOARCH="${TARGETARCH}" \
      go build -trimpath -o /out/derper \
      -ldflags "-s -w \
        -X tailscale.com/version.longStamp=$${VERSION_LONG} \
        -X tailscale.com/version.shortStamp=$${VERSION_SHORT} \
        -X tailscale.com/version.gitCommitStamp=$${VERSION_GIT_HASH}" \
      ./cmd/derper; \
    /out/derper --version

# ---------------------------------------------------------------- 运行阶段
FROM alpine:3.22
RUN set -eux; \
    apk add --no-cache ca-certificates openssl curl tzdata

COPY --from=builder /out/derper /usr/bin/derper
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

WORKDIR /app

ENV DERP_DOMAIN your-hostname.com
ENV DERP_CERT_MODE manual
ENV DERP_CERT_DIR /app/certs
ENV DERP_ADDR :443
ENV DERP_STUN true
ENV DERP_STUN_PORT 3478
ENV DERP_HTTP_PORT -1
ENV DERP_VERIFY_CLIENTS true
ENV DERP_VERIFY_CLIENT_URL ""

EXPOSE 443 3478/udp

ENTRYPOINT ["/docker-entrypoint.sh"]
CMD exec derper --hostname=$DERP_DOMAIN \
  --certmode=$DERP_CERT_MODE \
  --certdir=$DERP_CERT_DIR \
  --a=$DERP_ADDR \
  --stun=$DERP_STUN \
  --stun-port=$DERP_STUN_PORT \
  --http-port=$DERP_HTTP_PORT \
  --verify-clients=$DERP_VERIFY_CLIENTS \
  --verify-client-url=$DERP_VERIFY_CLIENT_URL
