#!/bin/sh

nginx -g "daemon on;"

exec /usr/local/x-ui/x-ui
