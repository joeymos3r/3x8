FROM ghcr.io/mhsanaei/3x-ui:latest

RUN apk add --no-cache nginx supervisor bash

COPY nginx.conf /etc/nginx/http.d/default.conf
COPY supervisord.conf /etc/supervisord.conf

RUN nginx -t

EXPOSE 3000

CMD ["/bin/sh", "-c", "x-ui start & sleep 3 && exec nginx -g 'daemon off;'"]
