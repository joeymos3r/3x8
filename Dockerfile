FROM ghcr.io/mhsanaei/3x-ui:latest

RUN apk add --no-cache nginx wget

COPY nginx.conf /etc/nginx/http.d/default.conf
COPY start.sh /start.sh

RUN chmod +x /start.sh

EXPOSE 3000
EXPOSE 8080
EXPOSE 18080-18094

ENTRYPOINT ["/start.sh"]
