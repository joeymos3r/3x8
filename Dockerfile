FROM ghcr.io/mhsanaei/3x-ui:latest

RUN apk add --no-cache nginx supervisor bash

COPY nginx.conf /etc/nginx/http.d/default.conf
COPY supervisord.conf /etc/supervisord.conf
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

RUN nginx -t

EXPOSE 3000

CMD ["/entrypoint.sh"]
