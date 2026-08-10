FROM alpine:3.20

ARG XUI_VERSION=v3.6.0
ENV XUI_PORT=3000

RUN apk add --no-cache \
    bash \
    ca-certificates \
    curl \
    jq \
    tzdata \
    wget

WORKDIR /opt/3x-ui

RUN set -eux; \
    mkdir -p /opt/3x-ui/config; \
    arch="$(uname -m)"; \
    case "$arch" in \
      x86_64) asset_arch="amd64" ;; \
      aarch64) asset_arch="arm64" ;; \
      armv7) asset_arch="armv7" ;; \
      *) echo "Unsupported architecture: $arch" >&2; exit 1 ;; \
    esac; \
    url="https://github.com/MHSanaei/3x-ui/releases/download/${XUI_VERSION}/x-ui-linux-${asset_arch}.tar.gz"; \
    wget -O /tmp/x-ui.tar.gz "$url"; \
    tar -xzf /tmp/x-ui.tar.gz -C /opt/3x-ui --strip-components=1; \
    rm -f /tmp/x-ui.tar.gz

COPY config/inbounds.json /opt/3x-ui/config/inbounds.json
COPY scripts/provision.sh /opt/3x-ui/provision.sh
COPY scripts/entrypoint.sh /opt/3x-ui/entrypoint.sh

RUN chmod +x /opt/3x-ui/provision.sh /opt/3x-ui/entrypoint.sh

EXPOSE 3000

ENTRYPOINT ["/opt/3x-ui/entrypoint.sh"]
