# Copyright 2019 The Kubernetes Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# This repo is build locally for dev/test by default;
# Override this variable in CI env.
BUILD_LOCALLY ?= 1

# Image URL to use all building/pushing image targets;
# Use your own docker registry and image name for dev/test by overridding the IMG and REGISTRY environment variable.
IMG ?= multicloud-operators-subscription-release
REGISTRY ?= quay.io/multicloudlab

# Github host to use for checking the source tree;
# Override this variable ue with your own value if you're working on forked repo.
GIT_HOST ?= github.com/IBM

PWD := $(shell pwd)
BASE_DIR := $(shell basename $(PWD))

# Keep an existing GOPATH, make a private one if it is undefined
GOPATH_DEFAULT := $(PWD)/.go
export GOPATH ?= $(GOPATH_DEFAULT)
GOBIN_DEFAULT := $(GOPATH)/bin
export GOBIN ?= $(GOBIN_DEFAULT)
TESTARGS_DEFAULT := "-v"
export TESTARGS ?= $(TESTARGS_DEFAULT)
DEST := $(GOPATH)/src/$(GIT_HOST)/$(BASE_DIR)
VERSION ?= $(shell git describe --exact-match 2> /dev/null || \
                 git describe --match=$(git rev-parse --short=8 HEAD) --always --dirty --abbrev=8)

LOCAL_OS := $(shell uname)
ifeq ($(LOCAL_OS),Linux)
    TARGET_OS ?= linux
    XARGS_FLAGS="-r"
else ifeq ($(LOCAL_OS),Darwin)
    TARGET_OS ?= darwin
    XARGS_FLAGS=
else
    $(error "This system's OS $(LOCAL_OS) isn't recognized/supported")
endif

.PHONY: all work fmt check coverage lint test build images build-push-images

all: fmt check test coverage build images

# ifneq ("$(realpath $(DEST))", "$(realpath $(PWD))")
#     $(error Please run 'make' from $(DEST). Current directory is $(PWD))
# endif

# The MARKDOWN_LINT_WHITELIST is used to white-list the urls
MARKDOWN_LINT_WHITELIST := mycluster.icp

include common/Makefile.common.mk
# include Makefile.local

init:
	@find .git/hooks -type l -exec rm {} \;
	@find .githooks -type f -exec ln -sf ../../{} .git/hooks/ \;

############################################################
# work section
############################################################
$(GOBIN):
	@echo "create gobin"
	@mkdir -p $(GOBIN)

work: $(GOBIN)

############################################################
# format section
############################################################

# All available format: format-go format-protos format-python
# Default value will run all formats, override these make target with your requirements:
#    eg: fmt: format-go format-protos
fmt: format-go format-protos format-python

############################################################
# check section
############################################################

check: fmt lint

# All available linters: lint-dockerfiles lint-scripts lint-yaml lint-copyright-banner lint-go lint-python lint-helm lint-markdown lint-sass lint-typescript lint-protos
# Default value will run all linters, override these make target with your requirements:
#    eg: lint: lint-go lint-yaml
lint: fmt lint-all

############################################################
# generate helm repo for test
############################################################

generate-helmrepo:
	@rm -rf test/helmrepo
	@mkdir test/helmrepo
	@helm init --client-only 
	@helm package test/github/subscription-release-test-1 -d test/helmrepo --version "0.2.0"
	@build/generate-helmrepo.sh test/github

############################################################
# test section
############################################################

test:
	@go test ${TESTARGS} ./...

############################################################
# coverage section
############################################################

coverage:
	@common/scripts/codecov.sh ${BUILD_LOCALLY}

############################################################
# generate code section
############################################################

generate:
	operator-sdk generate k8s
	operator-sdk generate openapi

############################################################
# build section
############################################################

build:
	# @common/scripts/gobuild.sh go-repo-template ./cmd/manager
	@$(GOBIN)/operator-sdk version ; \
	if [ $$? -ne 0 ]; then \
	   build/install-operator-sdk.sh; \
	fi
	@$(GOBIN)/operator-sdk version


############################################################
# images section
############################################################

images: build build-push-images

ifeq ($(BUILD_LOCALLY),0)
    export CONFIG_DOCKER_TARGET = config-docker
endif

build-push-images: $(CONFIG_DOCKER_TARGET)
	@$(GOBIN)/operator-sdk build $(REGISTRY)/$(IMG):$(VERSION)
	@docker tag $(REGISTRY)/$(IMG):$(VERSION) $(REGISTRY)/$(IMG):latest
ifeq ($(BUILD_LOCALLY),0)
	@docker push $(REGISTRY)/$(IMG):$(VERSION)
	@docker push $(REGISTRY)/$(IMG):latest
endif

############################################################
# clean section
############################################################
clean:
	rm -f go-repo-template
	