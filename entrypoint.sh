#!/bin/bash
set -e

# جایگذاری PORT واقعی Railway در کانفیگ nginx
envsubst '${PORT}' < /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf

# اجرای 3x-ui در پس‌زمینه
x-ui &

# کمی صبر کن تا 3x-ui بالا بیاید
sleep 3

# اجرای nginx در foreground
exec nginx -g 'daemon off;'
