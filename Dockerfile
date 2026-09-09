FROM alpine:3.20

RUN apk add --no-cache minio minio-client ca-certificates \
  bash curl date file rsync tar unzip xz shadow util-linux-misc \
  && ln -fs /usr/bin/mcli /usr/bin/mc

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
CMD ["minio"]

# The initialization phase keeps MINIO_PORT closed, so every probe fails until
# the final server is serving. The start period is the maximum initialization
# time we tolerate (seeding a large bucket, then chown -R over its files): it
# costs nothing on a fast start, because start-interval probes every 5s inside
# it and the first success ends it, so a clean start reports healthy in seconds.
# Past the start period the first failed probe lands at the boundary and the
# 7th, 6 intervals later, declares the container unhealthy: 10m + 6 x 30s = 13m.
HEALTHCHECK --start-period=10m --start-interval=5s --interval=30s --timeout=5s --retries=7 \
  CMD curl -f http://localhost:${MINIO_PORT:-9000}/minio/health/live || exit 1
