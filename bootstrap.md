# Manual Bootstrap

## Debian

### Configure Network

```sh
# /etc/network/interfaces

auto lo
iface lo inet loopback

iface nic0 inet manual

auto vmbr0
iface vmbr0 inet manual
    bridge-ports nic0
    bridge-stp off
    bridge-fd 0
    bridge-vlan-aware yes
    bridge-vids 10 30 60

auto vmbr0.10
iface vmbr0.10 inet6 static
    address fd22:1337:6769:10::2/64
    accept_ra 2
    autoconf 1
```

### Reload Network Configuration

```sh
ifreload -a
```

### Create User

```sh
adduser {user}
usermod -aG sudo {user}  # optional: add the user to the sudo group
```

### Configure Temporary DNS

```sh
echo "nameserver 2001:4860:4860::6464" > /etc/resolv.conf
```

### Install sudo

```sh
apt install sudo
```

### Configure SSH keys from the client

```sh
ssh-copy-id {user}@{ip}
```

## Vyos

```sh
configure
set interfaces ethernet eth3 address fd22:1337:6769:10::1/64

set service ssh
set system login user {user} authentication public-keys {label} type ssh-ed25519
set system login user {user} authentication public-keys {label} key AAAAC3Nza...  # base64 public key

commit
save
```