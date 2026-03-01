APP_NAME     := zerodowntime-app
VERSION      ?= $(shell git rev-parse --short HEAD 2>/dev/null || echo "dev")
REGISTRY     ?= ghcr.io/vaibhavsrivastava
IMAGE        := $(REGISTRY)/$(APP_NAME):$(VERSION)
NAMESPACE    ?= zerodowntime

.PHONY: all build test lint run docker-build docker-push deploy-base deploy-canary rollback smoke clean

all: lint test build

# ── Go ───────────────────────────────────────────
build:
	CGO_ENABLED=0 go build -ldflags="-s -w" -o bin/server ./cmd/server

test:
	go test -race -coverprofile=coverage.out ./...

lint:
	golangci-lint run ./...

run:
	APP_VERSION=$(VERSION) go run ./cmd/server

# ── Docker ───────────────────────────────────────
docker-build:
	docker build -t $(IMAGE) --build-arg VERSION=$(VERSION) .

docker-push: docker-build
	docker push $(IMAGE)

# ── Kubernetes ───────────────────────────────────
deploy-base:
	kubectl apply -k k8s/base

deploy-staging:
	kubectl apply -k k8s/overlays/staging

deploy-production:
	kubectl apply -k k8s/overlays/production

deploy-canary:
	kubectl apply -k k8s/canary
	kubectl set image deployment/$(APP_NAME)-canary app=$(IMAGE) -n $(NAMESPACE)

rollback:
	NAMESPACE=$(NAMESPACE) ./scripts/rollback.sh

rollback-full:
	NAMESPACE=$(NAMESPACE) ./scripts/rollback.sh --full

smoke:
	NAMESPACE=$(NAMESPACE) ./scripts/smoke-test.sh stable

smoke-canary:
	NAMESPACE=$(NAMESPACE) ./scripts/smoke-test.sh canary

# ── Cleanup ──────────────────────────────────────
clean:
	rm -rf bin/ coverage.out
