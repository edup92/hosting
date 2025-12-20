data "aws_vpc" "default" {
  default = true
}

data "cloudflare_ip_ranges" "cloudflare" {
  
}