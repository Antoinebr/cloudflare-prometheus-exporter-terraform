output "kv_namespace_id" {
  description = "ID of the KV namespace created for runtime config"
  value       = cloudflare_workers_kv_namespace.config.id
}

output "worker_name" {
  description = "Name of the deployed worker"
  value       = var.worker_name
}

output "wrangler_config_path" {
  description = "Path to the generated wrangler.jsonc"
  value       = local_file.wrangler_config.filename
}
