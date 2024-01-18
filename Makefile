.DEFAULT_GOAL := help
CURRENTTAG:=$(shell git describe --tags --abbrev=0)
NEWTAG ?= $(shell bash -c 'read -p "Please provide a new tag (currnet tag - ${CURRENTTAG}): " newtag; echo $$newtag')
GOFLAGS=-mod=mod
GO_BUILDER_VERSION=v1.21.3
OSXCROSS_PATH=/opt/osxcross-clang-17.0.3-macosx-14.0/target/bin

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
	@grep -E '[a-zA-Z\.\-]+:.*?@ .*$$' $(MAKEFILE_LIST)| tr -d '#' | awk 'BEGIN {FS = ":.*?@ "}; {printf "\033[32m%-13s\033[0m - %s\n", $$1, $$2}'

#clean: @ Cleanup
clean:
	@sudo rm -rf ./dist

#test: @ Run tests
test:
	@export GOFLAGS=$(GOFLAGS); go test $(go list ./...)

#build: @ Build binary
build:
	@export GOFLAGS=$(GOFLAGS); export CGO_ENABLED=0; go build -o ./read-values/main ./read-values/main.go
	@export GOFLAGS=$(GOFLAGS); export CGO_ENABLED=0; go build -o ./subscriber/main ./subscriber/main.go
	@export GOFLAGS=$(GOFLAGS); export CGO_ENABLED=0; go build -o ./write-values/main ./write-values/main.go

#run: @ Run binary
run:
	@export GOFLAGS=$(GOFLAGS); go run ./read-values/main.go

#get: @ Download and install dependency packages
get:
	@export GOFLAGS=$(GOFLAGS); go get . ; go mod tidy

test-release: clean
	docker run --rm --privileged \
		-v $(CURDIR):/golang-cross-example \
		-v /var/run/docker.sock:/var/run/docker.sock \
		-v $(GOPATH)/src:/go/src \
		-w /golang-cross-example \
		ghcr.io/gythialy/golang-cross:$(GO_BUILDER_VERSION) --skip=publish --clean --snapshot --config .goreleaser-Linux.yml

	docker run --rm --privileged \
		-v $(CURDIR):/golang-cross-example \
		-v /var/run/docker.sock:/var/run/docker.sock \
		-v $(GOPATH)/src:/go/src \
		-w /golang-cross-example \
		ghcr.io/gythialy/golang-cross:$(GO_BUILDER_VERSION) --skip=publish --clean --snapshot --config .goreleaser-Darwin-cross.yml
#ifeq ($(IS_LINUX), 1)
#	export PATH=$(OSXCROSS_PATH):${PATH} && goreleaser --skip=publish --clean --snapshot --config .goreleaser-Linux.yml && goreleaser --skip=publish --clean --snapshot --config .goreleaser-Darwin-cross.yml
#endif
#ifeq ($(IS_DARWIN), 1)
#	export PATH=$(OSXCROSS_PATH):${PATH} && goreleaser --skip=publish --clean --snapshot --config .goreleaser-Darwin.yml
#endif

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

#update: @ Update dependencies to latest versions
update:
	@cd read-values && export GOFLAGS=$(GOFLAGS); go get -u; go mod tidy
	@cd subscriber && export GOFLAGS=$(GOFLAGS); go get -u; go mod tidy
	@cd write-values && export GOFLAGS=$(GOFLAGS); go get -u; go mod tidy

#version: @ Print current version(tag)
version:
	@echo $(shell git describe --tags --abbrev=0)

#image-build: @ Build a Docker image
image-build:
	docker build -t go-httpbin:$(CURRENTTAG) .
