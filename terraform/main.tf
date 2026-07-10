# ── Railway Project ──

resource "railway_project" "staffos" {
  name = "staffos"
}

# ── PostgreSQL Database ──
#
# The database is Railway's managed PostgreSQL (service name "Postgres"),
# provisioned from Railway's Postgres template (New → Database → PostgreSQL).
# It is deliberately NOT a Terraform resource:
#
#   * Railway's managed Postgres is the platform's first-class database
#     primitive — it ships with a persistent volume, automated backups, SSL,
#     and correct PGDATA handling.
#   * The community Railway provider cannot manage a service volume: attaching
#     one attaches on Railway but returns null to Terraform, failing every
#     apply's consistency check. A Terraform-defined raw postgres image would
#     therefore be either broken (with a volume) or ephemeral (without one).
#
# Terraform owns everything around it — the web service, domain, DNS, and the
# DATABASE_URL below, which references the managed service's own connection
# string over the private network.

# ── Web Application ──

resource "railway_service" "web" {
  name       = "web"
  project_id = railway_project.staffos.id

  source_repo        = "rajgurung/staffOS"
  source_repo_branch = "main"
}

# Environment variables for the web service
locals {
  # Reference the managed Postgres service's own DATABASE_URL (the private
  # railway.internal connection string it publishes). Railway reference syntax
  # is double-brace ${{Service.VARIABLE}}; in HCL "$$" escapes to a literal "$"
  # and the braces are literal (no "${" interpolation), so this renders to
  # exactly ${{Postgres.DATABASE_URL}} for Railway to resolve at deploy time.
  database_url = "$${{Postgres.DATABASE_URL}}"

  web_env_vars = {
    RAILS_ENV                = "production"
    RAILS_MASTER_KEY         = var.rails_master_key
    STAFFOS_HOST             = var.domain
    ANTHROPIC_API_KEY        = var.anthropic_api_key
    RAILS_LOG_TO_STDOUT      = "1"
    RAILS_SERVE_STATIC_FILES = "1"
  }
}

resource "railway_variable" "database_url" {
  name           = "DATABASE_URL"
  value          = local.database_url
  environment_id = railway_project.staffos.default_environment.id
  service_id     = railway_service.web.id
}

resource "railway_variable" "web_vars" {
  for_each = local.web_env_vars

  name           = each.key
  value          = each.value
  environment_id = railway_project.staffos.default_environment.id
  service_id     = railway_service.web.id
}

# Custom domain on Railway
resource "railway_custom_domain" "staffos" {
  domain         = var.domain
  environment_id = railway_project.staffos.default_environment.id
  service_id     = railway_service.web.id

  # The web app (Puma) listens on Railway's injected PORT=8080. Without an
  # explicit target_port the provider sends 0, so Railway's edge has no port to
  # route to — the domain returns "train has not arrived" and the TLS cert
  # never validates. This is why the custom domain never worked.
  target_port = 8080
}

# ── Cloudflare DNS ──

resource "cloudflare_record" "staffos" {
  zone_id = var.cloudflare_zone_id
  name    = "staffos"
  content = railway_custom_domain.staffos.dns_record_value
  type    = "CNAME"
  proxied = false # DNS only — Railway handles SSL
  ttl     = 1     # Auto
}

# Railway requires a TXT record to prove domain ownership before it will issue
# the TLS cert and route traffic (certificateStatus stays VALIDATING_OWNERSHIP
# without it). The railway provider doesn't expose this value, so it's taken
# from the dashboard's DNS instructions for this domain. Recreating the custom
# domain will change the token — update it from the dashboard if that happens.
resource "cloudflare_record" "staffos_railway_verify" {
  zone_id = var.cloudflare_zone_id
  name    = "_railway-verify.staffos"
  content = "railway-verify=78002dd81bb6f00d6adfcff47b5589810ab9903d81f870f0d3b1e4226f991ee6"
  type    = "TXT"
  proxied = false
  ttl     = 1 # Auto
}
