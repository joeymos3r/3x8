FROM ghcr.io/mhsanaei/3x-ui:latest

# Install required packages
RUN apt-get update && apt-get install -y \
    curl \
    jq \
    sqlite3 \
    openssl \
    && rm -rf /var/lib/apt/lists/*

# Copy config files
COPY config/inbounds.json /opt/3x-ui/config/inbounds.json
COPY provision.sh /opt/3x-ui/provision.sh
RUN chmod +x /opt/3x-ui/provision.sh

# Copy entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 3000

ENTRYPOINT ["/entrypoint.sh"]
