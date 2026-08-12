FROM alpine:latest

RUN apk add --no-cache curl bash tzdata nginx sqlite

# Install 3x-ui
RUN curl -L https://github.com/MHSanaei/3x-ui/releases/download/v3.6.0/x-ui-linux-amd64.tar.gz -o /tmp/x-ui.tar.gz && \
    tar -xzf /tmp/x-ui.tar.gz -C /usr/local/ && \
    rm /tmp/x-ui.tar.gz && \
    chmod +x /usr/local/x-ui/x-ui && \
    ln -s /usr/local/x-ui/x-ui /usr/bin/x-ui

COPY nginx.conf /etc/nginx/http.d/default.conf

EXPOSE 3000

CMD sh -c "x-ui run & nginx -g 'daemon off;'"
