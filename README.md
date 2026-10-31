# derper

自建 Tailscale DERP 中继服务器的 Docker 镜像，每日自动跟随 [tailscale/tailscale](https://github.com/tailscale/tailscale) 正式版发布。

上游官方 `derper` 在 `--certmode=manual` 下会严格校验 TLS SNI 必须等于 `--hostname`，自建场景（Headscale、自签证书、客户端 HostName 与证书名不一致）会直接握手失败。本项目在上游源码上只保留**一处补丁**：移除该 SNI 严格匹配，其余行为、启动参数、环境变量与上游完全一致。

镜像：`ghcr.io/default102/derper:<上游版本号>`，例如 `ghcr.io/default102/derper:v1.104.4`，同时提供 `latest`。

> 因放宽了 SNI 校验，请仅在可控环境中使用自签证书。

## 快速开始

```bash
docker run -d \
  --name derper \
  -p 12345:12345/tcp -p 3478:3478/udp \
  -e DERP_DOMAIN=derp.example.com \
  -e DERP_ADDR=':12345' \
  -e DERP_STUN_PORT='3478' \
  -e DERP_HTTP_PORT='-1' \
  -e DERP_VERIFY_CLIENTS="false" \
  -e DERP_CERT_DIR=/cert \
  -v $(pwd)/cert:/cert \
  ghcr.io/default102/derper:latest
```

容器默认在 `DERP_CERT_MODE=manual` 且证书不存在时，自动生成有效期 730 天的自签证书（`${DERP_CERT_DIR}/${DERP_DOMAIN}.crt` / `.key`）。用自己的证书覆盖这两个文件即可。

### docker compose

```yaml
services:
  derper:
    image: ghcr.io/default102/derper:latest
    container_name: derper
    ports:
      - "12345:12345/tcp"
      - "3478:3478/udp"
    environment:
      DERP_DOMAIN: derp.example.com
      DERP_CERT_MODE: manual
      DERP_CERT_DIR: /cert
      DERP_ADDR: ':12345'
      DERP_STUN_PORT: '3478'
      DERP_HTTP_PORT: '-1'
      DERP_VERIFY_CLIENTS: "false"
    volumes:
      - ./cert:/cert
```

## 配置项

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `DERP_DOMAIN` | `your-hostname.com` | DERP 对外主机名，需与客户端配置一致 |
| `DERP_CERT_DIR` | `/app/certs` | 证书目录，存放 `${DERP_DOMAIN}.crt` / `.key` |
| `DERP_CERT_MODE` | `manual` | `manual` 读取本地证书；`letsencrypt` 走 ACME |
| `DERP_ADDR` | `:443` | DERP 监听地址 |
| `DERP_STUN` / `DERP_STUN_PORT` | `true` / `3478` | STUN 开关与端口（UDP） |
| `DERP_HTTP_PORT` | `-1` | HTTP 调试端口，`-1` 关闭 |
| `DERP_VERIFY_CLIENTS` | `true` | 通过本机 `tailscaled` 校验客户端；容器内通常无 `tailscaled`，自建场景建议置 `false` |
| `DERP_VERIFY_CLIENT_URL` | 空 | 外部准入控制 URL |

## 与上游版本的对应关系

- 镜像 tag = 上游 tailscale 的正式版 tag（`v1.104.4` → `ghcr.io/default102/derper:v1.104.4`）。
- 只跟随 `v<major>.<minor>.<patch>` 形式的正式版，`v1.105.0-pre` 这类预发布 tag 会被忽略。
- 每日 UTC 03:17 检查一次；也可用 Actions 手动触发并指定版本。

## 本地构建

```bash
make upstream          # 查看上游最新正式版
make build             # 下载上游源码 -> 打补丁 -> docker build（产出 :local）
make smoke             # 起容器 + 自签证书 + HTTPS 探活
make build VERSION=v1.104.4
```

`scripts/apply-patches.sh` 带前置/后置断言：上游代码结构一旦变化（补丁不再匹配），构建会**立刻失败**并给出原因，绝不会静默产出一个行为不符的镜像。此时只需更新该脚本中的匹配模式。

## 为什么不用 `FROM golang`

tailscale 的 `go.mod` 会在每次 Go 小版本发布后立刻抬高 `go` 指令（当前为 `go 1.27.3`），而官方 `golang` 镜像通常滞后几天，构建会直接失败在 `go.mod requires go >= X`。tailscale 自己的 Dockerfile 对此有专门说明（[issue #21072](https://github.com/tailscale/tailscale/issues/21072)），做法是依据仓库中的 `go.toolchain.rev` 下载他们维护的 Go fork。本项目的 `Dockerfile` 沿用同一方案；如需切回官方镜像：

```bash
docker build --build-arg GO_BUILDER_IMAGE=golang:1.27 ...
```

## 常见问题

**`not connected to home DERP region ...`** — 客户端不信任自签证书。Headscale 在 `derp.json` 中为该节点加 `"InsecureForTests": true`。

**`TLS connection error ... certificate is self-signed`** — 自建环境的预期告警，不影响功能，可忽略。

**客户端提示无法连接** — 检查安全组/防火墙是否放行 `DERP_ADDR` 的 TCP 与 STUN 的 UDP 端口。

Headscale 的 `derp.json` 示例：

```json
{
  "Regions": {
    "901": {
      "RegionID": 901,
      "RegionCode": "derp-cd",
      "RegionName": "derp-chengdu",
      "Nodes": [
        {
          "Name": "901a",
          "RegionID": 901,
          "DERPPort": 12345,
          "STUNPort": 3478,
          "STUNOnly": false,
          "HostName": "derp.example.com",
          "InsecureForTests": true
        }
      ]
    }
  }
}
```

## 许可

MIT。构建产物 `derper` 本身遵循 tailscale 的 BSD-3-Clause。
