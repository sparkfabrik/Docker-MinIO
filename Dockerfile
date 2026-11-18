# Silo is the maintained community fork of MinIO (https://github.com/pgsty/silo).
# Its image is built on UBI micro, which lacks the tools the entrypoint needs,
# so only its statically linked silo and mcli binaries are copied into Alpine.
FROM docker.io/pgsty/silo:RELEASE.2026-11-12T00-00-00Z@sha256:c20d112390b9a9ce8c11b8af95ad35bcaa62f4759663c09c936cd8d2b511f329 AS silo

FROM alpine:3.24

COPY --from=silo /usr/bin/silo /usr/bin/mcli /usr/bin/

# The minio symlink keeps the old binary path working for callers that still use it.
# The minio user and group keep the uid, gid and home that the Alpine minio package created.
RUN apk add --no-cache ca-certificates \
  bash curl date file rsync tar unzip xz shadow util-linux-misc \
  && ln -fs /usr/bin/mcli /usr/bin/mc \
  && ln -fs /usr/bin/silo /usr/bin/minio \
  && addgroup -S -g 101 minio \
  && adduser -S -D -H -u 100 -G minio -h /var/lib/minio -s /sbin/nologin -g minio minio \
  && install -d -o minio -g minio /var/lib/minio

# https://github.com/tianon/gosu/blob/3d395d499a92ffa47d70c79d24a738b85075f477/INSTALL.md
ENV GOSU_VERSION=1.19
RUN set -eux; \
  \
  apk add --no-cache --virtual .gosu-deps \
    dpkg  gnupg ; \
  \
  dpkgArch="$(dpkg --print-architecture | awk -F- '{ print $NF }')"; \
  wget -O /usr/local/bin/gosu "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$dpkgArch"; \
  wget -O /usr/local/bin/gosu.asc "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$dpkgArch.asc"; \
  \
# verify the signature
  export GNUPGHOME="$(mktemp -d)"; \
  gpg --batch --keyserver hkps://keys.openpgp.org --recv-keys B42F6819007F00F88E364FD4036A9C25BF357DD4; \
  gpg --batch --verify /usr/local/bin/gosu.asc /usr/local/bin/gosu; \
  gpgconf --kill all; \
  rm -rf "$GNUPGHOME" /usr/local/bin/gosu.asc; \
  \
# clean up fetch dependencies
  apk del --no-network .gosu-deps; \
  \
  chmod +x /usr/local/bin/gosu; \
# verify that the binary works
  gosu --version; \
  gosu nobody true

# Copy scripts folder
COPY scripts /scripts
RUN chmod +x /scripts/entrypoint.sh

EXPOSE 9000 9001

ENTRYPOINT ["/scripts/entrypoint.sh"]
CMD ["silo"]

# The initialization phase keeps MINIO_PORT closed, so every probe fails until
# the final server is serving. The start period is the maximum initialization
# time we tolerate (seeding a large bucket, then chown -R over its files): it
# costs nothing on a fast start, because start-interval probes every 5s inside
# it and the first success ends it, so a clean start reports healthy in seconds.
# Past the start period the first failed probe lands at the boundary and the
# 7th, 6 intervals later, declares the container unhealthy: 10m + 6 x 30s = 13m.
HEALTHCHECK --start-period=10m --start-interval=5s --interval=30s --timeout=5s --retries=7 \
  CMD curl -f http://localhost:${MINIO_PORT:-9000}/minio/health/live || exit 1
