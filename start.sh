#!/bin/bash

# Start 3x-ui panel v3.6.0
cd /usr/local/x-ui
./x-ui start

# Replace port variable in nginx template and start nginx
envsubst '${PORT}' < /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf
nginx -g 'daemon off;'
