#!/bin/bash

cd /usr/local/x-ui

# تنظیم پورت پنل
./x-ui setting -port 2053

# اجرای پنل در پس‌زمینه
./x-ui start &

# صبر تا پنل بالا بیاد
sleep 5

# اجرای Nginx در foreground
nginx -g 'daemon off;'
