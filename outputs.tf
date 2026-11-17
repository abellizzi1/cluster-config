output "website_url" {
  description = "Open this from a device on the local network."
  value       = "http://<your-host-LAN-IP>:${var.http_port}"
}

output "api_url" {
  value = "http://<your-host-LAN-IP>:${var.http_port}/v1/chat/completions"
}

output "argocd_access" {
  description = "Open on the Docker host; no port-forward process is needed."
  value       = "http://localhost:${var.argocd_http_port}"
}
