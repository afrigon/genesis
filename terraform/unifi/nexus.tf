locals {
  ssh_key             = split(" ", var.ssh_public_key)
  ap_networks         = ["trusted", "iot", "guest", "dualstack"]
  hypervisor_networks = ["management", "services", "untrusted", "edge", "dualstack"]
}

data "unifi_ap_group" "default" {
  name = "All APs"
}

data "unifi_client_qos_rate" "default" {
  name = "Default"
}

resource "unifi_network" "vlan" {
  for_each = var.vlans

  name                = each.key
  vlan                = each.value
  third_party_gateway = true # vanguard owns L3/DHCP/RA; UniFi only tags (vlan-only)
}

resource "unifi_setting" "this" {
  country = {
    code = 124 # Canada (ISO 3166-1 numeric)
  }

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

resource "unifi_port_profile" "access" {
  for_each = unifi_network.vlan

  name                  = each.key
  forward               = "native"
  native_networkconf_id = each.value.id
  tagged_vlan_mgmt      = "block_all"
  poe_mode              = "auto"
}

resource "unifi_port_profile" "hypervisor" {
  name             = "hypervisor"
  forward          = "customize"
  tagged_vlan_mgmt = "custom"
  excluded_networkconf_ids = [
    for name, network in unifi_network.vlan : network.id
    if !contains(local.hypervisor_networks, name)
  ]
  poe_mode = "auto"
}

resource "unifi_port_profile" "trunk" {
  name             = "trunk"
  forward          = "customize"
  tagged_vlan_mgmt = "custom"
  poe_mode         = "auto"
}

resource "unifi_port_profile" "ap" {
  name                  = "ap"
  forward               = "customize"
  native_networkconf_id = unifi_network.vlan["dualstack"].id
  tagged_vlan_mgmt      = "custom"
  excluded_networkconf_ids = [
    for name, network in unifi_network.vlan : network.id
    if !contains(local.ap_networks, name)
  ]
  poe_mode = "auto"
}

resource "unifi_wlan" "x" {
  name          = "x"
  security      = "wpapsk"
  passphrase    = var.wifi_password_trusted
  network_id    = unifi_network.vlan["trusted"].id
  ap_group_ids  = [data.unifi_ap_group.default.id]
  user_group_id = data.unifi_client_qos_rate.default.id

  wpa3_support    = true
  wpa3_transition = false
  pmf_mode        = "required"

  wlan_band  = "both"
  wlan_bands = ["2g", "5g", "6g"]
}

resource "unifi_wlan" "x_iot" {
  name          = "x-iot"
  security      = "wpapsk"
  passphrase    = var.wifi_password_iot
  network_id    = unifi_network.vlan["iot"].id
  ap_group_ids  = [data.unifi_ap_group.default.id]
  user_group_id = data.unifi_client_qos_rate.default.id

  hide_ssid = true
  # the provider derives the API payload from wlan_bands but defaults the two
  # attributes inconsistently — both must be pinned or the apply fails on
  # readback
  wlan_band    = "2g"
  wlan_bands   = ["2g"]
  enhanced_iot = true
  group_rekey  = 0
  no2ghz_oui   = false
}

resource "unifi_wlan" "x_dualstack" {
  name          = "x-dualstack"
  security      = "wpapsk"
  passphrase    = var.wifi_password_dualstack
  network_id    = unifi_network.vlan["dualstack"].id
  ap_group_ids  = [data.unifi_ap_group.default.id]
  user_group_id = data.unifi_client_qos_rate.default.id

  hide_ssid = true
}

resource "unifi_wlan" "x_guest" {
  name          = "x-guest"
  security      = "wpapsk"
  passphrase    = var.wifi_password_guest
  network_id    = unifi_network.vlan["guest"].id
  ap_group_ids  = [data.unifi_ap_group.default.id]
  user_group_id = data.unifi_client_qos_rate.default.id

  l2_isolation = true
}
