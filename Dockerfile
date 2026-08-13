FROM ghcr.io/mhsanaei/3x-ui:latest

RUN apk add --no-cache nginx curl

COPY nginx.conf /etc/nginx/http.d/default.conf

RUN nginx -t

EXPOSE 3000

ENTRYPOINT []

CMD ["/bin/sh", "-c", "\
echo 'Starting 3x-ui...' && \
x-ui start & \
XUI_PID=$!; \
echo 'Waiting for 3x-ui on port 2053...'; \
READY=0; \
for i in $(seq 1 60); do \
    if curl -s --max-time 2 http://127.0.0.1:2053/managepanel/ >/dev/null 2>&1; then \
        echo '3x-ui is ready on port 2053'; \
        READY=1; \
        break; \
    fi; \
    if ! kill -0 $XUI_PID 2>/dev/null; then \
        echo 'ERROR: x-ui process stopped'; \
        exit 1; \
    fi; \
    echo \"Waiting for 3x-ui... $i/60\"; \
    sleep 1; \
done; \
if [ \"$READY\" != \"1\" ]; then \
    echo 'ERROR: 3x-ui did not start on port 2053'; \
    exit 1; \
fi; \
echo 'Starting nginx...'; \
exec nginx -g 'daemon off;'\
"]
