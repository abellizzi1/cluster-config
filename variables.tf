variable "cluster_name" {
  description = "Name for the shared local k3d/K3s cluster hosting multiple applications and projects."
  type        = string
  default     = "apps-cluster"
}

variable "http_port" {
  description = "Host TCP port exposed to your local network."
  type        = number
  default     = 8080
}

variable "argocd_http_port" {
  description = "Localhost TCP port for the Argo CD UI, separate from the shared application ingress."
  type        = number
  default     = 8082

  validation {
    condition     = var.argocd_http_port >= 1024 && var.argocd_http_port <= 65535 && floor(var.argocd_http_port) == var.argocd_http_port
    error_message = "Use an integer port between 1024 and 65535."
  }
}

variable "k3s_image" {
  description = "K3s image for NEW clusters. Changing this does not upgrade or replace an existing cluster."
  type        = string
  default     = "rancher/k3s:v1.34.3-k3s1"
}

variable "argocd_version" {
  description = "Pinned Argo CD release installed by the bootstrap script. Review upgrade notes before changing."
  type        = string
  default     = "v3.5.6"

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$", var.argocd_version))
    error_message = "Use a release tag such as v3.5.6."
  }
}
