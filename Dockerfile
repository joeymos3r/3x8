FROM alpine:latest

RUN apk add --no-cache curl bash tzdata nginx supervisor sqlite unzip

# Install xray-core
RUN curl -L https://github.com/XTLS/Xray-core/releases/download/v26.7.28/Xray-linux-64.zip -o /tmp/xray.zip && \
    unzip /tmp/xray.zip -d /usr/local/bin/ && \
    rm /tmp/xray.zip && \
    chmod +x /usr/local/bin/xray

# Install 3x-ui
RUN curl -L https://github.com/MHSanaei/3x-ui/releases/download/v3.6.0/x-ui-linux-amd64.tar.gz -o /tmp/x-ui.tar.gz && \
    tar -xzf /tmp/x-ui.tar.gz -C /usr/local/ && \
    rm /tmp/x-ui.tar.gz && \
    chmod +x /usr/local/x-ui/x-ui && \
    ln -s /usr/local/x-ui/x-ui /usr/bin/x-ui

# Create symlink for xray binary where 3x-ui expects it
RUN mkdir -p /usr/local/x-ui/bin && \
    ln -s /usr/local/bin/xray /usr/local/x-ui/bin/xray-linux-amd64

COPY nginx.conf /etc/nginx/http.d/default.conf
COPY supervisord.conf /etc/supervisord.conf

EXPOSE 3000

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisord.conf"]
