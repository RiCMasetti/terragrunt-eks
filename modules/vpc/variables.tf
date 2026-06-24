variable "cluster_name" {
  type        = string
  description = "EKS cluster name; used for subnet tagging"
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC"
  default     = "10.0.0.0/16"
}

variable "single_nat_gateway" {
  type        = bool
  description = "Use a single NAT Gateway for all AZs (lower cost, lower HA)"
  default     = false
}
