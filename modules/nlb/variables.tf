variable "cluster_name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "node_security_group_id" {
  type        = string
  description = "Security group ID attached to EKS worker nodes"
}

variable "vpc_cidr_block" {
  type = string
}

variable "traefik_nodeport_http" {
  type    = number
  default = 30000
}

variable "traefik_nodeport_https" {
  type    = number
  default = 30001
}
