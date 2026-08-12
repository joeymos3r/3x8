FROM ghcr.io/mhsanaei/3x-ui:latest

RUN apk add --no-cache nginx gettext

COPY nginx.conf /etc/nginx/conf.d/default.conf.template
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 3000
ENTRYPOINT ["/entrypoint.sh"]
