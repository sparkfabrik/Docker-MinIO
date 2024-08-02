# Docker MinIO

This is a simple docker image for running a minio server. It is based on alpine linux and uses the minio and minio-client packages from the alpine package repository.

The `/scripts/entrypoint.sh` script is used to start the minio server. It is possible to configure the container to create and populate the new bucket at startup by setting the `BUCKET_NAME` environment variable and adding the seed files to the folder defined by the `INITFILES_FOLDER` environment variable.

## Environment Variables

| Variable                   | Description                                                 | Default                          |
| -------------------------- | ----------------------------------------------------------- | -------------------------------- |
| `BUCKET_NAME`              | The name of the bucket to create and populate at startup.   | `-`                              |
| `BUCKET_ROOT`              | The folder used by the minio server to store the files.     | `/data`                          |
| `INITFILES_FOLDER`         | The folder where the seed files are stored.                 | `/docker-entrypoint-initfiles.d` |
| `DO_NOT_PROCESS_INITFILES` | If set to `1`, the seed files are not processed at startup. | `0`                              |
| `MINIO_ROOT_USER`          | The access key used to authenticate with the minio server.  | `-`                              |
| `MINIO_ROOT_PASSWORD`      | The secret key used to authenticate with the minio server.  | `-`                              |
| `MINIO_BROWSER`            | If set to `on`, the minio browser is enabled.               | `off`                            |
| `MINIO_CONSOLE_PORT`       | The port used by the minio console.                         | `9001`                           |
| `MINIO_OPTS`               | Additional options to pass to the minio server.             | `-`                              |

### Deprecated Variables

| Variable           | Description                                                                                       |
| ------------------ | ------------------------------------------------------------------------------------------------- |
| `OSB_BUCKET`       | The name of the bucket to create and populate at startup. **Use `BUCKET_NAME` instead.**          |
| `MINIO_ACCESS_KEY` | The access key used to authenticate with the minio server. **Use `MINIO_ROOT_USER` instead.**     |
| `MINIO_SECRET_KEY` | The secret key used to authenticate with the minio server. **Use `MINIO_ROOT_PASSWORD` instead.** |
