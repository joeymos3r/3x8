#!/bin/sh

# Run nginx as daemon in background
nginx -g "daemon on;" &

# Replace current process with x-ui (PID 1)
exec x-ui start
