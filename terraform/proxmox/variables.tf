variable "proxmox_endpoint" {
  type    = string
  default = "https://[fd22:1337:6769:10::2]:8006"
}

variable "proxmox_node" {
  type    = string
  default = "sol"
}

variable "proxmox_node_address" {
  type    = string
  default = "fd22:1337:6769:10::2"
}

variable "vm_datastore" {
  type    = string
  default = "local-lvm"
}

variable "image_datastore" {
  type    = string
  default = "local"
}

variable "network_bridge" {
  type    = string
  default = "vmbr0"
}

variable "cloud_image_url" {
  type    = string
  default = "https://cloud.debian.org/images/cloud/trixie/latest/debian-13-generic-amd64.qcow2"
}

variable "username" {
  type = string
}

variable "ssh_public_key" {
  type        = string
  description = "SSH public key authorized on every VM"
}

variable "vms" {
  type = map(object({
    cores        = number
    memory       = number # MB
    disk_size    = number # GB
    vlan         = number
    ipv6_address = string
  }))

  default = {
    # Legacy single-container AdGuard VM. Kept live until the Phase 6 cutover
    # (clients repointed off it), then removed — polaris now targets core.
    dns      = { cores = 2, memory = 1024, disk_size = 16, vlan = 30, ipv6_address = "fd22:1337:6769:30::2" }
    core     = { cores = 2, memory = 2048, disk_size = 16, vlan = 30, ipv6_address = "fd22:1337:6769:30::3" }
    services = { cores = 4, memory = 6144, disk_size = 64, vlan = 30, ipv6_address = "fd22:1337:6769:30::4" }
    edge     = { cores = 2, memory = 1024, disk_size = 16, vlan = 70, ipv6_address = "fd22:1337:6769:70::2" }
  }
}
