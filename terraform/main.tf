# ------------------------------------------------------------------------------
# Cloudflare Prometheus Exporter — Infrastructure as Code
# ------------------------------------------------------------------------------

data "cloudflare_account" "this" {
  account_id = var.cloudflare_account_id
}

# Create the KV namespace for runtime configuration
resource "cloudflare_workers_kv_namespace" "config" {
  account_id = var.cloudflare_account_id
  title      = "${var.worker_name}-config"
}

# Generate wrangler.jsonc with the real KV namespace ID
resource "local_file" "wrangler_config" {
  content = templatefile("${path.module}/../wrangler.jsonc.tpl", {
    account_id      = var.cloudflare_account_id
    worker_name     = var.worker_name
    kv_namespace_id = cloudflare_workers_kv_namespace.config.id
  })
  filename = abspath("${path.module}/../wrangler.jsonc")

  lifecycle {
    replace_triggered_by = [cloudflare_workers_kv_namespace.config]
  }
}

# Deploy the worker via Wrangler (only reliable way for DO + migrations)
resource "null_resource" "deploy" {
  count = var.deploy_on_apply ? 1 : 0

  triggers = {
    # Redeploy if source code changes
    src_hash = sha256(join("", [
      for f in fileset("${path.module}/../src", "**/*") :
      filesha256("${path.module}/../src/${f}")
    ]))
    package_hash   = filesha256("${path.module}/../package.json")
    wrangler_hash  = sha256(local_file.wrangler_config.content)
    secret_token   = nonsensitive(sha256(var.CLOUDFLARE_API_TOKEN_secret))
    secret_user    = nonsensitive(sha256(var.BASIC_AUTH_USER))
    secret_pass    = nonsensitive(sha256(var.BASIC_AUTH_PASSWORD))
    worker_name    = var.worker_name
  }

  provisioner "local-exec" {
    working_dir = path.module
    environment = {
      CLOUDFLARE_API_TOKEN = var.cloudflare_api_token
    }
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      cd "${abspath("${path.module}/..")}"
      echo "[terraform] Installing dependencies..."
      if command -v bun &>/dev/null; then
        bun install
        WRANGLER="bunx wrangler"
      else
        echo "bun not found, falling back to npm"
        npm install
        WRANGLER="npx wrangler"
      fi
      echo "[terraform] Setting secrets..."
      printf '%s' "${replace(var.CLOUDFLARE_API_TOKEN_secret, "\"", "\\\"")}" | $WRANGLER secret put CLOUDFLARE_API_TOKEN --name ${var.worker_name}
      %{if var.BASIC_AUTH_USER != ""~}
      printf '%s' "${replace(var.BASIC_AUTH_USER, "\"", "\\\"")}" | $WRANGLER secret put BASIC_AUTH_USER --name ${var.worker_name}
      printf '%s' "${replace(var.BASIC_AUTH_PASSWORD, "\"", "\\\"")}" | $WRANGLER secret put BASIC_AUTH_PASSWORD --name ${var.worker_name}
      %{endif~}
      echo "[terraform] Deploying worker ${var.worker_name}..."
      $WRANGLER deploy
      echo "[terraform] Deployment complete."
    EOT
  }

  depends_on = [local_file.wrangler_config]
}
