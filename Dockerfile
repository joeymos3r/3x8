FROM ghcr.io/mhsanaei/3x-ui:latest

RUN echo "=== BUILD_START ===" 
RUN echo "=== BUILD_END ==="

EXPOSE 3000

CMD ["echo", "=== CONTAINER_STARTED ==="]
