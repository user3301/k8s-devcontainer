#!/usr/bin/env bash
# Runs on every container start.
# Waits for the docker-in-docker daemon, then makes sure a kind cluster exists.
# Set AUTO_CREATE_CLUSTER=false to skip cluster creation and do it manually
# with `make cluster`.
set -euo pipefail

CLUSTER_NAME="${KIND_CLUSTER_NAME:-playground}"
AUTO_CREATE_CLUSTER="${AUTO_CREATE_CLUSTER:-true}"
CONFIG_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/kind-cluster.yaml"

log() { echo "[post-start] $*"; }

log "waiting for the docker daemon..."
for _ in $(seq 1 60); do
  if docker info >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

if ! docker info >/dev/null 2>&1; then
  log "docker daemon did not become ready in time; skipping cluster bootstrap."
  log "once docker is up, run: make cluster"
  exit 0
fi
log "docker is ready."

if [ "$AUTO_CREATE_CLUSTER" != "true" ]; then
  log "AUTO_CREATE_CLUSTER=${AUTO_CREATE_CLUSTER}; skipping. Run 'make cluster' when ready."
  exit 0
fi

if kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME"; then
  log "kind cluster '${CLUSTER_NAME}' already exists."
else
  log "creating kind cluster '${CLUSTER_NAME}' (this takes a minute on first run)..."
  kind create cluster --name "$CLUSTER_NAME" --config "$CONFIG_FILE" --wait 120s
fi

mkdir -p "$(dirname "${KUBECONFIG:-$HOME/.kube/config}")"
kind export kubeconfig --name "$CLUSTER_NAME" >/dev/null 2>&1 || true

log "cluster nodes:"
kubectl get nodes -o wide 2>/dev/null || log "kubectl could not reach the cluster yet."
