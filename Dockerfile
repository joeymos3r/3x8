FROM ghcr.io/mhsanaei/3x-ui:latest

RUN apk add --no-cache nginx

COPY nginx.conf /etc/nginx/http.d/default.conf

RUN nginx -t

EXPOSE 3000

# خالی کردن ENTRYPOINT تصویر پایه
ENTRYPOINT []

# اجرای x-ui در پس‌زمینه و nginx در foreground
CMD ["/bin/sh", "-c", "x-ui start & sleep 3 && exec nginx -g 'daemon off;'"]
