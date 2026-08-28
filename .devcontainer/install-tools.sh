#!/usr/bin/env bash
# Installs tooling that is not covered by devcontainer features:
#   - GNU make (+ build essentials)
#   - kind (Kubernetes in Docker)
#   - grpcurl
# kubectl, helm, docker and go come from features in devcontainer.json.
set -euo pipefail

KIND_VERSION="${KIND_VERSION:-v0.33.0}"
GRPCURL_VERSION="${GRPCURL_VERSION:-1.9.3}"

log() { echo "[install-tools] $*"; }

arch="$(uname -m)"
case "$arch" in
  x86_64 | amd64) ARCH="amd64" ;;
  aarch64 | arm64) ARCH="arm64" ;;
  *)
    echo "[install-tools] unsupported architecture: $arch" >&2
    exit 1
    ;;
esac
log "detected architecture: ${ARCH}"

SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  SUDO="sudo"
fi

log "installing apt packages (make, curl, jq, ...)"
export DEBIAN_FRONTEND=noninteractive
$SUDO apt-get update -y
$SUDO apt-get install -y --no-install-recommends \
  build-essential \
  ca-certificates \
  curl \
  jq \
  bash-completion
$SUDO rm -rf /var/lib/apt/lists/*

tmp="$(mktemp -d)"
cleanup() { rm -rf "$tmp"; }
trap cleanup EXIT

log "installing kind ${KIND_VERSION}"
curl -fsSL -o "${tmp}/kind" \
  "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-${ARCH}"
$SUDO install -m 0755 "${tmp}/kind" /usr/local/bin/kind

log "installing grpcurl ${GRPCURL_VERSION}"
grpcurl_arch="$ARCH"
if [ "$ARCH" = "amd64" ]; then
  grpcurl_arch="x86_64"
fi
curl -fsSL -o "${tmp}/grpcurl.tar.gz" \
  "https://github.com/fullstorydev/grpcurl/releases/download/v${GRPCURL_VERSION}/grpcurl_${GRPCURL_VERSION}_linux_${grpcurl_arch}.tar.gz"
tar -xzf "${tmp}/grpcurl.tar.gz" -C "$tmp" grpcurl
$SUDO install -m 0755 "${tmp}/grpcurl" /usr/local/bin/grpcurl

log "configuring shell completions"
completion_dir="${HOME}/.local/share/bash-completion/completions"
mkdir -p "$completion_dir"
kubectl completion bash >"${completion_dir}/kubectl" 2>/dev/null || true
kind completion bash >"${completion_dir}/kind" 2>/dev/null || true
helm completion bash >"${completion_dir}/helm" 2>/dev/null || true

if [ -f "${HOME}/.zshrc" ]; then
  zsh_completion_dir="${HOME}/.zfunc"
  mkdir -p "$zsh_completion_dir"
  kubectl completion zsh >"${zsh_completion_dir}/_kubectl" 2>/dev/null || true
  kind completion zsh >"${zsh_completion_dir}/_kind" 2>/dev/null || true
  helm completion zsh >"${zsh_completion_dir}/_helm" 2>/dev/null || true
  if ! grep -q "zfunc" "${HOME}/.zshrc"; then
    {
      echo ''
      echo '# k8s playground completions'
      echo 'fpath=(~/.zfunc $fpath)'
      echo 'autoload -Uz compinit && compinit'
      echo 'alias k=kubectl'
      echo 'compdef k=kubectl 2>/dev/null || true'
    } >>"${HOME}/.zshrc"
  fi
fi

log "versions:"
kind --version
kubectl version --client=true 2>/dev/null | head -n 1 || true
helm version --short 2>/dev/null || true
grpcurl --version 2>&1 | head -n 1 || true
make --version | head -n 1

log "done"
