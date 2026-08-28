SHELL := /bin/bash
.DEFAULT_GOAL := help

CLUSTER_NAME ?= playground
KIND_CONFIG  ?= kind-cluster.yaml
MANIFESTS    ?= manifests

.PHONY: help
help: ## Show this help
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-16s\033[0m %s\n", $$1, $$2}'

.PHONY: cluster
cluster: ## Create the kind cluster (no-op if it already exists)
	@if kind get clusters 2>/dev/null | grep -qx '$(CLUSTER_NAME)'; then \
		echo "cluster '$(CLUSTER_NAME)' already exists"; \
	else \
		kind create cluster --name '$(CLUSTER_NAME)' --config '$(KIND_CONFIG)' --wait 120s; \
	fi
	@kubectl cluster-info --context 'kind-$(CLUSTER_NAME)'

.PHONY: delete
delete: ## Delete the kind cluster
	kind delete cluster --name '$(CLUSTER_NAME)'

.PHONY: recreate
recreate: delete cluster ## Recreate the cluster (needed after editing port mappings)

.PHONY: status
status: ## Show nodes and all pods
	kubectl get nodes -o wide
	@echo
	kubectl get pods -A

.PHONY: deploy
deploy: ## Apply everything under manifests/
	kubectl apply -f '$(MANIFESTS)'

.PHONY: undeploy
undeploy: ## Delete everything under manifests/
	kubectl delete -f '$(MANIFESTS)' --ignore-not-found

.PHONY: logs
logs: ## Tail logs of the sample gRPC app
	kubectl logs -l app=grpcbin --tail=100 -f

.PHONY: grpc-list
grpc-list: ## List gRPC services on the sample app via reflection
	grpcurl -plaintext localhost:30000 list

.PHONY: grpc-describe
grpc-describe: ## Describe the sample gRPC API via reflection
	grpcurl -plaintext localhost:30000 describe grpcbin.GRPCBin

.PHONY: load
load: ## Load a local docker image into the cluster (make load IMAGE=my:tag)
	@test -n '$(IMAGE)' || (echo "usage: make load IMAGE=<name:tag>" && exit 1)
	kind load docker-image '$(IMAGE)' --name '$(CLUSTER_NAME)'

.PHONY: ingress
ingress: ## Install the ingress-nginx controller (kind flavour)
	kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
	kubectl wait --namespace ingress-nginx \
		--for=condition=ready pod \
		--selector=app.kubernetes.io/component=controller \
		--timeout=180s

.PHONY: metrics
metrics: ## Install metrics-server (patched for kind's self-signed kubelet certs)
	helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/ >/dev/null
	helm repo update >/dev/null
	helm upgrade --install metrics-server metrics-server/metrics-server \
		--namespace kube-system \
		--set 'args={--kubelet-insecure-tls}'

.PHONY: verify
verify: ## Verify every required tool is on PATH
	@for bin in kubectl helm kind grpcurl docker make; do \
		if command -v $$bin >/dev/null 2>&1; then \
			printf '  ok      %-9s %s\n' "$$bin" "$$(command -v $$bin)"; \
		else \
			printf '  MISSING %-9s\n' "$$bin"; exit 1; \
		fi; \
	done

.PHONY: clean
clean: undeploy ## Remove workloads (keeps the cluster)
