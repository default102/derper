SHELL := /bin/bash
IMAGE ?= ghcr.io/default102/derper
VERSION ?= $(shell ./scripts/upstream-version.sh)
PLATFORM ?= linux/$(shell uname -m | sed -e 's/x86_64/amd64/' -e 's/aarch64/arm64/')

.PHONY: upstream src build smoke clean

## 查询上游最新正式版
upstream:
	@echo "$(VERSION)"

## 下载上游源码并打补丁
src:
	./scripts/fetch-upstream.sh "$(VERSION)"
	./scripts/apply-patches.sh

## 本地构建（与 CI 完全同一条路径）
build: src
	@set -euo pipefail; \
	VERSION_LONG=$$(sed -n 1p build_src/VERSION); \
	VERSION_GIT_HASH=$$(sed -n 2p build_src/VERSION); \
	echo "building $$VERSION_LONG ($$VERSION_GIT_HASH) for $(PLATFORM)"; \
	docker build --platform "$(PLATFORM)" \
	  --build-arg VERSION_LONG="$$VERSION_LONG" \
	  --build-arg VERSION_GIT_HASH="$$VERSION_GIT_HASH" \
	  -t "$(IMAGE):local" .

## 冒烟测试：起容器 + 自签证书 + HTTPS 探活
smoke:
	@set -euo pipefail; \
	docker rm -f derper-smoke >/dev/null 2>&1 || true; \
	docker run -d --name derper-smoke \
	  -e DERP_DOMAIN=derp.example.com -e DERP_ADDR=:13443 \
	  -e DERP_HTTP_PORT=-1 -e DERP_VERIFY_CLIENTS=false \
	  -p 13443:13443 "$(IMAGE):local" >/dev/null; \
	trap 'docker rm -f derper-smoke >/dev/null 2>&1 || true' EXIT; \
	for i in $$(seq 1 30); do \
	  if curl -ksSf -o /dev/null https://127.0.0.1:13443/; then \
	    echo "smoke OK: derper 已响应 HTTPS"; exit 0; \
	  fi; sleep 1; \
	done; \
	echo "smoke FAILED" >&2; docker logs derper-smoke >&2; exit 1

clean:
	rm -rf build_src
