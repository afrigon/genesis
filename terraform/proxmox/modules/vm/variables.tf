variable "name" {
  type = string
}

variable "node" {
  type = string
}

variable "cores" {
  type = number
}

variable "memory" {
  type = number
}

variable "disk_size" {
  type = number
}

variable "vlan" {
  type = number
}

variable "ipv6_address" {
  type = string
}

# Only for VMs on the dualstack VLAN (the network's sole IPv4 VLAN); everything
# else stays IPv6-only.
variable "ipv4" {
  type = object({
    address = string
    gateway = string
  })
  default = null
}

variable "datastore" {
  type = string
}

variable "snippet_datastore" {
  type = string
}

variable "bridge" {
  type = string
}

variable "image_file_id" {
  type = string
}

variable "username" {
  type = string
}

variable "ssh_public_key" {
  type = string
}
