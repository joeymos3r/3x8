#!/bin/sh

# اجرای x-ui در پس‌زمینه
x-ui start &

# صبر برای بالا اومدن پنل
sleep 3

# اجرای Nginx به‌عنوان فرآیند اصلی (جایگزین)
exec nginx -g 'daemon off;'
