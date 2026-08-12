#!/bin/sh

envsubst '${PORT}' < /etc/nginx/http.d/default.conf.template > /etc/nginx/http.d/default.conf

x-ui start

nginx -g 'daemon off;'
