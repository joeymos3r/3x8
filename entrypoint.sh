#!/bin/sh
set -e

# تنظیم پورت
if [ -n "$PORT" ]; then
  sed -i "s/listen 3000;/listen ${PORT};/g" /etc/nginx/http.d/default.conf
fi

# اجرای x-ui در پس‌زمینه
x-ui start &

# صبر کن x-ui بالا بیاد
sleep 2

# اجرای nginx در foreground
exec nginx -g "daemon off;"
