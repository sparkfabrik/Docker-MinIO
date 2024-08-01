#!/usr/bin/env bash

set -eo pipefail
shopt -s nullglob

source /scripts/common.sh

# Configure Minio
export BUCKET_ROOT=${BUCKET_ROOT:-"/data"}
export INITFILES_FOLDER=${INITFILES_FOLDER:-"/docker-entrypoint-initfiles.d"}
export DO_NOT_PROCESS_INITFILES=${DO_NOT_PROCESS_INITFILES:-"0"}
export MINIO_BROWSER=${MINIO_BROWSER:-"off"}
export MINIO_CONSOLE_PORT=${MINIO_CONSOLE_PORT:-"9001"}
export MINIO_OPTS=${MINIO_OPTS:-""}

# Backward compatibility for MINIO_ACCESS_KEY and MINIO_SECRET_KEY.
# The variables are overwritten if MINIO_ROOT_USER and MINIO_ROOT_PASSWORD are not set.
if [ -z "${MINIO_ROOT_USER}" ] && [ -n "${MINIO_ACCESS_KEY}" ]; then
  export MINIO_ROOT_USER="${MINIO_ACCESS_KEY}"
fi

if [ -z "${MINIO_ROOT_PASSWORD}" ] && [ -n "${MINIO_SECRET_KEY}" ]; then
  export MINIO_ROOT_PASSWORD="${MINIO_SECRET_KEY}"
fi

# Backward compatibility for OSB_BUCKET.
# The variable is overwritten if BUCKET_NAME is not set.
if [ -z "${BUCKET_NAME}" ] && [ -n "${OSB_BUCKET}" ]; then
  export BUCKET_NAME="${OSB_BUCKET}"
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
