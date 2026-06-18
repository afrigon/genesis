provider "proxmox" {
  endpoint = var.proxmox_endpoint

  # Proxmox serves the API on :8006 with a self-signed cert. Revisit once
  # atlas can issue one for sol.
  insecure = true

  # Token supplied via the PROXMOX_VE_API_TOKEN environment variable.
}
