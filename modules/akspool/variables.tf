variable "pool_name" {
  description = "The name of the AKS node pool (max 12 characters)"
  type        = string
}

variable "kubernetes_cluster_id" {
  description = "The resource ID of the existing AKS cluster"
  type        = string
}

variable "vm_size" {
  description = "The VM size to use for the node pool"
  type        = string
  default     = "Standard_DS2_v2"
}

variable "auto_scaling_enabled" {
  description = "Whether autoscaling is enabled for this node pool"
  type        = bool
  default     = true
}

variable "node_public_ip_enabled" {
  description = "Whether to enable a public IP on each node"
  type        = bool
  default     = false
}

variable "mode" {
  description = "The mode for the node pool (System/User)"
  type        = string
  default     = "User"
}

variable "node_labels" {
  description = "A map of labels to apply to the nodes"
  type        = map(string)
  default     = {}
}

variable "node_taints" {
  description = "A list of taints to apply to the nodes"
  type        = list(string)
  default     = []
}

variable "pod_subnet_id" {
  description = "The subnet ID to use for the pod network"
  type        = string
  default = null
}

variable "priority" {
  description = "The priority of the nodes (Regular or Spot)"
  type        = string
  default     = "Spot"
}

variable "vnet_subnet_id" {
  description = "The subnet ID to attach the node pool to"
  type        = string
}

variable "max_count" {
  description = "Maximum number of nodes in the pool (used for autoscaling)"
  type        = number
  default     = 3
}

variable "min_count" {
  description = "Minimum number of nodes in the pool (used for autoscaling)"
  type        = number
  default     = 1
}

variable "node_count" {
  description = "Number of nodes in the pool (ignored if autoscaling is enabled)"
  type        = number
  default     = 1
}