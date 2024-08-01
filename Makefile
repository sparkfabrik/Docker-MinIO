IMAGE_NAME ?= sparkfabrik/docker-minio
IMAGE_TAG ?= latest

MINIO_ROOT_USER ?= minioadmin
MINIO_ROOT_PASSWORD ?= minioadmin

build:
	docker build -t $(IMAGE_NAME):$(IMAGE_TAG) .

cli: build
	docker run --rm -it --entrypoint ash $(IMAGE_NAME):$(IMAGE_TAG)

start: build
	@docker run \
	-e OSB_BUCKET=drupal \
	-e MINIO_ROOT_USER=$(MINIO_ROOT_USER) \
	-e MINIO_ROOT_PASSWORD=$(MINIO_ROOT_PASSWORD) \
	-e MINIO_BROWSER=on \
	-p 9001:9001 \
	-v ./initfiles:/docker-entrypoint-initfiles.d \
	$(IMAGE_NAME):$(IMAGE_TAG)