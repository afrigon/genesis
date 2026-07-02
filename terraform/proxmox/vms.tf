module "vm" {
  source   = "./modules/vm"
  for_each = var.vms

  name              = each.key
  node              = var.proxmox_node
  cores             = each.value.cores
  memory            = each.value.memory
  disk_size         = each.value.disk_size
  vlan              = each.value.vlan
  ipv6_address      = each.value.ipv6_address
  ipv4              = each.value.ipv4
  datastore         = var.vm_datastore
  snippet_datastore = var.image_datastore
  bridge            = var.network_bridge
  image_file_id     = proxmox_download_file.debian.id
  username          = var.username
  ssh_public_key    = var.ssh_public_key
}
