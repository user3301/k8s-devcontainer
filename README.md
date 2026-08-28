# k8s-devcontainer

A throwaway Kubernetes playground in a devcontainer. Spin it up, break things,
delete the cluster, start over — nothing touches your host cluster or your
host's Docker.

The cluster runs as [kind](https://kind.sigs.k8s.io) (Kubernetes in Docker)
inside a Docker-in-Docker devcontainer, so the whole environment — nodes
included — disappears when you delete the container.

## What's inside

| Tool | How it's installed |
| --- | --- |
| `kubectl` | `kubectl-helm-minikube` devcontainer feature |
| `helm` | `kubectl-helm-minikube` devcontainer feature |
| `kind` v0.33.0 | pinned download in `.devcontainer/install-tools.sh` |
| `grpcurl` v1.9.3 | pinned download in `.devcontainer/install-tools.sh` |
| GNU `make` | `build-essential` via apt |
| `docker` | `docker-in-docker` devcontainer feature |
| `go` | `go` devcontainer feature (handy for controllers/operators) |

## Quick start

Open the folder in VS Code and choose **Reopen in Container**. On first start
the container installs the tooling and creates a 3-node kind cluster
(1 control-plane + 2 workers) automatically.

When it finishes:

```bash
make verify     # confirm every tool is on PATH
make status     # nodes + all pods
```

Deploy the sample gRPC workload and poke at it with grpcurl:

```bash
make deploy
make grpc-list                  # discover services via server reflection
make grpc-describe              # inspect the API
grpcurl -plaintext localhost:30000 grpcbin.GRPCBin/Index
```

## Common tasks

```bash
make cluster                    # create the cluster (no-op if it exists)
make delete                     # tear it down
make recreate                   # delete + create
make deploy / make undeploy     # apply / remove manifests/
make logs                       # tail the sample app
make load IMAGE=myapp:dev       # push a locally-built image into the cluster
make ingress                    # install ingress-nginx (kind flavour)
make metrics                    # install metrics-server
```

Run `make` with no arguments for the full list.

### Using your own images

kind nodes have their own image store and cannot see your local Docker images.
Build, then load explicitly:

```bash
docker build -t myapp:dev .
make load IMAGE=myapp:dev
```

Use `imagePullPolicy: IfNotPresent` in your manifests, otherwise Kubernetes
tries to pull `myapp:dev` from a registry and fails.

## Ports

`extraPortMappings` in `kind-cluster.yaml` wires container ports through to the
devcontainer, and `forwardPorts` in `devcontainer.json` forwards them to your
real machine:

| Port | Purpose |
| --- | --- |
| 30000-30002 | NodePort range for experiments |
| 80 / 443 | ingress controller (control-plane is labelled `ingress-ready=true`) |

**Port mappings are fixed at cluster-creation time.** To expose a port outside
this range, add it to `kind-cluster.yaml` and then run `make recreate` — editing
the file alone does nothing to a running cluster.

To expose a Service, give it `type: NodePort` and a `nodePort` in the mapped
range; see `manifests/grpcbin.yaml` for a working example.

## Configuration

| Variable | Default | Effect |
| --- | --- | --- |
| `KIND_CLUSTER_NAME` | `playground` | cluster name |
| `AUTO_CREATE_CLUSTER` | `true` | set `false` to skip cluster creation on start |
| `KIND_VERSION` / `GRPCURL_VERSION` | pinned | override before a rebuild |

## Notes and gotchas

- **Resources.** kind wants headroom. Give Docker Desktop at least 4 CPUs and
  8 GB RAM, or the control-plane will fail to become ready.
- **The cluster survives container restarts** but not a container rebuild —
  a rebuild resets the Docker-in-Docker storage along with every node.
- **`kubectl` context** is `kind-playground`. `make cluster` prints it.
- **Slow first start.** Pulling the node image plus booting the control-plane
  takes a couple of minutes. Later starts reuse the existing cluster.
- **`Too many open files`** when pods crash-loop usually means the *host*
  inotify limits are too low. On Linux/WSL raise them on the host:
  `sysctl -w fs.inotify.max_user_watches=524288 fs.inotify.max_user_instances=512`.

## Why Docker-in-Docker?

kind creates Kubernetes nodes *as Docker containers*, so something inside the
devcontainer has to be a Docker daemon. The `docker-in-docker` feature provides
one; `post-start.sh` waits for it before creating the cluster.

The alternative is mounting the host's Docker socket
("docker-outside-of-docker"). This repo deliberately does not, because the nodes
would then be siblings on your *host* Docker: they outlive the devcontainer,
`extraPortMappings` land on the host directly and collide with whatever already
uses 80/443, and failed experiments leave orphaned node containers to clean up
by hand. With Docker-in-Docker, deleting the devcontainer takes the cluster with
it.

The tradeoff is that a container *rebuild* also wipes the Docker-in-Docker
storage — the cluster and any images you `make load`ed go with it. Restarts are
unaffected.

## Layout

```
.devcontainer/
  devcontainer.json     container definition, features, port forwarding
  install-tools.sh      kind, grpcurl, make + shell completions (runs once)
  post-start.sh         waits for docker, ensures the cluster exists
kind-cluster.yaml       cluster topology and port mappings
manifests/              sample workloads (kubectl apply -f manifests)
Makefile                cluster and workload shortcuts
```