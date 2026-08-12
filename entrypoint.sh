#!/bin/sh

# Start nginx as daemon (background)
nginx -g "daemon on;"

# Replace current process with x-ui as PID 1
exec x-ui run
