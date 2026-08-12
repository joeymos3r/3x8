#!/bin/sh

envsubst '${PORT}' < /etc/nginx/conf.d/default.conf.template > /etc/nginx/conf.d/default.conf

/usr/local/bin/x-ui start

nginx -g 'daemon off;'
