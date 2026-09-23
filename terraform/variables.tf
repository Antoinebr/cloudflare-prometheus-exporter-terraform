variable "cloudflare_account_id" {
  description = "Cloudflare account ID where the worker is deployed"
  type        = string
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token with permissions Workers Scripts:Edit, Workers KV Storage:Edit, Account:Read, Zone:Read, Analytics:Read"
  type        = string
  sensitive   = true
}

variable "worker_name" {
  description = "Worker name (must be unique within the account)"
  type        = string
  default     = "cloudflare-prometheus-exporter"
}

variable "CLOUDFLARE_API_TOKEN_secret" {
  description = "Cloudflare API token used BY the worker to query CF APIs (GraphQL + REST). Permissions: Zone > Analytics Read, Account > Account Analytics Read, Account > Workers Scripts Read, Zone > SSL Read, Zone > Firewall Services Read, Zone > Load Balancers Read, Account > Logs Read, Account > Magic Transit Read"
  type        = string
  sensitive   = true
}

variable "BASIC_AUTH_USER" {
  description = "HTTP Basic Auth user (optional — leave empty to disable auth)"
  type        = string
  default     = ""
}

variable "BASIC_AUTH_PASSWORD" {
  description = "HTTP Basic Auth password (optional)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "deploy_on_apply" {
  description = "If true, terraform apply automatically triggers wrangler deploy"
  type        = bool
  default     = true
}
