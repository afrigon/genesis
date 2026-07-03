variable "unifi_api_url" {
  type    = string
  default = "https://unity.x"
}

variable "vlans" {
  type = map(number)

  # Mirror of the ansible vlans map (ansible/host_vars/vanguard.yml). Keep in sync.
  default = {
    management = 10
    trusted    = 20
    services   = 30
    iot        = 40
    guest      = 50
    untrusted  = 60
    edge       = 70
    dualstack  = 80
  }
}

variable "ssh_public_key" {
  type        = string
  description = "Public key authorized for UniFi device SSH (from 1Password)"
}

variable "username" {
  type        = string
  description = "Device SSH login user"
}

variable "wifi_password_trusted" {
  type      = string
  sensitive = true
}

variable "wifi_password_iot" {
  type      = string
  sensitive = true
}

variable "wifi_password_guest" {
  type      = string
  sensitive = true
}

variable "wifi_password_dualstack" {
  type      = string
  sensitive = true
}
