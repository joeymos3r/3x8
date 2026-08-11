FROM ghcr.io/alireza0/x-ui:latest

# نصب وابستگی‌ها (برای Alpine)
RUN apk add --no-cache sqlite curl jq openssl

# کپی فایل‌های پروژه
COPY config/inbounds.json /opt/3x-ui/config/inbounds.json
COPY scripts/provision.sh /opt/3x-ui/provision.sh
COPY entrypoint.sh /opt/3x-ui/entrypoint.sh

# اجرایی کردن اسکریپت‌ها
RUN chmod +x /opt/3x-ui/provision.sh /opt/3x-ui/entrypoint.sh

ENTRYPOINT ["/opt/3x-ui/entrypoint.sh"]
