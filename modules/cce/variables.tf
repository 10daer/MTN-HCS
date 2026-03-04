###############################################################################
# Module: cce — Variables
###############################################################################

# ─────────────────────────────────────────────
# Naming
# ─────────────────────────────────────────────
variable "name_prefix" {
  description = "Prefix for all CCE resource names (e.g. myapp-dev)"
  type        = string
}

# ─────────────────────────────────────────────
# Cluster
# ─────────────────────────────────────────────
variable "cluster_flavor_id" {
  description = <<-EOT
    CCE cluster size/HA flavour:
      cce.s1.small   — single master, up to 50 nodes
      cce.s1.medium  — single master, up to 200 nodes
      cce.s2.small   — HA masters, up to 50 nodes
      cce.s2.medium  — HA masters, up to 200 nodes
      cce.s2.large   — HA masters, up to 1000 nodes
      cce.s2.xlarge  — HA masters, up to 2000 nodes
  EOT
  type        = string
  default     = "cce.s1.small"
}

variable "vpc_id" {
  description = "VPC ID where the cluster will be created"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID for the cluster. Must have DNS configured."
  type        = string
}

variable "container_network_type" {
  description = "Container networking mode: overlay_l2, vpc-router, or eni"
  type        = string
  default     = "overlay_l2"
}

variable "container_network_cidr" {
  description = "Container network CIDR (e.g. 172.16.0.0/16). Leave empty for provider default."
  type        = string
  default     = ""
}

variable "service_network_cidr" {
  description = "Service network CIDR (e.g. 10.247.0.0/16). Leave empty for provider default."
  type        = string
  default     = ""
}

variable "cluster_type" {
  description = "Cluster type: VirtualMachine or ARM64"
  type        = string
  default     = "VirtualMachine"
}

variable "cluster_version" {
  description = "Kubernetes version (leave empty for latest supported)"
  type        = string
  default     = ""
}

variable "cluster_description" {
  description = "Human-readable cluster description"
  type        = string
  default     = "Managed by Terraform"
}

variable "authentication_mode" {
  description = "Cluster auth mode: rbac or authenticating_proxy"
  type        = string
  default     = "rbac"
}

variable "kube_proxy_mode" {
  description = "Service forwarding mode: iptables or ipvs"
  type        = string
  default     = "iptables"
}

variable "cluster_eip" {
  description = "EIP address to expose the K8s API server. Leave empty for private-only."
  type        = string
  default     = ""
}

variable "cluster_multi_az" {
  description = "Deploy master nodes across multiple AZs (only for HA flavors cce.s2.*)"
  type        = bool
  default     = false
}

variable "cluster_hibernate" {
  description = "Hibernate the cluster (freeze workloads, save resources)"
  type        = bool
  default     = false
}

variable "delete_storage_on_destroy" {
  description = "Delete associated EVS/OBS/SFS storage when destroying the cluster"
  type        = bool
  default     = true
}

# ─────────────────────────────────────────────
# Tags
# ─────────────────────────────────────────────
variable "tags" {
  description = "Tags applied to cluster and node pool VMs"
  type        = map(string)
  default     = {}
}

# ─────────────────────────────────────────────
# Node Pools
# ─────────────────────────────────────────────
variable "key_pair_name" {
  description = "SSH key pair name for node login (must exist in HCS)"
  type        = string
}

variable "node_pools" {
  description = <<-EOT
    Map of node pools to create. Each key is the pool suffix name.
    Example:
      {
        workers = {
          flavor_id          = "s3.large.4"
          initial_node_count = 2
          availability_zone  = "az1.dc0"
          root_volume_size   = 50
          root_volume_type   = "SSD"
          data_volumes       = [{ size = 100, volumetype = "SSD" }]
          autoscaling_enabled       = true
          min_node_count            = 1
          max_node_count            = 5
          scale_down_cooldown_time  = 100
          priority                  = 1
          os                        = null
          runtime                   = "containerd"
          labels                    = { role = "worker" }
          tags                      = {}
          taints                    = []
          max_pods                  = null
          preinstall                = null
          postinstall               = null
          subnet_id                 = null
          type                      = "vm"
        }
      }
  EOT
  type        = any
  default     = {}
}

# ─────────────────────────────────────────────
# Namespaces
# ─────────────────────────────────────────────
variable "namespaces" {
  description = <<-EOT
    Map of Kubernetes namespaces to create. Key = namespace name.
    Example:
      {
        app         = { labels = { team = "backend" }, annotations = {} }
        monitoring  = { labels = {}, annotations = {} }
      }
  EOT
  type = map(object({
    labels      = optional(map(string), {})
    annotations = optional(map(string), {})
  }))
  default = {}
}
