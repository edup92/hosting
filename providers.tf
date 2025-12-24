
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
	}
}

provider "aws" {
}

provider "cloudflare" {
	api_token = var.cf_token
}