# Docker MinIO

This is a simple docker image for running a MinIO server. It is based on alpine linux and uses the `minio` and `minio-client` packages from the alpine package repository.

The `/scripts/entrypoint.sh` script is used to start the MinIO server. It is possible to configure the container to create and populate the new bucket at startup by setting the `BUCKET_NAME` environment variable.

## Bucket initialization

**The bucket initialization is processed only if the bucket does not exist or is empty.** In any other case, the initialization is skipped. **ATTENTION**: when the MinIO filesystem is already present, the startup process takes care of checking that the `BUCKET_NAME` is configured accordingly with the final MinIO server configuration, performing the filesystem check (the `BUCKET_NAME` folder is present in the `BUCKET_ROOT` folder) and the MinIO client check (the `mc ls ${MC_ALIAS}/${BUCKET_NAME}` command does not return an error).

You can use two different methods to initialize the bucket: the `FileSystem` initialization and the `Seed` initialization. The two methods can be used together, and the `Seed` initialization is processed after the `FileSystem` initialization.

The order of the initialization is the following:

1. The `FileSystem` initialization is processed first, so the entire _MinIO filesystem structure_ is copied to the `BUCKET_ROOT` destination folder.
1. The `Seed` initialization is processed starting from the archives, so the archives are extracted and the files are uploaded in the bucket defined by the `BUCKET_NAME` environment variable.
1. The `Seed` initialization continues with the files, so the files in the `INITFILES_DIR` folder are uploaded in the bucket defined by the `BUCKET_NAME` environment variable.

If the versioning is enabled, the newer files will overwrite the older files, and the previous versions are preserved. See the [Versioning enabled example](#versioning-enabled-example) for more details.

## FileSystem initialization

If the `INITFILESYSTEM_DIR` path is not empty, the files in the folder are copied to the `BUCKET_ROOT` destination folder as a startup filesystem for the MinIO server. **The folder must contain a valid MinIO filesystem structure.** **ATTENTION**: when the `INITFILESYSTEM_DIR` is used, the startup process takes care of checking that the `BUCKET_NAME` is configured accordingly with the final MinIO server configuration, performing the filesystem check (the `BUCKET_NAME` folder is present in the `BUCKET_ROOT` folder) and the MinIO client check (the `mc ls ${MC_ALIAS}/${BUCKET_NAME}` command does not return an error).

## Seed initialization

This initialization method is used to populate the bucket with **seed archives and files**. Both the archives and the files are processed at startup, and the resulting bucket content is the union of the archives and files content.

The archives are processed first, and then the files. So, if the file with the same name is present in one or more archives and in the `INITFILES_DIR` folder, the file in the `INITFILES_DIR` will overwrite the files in the archives. If the bucket has a versioning enabled, the previous versions of the files are preserved. See the [Versioning enabled example](#versioning-enabled-example) for more details.

If the `DO_NOT_PROCESS_INITFILES` environment variable is set to `1`, the seed archives and files are not processed at startup.

### Process the seed archives

If the `INITARCHIVES_DIR` path is not empty, the archives in the folder are extracted in a temporary folder and all the resulting files and folders are uploaded in the bucket defined by the `BUCKET_NAME` environment variable using the MinIO client (`mc cp --recursive`). The archives are extracted and files are uploaded sequentially in the alphabetical order of the filenames, using the output of the `ls -A ${INITARCHIVES_DIR}` command. So, if the archives contain the same files, the last archive extracted will overwrite the files extracted by the previous archives. If the bucket has a versioning enabled, the previous versions of the files are preserved.

**The supported archive formats are `.zip`, `.tar`, `.tar.gz`, `.tar.bz2` and `.tar.xz`.**

### Process the seed files

If the `INITFILES_DIR` path is not empty, the files in the folder are uploaded in the bucket defined by the `BUCKET_NAME` environment variable using the MinIO client (`mc cp --recursive`). As for the archives, if the `INITFILES_DIR` contains files with the same name of one or more files already present in the bucket (processed by the `INITARCHIVES_DIR`), the files in the `INITFILES_DIR` will overwrite the files in the bucket. If the bucket has a versioning enabled, the previous versions of the files are preserved.

## Versioning enabled example

To be more clear, here is an example of the initialization process if the versioning is enabled:

1. The `INITFILESYSTEM_DIR` populates the bucket with these files:
   - `file1.txt`
   - `file2.txt`
1. The `INITARCHIVES_DIR` contains the following archives:
   - `archive1.zip` with the files `file2.txt`, `file3.txt`
   - `archive2.tar.xz` with the files `file3.txt` and `file4.txt`
1. The `INITFILES_DIR` contains the following files:
   - `file3.txt`
   - `file4.txt`
   - `file5.txt`

The resulting bucket content will be:

- `file1.txt`:
  - single version, is the content of the `INITFILESYSTEM_DIR` _MinIO filesystem structure_.
- `file2.txt`:
  - in the first version, is the content of the `INITFILESYSTEM_DIR` _MinIO filesystem structure_.
  - in the current version, is the content of the `archive1.zip` file.
- `file3.txt`:
  - in the first version, is the content of the `archive1.zip` file.
  - in the second version, is the content of the `archive2.tar.xz` file.
  - in the current version, is the content of the `INITFILES_DIR` file.
- `file4.txt`:
  - in the first version, is the content of the `archive2.tar.xz` file.
  - in the current version, is the content of the `INITFILES_DIR` file.
- `file5.txt`:
  - single version, is the content of the `INITFILES_DIR` file.

## Environment Variables

| Variable                   | Description                                                                                                                                                             | Default                             |
| -------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------- |
| `DEBUG`                    | If set to `1`, the script prints the debug information.                                                                                                                 | `0`                                 |
| `BUCKET_NAME`              | The name of the bucket to create and populate at startup.                                                                                                               | `-`                                 |
| `OSB_BUCKET`               | Alternative way to configure the name of the bucket to create and populate at startup. **If `BUCKET_NAME` is not set, this variable is used to configure it.**          | `-`                                 |
| `BUCKET_ROOT`              | The folder used by the MinIO server to store the files.                                                                                                                 | `/data`                             |
| `INITFILESYSTEM_DIR`       | The folder where the root init filesystem is stored. If not empty, the files are copied to the `BUCKET_ROOT` folder.                                                    | `/docker-entrypoint-initfs.d`       |
| `INITARCHIVES_DIR`         | The folder where the seed archives are stored.                                                                                                                          | `/docker-entrypoint-initarchives.d` |
| `INITFILES_DIR`            | The folder where the seed files are stored.                                                                                                                             | `/docker-entrypoint-initfiles.d`    |
| `DO_NOT_PROCESS_INITFILES` | If set to `1`, the seed archives and files are not processed at startup.                                                                                                | `0`                                 |
| `MINIO_ROOT_USER`          | The access key used to authenticate with the MinIO server.                                                                                                              | `-`                                 |
| `OSB_ACCESS_KEY`           | Alternative way to configure the access key used to authenticate with the MinIO server. **If `MINIO_ROOT_USER` is not set, this variable is used to configure it.**     | `-`                                 |
| `MINIO_ROOT_PASSWORD`      | The secret key used to authenticate with the MinIO server.                                                                                                              | `-`                                 |
| `OSB_SECRET_KEY`           | Alternative way to configure the secret key used to authenticate with the MinIO server. **If `MINIO_ROOT_PASSWORD` is not set, this variable is used to configure it.** | `-`                                 |
| `MINIO_VERSION_ENABLED`    | If set to `1`, the MinIO version is enabled.                                                                                                                            | `0`                                 |
| `MINIO_OPTS`               | Additional options to pass to the MinIO server.                                                                                                                         | `-`                                 |
| `MINIO_BROWSER`            | If set to `on`, the MinIO console is enabled.                                                                                                                           | `off`                               |
| `MINIO_CONSOLE_PORT`       | The port used by the MinIO console.                                                                                                                                     | `9001`                              |
| `MC_ALIAS`                 | The alias used by the MinIO client.                                                                                                                                     | `minio`                             |
| `MINIO_PROTO`              | The protocol used to connect to the MinIO server.                                                                                                                       | `http`                              |
| `MINIO_HOST`               | The host used to connect to the MinIO server.                                                                                                                           | `localhost`                         |
| `MINIO_PORT`               | The port used to connect to the MinIO server.                                                                                                                           | `9000`                              |

### Deprecated Variables

The following variables are deprecated and will be removed. Use the new variables instead.

| Variable           | Description                                                                                       |
| ------------------ | ------------------------------------------------------------------------------------------------- |
| `MINIO_ACCESS_KEY` | The access key used to authenticate with the MinIO server. **Use `MINIO_ROOT_USER` instead.**     |
| `MINIO_SECRET_KEY` | The secret key used to authenticate with the MinIO server. **Use `MINIO_ROOT_PASSWORD` instead.** |

`MINIO_ACCESS_KEY` and `MINIO_SECRET_KEY` are used only if the new variables (`MINIO_ROOT_USER` or `OSB_ACCESS_KEY` and `MINIO_ROOT_PASSWORD` or `OSB_SECRET_KEY`) are not set.
