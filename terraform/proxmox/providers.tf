provider "proxmox" {
  endpoint = var.proxmox_endpoint

  # Proxmox serves the API on :8006 with a self-signed cert. Revisit once
  # atlas can issue one for sol.
  insecure = true

  # Snippet uploads go over SSH; no DNS for the node yet, so set its IP.
  ssh {
    agent = true

    node {
      name    = var.proxmox_node
      address = var.proxmox_node_address
    }
  }
}
