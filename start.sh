#!/bin/sh

set -e

echo "========================================"
echo " 3x-ui + Xray + Nginx / Railway"
echo "========================================"

PORT="${PORT:-3000}"

echo "Railway HTTP PORT: ${PORT}"
echo "Xray TCP PORT: 8080"

# ---------------------------------------------------------
# Nginx must listen on Railway HTTP PORT.
# Xray is free to use 8080 for TCP Proxy.
# ---------------------------------------------------------

sed -i "s/__RAILWAY_PORT__/${PORT}/g" /etc/nginx/http.d/default.conf

echo "Testing nginx configuration..."
nginx -t

# ---------------------------------------------------------
# Start 3x-ui / Xray
# ---------------------------------------------------------

echo "Starting 3x-ui..."

# Disable the VPS-only fail2ban integration.
export X_UI_ENABLE_FAIL2BAN=false
export XUI_ENABLE_FAIL2BAN=false

/app/x-ui &
XUI_PID=$!

echo "3x-ui PID: ${XUI_PID}"

# ---------------------------------------------------------
# Wait for panel
# ---------------------------------------------------------

echo "Waiting for 3x-ui on 2053..."

READY=0

for i in $(seq 1 60); do

    if wget -q -O /dev/null \
        --timeout=2 \
        http://127.0.0.1:2053/ 2>/dev/null
    then
        READY=1
        echo "3x-ui is ready."
        break
    fi

    if ! kill -0 "$XUI_PID" 2>/dev/null; then
        echo "ERROR: 3x-ui stopped."
        exit 1
    fi

    echo "Waiting for 3x-ui... ${i}/60"

    sleep 1
done

if [ "$READY" != "1" ]; then
    echo "ERROR: 3x-ui did not start."
    exit 1
fi

# ---------------------------------------------------------
# Start Nginx
# ---------------------------------------------------------

echo "Starting nginx..."

nginx -g "daemon off;" &
NGINX_PID=$!

echo "nginx PID: ${NGINX_PID}"

# ---------------------------------------------------------
# Keep both services alive
# ---------------------------------------------------------

while true; do

    if ! kill -0 "$XUI_PID" 2>/dev/null; then
        echo "ERROR: 3x-ui/Xray stopped."
        kill "$NGINX_PID" 2>/dev/null || true
        exit 1
    fi

    if ! kill -0 "$NGINX_PID" 2>/dev/null; then
        echo "ERROR: nginx stopped."
        kill "$XUI_PID" 2>/dev/null || true
        exit 1
    fi

    sleep 2
done
