# Image URL to use all building/pushing image targets
IMG ?= fluxcd/source-controller:latest
RELEASE_NAME ?= flux

IMG_PARTS := $(subst :, ,$(IMG))
IMG_REPOSITORY := $(word 1, $(IMG_PARTS))
IMG_TAG := $(word 2, $(IMG_PARTS))

# Produce CRDs that work back to Kubernetes 1.16
CRD_OPTIONS ?= crd:crdVersions=v1

# Get the currently used golang install path (in GOPATH/bin, unless GOBIN is set)
ifeq (,$(shell go env GOBIN))
GOBIN=$(shell go env GOPATH)/bin
else
GOBIN=$(shell go env GOBIN)
endif

all: manager

# Run tests
test: generate fmt vet manifests api-docs sync-chart
	go test ./... -coverprofile cover.out
	cd api; go test ./... -coverprofile cover.out

# Build manager binary
manager: generate fmt vet
	go build -o bin/manager main.go

# Run against the configured Kubernetes cluster in ~/.kube/config
run: generate fmt vet manifests
	go run ./main.go

# Install CRDs into a cluster
install: manifests
	kustomize build config/crd | kubectl apply -f -

# Uninstall CRDs from a cluster
uninstall: manifests
	kustomize build config/crd | kubectl delete -f -

# Synchronize the manifest CRDs and RBAC roles into the helm chart
sync-chart: manifests
	./hack/sync-chart.sh

# Deploy controller in the configured Kubernetes cluster in ~/.kube/config
deploy: manifests
	cd config/manager && kustomize edit set image fluxcd/source-controller=${IMG}
	kustomize build config/default | kubectl apply -f -

# Deploy controller in the configured Kubernetes cluster in ~/.kube/config using helm
chart-deploy: sync-chart
	helm upgrade ${RELEASE_NAME} \
		--install \
		--namespace=source-system \
		--create-namespace \
		--wait \
		--timeout=1m \
		--set image.repository=${IMG_REPOSITORY} \
		--set image.tag=${IMG_TAG} \
		./chart

	sleep 5

	helm test ${RELEASE_NAME} --namespace=source-system --timeout 1m --logs

# Deploy controller dev image in the configured Kubernetes cluster in ~/.kube/config
dev-deploy:
	mkdir -p config/dev && cp config/default/* config/dev
	cd config/dev && kustomize edit set image fluxcd/source-controller=${IMG}
	kustomize build config/dev | kubectl apply -f -
	rm -rf config/dev

# Generate manifests e.g. CRD, RBAC etc.
manifests: controller-gen
	$(CONTROLLER_GEN) $(CRD_OPTIONS) rbac:roleName=manager-role paths="./..." output:crd:artifacts:config="config/crd/bases"
	cd api; $(CONTROLLER_GEN) $(CRD_OPTIONS) rbac:roleName=manager-role paths="./..." output:crd:artifacts:config="../config/crd/bases"

# Generate API reference documentation
api-docs: gen-crd-api-reference-docs
	$(API_REF_GEN) -api-dir=./api/v1beta1 -config=./hack/api-docs/config.json -template-dir=./hack/api-docs/template -out-file=./docs/api/source.md

# Run go mod tidy
tidy:
	go mod tidy
	cd api; go mod tidy

# Run go fmt against code
fmt:
	go fmt ./...
	cd api; go fmt ./...

# Run go vet against code
vet:
	go vet ./...
	cd api; go vet ./...

# Generate code
generate: controller-gen
	cd api; $(CONTROLLER_GEN) object:headerFile="../hack/boilerplate.go.txt" paths="./..."

# Build the docker image
docker-build:
	docker build . -t ${IMG}

# Push the docker image
docker-push:
	docker push ${IMG}

# Find or download controller-gen
controller-gen:
ifeq (, $(shell which controller-gen))
	@{ \
	set -e ;\
	CONTROLLER_GEN_TMP_DIR=$$(mktemp -d) ;\
	cd $$CONTROLLER_GEN_TMP_DIR ;\
	go mod init tmp ;\
	go get sigs.k8s.io/controller-tools/cmd/controller-gen@v0.4.1 ;\
	rm -rf $$CONTROLLER_GEN_TMP_DIR ;\
	}
CONTROLLER_GEN=$(GOBIN)/controller-gen
else
CONTROLLER_GEN=$(shell which controller-gen)
endif

# Find or download gen-crd-api-reference-docs
gen-crd-api-reference-docs:
ifeq (, $(shell which gen-crd-api-reference-docs))
	@{ \
	set -e ;\
	API_REF_GEN_TMP_DIR=$$(mktemp -d) ;\
	cd $$API_REF_GEN_TMP_DIR ;\
	go mod init tmp ;\
	go get github.com/ahmetb/gen-crd-api-reference-docs@v0.2.0 ;\
	rm -rf $$API_REF_GEN_TMP_DIR ;\
	}
API_REF_GEN=$(GOBIN)/gen-crd-api-reference-docs
else
API_REF_GEN=$(shell which gen-crd-api-reference-docs)
endif
