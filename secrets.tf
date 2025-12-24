variable "cf_token" {
	description = "Cloudflare Token"
	type        = string
	sensitive = true
}

variable "uptimerobot_token" {
	description = "Uptimerobot Token"
	type        = string
	sensitive = true
}

variable "admin_ip" {
	description = "Admin IP Access"
	type        = string
	sensitive = true
}