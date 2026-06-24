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

variable "aws_region" {
  type = string
}

variable "domain_name" {
  type        = string
  description = "Primary domain managed in Route53, used by Traefik cert resolver"
}

variable "route53_zone_id" {
  type        = string
  description = "Route53 hosted zone ID for the domain"
}
