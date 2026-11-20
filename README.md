# Local cluster setup

This is the starting point for the shared k3d cluster. Terraform is used to create the cluster and deploy ArgoCD.

Traefik shares one HTTP port (default `8080`) between applications:

| Application | URL on the Docker host | URL from another LAN device |
| --- | --- | --- |
| Argo CD | `http://localhost:8080/argocd/` | `http://<HOST_LAN_IP>:8080/argocd/` |
| AI Gateway | `http://localhost:8080/ai/` | `http://<HOST_LAN_IP>:8080/ai/` |

Opening `/` on either address redirects to `/argocd/`.

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

### Access Argo CD

In the infra container, retrieve the initial password:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
```

Argo CD is accessible at `http://localhost:8080/argocd/` (substitute your Terraform `http_port` if changed). Use the `admin` username and the password retrieved above.

### Using Ollama

Set the AI Application path in `clusters/local/ai-lan-application.yaml` to `overlays/ollama`, and export the following environment variable:

```bash
export PROVIDER_API_KEY='ollama'
```

The path can also be edited in ArgoCD to `overlays/ollama` post-deployment.

## Teardown

Inside the infra container:

```bash
bash scripts/teardown.sh
```

This stops Argo reconciliation and the gateway, backs up AI PostgreSQL to `backups/`, and runs `terraform destroy`. Backup or API failures abort destruction.

**Teardown deletes the entire cluster and every local volume. Only AI PostgreSQL is backed up by this script.** Back up other applications separately.
