FROM ghcr.io/mhsanaei/3x-ui:latest

# نصب nginx, supervisor, bash
RUN apk add --no-cache nginx supervisor bash

COPY nginx.conf /etc/nginx/http.d/default.conf
COPY supervisord.conf /etc/supervisord.conf

# تست اعتبار کانفیگ در زمان build
RUN nginx -t

EXPOSE 3000

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisord.conf"]
