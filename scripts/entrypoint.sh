#!/bin/bash

set -e

echo "=========================================="
echo "  Starting 3x-ui"
echo "  Port: 3000"
echo "  DB: /etc/x-ui"
echo "=========================================="

# استارت پنل
echo "[1/3] Starting 3x-ui..."
/usr/local/x-ui/x-ui start &

# منتظر ماندن برای آماده شدن پنل
echo "[2/3] Waiting for panel..."
for i in {1..30}; do
    if curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:3000/ | grep -q "200\|302\|307"; then
        echo "Panel is ready!"
        break
    fi
    sleep 2
done

# اجرای اسکریپت Provisioning
echo "[3/3] Running provisioning..."
if [ -f "/opt/3x-ui/provision.sh" ]; then
    /opt/3x-ui/provision.sh || echo "⚠️  Provisioning failed, but continuing..."
else
    echo "⚠️  provision.sh not found!"
fi

echo "=========================================="
echo "  3x-ui is ONLINE"
echo "  URL: https://3x8-production.up.railway.app/panel"
echo "=========================================="

tail -f /dev/null
