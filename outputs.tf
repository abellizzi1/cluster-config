output "website_url" {
  description = "Open this from a device on the local network."
  value       = "http://<your-host-LAN-IP>:${var.http_port}/ai/"
}

output "api_url" {
  value = "http://<your-host-LAN-IP>:${var.http_port}/ai/v1/chat/completions"
}

output "argocd_access" {
  description = "Argo CD shares the application ingress port and is also reachable on the LAN."
  value       = "http://localhost:${var.http_port}/argocd/"
}
