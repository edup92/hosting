variable "project_name" {
	description = "Name of the project (used for naming resources)"
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
		monitor_keyword = string
	}))
}