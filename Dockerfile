FROM ghcr.io/mhsanaei/3x-ui:latest

RUN apk add --no-cache nginx

COPY nginx.conf /etc/nginx/http.d/default.conf
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 3000
ENTRYPOINT ["/entrypoint.sh"]
