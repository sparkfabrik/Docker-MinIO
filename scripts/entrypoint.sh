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

# Configure the temporary MinIO server used during initialization. It stays off
# MINIO_PORT so that port only answers once the final server is serving.
export MINIO_TEMP_HOST="${MINIO_TEMP_HOST:-"127.0.0.1"}"
export MINIO_TEMP_PORT="${MINIO_TEMP_PORT:-"19000"}"
export MINIO_TEMP_CONSOLE_PORT="${MINIO_TEMP_CONSOLE_PORT:-"19001"}"

# Configure the local MinIO client.
export MC_ALIAS="${MC_ALIAS:-"minio"}"
export MINIO_PROTO="${MINIO_PROTO:-"http"}"
export MINIO_HOST="${MINIO_HOST:-"localhost"}"
export MINIO_PORT="${MINIO_PORT:-"9000"}"

# The health check probes MINIO_PORT, so neither port of the temporary server
# may be MINIO_PORT: a collision reports the container healthy while the bucket
# is still being seeded. Refuse to start rather than run with a misleading probe.
if [ "${MINIO_TEMP_PORT}" = "${MINIO_PORT}" ] || [ "${MINIO_TEMP_CONSOLE_PORT}" = "${MINIO_PORT}" ]; then
  minio_log_error "MINIO_TEMP_PORT (${MINIO_TEMP_PORT}) and MINIO_TEMP_CONSOLE_PORT (${MINIO_TEMP_CONSOLE_PORT}) must differ from MINIO_PORT (${MINIO_PORT}): the health check probes MINIO_PORT and would report the container healthy before the initialization is finished."
fi

# Alternative way to set the MinIO credentials.
# if `OSB_ACCESS_KEY` variable is set, then `OSB_ACCESS_KEY` variable is used to set `MINIO_ROOT_USER`.
# if `OSB_SECRET_KEY` variable is set, then `OSB_SECRET_KEY` variable is used to set `MINIO_ROOT_PASSWORD`.
if [ -z "${MINIO_ROOT_USER}" ] && [ -n "${OSB_ACCESS_KEY}" ]; then
  export MINIO_ROOT_USER="${OSB_ACCESS_KEY}"
fi

if [ -z "${MINIO_ROOT_PASSWORD}" ] && [ -n "${OSB_SECRET_KEY}" ]; then
  export MINIO_ROOT_PASSWORD="${OSB_SECRET_KEY}"
fi

# Alternative way to set the name of the bucket.
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
  minio_wait_for_readiness "${MINIO_TEMP_HOST}" "${MINIO_TEMP_PORT}"

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
      minio_wait_for_readiness "${MINIO_TEMP_HOST}" "${MINIO_TEMP_PORT}"
      # Check if the init filesystem is consistent with the BUCKET_NAME variable.
      minio_check_initialized_filesystem
    fi

    # Start the 'Seed' initialization mode.
    minio_log_note "Start the 'Seed' initialization mode."
    # Restart of MinIO server.
    minio_restart_temp_server
    # Wait for MinIO server to be ready.
    minio_wait_for_readiness "${MINIO_TEMP_HOST}" "${MINIO_TEMP_PORT}"
    # Create bucket and upload files.
    minio_create_bucket
    # Eventually process init files.
    if [ "${DO_NOT_PROCESS_INITFILES}" -eq 0 ]; then
      minio_process_seed_archives_and_files
    fi
  fi
  # Stop temporary MinIO server.
  minio_stop_temp_server

  # No need to execute the following, minio runs ok with a (potentially) userless approach.
  #   usermod -u "${MY_UID:-0}" minio
  #   groupmod -g "${MY_GID:-0}" minio

  MY_UID="${MY_UID:-0}"
  MY_GID="${MY_GID:-0}"

  minio_log_debug "MY_UID=${MY_UID}"
  minio_log_debug "MY_GID=${MY_GID}"

  # Docker Desktop >= 4.80 with VirtioFS accepts chown but does not persist it:
  # stat keeps reporting the host owner. MinIO opens backend files with
  # O_NOATIME, which the kernel grants only when the euid matches the file
  # owner or the process holds CAP_FOWNER, so dropping privileges after an
  # ineffective chown makes backend init fail with EPERM. Probe whether chown
  # is effective on BUCKET_ROOT before relying on it.
  # Any probe failure counts as "chown not effective": the setpriv path works
  # regardless of ownership, while the gosu path only works when it sticks.
  CHOWN_IS_EFFECTIVE=1
  if [ "${MY_UID}" != "0" ]; then
    if PROBE_FILE="$(mktemp "${BUCKET_ROOT}/.chown-probe.XXXXXX")"; then
      chown "${MY_UID}:${MY_GID}" "${PROBE_FILE}" || true
      PROBE_OWNER="$(stat -c '%u:%g' "${PROBE_FILE}" || echo "")"
      rm -f "${PROBE_FILE}"
      if [ "${PROBE_OWNER}" != "${MY_UID}:${MY_GID}" ]; then
        CHOWN_IS_EFFECTIVE=0
      fi
    else
      CHOWN_IS_EFFECTIVE=0
    fi
  fi

  # Run minio.
  if [ "${CHOWN_IS_EFFECTIVE}" -eq 1 ]; then
    chown -R "${MY_UID}" "${BUCKET_ROOT}"
    chgrp -R "${MY_GID}" "${BUCKET_ROOT}"

    gosu "${MY_UID}:${MY_GID}" /usr/bin/minio server "${BUCKET_ROOT}" --address ":${MINIO_PORT}" --console-address ":${MINIO_CONSOLE_PORT}" ${MINIO_OPTS}
  else
    minio_log_warn "chown on '${BUCKET_ROOT}' is not persisted by the filesystem (Docker Desktop >= 4.80 with VirtioFS). Skipping the recursive chown and starting MinIO as ${MY_UID}:${MY_GID} with CAP_FOWNER."
    setpriv --reuid "${MY_UID}" --regid "${MY_GID}" --clear-groups \
      --inh-caps +fowner --ambient-caps +fowner \
      /usr/bin/minio server "${BUCKET_ROOT}" --address ":${MINIO_PORT}" --console-address ":${MINIO_CONSOLE_PORT}" ${MINIO_OPTS}
  fi
fi

if [ "${1}" = "mc" ]; then
  # Wait for minio server to be ready.
  minio_wait_for_readiness
fi
exec "$@"
