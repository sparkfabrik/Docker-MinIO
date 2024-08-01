# docker-minio

This is a simple docker image for running a minio server. It is based on alpine linux and uses the minio and minio-client packages from the alpine package repository.

The `/scripts/entrypoint.sh` script is used to start the minio server. It is possible to configure the container to create and populate the new bucket at startup by setting the `OSB_BUCKET` environment variable and adding the seed files to the folder defined by the `INITFILES_FOLDER` environment variable.
