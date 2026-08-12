#!/bin/sh

x-ui start &

sleep 5

nginx -g 'daemon off;'
