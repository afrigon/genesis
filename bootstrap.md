# Manual Bootstrap

## Debian

### Configure Network

```
# /etc/network/interfaces


```

### Create User

```sh
adduser {user}
usermod -aG sudo {user}  # optional: add the user to the sudo group
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