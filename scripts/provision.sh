#!/bin/bash

set -e

echo "=========================================="
echo "  3x-ui inbound provisioning (Fixed)"
echo "=========================================="

DB_PATH="/etc/x-ui/x-ui.db"
CONFIG_FILE="/opt/3x-ui/config/inbounds.json"

# نصب ابزارهای مورد نیاز
if ! command -v sqlite3 &> /dev/null; then
    echo "Installing sqlite3..."
    apt-get update && apt-get install -y sqlite3 jq
fi

# چک کردن وجود فایل کانفیگ
if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: Config file not found: $CONFIG_FILE"
    exit 1
fi

# چک کردن وجود دیتابیس
if [ ! -f "$DB_PATH" ]; then
    echo "ERROR: Database not found: $DB_PATH"
    exit 1
fi

# خوندن اینباندها از فایل JSON
echo "Reading inbounds from config..."
INBOUNDS=$(jq -c '.inbounds[]' "$CONFIG_FILE" 2>/dev/null)

if [ -z "$INBOUNDS" ]; then
    echo "ERROR: No inbounds found in config"
    exit 1
fi

COUNT=$(echo "$INBOUNDS" | wc -l)
echo "Configured inbounds: $COUNT"
echo ""

# گرفتن پورت‌های موجود
EXISTING_PORTS=$(sqlite3 "$DB_PATH" "SELECT port FROM inbounds;" 2>/dev/null || echo "")

# اضافه کردن هر اینباند
echo "$INBOUNDS" | while read -r inbound; do
    PORT=$(echo "$inbound" | jq -r '.port')
    PROTOCOL=$(echo "$inbound" | jq -r '.protocol')
    
    # چک کردن تکراری نبودن پورت
    if echo "$EXISTING_PORTS" | grep -q "^$PORT$"; then
        echo "⚠️  Port $PORT already exists, skipping..."
        continue
    fi
    
    # گرفتن تنظیمات (با escape کردن کووت‌ها برای sqlite)
    SETTINGS=$(echo "$inbound" | jq -c '.settings' | sed "s/'/''/g")
    STREAM=$(echo "$inbound" | jq -c '.streamSettings' | sed "s/'/''/g")
    SNIFFING=$(echo "$inbound" | jq -c '.sniffing' | sed "s/'/''/g")
    ENABLE=$(echo "$inbound" | jq -r '.enable')
    
    # تبدیل enable به عدد
    if [ "$ENABLE" = "true" ]; then
        ENABLE_INT=1
    else
        ENABLE_INT=0
    fi
    
    echo "Adding inbound: $PROTOCOL on port $PORT"
    
    # درج در دیتابیس (بدون ستون ssl)
    sqlite3 "$DB_PATH" "INSERT INTO inbounds (
        port,
        protocol,
        settings,
        streamSettings,
        sniffing,
        enable,
        created_at,
        updated_at
    ) VALUES (
        $PORT,
        '$PROTOCOL',
        '$SETTINGS',
        '$STREAM',
        '$SNIFFING',
        $ENABLE_INT,
        datetime('now'),
        datetime('now')
    );" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        echo "✅ Added inbound on port $PORT"
    else
        echo "❌ Failed to add inbound on port $PORT"
    fi
done

echo ""
echo "=========================================="
echo "✅ Provisioning completed successfully!"
echo "=========================================="
