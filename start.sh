#!/bin/sh

set -e

echo "========================================"
echo " Starting 3x-ui + Nginx on Railway"
echo "========================================"

# Disable Fail2Ban on Railway.
# Railway containers do not provide the VPS-style SSH environment
# expected by the sshd-ddos jail.
export XUI_ENABLE_FAIL2BAN=false

# Railway provides the public HTTP port through $PORT.
PORT="${PORT:-3000}"

echo "Railway PORT: ${PORT}"

# Make nginx listen on Railway's assigned HTTP port.
sed -i "s/listen 3000;/listen ${PORT};/" /etc/nginx/http.d/default.conf

echo "Testing nginx configuration..."
nginx -t

echo "Starting 3x-ui..."

# Start 3x-ui in background.
# The official image uses /app/x-ui as the actual panel process.
# We keep its PID so the container can terminate correctly.
 /app/x-ui &
XUI_PID=$!

echo "3x-ui PID: ${XUI_PID}"

echo "Waiting for 3x-ui on port 2053..."

READY=0

for i in $(seq 1 60); do
    if wget -q -O /dev/null http://127.0.0.1:2053/ 2>/dev/null; then
        READY=1
        echo "3x-ui is ready."
        break
    fi

    if ! kill -0 "$XUI_PID" 2>/dev/null; then
        echo "ERROR: 3x-ui process stopped."
        wait "$XUI_PID" || true
        exit 1
    fi

    echo "Waiting for 3x-ui... ${i}/60"
    sleep 1
done

if [ "$READY" != "1" ]; then
    echo "ERROR: 3x-ui did not become ready within 60 seconds."
    exit 1
fi

echo "Starting nginx..."

nginx -g "daemon off;" &
NGINX_PID=$!

echo "nginx PID: ${NGINX_PID}"

# Keep container alive while both processes are running.
while true; do

    if ! kill -0 "$XUI_PID" 2>/dev/null; then
        echo "ERROR: 3x-ui stopped."
        kill "$NGINX_PID" 2>/dev/null || true
        wait "$XUI_PID" 2>/dev/null || true
        exit 1
    fi

    if ! kill -0 "$NGINX_PID" 2>/dev/null; then
        echo "ERROR: nginx stopped."
        kill "$XUI_PID" 2>/dev/null || true
        wait "$NGINX_PID" 2>/dev/null || true
        exit 1
    fi

    sleep 2
done
