variable "cluster_name" {
  type = string
}

variable "cluster_version" {
  type = string
}

variable "oidc_provider_arn" {
  type = string
}

variable "oidc_provider_url" {
  type        = string
  description = "OIDC provider URL without the https:// scheme"
}

variable "route53_zone_id" {
  type        = string
  description = "Route53 hosted zone ID — scopes the Traefik IAM policy to this zone"
}
