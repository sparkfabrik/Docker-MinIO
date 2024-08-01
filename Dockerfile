FROM alpine:3.20

RUN apk add --no-cache minio minio-client bash date && \
  ln -fs /usr/bin/mcli /usr/bin/mc

# Copy scripts folder
COPY scripts /scripts
RUN chmod +x /scripts/entrypoint.sh

EXPOSE 9000 9001

ENTRYPOINT ["/scripts/entrypoint.sh"]
