# Local cluster setup

This is the starting point for the shared k3d cluster. Terraform is used to create the cluster and deploy ArgoCD.

## Related apps

- Self-Hosted AI Gateway
  - [ai-lan](https://github.com/abellizzi1/ai-lan)
  - [ai-lan-config](https://github.com/abellizzi1/ai-lan-config)

## Setup

### Infra container

```bash
docker compose build infra
docker compose run --rm --service-ports infra bash
```

Inside the container:

```bash
terraform init
terraform plan
terraform apply
```

### Starting ArgoCD

Export necessary environment variables and run `scripts/prepare-ai-lan.sh`:

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

### Access Argo CD

In the runner launched with `--service-ports`, retrieve the initial password and start port forwarding:

```bash
kubectl -n argocd port-forward --address 0.0.0.0 svc/argocd-server 8081:443 &
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
```

ArgoCD should now be accessible at `https://localhost:8081`.

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
