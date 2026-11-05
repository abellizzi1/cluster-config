# Local cluster infrastructure and GitOps

Start here to create and operate the shared local Kubernetes cluster. This repository owns the infrastructure runner image, Terraform, operator scripts, and Argo CD application registrations.

Terraform creates k3d and installs Argo CD. After that bootstrap, Argo CD deploys applications from their configuration repositories. Application source repositories are needed when changing application code, rather than when creating the cluster.

## Repositories and layout

Keep these checkouts beside each other:

```text
workspace/
  cluster-config/    # Start here: infrastructure and Argo CD registrations
  ai-lan-config/     # AI manifests, browser files, and deployed image version
  ai-lan/            # Optional for deployment: gateway source and service Dockerfile
```

| Repository | Purpose |
| --- | --- |
| [cluster-config](https://github.com/abellizzi1/cluster-config) | Cluster creation, infrastructure Dockerfile, Terraform state, backups, and Argo CD registrations. |
| [ai-lan-config](https://github.com/abellizzi1/ai-lan-config) | AI workload manifests, frontend assets, provider/model configuration, and gateway image tag. Required alongside this checkout for initial AI data preparation. |
| [ai-lan source checkout](https://github.com/abellizzi1/model-api) | Gateway source, manual Docker Hub image publishing, and application usage. Not required to build the cluster. |

| Path in this repo | Purpose |
| --- | --- |
| `Dockerfile.infra`, `compose.yaml` | Linux infrastructure runner containing Docker CLI, Terraform, k3d, and kubectl. |
| `*.tf` | Shared cluster creation and pinned Argo CD installation. |
| `scripts/` | Cluster connection, Argo installation, AI secrets/data preparation, backups, and teardown. |
| `bootstrap/` | Operator-managed bootstrap project and `local-cluster` root Application. |
| `clusters/local/` | Projects and child Applications watched by the root Application. |
| `backups/`, `terraform.tfstate*`, `.kubeconfig` | Ignored local runtime data; never commit these. |

## Existing installations: move infrastructure ownership first

Infrastructure previously lived in `ai-lan`. Its Dockerfile, Compose file, Terraform files, and scripts now live here. Existing local Terraform state, kubeconfig, private infrastructure variables/environment files, and backups must accompany that move before running Terraform. Do not initialize a second independent state for the same cluster.

When applying these changes to another checkout, move the ignored runtime files from the old infrastructure directory into this repository, without overwriting any existing destination files. Retain backup copies securely. Do not copy the old repository's `.git/` or personal `.codex/` configuration. Regenerate `.terraform/` with `terraform init`.

The resource address `terraform_data.cluster`, default cluster name `ai-lan`, and container path `/workspace` are unchanged. Inspect `terraform plan` before applying; investigate unexpected cluster replacement. Older state may still include the removed image/application resources; those had no Kubernetes destroy provisioners and can leave Terraform state without deleting workloads.

The bootstrap accepts Kubernetes 1.33-1.36; new clusters use `rancher/k3s:v1.34.3-k3s1` and Argo CD `v3.5.6`. An older Kubernetes 1.31 cluster is not automatically upgraded. If using a backup-and-recreate migration, back up its data with a compatible existing runner, intentionally run teardown, create the new cluster, and restore before registering applications. Recreating a cluster destroys every project's local volumes.

## Create the cluster

A running Docker daemon, Docker Compose, and the sibling `ai-lan-config` checkout are required. From the workspace parent, clone any missing configuration repos:

```bash
git clone https://github.com/abellizzi1/cluster-config.git
git clone https://github.com/abellizzi1/ai-lan-config.git
cd cluster-config
```

For existing checkouts, just open `cluster-config`. Build and launch its runner:

```bash
docker compose build infra
docker compose run --rm --service-ports infra bash
```

Compose mounts this repository at `/workspace`, the sibling AI configuration at `/ai-lan-config` read-only, and the host Docker socket. The sibling bind mount fails if its directory is missing. No `ai-lan` source checkout is mounted or required.

Inside the runner:

```bash
terraform init
terraform plan
terraform apply
```

This creates the cluster and installs Argo CD; it does not register application workloads yet. `KUBECONFIG=/workspace/.kubeconfig` is set by Compose. Each fresh runner must connect to the cluster network:

```bash
bash scripts/connect-cluster.sh
```

Use `TF_VAR_cluster_name` and matching `CLUSTER_NAME` exports for a nondefault cluster. `http_port` defaults to `8080`; `k3s_image` only affects new clusters. Changing it does not upgrade an existing cluster. The bootstrap validates the Kubernetes version before installing Argo.

## Prepare the AI application

Set runtime credentials inside the runner, reusing existing passwords when preserving or restoring a database:

```bash
export GATEWAY_ADMIN_USERNAME='admin'
export GATEWAY_API_KEY='<your-admin-password>'
export POSTGRES_PASSWORD='<your-postgres-password>'
export PROVIDER_API_KEY='<your-provider-api-key>'
bash scripts/prepare-ai-lan.sh
```

The script reads manifests from `AI_LAN_CONFIG_DIR`, which Compose sets to `/ai-lan-config`; outside Compose it defaults to the sibling checkout. It creates the externally managed `gateway-secrets` Secret, starts PostgreSQL, and restores the newest timestamped `backups/postgres-*.dump` into an empty database before the gateway starts. Existing tables are preserved. Restore failures roll back the transaction. Move dumps elsewhere beforehand if intentionally starting with an empty database.

Preparation refuses to run once the Argo `ai-lan` Application is registered, to avoid racing a running gateway. Later secret updates use `bash scripts/configure-ai-secrets.sh`, followed by `kubectl -n ai-lan rollout restart deployment/gateway`. Changing the PostgreSQL Secret does not change an existing database role password; rotate that password separately in PostgreSQL.

Hosted inference uses the provider/model settings in `ai-lan-config/base/kustomization.yaml`. For local inference, set `PROVIDER_API_KEY=ollama` and change the child Application's `spec.source.path` to `overlays/ollama` before first registration. That overlay adds Ollama and downloads `gemma3:270m`. Model changes also require updating its pull command and readiness probe.

Credentials stay outside Git. For migration, the secret script also accepts the old `TF_VAR_gateway_api_key`, `TF_VAR_gateway_admin_username`, `TF_VAR_postgres_password`, and `TF_VAR_provider_api_key` exports. Remove obsolete application settings from private Terraform variable files/CLI flags; provider/model choices now live in the application configuration repo.

## Register applications with Argo CD

The bootstrap project and root Application use `https://github.com/abellizzi1/cluster-config.git` at `clusters/local`. The AI project and child Application use `https://github.com/abellizzi1/ai-lan-config.git` at `overlays/lan` (or `overlays/ollama`). Both Applications track `main`.

Commit and push registration changes before bootstrap: Argo reads Git remotes, not local working files. For private repositories, add credentials through Argo CD's repository settings or Kubernetes Secrets first. Do not commit tokens or SSH keys. For a private Docker Hub image, provision an image pull Secret as described in the AI configuration README.

After AI secrets and any database restoration are ready, run inside the runner from `/workspace`:

```bash
kubectl apply -k bootstrap
kubectl -n argocd get applications
```

Once Argo's first sync creates the gateway:

```bash
kubectl -n ai-lan rollout status deployment/gateway --timeout=300s
```

The root creates projects before child Application registrations. Children reconcile independently; root sync waves do not order workloads across applications. Bootstrap files are operator-managed; reapply `kubectl apply -k bootstrap` after changing them.

The root syncs and repairs drift but does not prune registrations. The AI child also prunes removed workloads. Namespace and data PVCs opt out of pruning/deletion. Applications have no cascading deletion finalizers, so deleting a registration leaves workloads running. To decommission, remove the definition from Git, explicitly delete its registration, then remove workloads after backing up data. Removing only a child file does not stop its existing registration.

Restrict write access to this repository to trusted administrators: AppProject/Application registration grants deployment control. Each application project should limit its Git sources, destination namespace, and resource types.

## Open Argo CD and the AI site

From the runner started with `--service-ports`:

```bash
kubectl -n argocd port-forward --address 0.0.0.0 svc/argocd-server 8081:443
```

Open `https://localhost:8081` on the Docker host and accept the initial self-signed certificate. The host binding is loopback-only. In a second shell, run `docker compose run --rm infra bash` from this repository, connect with `bash scripts/connect-cluster.sh`, and obtain the initial admin password:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
```

Sign in as `admin`, change the password, and delete `argocd-initial-admin-secret`. AI ingress remains available at `http://<your-host-LAN-IP>:8080`. The AI application currently serves HTTP on a trusted LAN; HTTPS is not configured for it.

## Publish an AI service update

Edit gateway code in `ai-lan`, then manually build and push from that repository:

```bash
docker build -t angelobellizzi/ai-gateway:0.0.2 services/gateway
docker push angelobellizzi/ai-gateway:0.0.2
```

Update `images[0].newTag` in `ai-lan-config/overlays/lan/kustomization.yaml`, commit, and push that repository. Both AI overlays inherit the tag. Argo detects the commit and deploys it; allow time for polling or refresh/sync in its UI. Use a new immutable tag for every build. No Terraform apply or service image build runs during application sync.

Browser files and provider/model settings live in `ai-lan-config`. Their generated ConfigMap hashes roll affected pods on updates. Rolling an image tag back does not undo database schema changes.

## Backups and teardown

From this repository's runner:

```bash
# Online AI database backup; keeps the cluster running.
bash scripts/backup-postgres.sh
```

Dumps are saved in this repository's ignored `backups/` directory. Keep a secure copy outside the cluster and outside this working directory.

For an intentional teardown:

```bash
bash scripts/teardown.sh
```

This stops Argo reconciliation and the AI gateway, backs up PostgreSQL, then invokes `terraform destroy`. API errors and backup failures abort destruction. If cancelled or failed, resume the Argo controller with `kubectl -n argocd scale statefulset/argocd-application-controller --replicas=1`. Argo restores gateway replicas; before Argo adoption, restore the gateway explicitly with `kubectl -n ai-lan scale deployment/gateway --replicas=1`.

Teardown destroys every application and local volume in the shared cluster. These scripts only back up AI PostgreSQL; add backup procedures for other stateful applications before cluster teardown. Argo PVC protection does not survive cluster deletion. After recreation, run AI preparation to restore data before registering the root Application. Ollama models are downloaded again.

## Add another project

1. Create its application configuration repo, namespace plan, runtime secrets, and any data restoration/backup procedure.
2. Add its AppProject and Application to `clusters/local/`, with unique names, its Git URL/path, destination namespace, and required resource permissions.
3. Add both files to `clusters/local/kustomization.yaml` and push this repo. The root registers the project alongside AI.
4. Give its ingress an explicit hostname with LAN DNS/hosts entries; AI currently has a catch-all route on port 8080.

Monitoring components that need ClusterRoles or other cluster-scoped resources require explicit AppProject permissions.

## Validate configuration

Use the runner for `terraform fmt -check -diff`, `terraform validate` after initialization, and `bash -n scripts/<changed-script>.sh`. Render `bootstrap` and `clusters/local` with `kubectl kustomize`; render both AI overlays from `/ai-lan-config/overlays/`. Run `git diff --check` in each changed repository. Validation does not require deploying the stack.
