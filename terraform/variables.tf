variable "railway_token" {
  description = "Railway API token"
  type        = string
  sensitive   = true
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token"
  type        = string
  sensitive   = true
}

variable "cloudflare_zone_id" {
  description = "Cloudflare zone ID for rajgurung.me"
  type        = string
}

variable "domain" {
  description = "Custom domain for StaffOS"
  type        = string
  default     = "staffos.rajgurung.me"
}

variable "rails_master_key" {
  description = "Rails master key for credentials decryption"
  type        = string
  sensitive   = true
}

variable "anthropic_api_key" {
  description = "Anthropic API key for LLM-powered reviews"
  type        = string
  sensitive   = true
  default     = ""
}
