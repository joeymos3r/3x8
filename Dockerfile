FROM ghcr.io/mhsanaei/3x-ui:latest

RUN apk add --no-cache nginx supervisor bash

COPY nginx.conf /etc/nginx/http.d/default.conf
COPY supervisord.conf /etc/supervisord.conf

RUN echo "=== NGINX VERSION ===" && nginx -v
RUN echo "=== NGINX TEST ===" && nginx -t
RUN echo "=== NGINX CONF ===" && cat /etc/nginx/http.d/default.conf
RUN echo "=== NGINX PATH ===" && which nginx

EXPOSE 3000

CMD ["/bin/sh", "-c", "x-ui start & sleep 3 && echo '=== STARTING NGINX ===' && nginx -g 'daemon off;'"]
