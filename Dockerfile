FROM alpine:3.20

RUN apk add --no-cache minio minio-client bash date && \
  ln -fs /usr/bin/mcli /usr/bin/mc

# Set priviledges on default folders for user minio
RUN mkdir -p /data \
  && mkdir -p /docker-entrypoint-initfiles.d \
  && chown -R minio:minio /data \
  && chown -R minio:minio /docker-entrypoint-initfiles.d

# Copy scripts folder
COPY scripts /scripts
RUN chmod +x /scripts/entrypoint.sh

EXPOSE 9000 9001

ENTRYPOINT ["/scripts/entrypoint.sh"]

USER minio
