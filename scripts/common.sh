# Helper functions for the entrypoint script.
docker_process_init_files() {
  if [ "$(ls "${INITFILES_FOLDER}" | wc -l)" -gt 0 ]; then
    minio_note "Uploading files to bucket ${BUCKET_NAME}"
    # Note the trailing slash in the source folder. This is required to copy the CONTENTS of the folder and not the folder itself.
    mc cp --recursive "${INITFILES_FOLDER}/" "minio/${BUCKET_NAME}"
  fi
}

docker_create_bucket() {
  # Start minio server. We need to start it to create the bucket and eventually upload files.
  /usr/bin/minio server "${BUCKET_ROOT}" &>/dev/null &
  MINIO_TEMP_PID=$!
  sleep 1

  # Check if bucket exists, otherwise create it.
  if [ -z "$(mc ls "minio/${BUCKET_NAME}" 2>&1 || true)" ]; then
    minio_note "Bucket ${BUCKET_NAME} already exists"
  else
    minio_note "Creating bucket ${BUCKET_NAME}"
    mc config host add minio http://localhost:9000 "${MINIO_ROOT_USER}" "${MINIO_ROOT_PASSWORD}"
    mc mb -p "minio/${BUCKET_NAME}"
    mc policy set public "minio/${BUCKET_NAME}"
  fi

  # Eventually process init files.
  docker_process_init_files

  # Stop minio server.
  kill -9 "${MINIO_TEMP_PID}"
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
