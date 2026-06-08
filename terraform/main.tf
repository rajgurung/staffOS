# ── Railway Project ──

resource "railway_project" "staffos" {
  name = "staffos"
}

# ── PostgreSQL Database ──

resource "railway_service" "postgres" {
  name       = "postgres"
  project_id = railway_project.staffos.id

  source_image = "postgres:16"
}

resource "railway_variable" "pg_user" {
  name           = "POSTGRES_USER"
  value          = "staffos"
  environment_id = railway_project.staffos.default_environment.id
  service_id     = railway_service.postgres.id
}

resource "railway_variable" "pg_db" {
  name           = "POSTGRES_DB"
  value          = "staffos_production"
  environment_id = railway_project.staffos.default_environment.id
  service_id     = railway_service.postgres.id
}

resource "railway_tcp_proxy" "postgres" {
  application_port = 5432
  environment_id   = railway_project.staffos.default_environment.id
  service_id       = railway_service.postgres.id
}

# ── Web Application ──

resource "railway_service" "web" {
  name       = "web"
  project_id = railway_project.staffos.id

  source_repo        = "rajgurung/staffOS"
  source_repo_branch = "main"
}

# Environment variables for the web service
locals {
  # Railway resolves reference variables at deploy time using this syntax
  database_url_template = "$${${railway_service.postgres.name}.DATABASE_PRIVATE_URL}"

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
  value          = local.database_url_template
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
