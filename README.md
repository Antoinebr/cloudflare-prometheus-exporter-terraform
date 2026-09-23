# Cloudflare Prometheus Exporter — Terraform Deployment

> Reproducible deployment of the [cloudflare-prometheus-exporter](https://github.com/cloudflare/cloudflare-prometheus-exporter) using Terraform + Wrangler.

## Attribution

The core Cloudflare Prometheus Exporter code (Worker, Durable Objects, GraphQL queries, and REST client) comes from the official Cloudflare repository:

**https://github.com/cloudflare/cloudflare-prometheus-exporter**

This repository adds Terraform-based deployment automation, Wrangler configuration generation, and local development tooling around that upstream code. All exporter logic remains the work of Cloudflare.

## What it does

A Cloudflare Worker that exposes Prometheus-formatted metrics for every zone and account you have access to.

## Structure

```
.
├── src/                        # Source code (Worker + Durable Objects)
├── test/                       # Tests
├── terraform/                  # IaC — KV namespace + wrangler.jsonc generation
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── providers.tf
│   └── versions.tf
├── wrangler.jsonc.tpl          # Terraform template → wrangler.jsonc
├── wrangler.jsonc.dev          # Local dev config for `wrangler dev`
├── Makefile                    # CLI shortcuts
├── terraform.tfvars.example    # Configuration template
└── README.md                   # This file
```

## Prerequisites

| Tool | Version |
|------|---------|
| [Bun](https://bun.sh) | latest (or Node.js >= 20 + npm) |
| [Terraform](https://developer.hashicorp.com/terraform/downloads) | >= 1.5 |
| [Wrangler](https://developers.cloudflare.com/workers/wrangler/install-and-update/) | >= 4.x (installed automatically by the project) |

## Required Cloudflare tokens

### 1. Token for Terraform / Wrangler (deployment)

Minimum permissions:
- `Workers Scripts` **Edit**
- `Workers KV Storage` **Edit**
- `Account` **Read**

### 2. Token for the Worker (scraping)

This token is consumed **by the Worker** when querying the Cloudflare API:

| Permission | Scope | Required |
|------------|-------|----------|
| Zone > Analytics | Read | Yes |
| Account > Account Analytics | Read | Yes |
| Account > Workers Scripts | Read | Yes |
| Zone > SSL and Certificates | Read | No |
| Zone > Firewall Services | Read | No |
| Zone > Load Balancers | Read | No |
| Account > Logs | Read | No |
| Account > Magic Transit | Read | No |

Quick link (pre-filled): [Create token](https://dash.cloudflare.com/profile/api-tokens?permissionGroupKeys=%5B%7B%22key%22%3A%22analytics%22%2C%22type%22%3A%22read%22%7D%2C%7B%22key%22%3A%22account_analytics%22%2C%22type%22%3A%22read%22%7D%2C%7B%22key%22%3A%22workers_scripts%22%2C%22type%22%3A%22read%22%7D%2C%7B%22key%22%3A%22ssl_and_certificates%22%2C%22type%22%3A%22read%22%7D%2C%7B%22key%22%3A%22firewall_services%22%2C%22type%22%3A%22read%22%7D%2C%7B%22key%22%3A%22load_balancers%22%2C%22type%22%3A%22read%22%7D%2C%7B%22key%22%3A%22account_logs%22%2C%22type%22%3A%22read%22%7D%2C%7B%22key%22%3A%22magic_transit%22%2C%22type%22%3A%22read%22%7D%5D&name=Cloudflare%20Prometheus%20Exporter)

## Deployment

```bash
# 1. Clone
cd /home/code/cloudflare-prometheus-exporter

# 2. Configure
cp terraform.tfvars.example terraform/terraform.tfvars
# Edit terraform/terraform.tfvars with your tokens

# 3. Deploy (Terraform creates the KV namespace, generates wrangler.jsonc, then wrangler deploy)
make init
make apply
```

Or without the Makefile:

```bash
cd terraform
terraform init
terraform apply
```

## Terraform variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `cloudflare_account_id` | `string` | — | Cloudflare account ID |
| `cloudflare_api_token` | `string` | — | Token for Terraform / Wrangler |
| `worker_name` | `string` | `cloudflare-prometheus-exporter` | Worker name |
| `CLOUDFLARE_API_TOKEN_secret` | `string` | — | Token consumed BY the Worker |
| `BASIC_AUTH_USER` | `string` | `""` | Basic Auth user (optional) |
| `BASIC_AUTH_PASSWORD` | `string` | `""` | Basic Auth password (optional) |
| `deploy_on_apply` | `bool` | `true` | Auto-deploy on `apply` |

## Local development

```bash
# wrangler.jsonc.dev is used for local dev (empty KV id → auto preview)
make dev
```

## Quick Start — Scrape the Worker

Once deployed, the Worker exposes `/metrics` as `text/plain` (native Prometheus format).

### Endpoint URL

```
https://your-domain.workers.dev/metrics
```

### HTTP Basic Auth

- **User:** `admin`
- **Password:** `changeme` *(configured via Wrangler secrets, see `terraform.tfvars`)*

### Quick checks (curl)

```bash
# Health check
curl -s -u admin:changeme https://your-domain.workers.dev/health
# → {"status":"healthy","timestamp":"...","checks":{"cloudflare_api":{"status":"healthy"},"graphql_api":{"status":"healthy"}}}

# Scrape metrics (first 10 lines)
curl -s -u admin:changeme https://your-domain.workers.dev/metrics | head -10
# → # HELP cloudflare_exporter_up Exporter health
# → # TYPE cloudflare_exporter_up gauge
# → cloudflare_exporter_up 1
# → cloudflare_accounts 1
# → cloudflare_zones 6
# → cloudflare_zones_filtered 6
# → cloudflare_zones_processed 3
```

### Prometheus config (`prometheus.yml`)

```yaml
scrape_configs:
  - job_name: 'cloudflare'
    scrape_interval: 60s
    scrape_timeout: 30s
    basic_auth:
      username: 'admin'
      password: 'changeme'
    static_configs:
      - targets: ['your-domain.workers.dev']
```

### Run Prometheus locally (Docker Compose)

```bash
# Update prometheus.yml with your worker credentials, then:
docker compose up prometheus
```

> The project already includes a `prometheus.yml` + `docker-compose.yml` at the root.

---

## Secrets

Secrets (`CLOUDFLARE_API_TOKEN`, `BASIC_AUTH_USER`, `BASIC_AUTH_PASSWORD`) are managed automatically by Terraform via Wrangler.

To update manually:

```bash
make secrets TOKEN=xxx USER=admin PASS=xxx
```

## Prometheus configuration

```yaml
scrape_configs:
  - job_name: 'cloudflare'
    scrape_interval: 60s
    scrape_timeout: 30s
    static_configs:
      - targets: ['your-domain.workers.dev']
```

With Basic Auth:

```yaml
    basic_auth:
      username: 'admin'
      password: 'xxx'
```

## Cleanup

```bash
make clean      # Remove generated wrangler.jsonc + local state
make destroy    # Destroy the KV namespace via Terraform (the Worker remains — delete manually)
```

> **Note:** `terraform destroy` does not delete the Worker because it is managed by Wrangler, not Terraform. Use `wrangler delete` or the Cloudflare dashboard to remove it.

## License

MIT (same as the upstream project).
