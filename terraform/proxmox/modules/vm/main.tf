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
            - ${var.ipv4.address}%{ endif }
          routes:
            # RA still supplies the SLAAC GUA; the default route is static so
            # reachability does not depend on RA processing staying alive.
            - to: default
              via: ${cidrhost("${var.ipv6_address}/64", 1)}%{ if var.ipv4 != null }
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

  # cloud images ship a serial getty; without a serial device it restart-loops
  serial_device {
    device = "socket"
  }

  initialization {
    datastore_id = var.datastore

    user_data_file_id    = proxmox_virtual_environment_file.user_config.id
    network_data_file_id = proxmox_virtual_environment_file.network_config.id
  }

  operating_system {
    type = "l26"
  }

  # never let the provider reboot VMs itself: a hardware change would trigger
  # a fleet-wide reboot mid-apply, taking polaris (DNS) down with it. Hardware
  # changes stay pending until the operator stop/starts the VM.
  reboot_after_update = false

  # snippet files are immutable to the provider: editing one replaces the file
  # resource, and a changed file id would force-replace the VM (destroying its
  # disk). Proxmox reads the snippet when the VM starts, so snippet edits reach
  # live VMs on their next stop/start; initialization changes only apply in
  # full to freshly created VMs.
  lifecycle {
    ignore_changes = [initialization]
  }
}
