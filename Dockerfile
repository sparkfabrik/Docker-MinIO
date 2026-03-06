FROM alpine:3.23

RUN apk add --no-cache minio minio-client ca-certificates \
  bash curl date file rsync tar unzip xz shadow \
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

HEALTHCHECK --start-period=1m --interval=5m --timeout=5s \
  CMD curl -f http://localhost:${MINIO_PORT:-9000}/minio/health/live || exit 1
