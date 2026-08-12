FROM debian:bookworm-slim

ENV XUI_VERSION=v3.6.0

# نصب nginx و ابزارهای لازم
RUN apt-get update && apt-get install -y --no-install-recommends \
    nginx \
    wget \
    ca-certificates \
    gettext-base \
    && rm -rf /var/lib/apt/lists/*

# دانلود و نصب 3x-ui
RUN wget -O /tmp/3x-ui-linux-amd64.tar.gz "https://github.com/MHSanaei/3x-ui/releases/download/${XUI_VERSION}/3x-ui-linux-amd64.tar.gz" \
 && tar -xzf /tmp/3x-ui-linux-amd64.tar.gz -C /usr/local/bin/ \
 && chmod +x /usr/local/bin/x-ui \
 && rm /tmp/3x-ui-linux-amd64.tar.gz

# پوشه دیتابیس 3x-ui
RUN mkdir -p /etc/x-ui

# کپی فایل‌های کانفیگ
COPY nginx.conf.template /etc/nginx/nginx.conf.template
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

WORKDIR /etc/x-ui

EXPOSE 3000

ENTRYPOINT ["/entrypoint.sh"]
