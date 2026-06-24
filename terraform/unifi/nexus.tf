locals {
  ssh_key = split(" ", var.ssh_public_key)
}

resource "unifi_network" "vlan" {
  for_each = var.vlans

  name                = each.key
  vlan                = each.value
  third_party_gateway = true # vanguard owns L3/DHCP/RA; UniFi only tags (vlan-only)
}

resource "unifi_setting" "this" {
  mgmt = {
    ssh_enabled               = true
    ssh_auth_password_enabled = false
    wifiman_enabled           = true

    ssh_keys = [{
      name = var.username
      type = local.ssh_key[0]
      key  = local.ssh_key[1]
    }]
  }
}
