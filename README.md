# Local cluster setup

This is the starting point for the shared k3d cluster. Terraform is used to create the cluster and deploy ArgoCD.

## Related apps

- Self-Hosted AI Gateway
  - [ai-lan](https://github.com/abellizzi1/ai-lan)
  - [ai-lan-config](https://github.com/abellizzi1/ai-lan-config)
- LAN monitoring
  - `../lanmark`: application, Linux discovery agent, Docker images/Compose
  - `../lanmark-config`: Kubernetes manifests, probes, alerts, Grafana dashboard

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

## Add Lanmark

Lanmark combines device inventory/approval, connection history, reliability probes,
and statistical anomaly incidents. The app runs in the `lanmark` namespace;
ARP discovery runs on a native Linux host on the home LAN. A k3d pod or Docker
Desktop host-network container cannot ARP-scan the physical Wi-Fi network.

The local application/config repositories are separate, following the `ai-lan`
layout. Publish them and their API/agent images before syncing. The registration
expects `https://github.com/abellizzi1/lanmark-config.git`; adjust both the
AppProject and Application if you choose another URL. For private repositories,
configure Argo repository credentials; `GITHUB_TOKEN` alone does not configure Argo.

1. Build/push `angelobellizzi/lanmark:0.1.0` and
   `angelobellizzi/lanmark-agent:0.1.0` from `../lanmark` (see its README).
2. Edit router/DNS targets and `expected_agents` in
   `../lanmark-config/base/config/lanmark.yaml`; commit and publish that repo.
3. In this repository's infra runner, set secrets and create the runtime Secret:

```bash
export LANMARK_API_TOKEN='<random admin token of 32+ characters>'
export LANMARK_AGENT_TOKEN='<different random ingestion token of 32+ characters>'
export GRAFANA_ADMIN_PASSWORD='<strong Grafana password>'
# Optional receiver for generic JSON incident events:
export NOTIFICATION_WEBHOOK_URL=''
bash scripts/configure-lanmark-secrets.sh
```

Generate tokens independently, for example with `openssl rand -hex 32` on your
workstation. Keep these values in a password manager or ignored local environment
file, never in Git. The agent receives only the ingestion token. Updating secrets
requires restarting Lanmark; an existing Grafana admin password must be changed
through Grafana rather than resetting its bootstrap environment variable.

4. Commit/publish the new registrations in `clusters/local`, then apply bootstrap
   if not already installed (`kubectl apply -k bootstrap`). The root application
   will register Lanmark. Its first sync is manual until configuration, images,
   and secrets are ready. Sync it in the Argo UI. To enable automatic reconciliation,
   add `automated: {prune: true, selfHeal: true, allowEmpty: false}` beneath its
   `spec.syncPolicy` and publish the change.
5. Point `lanmark.home.arpa` and `grafana.lanmark.home.arpa` at the Docker host
   in LAN DNS or hosts files. Access the API at `http://lanmark.home.arpa:8080/docs`
   and Grafana at `http://grafana.lanmark.home.arpa:8080` (adjust if `http_port`
   differs). Grafana login is `admin` with your password. Configure the Linux LAN
   agent using `../lanmark/agent.example.yaml` and `compose.agent.yaml`.

Only the API/Grafana have ingress routes, on separate hostnames from AI. The
current ingress is trusted-LAN HTTP; configure TLS or a VPN for other networks.
The monitoring stack requests 15Gi of persistent storage. Namespace/PVC pruning
is disabled, and the Application has no deletion finalizer.

Back up inventory/history/incidents at any time with
`bash scripts/backup-lanmark.sh`. Full measurement details and limitations are in
`../lanmark/README.md`; configuration and restore guidance are in
`../lanmark-config/README.md`.

## Teardown

Inside the infra container:

```bash
bash scripts/teardown.sh
```

This stops Argo reconciliation and the gateway, backs up AI PostgreSQL and an installed Lanmark SQLite database to `backups/`, and runs `terraform destroy`. Backup or API failures abort destruction.

**Teardown deletes the entire cluster and every local volume. Only AI PostgreSQL and Lanmark's SQLite database are backed up by this script.** Back up Prometheus history, Grafana state, Alertmanager silences, and other applications separately.
