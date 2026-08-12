FROM alpine:latest

RUN apk add --no-cache curl bash tzdata nginx supervisor sqlite unzip

# Install xray-core
RUN curl -L https://github.com/XTLS/Xray-core/releases/download/v26.7.28/Xray-linux-64.zip -o /tmp/xray.zip && \
    unzip /tmp/xray.zip -d /tmp/xray && \
    mv /tmp/xray/xray /usr/local/bin/xray && \
    chmod +x /usr/local/bin/xray && \
    rm -rf /tmp/xray.zip /tmp/xray

# Install 3x-ui
RUN curl -L https://github.com/MHSanaei/3x-ui/releases/download/v3.6.0/x-ui-linux-amd64.tar.gz -o /tmp/x-ui.tar.gz && \
    tar -xzf /tmp/x-ui.tar.gz -C /usr/local/ && \
    rm /tmp/x-ui.tar.gz && \
    chmod +x /usr/local/x-ui/x-ui && \
    ln -s /usr/local/x-ui/x-ui /usr/bin/x-ui

# Create bin directory and copy xray binary (instead of symlink)
RUN mkdir -p /usr/local/x-ui/bin && \
    cp /usr/local/bin/xray /usr/local/x-ui/bin/xray-linux-amd64

COPY nginx.conf /etc/nginx/http.d/default.conf
COPY supervisord.conf /etc/supervisord.conf

EXPOSE 3000

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisord.conf"]
