# Helper functions for the entrypoint script.
minio_start_temp_server() {
  if [ -n "${MINIO_TEMP_PID}" ]; then
    minio_log_debug "Temporary Minio server is already running (PID: ${MINIO_TEMP_PID})."
    return
  fi

  # Start minio server. We need to start it to create the bucket and eventually upload files.
  exec /usr/bin/minio server "${BUCKET_ROOT}" &>/dev/null &
  MINIO_TEMP_PID=$!
  sleep 1
}

minio_stop_temp_server() {
  if [ -z "${MINIO_TEMP_PID}" ]; then
    minio_log_warn "MINIO_TEMP_PID is not set."
    return
  fi

  # Stop minio server.
  minio_log_debug "Stopping temporary Minio server (PID: ${MINIO_TEMP_PID})."
  kill -9 "${MINIO_TEMP_PID}"
  MINIO_TEMP_PID=""
  minio_log_debug "Temporary Minio server has been stopped."
}

minio_restart_temp_server() {
  minio_log_debug "Restarting temporary Minio server."
  mc admin service restart "${MC_ALIAS}" &>/dev/null
  minio_log_debug "Temporary Minio server has been restarted."
}

minio_wait_for_readiness() {
  local CNT TRESHOLD
  CNT=0
  TRESHOLD=10
  while [ "${CNT}" -lt 10 ]; do
    if mc config host add "${MC_ALIAS}" "${MINIO_PROTO}://${MINIO_HOST}:${MINIO_PORT}" "${MINIO_ROOT_USER}" "${MINIO_ROOT_PASSWORD}" &>/dev/null && mc admin info "${MC_ALIAS}" &>/dev/null; then
      minio_log_debug "Minio server is ready."
      return 0
    fi
    minio_log_debug "Minio server is not ready. Waiting..."
    CNT=$((CNT + 1))
    sleep 1
  done
  minio_log_error "Minio server is not ready in ${TRESHOLD} seconds."
}

minio_initialization_is_needed() {
  if [ "$(mc ls "${MC_ALIAS}/${BUCKET_NAME}/" 2>/dev/null | wc -l)" -ne 0 ]; then
    return 1
  fi
  return 0
}

minio_process_init_filesystem() {
  # Copy the contents of the initfs folder to the bucket root.
  minio_log_note "Copying the contents of '${INITFILESYSTEM_DIR}' to '${BUCKET_ROOT}'."
  minio_log_note "Please wait, this may take a while..."
  rsync -a --delete "${INITFILESYSTEM_DIR}/" "${BUCKET_ROOT}/"
  minio_log_note "The contents of '${INITFILESYSTEM_DIR}' have been copied to '${BUCKET_ROOT}'."
}

minio_check_initialized_filesystem() {
  # Check if the configured BUCKET_NAME is consistent with the imported filesystem using filesystem folder name.
  if [ ! -d "${BUCKET_ROOT}/${BUCKET_NAME}" ]; then
    minio_log_error "The folder '${BUCKET_NAME}' does not exist in the filesystem. The init filesystem is not consistent with the BUCKET_NAME variable. Please configure the BUCKET_NAME variable to match the bucket present in the init filesystem."
  fi

  # Check if the configured BUCKET_NAME is consistent with the imported filesystem using MinIO client.
  if ! mc ls "${MC_ALIAS}/${BUCKET_NAME}" &>/dev/null; then
    minio_log_error "The bucket '${BUCKET_NAME}' does not exist in the MinIO server. The init filesystem is not consistent with the BUCKET_NAME variable. Please configure the BUCKET_NAME variable to match the bucket present in the init filesystem."
  fi

  minio_log_note "The init filesystem is consistent with the BUCKET_NAME variable."
}

minio_create_bucket() {
  # Check if bucket exists, otherwise create it.
  if mc ls "${MC_ALIAS}/${BUCKET_NAME}" &>/dev/null; then
    minio_log_note "Bucket '${BUCKET_NAME}' already exists."
  else
    mc mb -p "${MC_ALIAS}/${BUCKET_NAME}" | minio_log_note
    minio_log_note "Bucket '${BUCKET_NAME}' created."
  fi

  # Set the bucket policy.
  mc anonymous set download "${MC_ALIAS}/${BUCKET_NAME}" | minio_log_note

  # Enable versioning for the bucket if the MINIO_VERSION_ENABLED variable is set to 1.
  if [ "${MINIO_VERSION_ENABLED}" = "1" ]; then
    mc version enable "${MC_ALIAS}/${BUCKET_NAME}" | minio_log_note
  fi
}

minio_process_seed_archives_and_files() {
  local SOMETHING_UPLOADED TMP_ARCHIVE_EXTRACTION_DIR LOGERR_FILE
  SOMETHING_UPLOADED=0
  TMP_ARCHIVE_EXTRACTION_DIR="/tmp/archives"
  LOGERR_FILE="/tmp/error.log"

  # Processing archives.
  if [ "$(ls -A "${INITARCHIVES_DIR}" 2>/dev/null | wc -l)" -gt 0 ]; then
    minio_log_note "Extracting seed archives and uploading files to bucket '${BUCKET_NAME}'."

    # Extract all archives in the temporary folder.
    local archive
    for archive in $(ls -A "${INITARCHIVES_DIR}"); do
      # Clean up the temporary folder if it exists.
      rm -rf "${TMP_ARCHIVE_EXTRACTION_DIR}"
      # Create a temporary folder for archive extraction.
      mkdir -p "${TMP_ARCHIVE_EXTRACTION_DIR}"

      # Check if the file is a zip archive.
      if [ "$(file -b --mime-type "${INITARCHIVES_DIR}/${archive}")" = "application/zip" ]; then
        minio_log_debug "Extracting archive '${INITARCHIVES_DIR}/${archive}' using unzip."
        unzip -q "${INITARCHIVES_DIR}/${archive}" -d "${TMP_ARCHIVE_EXTRACTION_DIR}" 1>/dev/null
      elif is_tar_valid_mime_type "${INITARCHIVES_DIR}/${archive}"; then
        # Try to extract the archive using tar.
        minio_log_debug "Extracting archive '${INITARCHIVES_DIR}/${archive}' using tar."
        tar xf "${INITARCHIVES_DIR}/${archive}" -C "${TMP_ARCHIVE_EXTRACTION_DIR}" 1>/dev/null
      else
        minio_log_warn "Unsupported archive format '${INITARCHIVES_DIR}/${archive}'. Skipping extraction."
        continue
      fi

      # We want to upload the contents of each extracted archive to the bucket.
      # This is useful when the bucket is configured to use versioning to keep track of the changes.
      # Check if the temporary folder is empty.
      if [ "$(ls -A "${TMP_ARCHIVE_EXTRACTION_DIR}" 2>/dev/null | wc -l)" -eq 0 ]; then
        minio_log_debug "No files found in the extracted archive '${INITARCHIVES_DIR}/${archive}'. Skipping upload."
        continue
      fi

      # Copy the contents of the temporary folder to the bucket.
      minio_log_note "Uploading all extracted files to bucket '${BUCKET_NAME}'."
      # Note the trailing slash in the source folder. This is required to copy the CONTENTS of the folder and not the folder itself.
      mc cp --recursive "${TMP_ARCHIVE_EXTRACTION_DIR}/" "${MC_ALIAS}/${BUCKET_NAME}" 1>/dev/null 2>"${LOGERR_FILE}"
      if [ -s "${LOGERR_FILE}" ]; then
        minio_log_error "Error uploading files to bucket '${BUCKET_NAME}'."
        minio_log_error "$(cat "${LOGERR_FILE}")"
      fi

      SOMETHING_UPLOADED=1
    done

    # Final clean up the temporary folder if it exists.
    rm -rf "${TMP_ARCHIVE_EXTRACTION_DIR}"

    if [ "${SOMETHING_UPLOADED}" = "0" ]; then
      minio_log_warn "All archives in '${INITARCHIVES_DIR}' have been processed, but no files were found in the extracted archives destination folder."
    fi
  fi

  # Processing files.
  if [ "$(ls -A "${INITFILES_DIR}" 2>/dev/null | wc -l)" -gt 0 ]; then
    minio_log_note "Uploading seed files to bucket '${BUCKET_NAME}'."

    # Note the trailing slash in the source folder. This is required to copy the CONTENTS of the folder and not the folder itself.
    mc cp --recursive "${INITFILES_DIR}/" "${MC_ALIAS}/${BUCKET_NAME}" 1>/dev/null 2>"${LOGERR_FILE}"
    if [ -s "${LOGERR_FILE}" ]; then
      minio_log_error "Error uploading files to bucket '${BUCKET_NAME}'."
      minio_log_error "$(cat "${LOGERR_FILE}")"
    fi
    SOMETHING_UPLOADED=1
  fi

  if [ "${SOMETHING_UPLOADED}" = "0" ]; then
    minio_log_note "No files found after processing archives in '${INITARCHIVES_DIR}' and files in '${INITFILES_DIR}'. The bucket '${BUCKET_NAME}' will remain empty."
  fi
}

# Utility functions.
is_tar_valid_mime_type() {
  if [ "$#" -ne 1 ]; then
    minio_log_error "is_tar_valid_mime_type() requires one argument."
  fi

  local valid_mime_types
  valid_mime_types="application/x-tar,application/gzip,application/x-bzip2,application/x-xz"
  local mime_type
  mime_type="$(file -b --mime-type "${1}")"
  for valid_mime_type in $(echo ${valid_mime_types} | tr "," " "); do
    if [ "${mime_type}" = "${valid_mime_type}" ]; then
      return 0
    fi
  done
  return 1
}

# Logging functions.
minio_log() {
  local type="$1"
  shift
  # Accept argument string or stdin.
  local text="$*"
  if [ "$#" -eq 0 ]; then text="$(cat)"; fi
  local dt
  dt="$(date -I'seconds')"
  printf '%s [%s] [Entrypoint]: %s\n' "$dt" "$type" "$text"
}

minio_log_debug() {
  if [ "${DEBUG}" = "1" ]; then
    minio_log Debug "$@"
  fi
}

minio_log_note() {
  minio_log Note "$@"
}

minio_log_warn() {
  minio_log Warn "$@" >&2
}

minio_log_error() {
  minio_log ERROR "$@" >&2
  exit 1
}
