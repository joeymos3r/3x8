FROM ghcr.io/mhsanaei/3x-ui:latest

RUN apk add --no-cache nginx

COPY nginx.conf /etc/nginx/http.d/default.conf
COPY start.sh /start.sh

RUN chmod +x /start.sh && nginx -t

EXPOSE 3000

ENTRYPOINT ["/start.sh"]
