FROM ghcr.io/mhsanaei/3x-ui:latest

RUN apk add --no-cache nginx curl

COPY nginx.conf /etc/nginx/http.d/default.conf
COPY startup.sh /startup.sh
COPY config.env /config.env

RUN chmod +x /startup.sh

EXPOSE 3000
EXPOSE 8080
EXPOSE 18080
EXPOSE 18081
EXPOSE 18082
EXPOSE 18083
EXPOSE 18084
EXPOSE 18085
EXPOSE 18086
EXPOSE 18087
EXPOSE 18088
EXPOSE 18089
EXPOSE 18090
EXPOSE 18091
EXPOSE 18092
EXPOSE 18093
EXPOSE 18094

ENTRYPOINT ["/startup.sh"]
