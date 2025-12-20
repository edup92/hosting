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

variable "instance_disk_type" {
	description = "EBS volume type for the instance"
	type        = string
}

variable "instance_disk_size" {
	description = "EBS volume size (GB) for the instance"
	type        = number
}

variable "instance_ami" {
	description = "Optional AMI id for the instance; if empty, a default Amazon Linux 2 AMI is used."
	type        = string
	default     = ""
}

variable "lambda_runtime" {
	description = "Runtime identifier for AWS Lambda functions (e.g. python3.11, nodejs18.x)"
	type        = string
}

variable "sites" {
	description = "Mapa de sitios con dominio y palabra clave de monitorización"
	type = map(object({
		domain = string
		monitor_keyworkd = string
	}))
}