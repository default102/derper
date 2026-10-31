#!/bin/sh
# 行为与原项目一致：DERP_CERT_MODE=manual 且证书不存在时，自动生成 2 年自签证书。
# 改进点：POSIX 兼容写法（== 改 =）、命令透传更清晰、证书生成失败立即退出。

if [ -n "${DEBUG:-}" ]; then set -x; fi
set -e

gen_self_signed_cert() {
    mkdir -p "$DERP_CERT_DIR"

    if echo "$DERP_DOMAIN" | grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}$'; then
        alt_name="IP.1 = $DERP_DOMAIN"
    else
        alt_name="DNS.1 = $DERP_DOMAIN"
    fi

    conf=$(mktemp)
    cat > "$conf" <<EOF
[req]
default_bits  = 2048
distinguished_name = req_distinguished_name
req_extensions = req_ext
x509_extensions = v3_req
prompt = no

[req_distinguished_name]
countryName = XX
stateOrProvinceName = N/A
localityName = N/A
organizationName = Self-signed certificate
commonName = $DERP_DOMAIN: Self-signed certificate

[req_ext]
subjectAltName = @alt_names

[v3_req]
subjectAltName = @alt_names

[alt_names]
$alt_name
EOF

    echo "生成自签证书: ${DERP_CERT_DIR}/${DERP_DOMAIN}.crt (有效期 730 天)"
    openssl req -x509 -nodes -days 730 -newkey rsa:2048 \
        -keyout "${DERP_CERT_DIR}/${DERP_DOMAIN}.key" \
        -out "${DERP_CERT_DIR}/${DERP_DOMAIN}.crt" \
        -config "$conf"
    rm -f "$conf"
}

if [ "${DERP_CERT_MODE:-manual}" = "manual" ] \
    && [ -n "${DERP_DOMAIN:-}" ] \
    && [ -n "${DERP_CERT_DIR:-}" ] \
    && [ ! -f "${DERP_CERT_DIR}/${DERP_DOMAIN}.crt" ]; then
    gen_self_signed_cert
fi

# 支持 `docker run <image> --a=:12345` 这类直接传参的写法
case "${1:-}" in
    ""|derper|/*) ;;
    *) set -- derper "$@" ;;
esac

exec "$@"
