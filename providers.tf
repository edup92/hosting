
terraform {
	required_providers {
		aws = {
			source  = "hashicorp/aws"
			version = ">= 4.0"
		}
		cloudflare = {
			source  = "cloudflare/cloudflare"
			version = ">= 3.0"
		}
		uptimerobot = {
      source  = "uptimerobot/uptimerobot"
      version = "1.3.5"
		}
	}
}

provider "aws" {
}

provider "cloudflare" {
	api_token = var.cf_token
}

provider "uptimerobot" {
  api_key = var.uptimerobot_token
}