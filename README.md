# Local cluster setup

This is the starting point for the shared k3d cluster. Terraform creates the cluster and installs Argo CD; Argo CD deploys applications from Git.

[ai-lan-config](https://github.com/abellizzi1/ai-lan-config) provides AI manifests and image versions. Setup fetches what it needs from GitHub; no local clone is required. The [service source](https://github.com/abellizzi1/model-api) is only needed when building gateway images.

## Setup

Requires Docker and Docker Compose. Run from `cluster-config` on the host:

```bash
docker compose build infra
docker compose run --rm --service-ports infra bash
```

Inside the runner:

```bash
terraform init
terraform plan
terraform apply
```

For an existing deployment, keep its Terraform state and backups in this repository before applying. The bootstrap accepts Kubernetes 1.33-1.36; older clusters require a planned upgrade or backup-and-recreate migration.

Prepare AI credentials and data, reusing existing passwords when restoring. For a private AI config repo, also export `GITHUB_TOKEN` inside the runner with repository Contents read access:

```bash
export GATEWAY_ADMIN_USERNAME='admin'
export GATEWAY_API_KEY='<your-admin-password>'
export POSTGRES_PASSWORD='<your-postgres-password>'
export PROVIDER_API_KEY='<your-provider-api-key>'
bash scripts/prepare-ai-lan.sh
```

Preparation downloads only the PostgreSQL manifest from the repo and revision in `clusters/local/ai-lan-application.yaml`. It preserves existing tables or restores the newest dump in `backups/` into an empty database. Run it before registering the application. For Ollama, use `PROVIDER_API_KEY=ollama` and set the AI Application path in `clusters/local/ai-lan-application.yaml` to `overlays/ollama`.

Commit and push configuration changes first. If Git repos are private, configure their credentials in Argo CD before registration; the runner's `GITHUB_TOKEN` is separate. Then run:

```bash
kubectl apply -k bootstrap
kubectl -n argocd get applications
```

The AI site becomes available at `http://<your-host-LAN-IP>:8080`.

## Access Argo CD

In the runner launched with `--service-ports`, retrieve the initial password and start port forwarding:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
kubectl -n argocd port-forward --address 0.0.0.0 svc/argocd-server 8081:443
```

Open **https://localhost:8081** on the Docker host. Accept the self-signed certificate and sign in as `admin`. Change the initial password, then delete `argocd-initial-admin-secret`. The port-forward command stays running while you use the UI.

## Cluster maintenance

For a new maintenance session, run from this repository on the host:

```bash
docker compose run --rm infra bash
```

Connect inside the runner, then check status or create an online AI database backup:

```bash
bash scripts/connect-cluster.sh
kubectl get nodes
kubectl get pods -A
kubectl -n argocd get applications
bash scripts/backup-postgres.sh
```

- **Application updates:** commit image tags or manifests to the application's config repo. Argo CD syncs them automatically.
- **New applications:** add an AppProject and Application under `clusters/local/`, include them in its `kustomization.yaml`, and push.
- **Infrastructure updates:** rebuild the runner if its Dockerfile changes, then run `terraform plan` and `terraform apply`. Existing K3s clusters are not automatically upgraded.
- **Secret updates:** export the credential values, run `bash scripts/configure-ai-secrets.sh`, then `kubectl -n ai-lan rollout restart deployment/gateway`. Existing PostgreSQL passwords must also be changed in the database itself.

Keep Terraform state, kubeconfig, secrets, and backups out of Git. Copy database dumps somewhere secure outside this working directory.

## Teardown

Inside the connected runner:

```bash
bash scripts/teardown.sh
```

This stops Argo reconciliation and the gateway, backs up AI PostgreSQL to `backups/`, and runs `terraform destroy`. Backup or API failures abort destruction.

**Teardown deletes the entire cluster and every local volume. Only AI PostgreSQL is backed up by this script.** Back up other applications separately. After rebuilding, run AI preparation before registering applications to restore the database.

If teardown is cancelled or fails after stopping workloads, resume them:

```bash
kubectl -n argocd scale statefulset/argocd-application-controller --replicas=1
kubectl -n ai-lan scale deployment/gateway --replicas=1
```
