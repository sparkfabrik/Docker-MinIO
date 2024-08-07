#!/usr/bin/env bash

set -eo pipefail
shopt -s nullglob

source /scripts/common.sh

# Debug mode.
export DEBUG=${DEBUG:-"0"}

# Configure Minio.
export BUCKET_ROOT=${BUCKET_ROOT:-"/data"}
export INITFILESYSTEM_DIR=${INITFILESYSTEM_DIR:-"/docker-entrypoint-initfs.d"}
export INITARCHIVES_DIR=${INITARCHIVES_DIR:-"/docker-entrypoint-initarchives.d"}
export INITFILES_DIR=${INITFILES_DIR:-"/docker-entrypoint-initfiles.d"}
export DO_NOT_PROCESS_INITFILES=${DO_NOT_PROCESS_INITFILES:-"0"}
export MINIO_VERSION_ENABLED=${MINIO_VERSION_ENABLED:-"0"}
export MINIO_OPTS=${MINIO_OPTS:-""}

# Configure Minio console.
export MINIO_BROWSER=${MINIO_BROWSER:-"off"}
export MINIO_CONSOLE_PORT=${MINIO_CONSOLE_PORT:-"9001"}

# Configure the local MinIO client.
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
  minio_log_error "BUCKET_NAME environment variable is required."
fi

if [ -z "${MINIO_ROOT_USER}" ]; then
  minio_log_error "MINIO_ROOT_USER environment variable is required."
fi

if [ -z "${MINIO_ROOT_PASSWORD}" ]; then
  minio_log_error "MINIO_ROOT_PASSWORD environment variable is required."
fi

if [ "${1}" = "minio" ]; then
  # Start temporary MinIO server.
  minio_start_temp_server
  # Wait for MinIO server to be ready.
  minio_wait_for_readiness

  if ! minio_initialization_is_needed; then
    minio_log_note "Bucket '${BUCKET_NAME}' exists and it is not empty. Skipping initialization."
    minio_log_debug "The 'FileSystem' and 'Seed' initialization modes will be skipped."
    # Check if the already present filesystem is consistent with the BUCKET_NAME variable.
    minio_check_initialized_filesystem
  else
    minio_log_note "Bucket '${BUCKET_NAME}' does not exist or it is empty. Starting initialization process."

    # Check if init filesystem folder exists and it is not empty.
    if [ "$(ls "${INITFILESYSTEM_DIR}" 2>/dev/null | wc -l)" -gt 0 ]; then
      # The folder is not empty. Start the 'FileSystem' initialization mode.
      minio_log_note "Start the 'FileSystem' initialization mode."

      # Process init filesystem.
      minio_process_init_filesystem
      # Restart of MinIO server.
      minio_restart_temp_server
      # Wait for MinIO server to be ready.
      minio_wait_for_readiness
      # Check if the init filesystem is consistent with the BUCKET_NAME variable.
      minio_check_initialized_filesystem
    fi

    # Start the 'Seed' initialization mode.
    minio_log_note "Start the 'Seed' initialization mode."
    # Restart of MinIO server.
    minio_restart_temp_server
    # Wait for MinIO server to be ready.
    minio_wait_for_readiness
    # Create bucket and upload files.
    minio_create_bucket
    # Eventually process init files.
    if [ "${DO_NOT_PROCESS_INITFILES}" -eq 0 ]; then
      minio_process_seed_archives_and_files
    fi
  fi
  # Stop temporary MinIO server.
  minio_stop_temp_server

  # Run minio.
  exec /usr/bin/minio server "${BUCKET_ROOT}" --console-address ":${MINIO_CONSOLE_PORT}" ${MINIO_OPTS}
fi

if [ "${1}" = "mc" ]; then
  # Wait for minio server to be ready.
  minio_wait_for_readiness
fi
exec "$@"
