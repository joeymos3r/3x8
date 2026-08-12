#!/bin/sh

# Start nginx in background
nginx -g "daemon on;" &

# Start x-ui (foreground - it will run as PID 1)
x-ui start
