
terraform {
	required_providers {
    archive = {
      source = "hashicorp/archive"
      version = "2.7.1"
    }
    tls = {
      source = "hashicorp/tls"
      version = "4.1.0"
    }
    null = {
      source = "hashicorp/null"
      version = "3.2.4"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "6.27.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "5.15.0"
    }
  }
}

provider "aws" {
}

provider "cloudflare" {
	api_token = var.cf_token
}