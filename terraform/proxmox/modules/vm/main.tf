resource "proxmox_virtual_environment_file" "network_config" {
  content_type = "snippets"
  datastore_id = var.snippet_datastore
  node_name    = var.node

  source_raw {
    file_name = "${var.name}-network.yaml"
    data      = <<-EOT
      version: 2
      ethernets:
        primary:
          match:
            name: "en*"
          dhcp4: false
          accept-ra: true
          addresses:
            - ${var.ipv6_address}/64%{ if var.ipv4 != null }
            - ${var.ipv4.address}
          routes:
            - to: default
              via: ${var.ipv4.gateway}%{ endif }
    EOT
  }
}

resource "proxmox_virtual_environment_file" "user_config" {
  content_type = "snippets"
  datastore_id = var.snippet_datastore
  node_name    = var.node

  source_raw {
    file_name = "${var.name}-user.yaml"
    data = "#cloud-config\n${yamlencode({
      users = [{
        name                = var.username
        groups              = ["sudo"]
        sudo                = "ALL=(ALL) NOPASSWD:ALL"
        shell               = "/bin/bash"
        ssh_authorized_keys = [var.ssh_public_key]
      }]
    })}"
  }
}

resource "proxmox_virtual_environment_vm" "this" {
  name      = var.name
  node_name = var.node
  tags      = ["genesis", var.name]
  on_boot   = true

  cpu {
    cores = var.cores
    type  = "host"
  }

  memory {
    dedicated = var.memory
  }

  disk {
    datastore_id = var.datastore
    import_from  = var.image_file_id
    interface    = "scsi0"
    size         = var.disk_size
    discard      = "on"
  }

  network_device {
    bridge  = var.bridge
    vlan_id = var.vlan
  }

  initialization {
    datastore_id = var.datastore

    user_data_file_id    = proxmox_virtual_environment_file.user_config.id
    network_data_file_id = proxmox_virtual_environment_file.network_config.id
  }

  operating_system {
    type = "l26"
  }
}
