FROM ghcr.io/mhsanaei/3x-ui:latest

RUN apk add --no-cache nginx

COPY nginx.conf /etc/nginx/http.d/default.conf

EXPOSE 3000

CMD sh -c "nohup x-ui run > /dev/null 2>&1 & sleep 3 && nginx -g 'daemon off;'"
