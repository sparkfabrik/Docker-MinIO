# Helper functions for the entrypoint script.
minio_start_temp_server() {
  # Start minio server. We need to start it to create the bucket and eventually upload files.
  /usr/bin/minio server "${BUCKET_ROOT}" &>/dev/null &
  MINIO_TEMP_PID=$!
  sleep 1
}

minio_stop_temp_server() {
  if [ -z "${MINIO_TEMP_PID}" ]; then
    minio_error "MINIO_TEMP_PID is not set."
  fi
  # Stop minio server.
  kill -9 "${MINIO_TEMP_PID}"
}

minio_wait_for_readiness() {
  local CNT TRESHOLD
  CNT=0
  TRESHOLD=10
  while [ "${CNT}" -lt 10 ]; do
    if [ -n "$(mc admin info 2>&1 || true)" ]; then
      minio_note "Minio server is ready."
      return 0
    fi
    minio_note "Minio server is not ready. Waiting..."
    CNT=$((CNT + 1))
    sleep 1
  done
  minio_error "Minio server is not ready in ${TRESHOLD} seconds."
}

docker_process_init_files() {
  if [ "$(mc ls "minio/${BUCKET_NAME}/" | wc -l)" -ne 0 ]; then
    minio_note "Bucket '${BUCKET_NAME}' is not empty. Skipping initialization files."
    return
  fi

  minio_note "Bucket '${BUCKET_NAME}' is empty. Processing initialization files."
  if [ "$(ls "${INITFILES_FOLDER}" | wc -l)" -gt 0 ]; then
    minio_note "Uploading files to bucket '${BUCKET_NAME}'."
    # Note the trailing slash in the source folder. This is required to copy the CONTENTS of the folder and not the folder itself.
    mc cp --recursive "${INITFILES_FOLDER}/" "minio/${BUCKET_NAME}" 1>/dev/null 2>/tmp/minio_error.log
    if [ -s /tmp/minio_error.log ]; then
      minio_error "Error uploading files to bucket '${BUCKET_NAME}'."
      minio_error "$(cat /tmp/minio_error.log)"
    fi
    return
  fi

  minio_note "No files found in '${INITFILES_FOLDER}'. The bucket '${BUCKET_NAME}' will remain empty."
}

docker_create_bucket() {
  # Check if bucket exists, otherwise create it.
  if [ -z "$(mc ls "minio/${BUCKET_NAME}" 2>&1 || true)" ]; then
    minio_note "Bucket '${BUCKET_NAME}' already exists."
  else
    minio_note "Creating bucket '${BUCKET_NAME}'."
    mc config host add minio http://localhost:9000 "${MINIO_ROOT_USER}" "${MINIO_ROOT_PASSWORD}" | minio_note
    mc mb -p "minio/${BUCKET_NAME}" | minio_note
    mc anonymous set download "minio/${BUCKET_NAME}" | minio_note
  fi
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

minio_note() {
  minio_log Note "$@"
}

minio_warn() {
  minio_log Warn "$@" >&2
}

minio_error() {
  minio_log ERROR "$@" >&2
  exit 1
}
