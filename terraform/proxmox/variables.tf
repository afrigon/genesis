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
    ipv4 = optional(object({
      address = string
      gateway = string
    }))
  }))

  default = {
    core     = { cores = 2, memory = 2048, disk_size = 16, vlan = 30, ipv6_address = "fd22:1337:6769:30::3" }
    services = { cores = 4, memory = 6144, disk_size = 256, vlan = 30, ipv6_address = "fd22:1337:6769:30::4" }
    edge     = { cores = 2, memory = 1024, disk_size = 16, vlan = 70, ipv6_address = "fd22:1337:6769:70::2" }

    # native IPv4 (static, from the reserved .2-.99 block): UniFi is IPv4-first
    # for device adoption — the reason the dualstack VLAN exists
    unity = {
      cores        = 4
      memory       = 4096
      disk_size    = 50
      vlan         = 80
      ipv6_address = "fd22:1337:6769:80::2"
      ipv4         = { address = "10.0.80.2/24", gateway = "10.0.80.1" }
    }
  }
}
