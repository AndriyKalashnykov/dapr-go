.DEFAULT_GOAL := help
CURRENTTAG:=$(shell git describe --tags --abbrev=0)
NEWTAG ?= $(shell bash -c 'read -p "Please provide a new tag (currnet tag - ${CURRENTTAG}): " newtag; echo $$newtag')
GOFLAGS=-mod=mod

IS_DARWIN := 0
IS_LINUX := 0
IS_FREEBSD := 0
IS_WINDOWS := 0
IS_AMD64 := 0
IS_AARCH64 := 0
IS_RISCV64 := 0

# Test Windows apart because it doesn't support `uname -s`.
ifeq ($(OS), Windows_NT)
	# We can assume it will likely be in amd64.
	IS_AMD64 := 1
	IS_WINDOWS := 1
else
	# Platform
	uname := $(shell uname -s)

	ifeq ($(uname), Darwin)
		IS_DARWIN := 1
	else ifeq ($(uname), Linux)
		IS_LINUX := 1
	else ifeq ($(uname), FreeBSD)
		IS_FREEBSD := 1
	else
		# We use spaces instead of tabs to indent `$(error)`
		# otherwise it's considered as a command outside a
		# target and it will fail.
                $(error Unrecognized platform, expect `Darwin`, `Linux` or `Windows_NT`)
	endif

	# Architecture
	uname := $(shell uname -m)

	ifneq (, $(filter $(uname), x86_64 amd64))
		IS_AMD64 := 1
	else ifneq (, $(filter $(uname), aarch64 arm64))
		IS_AARCH64 := 1
	else ifneq (, $(filter $(uname), riscv64))
		IS_RISCV64 := 1
	else
		# We use spaces instead of tabs to indent `$(error)`
		# otherwise it's considered as a command outside a
		# target and it will fail.
                $(error Unrecognized architecture, expect `x86_64`, `aarch64`, `arm64`, 'riscv64')
	endif
endif

#help: @ List available tasks
help:
	@clear
	@echo "Usage: make COMMAND"
	@echo "Commands :"
	@grep -E '[a-zA-Z\.\-]+:.*?@ .*$$' $(MAKEFILE_LIST)| tr -d '#' | awk 'BEGIN {FS = ":.*?@ "}; {printf "\033[32m%-15s\033[0m - %s\n", $$1, $$2}'

#minikube-start: @ Start Minikube, parametrized example: ./scripts/minikube.sh start dapr-go 1 8000mb 2 40g docker 192.168.200.200
minikube-start:
	./scripts/minikube.sh start

#minikube-stop: @ Stop Minikube
minikube-stop:
	./scripts/minikube.sh stop

#minikube-delete: @ Delete Minikube
minikube-delete:
	./scripts/minikube.sh delete

#minikube-list: @ List Minikube profiles
minikube-list:
	minikube profile list

#clean: @ Cleanup
clean:
	@rm ./read-values/main
	@rm ./subscriber/main
	@rm ./write-values/main

#test: @ Run tests
test:
	@cd read-values && export GOFLAGS=$(GOFLAGS); go test $(go list ./...)
	@cd subscriber && export GOFLAGS=$(GOFLAGS); go test $(go list ./...)
	@cd write-values && export GOFLAGS=$(GOFLAGS); go test $(go list ./...)

#build: @ Build binary
build:
	@export GOFLAGS=$(GOFLAGS); export CGO_ENABLED=0; GOOS=linux GOARCH=amd64 go build -o ./read-values/main ./read-values/main.go
	@export GOFLAGS=$(GOFLAGS); export CGO_ENABLED=0; GOOS=linux GOARCH=amd64 go build -o ./subscriber/main ./subscriber/main.go
	@export GOFLAGS=$(GOFLAGS); export CGO_ENABLED=0; GOOS=linux GOARCH=amd64 go build -o ./write-values/main ./write-values/main.go
	@cd ./state/frontendsvc && export GOFLAGS=$(GOFLAGS); export CGO_ENABLED=0; GOOS=linux GOARCH=amd64 go build -o ./main ./main.go

#run: @ Run binary
run:
	@export GOFLAGS=$(GOFLAGS); go run ./read-values/main.go

#get: @ Download and install dependency packages
get:
	@cd read-values && export GOFLAGS=$(GOFLAGS); go get . ; go mod tidy
	@cd subscriber && export GOFLAGS=$(GOFLAGS); go get . ; go mod tidy
	@cd write-values && export GOFLAGS=$(GOFLAGS); go get . ; go mod tidy
	@cd state/frontendsvc && export GOFLAGS=$(GOFLAGS); go get . ; go mod tidy

#update: @ Update dependencies to latest versions
update:
	@cd read-values && export GOFLAGS=$(GOFLAGS); go get -u; go mod tidy
	@cd subscriber && export GOFLAGS=$(GOFLAGS); go get -u; go mod tidy
	@cd write-values && export GOFLAGS=$(GOFLAGS); go get -u; go mod tidy
	@cd state/frontendsvc && export GOFLAGS=$(GOFLAGS); go get -u; go mod tidy

#release: @ Create and push a new tag
release: build
	$(eval NT=$(NEWTAG))
	@echo -n "Are you sure to create and push ${NT} tag? [y/N] " && read ans && [ $${ans:-N} = y ]
	@echo ${NT} > ./version.txt
	@git add -A
	@git commit -a -s -m "Cut ${NT} release"
	@git tag -a -m "Cut ${NT} release" ${NT}
	@git push origin ${NT}
	@git push
	@echo "Done."

#version: @ Print current version(tag)
version:
	@echo $(shell git describe --tags --abbrev=0)

#image-build: @ Build a Docker image
image-build: build
	@cd read-values && DOCKER_BUILDKIT=1 docker build -t andriykalashnykov/dapr-go-read-values:v0.0.1 --build-arg TARGETPLATFORM=linux/amd64 .
#	@cd subscriber && DOCKER_BUILDKIT=1 docker build -t andriykalashnykov/dapr-go-subscriber:v0.0.1 .
#	@cd write-values && DOCKER_BUILDKIT=1 docker build -t andriykalashnykov/dapr-go-write-values:v0.0.1 .
#	@cd ./state/frontendsvc && ko build --local -B --platform=linux/amd64,linux/arm64 .

#deploy-dapr: @ Deploy DAPR
deploy-dapr:
	./scripts/dapr.sh deploy
# kubectl port-forward svc/dapr-dashboard 8080:8080 -n dapr-system
# xdg-open http://localhost:8080

#undeploy-dapr: @ Undeploy DAPR
undeploy-dapr:
	./scripts/dapr.sh undeploy

#deploy-components: @ Deploy Redis, Kafka, etc.
deploy-components:
	./scripts/components.sh deploy

#undeploy-components: @ Undeploy Redis, Kafka, etc.
undeploy-components:
	./scripts/components.sh undeploy

#deploy-workloads: @ deploy workloads
deploy-workloads: image-build
	./scripts/workloads.sh deploy

#undeploy-workloads: @ undeploy workloads
undeploy-workloads:
	./scripts/workloads.sh undeploy