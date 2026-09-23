.PHONY: init plan apply destroy dev secrets clean

# Default target
all: deploy

# Terraform
init:
	@cd terraform && terraform init

plan:
	@cd terraform && terraform plan

apply:
	@cd terraform && terraform apply

destroy:
	@cd terraform && terraform destroy

# Shortcuts
deploy: apply

# Local development (uses wrangler.jsonc.dev with empty KV id)
dev:
	@if [ ! -f wrangler.jsonc.dev ]; then echo "wrangler.jsonc.dev not found"; exit 1; fi
	@echo "Starting local dev with wrangler.jsonc.dev..."
	@cp wrangler.jsonc.dev wrangler.jsonc
	@if command -v bun >/dev/null 2>&1; then bun run dev; else npm run dev; fi

# Manually set secrets via Wrangler (alternative to Terraform)
secrets:
	@echo "Usage: make secrets TOKEN=xxx [USER=xxx PASS=xxx]"
	@test -n "$(TOKEN)" || (echo "TOKEN is required"; exit 1)
	@if command -v bun >/dev/null 2>&1; then \
		printf '%s' "$(TOKEN)" | bunx wrangler secret put CLOUDFLARE_API_TOKEN; \
	else \
		printf '%s' "$(TOKEN)" | npx wrangler secret put CLOUDFLARE_API_TOKEN; \
	fi
	@if [ -n "$(USER)" ] && [ -n "$(PASS)" ]; then \
		if command -v bun >/dev/null 2>&1; then \
			printf '%s' "$(USER)" | bunx wrangler secret put BASIC_AUTH_USER; \
			printf '%s' "$(PASS)" | bunx wrangler secret put BASIC_AUTH_PASSWORD; \
		else \
			printf '%s' "$(USER)" | npx wrangler secret put BASIC_AUTH_USER; \
			printf '%s' "$(PASS)" | npx wrangler secret put BASIC_AUTH_PASSWORD; \
		fi \
	fi

# Cleanup generated files
clean:
	@rm -f wrangler.jsonc
	@cd terraform && rm -rf .terraform terraform.tfstate terraform.tfstate.backup .terraform.lock.hcl
