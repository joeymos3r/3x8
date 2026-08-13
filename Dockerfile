FROM ghcr.io/mhsanaei/3x-ui:latest

RUN apk add --no-cache nginx

COPY nginx.conf /etc/nginx/http.d/default.conf

RUN nginx -t

EXPOSE 3000

CMD ["/bin/sh", "-c", "/app/x-ui & XUI_PID=$!; echo \"Waiting for 3x-ui...\"; for i in $(seq 1 60); do if wget -q -O /dev/null http://127.0.0.1:2053/; then echo \"3x-ui is ready\"; break; fi; if ! kill -0 $XUI_PID 2>/dev/null; then echo \"3x-ui stopped\"; exit 1; fi; sleep 1; done; if ! kill -0 $XUI_PID 2>/dev/null; then exit 1; fi; echo \"Starting nginx...\"; nginx -g 'daemon off;' & NGINX_PID=$!; wait -n $XUI_PID $NGINX_PID; exit 1"]
