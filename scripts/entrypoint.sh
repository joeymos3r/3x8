#!/bin/sh

set -e

# شروع x-ui در پس‌زمینه
x-ui &

# منتظر ماندن تا پنل آماده شود (حداکثر ۳۰ ثانیه)
sleep 10

# اجرای اسکریپت provisioning برای اضافه کردن اینباندها
/opt/3x-ui/provision.sh

# نگه داشتن کانتینر با wait
wait
