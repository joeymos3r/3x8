#!/bin/sh

set -e

# مطمئن شو پوشه دیتابیس وجود داره
mkdir -p /etc/x-ui

echo "Starting 3x-ui..."
# اجرای فایل اجرایی با مسیر کامل
/opt/3x-ui/x-ui &

echo "Waiting for database to be created..."
# صبر کن تا دیتابیس ساخته بشه (حداکثر ۱۰ ثانیه)
TIMEOUT=10
while [ ! -f /etc/x-ui/x-ui.db ] && [ $TIMEOUT -gt 0 ]; do
  sleep 1
  TIMEOUT=$((TIMEOUT - 1))
done

if [ -f /etc/x-ui/x-ui.db ]; then
  echo "Database found. Running provisioning..."
  /opt/3x-ui/provision.sh
else
  echo "ERROR: Database not created after 10 seconds!"
  exit 1
fi

# نگه داشتن کانتینر
wait
