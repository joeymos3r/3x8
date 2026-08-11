#!/bin/sh

set -e

echo "==========================================="
echo "  3x-ui inbound provisioning (DB Method)"
echo "==========================================="

# مسیر فایل‌ها
CONFIG_FILE="/opt/3x-ui/config/inbounds.json"
DB_FILE="/etc/x-ui/x-ui.db"

# بررسی وجود فایل کانفیگ
if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: Config file not found at $CONFIG_FILE"
    exit 1
fi

# بررسی وجود دیتابیس
if [ ! -f "$DB_FILE" ]; then
    echo "ERROR: Database not found at $DB_FILE"
    exit 1
fi

# خواندن اینباندها از فایل JSON
INBOUNDS=$(jq -c '.inbounds[]' "$CONFIG_FILE" 2>/dev/null)
if [ -z "$INBOUNDS" ]; then
    echo "No inbounds found in config file."
    exit 0
fi

COUNT=$(echo "$INBOUNDS" | wc -l)
echo "Configured inbounds: $COUNT"
echo ""
echo "Adding inbounds to database..."

# اضافه کردن هر اینباند به دیتابیس
echo "$INBOUNDS" | while read -r inbound; do
    # استخراج فیلدها
    PROTOCOL=$(echo "$inbound" | jq -r '.protocol')
    PORT=$(echo "$inbound" | jq -r '.port')
    REMARK=$(echo "$inbound" | jq -r '.remark // .protocol')
    SETTINGS=$(echo "$inbound" | jq -c '.settings // {}')
    STREAM_SETTINGS=$(echo "$inbound" | jq -c '.streamSettings // {}')
    SNI=$(echo "$inbound" | jq -r '.sni // ""')
    FALLBACKS=$(echo "$inbound" | jq -c '.fallbacks // []')

    echo "Adding inbound: $PROTOCOL on port $PORT"

    # درج در دیتابیس (جدول inbounds)
    sqlite3 "$DB_FILE" <<EOF
INSERT OR IGNORE INTO inbounds (
    user_id,
    up,
    down,
    total,
    remark,
    enable,
    expiry_time,
    listen,
    port,
    protocol,
    settings,
    stream_settings,
    tag,
    sniffing,
    ssl,
    fallbacks
) VALUES (
    1,
    0,
    0,
    0,
    '$REMARK',
    1,
    0,
    '',
    $PORT,
    '$PROTOCOL',
    '$SETTINGS',
    '$STREAM_SETTINGS',
    '',
    '',
    '',
    '$FALLBACKS'
);
EOF
done

echo ""
echo "✅ All inbounds added successfully."
