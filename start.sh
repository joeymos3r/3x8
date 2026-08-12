#!/bin/bash

cd /usr/local/x-ui
./x-ui start

nginx -g 'daemon off;'
