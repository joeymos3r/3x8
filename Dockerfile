FROM ghcr.io/mhsanaei/3x-ui:latest

ENV XUI_PORT=3000
ENV XUI_DB_FOLDER=/etc/x-ui

EXPOSE 3000

CMD ["/usr/local/x-ui/x-ui", "start"]
