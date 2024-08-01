IMAGE_NAME ?= sparkfabrik/docker-minio
IMAGE_TAG ?= latest

BUCKET_NAME ?= testbucket
MINIO_ROOT_USER ?= minioadmin
MINIO_ROOT_PASSWORD ?= minioadmin

build:
	docker build -t $(IMAGE_NAME):$(IMAGE_TAG) .

cli: build
	docker run --rm -it \
	-e BUCKET_NAME=$(BUCKET_NAME) \
	-e MINIO_ROOT_USER=$(MINIO_ROOT_USER) \
	-e MINIO_ROOT_PASSWORD=$(MINIO_ROOT_PASSWORD) \
	--entrypoint ash \
	$(IMAGE_NAME):$(IMAGE_TAG) -il

start: build
	@docker run \
	-e BUCKET_NAME=$(BUCKET_NAME) \
	-e MINIO_ROOT_USER=$(MINIO_ROOT_USER) \
	-e MINIO_ROOT_PASSWORD=$(MINIO_ROOT_PASSWORD) \
	-e MINIO_BROWSER=on \
	-p 9000:9000 \
	-p 9001:9001 \
	-v ./initfiles:/docker-entrypoint-initfiles.d \
	$(IMAGE_NAME):$(IMAGE_TAG)

aws-cli:
	@docker run --rm -it \
	-e AWS_ACCESS_KEY_ID=$(MINIO_ROOT_USER) \
	-e AWS_SECRET_ACCESS_KEY=$(MINIO_ROOT_PASSWORD) \
	-e AWS_DEFAULT_REGION=us-east-1 \
	-e AWS_ENDPOINT_URL=http://localhost:9000 \
	--network host \
	--entrypoint bash \
	amazon/aws-cli -il