#!/bin/sh

x-ui start &

sleep 3

nginx -g 'daemon off;'
