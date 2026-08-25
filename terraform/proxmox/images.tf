resource "proxmox_download_file" "debian" {
  content_type = "import"
  datastore_id = var.image_datastore
  node_name    = var.proxmox_node
  url          = var.cloud_image_url
  file_name    = basename(var.cloud_image_url)
  # the URL tracks latest; an upstream re-release must not replace the local
  # file — that replacement cascades into recreating every VM disk
  overwrite = false
}
