#!/usr/bin/env bash

set -eo pipefail
shopt -s nullglob

source /scripts/common.sh

# Configure Minio
export BUCKET_ROOT=${BUCKET_ROOT:-"/files"}
export INITFILES_FOLDER=${INITFILES_FOLDER:-"/docker-entrypoint-initfiles.d"}
export MINIO_BROWSER=${MINIO_BROWSER:-"off"}
export MINIO_CONSOLE_PORT=${MINIO_CONSOLE_PORT:-"9001"}

# Backward compatibility for MINIO_ACCESS_KEY and MINIO_SECRET_KEY.
# The variables are overwritten if MINIO_ROOT_USER and MINIO_ROOT_PASSWORD are not set.
if [ -z "${MINIO_ROOT_USER}" ] && [ -n "${MINIO_ACCESS_KEY}" ]; then
  export MINIO_ROOT_USER="${MINIO_ACCESS_KEY}"
fi

if [ -z "${MINIO_ROOT_PASSWORD}" ] && [ -n "${MINIO_SECRET_KEY}" ]; then
  export MINIO_ROOT_PASSWORD="${MINIO_SECRET_KEY}"
fi

# Check required environment variables
if [ -z "${OSB_BUCKET}" ]; then
  minio_error "OSB_BUCKET environment variable is required."
fi

if [ -z "${MINIO_ROOT_USER}" ]; then
  minio_error "MINIO_ROOT_USER environment variable is required."
fi

if [ -z "${MINIO_ROOT_PASSWORD}" ]; then
  minio_error "MINIO_ROOT_PASSWORD environment variable is required."
fi

# Temporary start of minio server
docker_create_bucket

# Run minio.
exec /usr/bin/minio server "${BUCKET_ROOT}" --console-address ":${MINIO_CONSOLE_PORT}"
