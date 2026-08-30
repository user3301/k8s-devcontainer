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
| `kubectx` / `kubens` v0.11.0 | pinned download in `.devcontainer/install-tools.sh` |
| `fzf` | `apt` (powers kubectx/kubens interactive mode) |
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

### Switching context and namespace

`kubectx` and `kubens` are installed, along with `fzf` so both work
interactively:

```bash
kubectx                  # list contexts (no args = fzf picker)
kubectx kind-playground  # switch context
kubectx -                # switch back to the previous context
kubens                   # list namespaces (no args = fzf picker)
kubens kube-system       # switch the active namespace
```

The zsh setup adds `k`, `kctx` and `kns` aliases plus completions.

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
| `KIND_VERSION` / `GRPCURL_VERSION` / `KUBECTX_VERSION` | pinned | override before a rebuild |

## Adding or updating tooling

`install-tools.sh` runs from `onCreateCommand`, so it fires **once**, when the
container is created. Editing it does nothing to a container that is already
running. The script is idempotent, so just run it again:

```bash
bash .devcontainer/install-tools.sh   # from inside the devcontainer
exec zsh                              # pick up new aliases/completions
make verify
```

From the host, if you'd rather not open a shell first:

```bash
docker exec -u vscode -w /workspaces/k8s-devcontainer <container-id> \
  bash .devcontainer/install-tools.sh
```

Prefer this over **Rebuild Container** simply because it is much faster. Only a
rebuild picks up changes to `devcontainer.json` itself (features, ports,
`containerEnv`), because those are fixed at creation time.

### Feature versions

`devcontainer.json` refers to features by floating major tag (`common-utils:2`,
`docker-in-docker:4`, ...), so the actual version resolved at build time drifts.
`.devcontainer/devcontainer-lock.json` pins each one to an exact version and
SHA-256 digest, and **is checked in** — same reasoning as the pinned
`KIND_VERSION` / `KUBECTX_VERSION` in `install-tools.sh`, and the same role
`package-lock.json` plays for npm.

To deliberately pick up newer features, delete the lockfile and rebuild, then
commit the regenerated file alongside any `devcontainer.json` change.

## Notes and gotchas

- **Resources.** kind wants headroom. Give Docker Desktop at least 4 CPUs and
  8 GB RAM, or the control-plane will fail to become ready.
- **The cluster outlives both restarts and rebuilds.** The Docker-in-Docker
  feature mounts `/var/lib/docker` as a named volume keyed by
  `${devcontainerId}`, which the spec guarantees is stable across rebuilds, so
  the nodes and any `make load`ed images survive. To really start clean, delete
  the volume (`docker volume ls | grep dind-var-lib-docker`) or just run
  `make recreate`, which is usually what you actually want.
- **Stale shells.** Terminals opened before a tooling change won't have the new
  aliases or completions. Run `exec zsh`.
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

A second benefit is insulation from host Docker settings. Docker Desktop's
"Use containerd for pulling and storing images" is known to break
`kind load docker-image`
([kind#4236](https://github.com/kubernetes-sigs/kind/issues/4236)), but the
inner daemon has its own `/var/lib/docker` and `/var/lib/containerd` volumes and
default configuration, so `make load` here is unaffected by whatever the host is
set to.

Note that the cluster is *not* torn down by a rebuild — those volumes are keyed
by `${devcontainerId}`, which is stable across rebuilds. See the notes above for
how to genuinely start clean.

## Starting from the CLI

If you'd rather not use VS Code, the
[devcontainers CLI](https://github.com/devcontainers/cli) builds and runs the
same container from this repo's config:

```bash
npm install -g @devcontainers/cli

devcontainer up --workspace-folder .          # build + start (first run: several min)
devcontainer exec --workspace-folder . bash   # get a shell inside
```

Once inside, everything works as documented above:

```bash
make verify
make status
make deploy && make grpc-list
```

Useful variants:

```bash
# recreate the container (the kind cluster survives - see the DinD note above)
devcontainer up --workspace-folder . --remove-existing-container

# run a one-off command without an interactive shell
devcontainer exec --workspace-folder . kubectl get nodes

# check the config parses without starting anything (still needs a running daemon)
devcontainer read-configuration --workspace-folder .
```

The CLI needs a **running Docker daemon on the host** — every subcommand,
including `read-configuration`, shells out to `docker` and fails with a bare
exit 1 if the daemon is down. Start Docker Desktop first.

On **Docker Desktop + WSL2**, also check that WSL integration is enabled for
your distro (Settings → Resources → WSL integration). Without it, `docker` in
WSL is a shim that reports `The command 'docker' could not be found in this
WSL 2 distro` even though Docker Desktop is running perfectly well on the
Windows side.

Two differences from the VS Code flow: the CLI ignores everything under
`customizations.vscode` (extensions and settings are a VS Code concern), and it
does not forward `forwardPorts` for you. Port mappings still work, because
`extraPortMappings` in `kind-cluster.yaml` publishes them on the devcontainer
itself — but reaching them from the host may need an explicit
`docker port` lookup or an `--publish` on the underlying container.

## Layout

```
.devcontainer/
  devcontainer.json     container definition, features, port forwarding
  devcontainer-lock.json  resolved feature versions + digests (committed)
  install-tools.sh      kind, grpcurl, make + shell completions (runs once)
  post-start.sh         waits for docker, ensures the cluster exists
kind-cluster.yaml       cluster topology and port mappings
manifests/              sample workloads (kubectl apply -f manifests)
Makefile                cluster and workload shortcuts
```