#!/usr/bin/env bash

set -eo pipefail
shopt -s nullglob

source /scripts/common.sh

# Configure Minio
export BUCKET_ROOT=${BUCKET_ROOT:-"/data"}
export INITFILES_FOLDER=${INITFILES_FOLDER:-"/docker-entrypoint-initfiles.d"}
export DO_NOT_PROCESS_INITFILES=${DO_NOT_PROCESS_INITFILES:-"0"}
export MINIO_VERSION_ENABLED=${MINIO_VERSION_ENABLED:-"0"}
export MINIO_BROWSER=${MINIO_BROWSER:-"off"}
export MINIO_CONSOLE_PORT=${MINIO_CONSOLE_PORT:-"9001"}
export MINIO_OPTS=${MINIO_OPTS:-""}
# Host to configure the local MinIO client.
export MC_ALIAS="${MC_ALIAS:-"minio"}"
export MINIO_PROTO="${MINIO_PROTO:-"http"}"
export MINIO_HOST="${MINIO_HOST:-"localhost"}"
export MINIO_PORT="${MINIO_PORT:-"9000"}"

# Backward compatibility for OSB_BUCKET.
# If `BUCKET_NAME` variable is not set, then `OSB_BUCKET` variable is used to set `BUCKET_NAME`.
if [ -z "${BUCKET_NAME}" ] && [ -n "${OSB_BUCKET}" ]; then
  export BUCKET_NAME="${OSB_BUCKET}"
fi

# Backward compatibility for MINIO_ACCESS_KEY and MINIO_SECRET_KEY.
# If `MINIO_ROOT_USER` variable is not set, then `MINIO_ACCESS_KEY` variable is used to set `MINIO_ROOT_USER`.
# If `MINIO_ROOT_PASSWORD` variable is not set, then `MINIO_SECRET_KEY` variable is used to set `MINIO_ROOT_PASSWORD`.
if [ -z "${MINIO_ROOT_USER}" ] && [ -n "${MINIO_ACCESS_KEY}" ]; then
  export MINIO_ROOT_USER="${MINIO_ACCESS_KEY}"
fi

if [ -z "${MINIO_ROOT_PASSWORD}" ] && [ -n "${MINIO_SECRET_KEY}" ]; then
  export MINIO_ROOT_PASSWORD="${MINIO_SECRET_KEY}"
fi

# Check required environment variables
if [ -z "${BUCKET_NAME}" ]; then
  minio_error "BUCKET_NAME environment variable is required."
fi

if [ -z "${MINIO_ROOT_USER}" ]; then
  minio_error "MINIO_ROOT_USER environment variable is required."
fi

if [ -z "${MINIO_ROOT_PASSWORD}" ]; then
  minio_error "MINIO_ROOT_PASSWORD environment variable is required."
fi

if [ "${1}" = "minio" ]; then
  # Temporary start of minio server.
  minio_start_temp_server
  # Wait for minio server to be ready.
  minio_wait_for_readiness
  # Create bucket and upload files.
  docker_create_bucket
  # Eventually process init files.
  if [ "${DO_NOT_PROCESS_INITFILES}" -eq 0 ]; then
    docker_process_init_files
  fi
  # Stop temporary minio server.
  minio_stop_temp_server

  # Run minio.
  exec /usr/bin/minio server "${BUCKET_ROOT}" --console-address ":${MINIO_CONSOLE_PORT}" ${MINIO_OPTS}
fi

if [ "${1}" = "mc" ]; then
  # Wait for minio server to be ready.
  minio_wait_for_readiness
fi
exec "$@"
