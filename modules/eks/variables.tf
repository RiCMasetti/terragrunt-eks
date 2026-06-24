variable "cluster_name" {
  type = string
}

variable "kubernetes_version" {
  type    = string
  default = "1.32"
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "instance_types" {
  type        = list(string)
  description = "List of EC2 instance types for the managed node group"
  default     = ["t3.medium"]
}

variable "node_min_size" {
  type    = number
  default = 2
}

variable "node_max_size" {
  type    = number
  default = 5
}

variable "node_desired_size" {
  type    = number
  default = 3
}
