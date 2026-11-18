# Local cluster setup

This is the starting point for the shared k3d cluster. Terraform is used to create the cluster and deploy ArgoCD.

Traefik shares one HTTP port (default `8080`) between applications:

| Application | URL on the Docker host | URL from another LAN device |
| --- | --- | --- |
| Argo CD | `http://localhost:8080/argocd/` | `http://<HOST_LAN_IP>:8080/argocd/` |
| Hearth AI | `http://localhost:8080/ai/` | `http://<HOST_LAN_IP>:8080/ai/` |

Opening `/` on either address redirects to `/argocd/`. The AI ingress requires `/ai` or a child path; it does not serve the site root.

The shared port binds to all host interfaces, including for Argo CD. This setup uses HTTP on a trusted LAN. MetalLB and a separate Argo CD NodePort are not required.

## Related apps

- Self-Hosted AI Gateway
  - [ai-lan](https://github.com/abellizzi1/ai-lan)
  - [ai-lan-config](https://github.com/abellizzi1/ai-lan-config)

## Setup

### Infra container

```bash
docker compose build infra
docker compose run --rm infra bash
```

Inside the container:

```bash
terraform init
terraform plan
terraform apply
```

### Starting ArgoCD

Export necessary environment variables:

```bash
export GITHUB_TOKEN='<token>'  # optional if any repos are private
export GATEWAY_ADMIN_USERNAME='admin'
export GATEWAY_API_KEY='<your-admin-password>'
export POSTGRES_PASSWORD='<your-postgres-password>'
export PROVIDER_API_KEY='<your-provider-api-key>'
```

Then run:

```bash
./scripts/prepare-ai-lan.sh
kubectl apply -k bootstrap
```

Bootstrap creates a missing cluster or starts an existing one.

Both `local-cluster` and `ai-lan` use manual sync by default. After registering `bootstrap/`, open Argo CD and **Sync** `local-cluster` to register its child applications, then **Sync** `ai-lan` to deploy the workloads.

### Access Argo CD

In the infra container, retrieve the initial password:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
```

Argo CD is accessible at `http://localhost:8080/argocd/` (substitute your Terraform `http_port` if changed). Use the `admin` username and the password retrieved above.

The AI UI is at `http://localhost:8080/ai/` after running AI data preparation and registering `bootstrap/`; Terraform alone installs Argo CD. Its API endpoint is `/ai/v1/chat/completions`. Traefik redirects `/` to `/argocd/`, and `/argocd` and `/ai` to their trailing-slash URLs. Argo CD handles its own `/argocd` prefix; Traefik strips `/ai` before forwarding to the gateway, which uses `ROOT_PATH=/ai` for generated URLs and session-cookie scope. Ingress rules have no hostname restriction, so localhost and the host's LAN address use the same routes.

For the Argo CD CLI over this HTTP ingress:

```bash
argocd login localhost:8080 --plaintext --grpc-web --grpc-web-root-path /argocd
```

### Migrating from separate ports

1. Build and push the gateway image containing subpath support (`angelobellizzi/ai-gateway:1.0.3`) from the `ai-lan` repository before deploying the matching `ai-lan-config` changes. The previously deployed image does not support the new frontend URLs.
2. Commit/push the config changes to the revisions tracked by Argo CD. From the infra runner, run `terraform apply` to install the Argo CD ingress and restart its server with the new base path. Existing cluster nodes and volumes are reused.
3. Run `kubectl apply -k bootstrap` and `kubectl apply -f clusters/local/ai-lan-project.yaml` to allow the AI application's Traefik Middleware resources, then sync the `ai-lan` application in Argo CD. For a first deployment, complete AI data preparation before registering `bootstrap/` as described above.
4. Open the new URLs above. Existing accounts and conversations remain in PostgreSQL; sign in again if needed. Update API clients to use `/ai/auth/login` and `/ai/v1/chat/completions`.

The `argocd_http_port` Terraform variable has been removed; remove any corresponding value from your own variable files. New clusters publish only the shared application port. An existing cluster may retain its old Docker port mapping for `8082`, but the Argo CD service is now ClusterIP, so NodePort `30080` no longer serves it. No cluster recreation is needed for the new routes; this change does not alter existing Docker port mappings.

### Using Ollama

In Argo CD, open the `ai-lan` application's details and edit its source path from `overlays/lan` to `overlays/ollama`. Save, then click **Sync** to apply the change. Switch back to `overlays/lan` in the same way. The Git manifest retains `overlays/lan` as the initial default; no Git edit is required to switch an existing deployment.

The parent `local-cluster` application ignores changes to the child's source path and automated-sync policy, including during manual parent syncs. Both applications have automatic sync disabled by default; the UI can still enable it when desired. Changing a path with automatic sync disabled does not deploy it until you click **Sync**.

The `ai-lan` AppProject permits Application resource actions in `argocd`, which allows the UI's Enable/Disable Auto-Sync actions. Commit and push these project settings before manually syncing the parent from Git so older project permissions are not restored.

For Ollama secret configuration, use:

```bash
export PROVIDER_API_KEY='ollama'
```

If you update secrets, run `scripts/configure-ai-secrets.sh` with the other required credentials exported, then restart the gateway to pick up the change.

## Teardown

Inside the infra container:

```bash
bash scripts/teardown.sh
```

This stops Argo reconciliation and the gateway, backs up AI PostgreSQL to `backups/`, and runs `terraform destroy`. Backup or API failures abort destruction.

**Teardown deletes the entire cluster and every local volume. Only AI PostgreSQL is backed up by this script.** Back up other applications separately.
