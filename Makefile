TOOLS_DIR := hack/tools
TOOLS_BIN_DIR := $(abspath $(TOOLS_DIR)/bin)

GOLANGCI_LINT_VER := v1.41.1
GOLANGCI_LINT_BIN := golangci-lint
GOLANGCI_LINT := $(abspath $(TOOLS_BIN_DIR)/$(GOLANGCI_LINT_BIN)-$(GOLANGCI_LINT_VER))

# Scripts
GO_INSTALL := ./hack/go-install.sh

GO111MODULE := on
export GO111MODULE

TEST_CREDENTIALS_DIR ?= $(abspath .azure)
TEST_CREDENTIALS_JSON ?= $(TEST_CREDENTIALS_DIR)/credentials.json
TEST_LOGANALYTICS_JSON ?= $(TEST_CREDENTIALS_DIR)/loganalytics.json
export TEST_CREDENTIALS_JSON TEST_LOGANALYTICS_JSON

IMG_REPO ?= virtual-kubelet
OUTPUT_TYPE ?= docker
BUILDPLATFORM ?= linux/amd64
VERSION      := $(shell git describe --tags --always --dirty="-dev")
IMG_TAG ?= $(VERSION)


## --------------------------------------
## Tooling Binaries
## --------------------------------------

$(GOLANGCI_LINT):
	GOBIN=$(TOOLS_BIN_DIR) $(GO_INSTALL) github.com/golangci/golangci-lint/cmd/golangci-lint $(GOLANGCI_LINT_BIN) $(GOLANGCI_LINT_VER)

.PHONY: safebuild
# docker build
safebuild:
	@echo "Building image..."
	docker build -t $(DOCKER_IMAGE):$(VERSION) .

.PHONY: image
image:
	docker buildx build \
		--platform="$(BUILDPLATFORM)" \
		--tag $(IMG_REPO):$(IMG_TAG) \
		--output=type=$(OUTPUT_TYPE) \
		.

.PHONY: build
build: bin/virtual-kubelet

.PHONY: clean
clean: files := bin/virtual-kubelet bin/virtual-kubelet.tgz
clean:
	@rm -f $(files) &>/dev/null || exit 0

.PHONY: test
test:
	@echo running tests
	AZURE_AUTH_LOCATION=$(TEST_CREDENTIALS_JSON) LOG_ANALYTICS_AUTH_LOCATION=$(TEST_LOGANALYTICS_JSON) go test -v $(shell go list ./... | grep -v /e2e) -race -coverprofile=coverage.out -covermode=atomic

.PHONY: vet
vet:
	@go vet ./... #$(packages)

## --------------------------------------
## Linting
## --------------------------------------

.PHONY: lint
lint: $(GOLANGCI_LINT)
	$(GOLANGCI_LINT) run -v

.PHONY: lint-full
lint-full: $(GOLANGCI_LINT) ## Run slower linters to detect possible issues
	$(GOLANGCI_LINT) run -v --fast=false

.PHONY: check-mod
check-mod: # verifies that module changes for go.mod and go.sum are checked in
	# @chmod a+x hack/ci/check_mods.sh
	@hack/ci/check_mods.sh

.PHONY: mod
mod:
	@go mod tidy

.PHONY: testauth
testauth: test-cred-json test-loganalytics-json

test-cred-json:
	@echo Building test credentials
	chmod a+x hack/ci/create_credentials.sh
	hack/ci/create_credentials.sh

test-loganalytics-json:
	@echo Building log analytics credentials
	chmod a+x hack/ci/create_loganalytics_auth.sh
	hack/ci/create_loganalytics_auth.sh

bin/virtual-kubelet: BUILD_VERSION          ?= $(shell git describe --tags --always --dirty="-dev")
bin/virtual-kubelet: BUILD_DATE             ?= $(shell date -u '+%Y-%m-%d-%H:%M UTC')
bin/virtual-kubelet: VERSION_FLAGS    := -ldflags='-X "main.buildVersion=$(BUILD_VERSION)" -X "main.buildTime=$(BUILD_DATE)"'

bin/%:
	CGO_ENABLED=0 go build -ldflags '-extldflags "-static"' -o bin/$(*) $(VERSION_FLAGS) ./cmd/$(*)

.PHONY: helm
helm: bin/virtual-kubelet.tgz

bin/virtual-kubelet.tgz:
	rm -rf /tmp/virtual-kubelet
	mkdir /tmp/virtual-kubelet
	cp -r helm/* /tmp/virtual-kubelet/
	mkdir -p bin
	tar -zcvf bin/virtual-kubelet.tgz -C /tmp virtual-kubelet
