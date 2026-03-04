FROM alpine:3.20

RUN apk add --no-cache minio minio-client \
  bash curl date file rsync tar unzip xz \
  && ln -fs /usr/bin/mcli /usr/bin/mc

# Copy scripts folder
COPY scripts /scripts
RUN chmod +x /scripts/entrypoint.sh

EXPOSE 9000 9001

ENTRYPOINT ["/scripts/entrypoint.sh"]
CMD ["minio"]

HEALTHCHECK --start-period=1m --interval=5m --timeout=5s \
  CMD curl -f http://localhost:${MINIO_PORT:-9000}/minio/health/live || exit 1
