# genesis

Infrastructure as code for my personal home network.

The network is IPv6-only: ULA + delegated prefixes via SLAAC, NAT64/DNS64
for the IPv4 internet, and IPv4 only where strictly unavoidable. A VyOS
gateway (vanguard) routes and firewalls segmented VLANs; a Proxmox server
(sol) hosts the services, all space-themed and reachable by name behind a
reverse proxy — see [services.md](services.md).

```
internet ──── eth0 ─┐
5G backup ─── eth1 ─┤  vanguard (VyOS) ─── eth3 ── recovery workstation
                    └─ eth2 (VLAN trunk)
                          │
                       switch ──┬── sol (Proxmox VE — all services)
                                └── AP (x / x-iot / x-guest)
```