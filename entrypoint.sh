#!/bin/sh
set -e

if [ -n "$PORT" ]; then
  sed -i "s/listen 3000;/listen ${PORT};/g" /etc/nginx/http.d/default.conf
fi

exec /usr/bin/supervisord -c /etc/supervisord.conf
