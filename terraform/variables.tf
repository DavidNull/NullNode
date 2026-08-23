variable "cluster_name" {
  description = "Name of the K3d cluster"
  type        = string
  default     = "ironnode"
}

variable "server_count" {
  description = "Number of server nodes in the cluster"
  type        = number
  default     = 1
}

variable "agent_count" {
  description = "Number of agent nodes in the cluster"
  type        = number
  default     = 1
}

variable "enable_registry" {
  description = "Enable local container registry"
  type        = bool
  default     = true
}
