variable "cf_token" {
	description = "Cloudflare Token"
	type        = string
}

variable "uptimerobot_token" {
	description = "Uptimerobot Token"
	type        = string
}

variable "project_name" {
	description = "Name of the project (used for naming resources)"
	type        = string
}

variable "admin_ip" {
	description = "Admin IP Access"
	type        = string
}

variable "instance_type" {
	description = "EC2 instance type"
	type        = string
}

variable "instance_disk_size" {
	description = "EBS volume size (GB) for the instance"
	type        = number
}

variable "sites" {
	description = "Mapa de sitios con dominio y palabra clave de monitorización"
	type = map(object({
		domain = string
		monitor_keyworkd = string
	}))
}