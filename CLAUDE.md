# Genesis — Homelab Infrastructure as Code

Genesis configures the entire homelab with Terraform and Ansible. The guiding
principle is **full recoverability**: if the hardware died tomorrow, the whole
environment (minus application data) must be rebuildable from this repo with a
few commands, starting from `bootstrap.md` (the minimal manual steps needed
before automation can take over).

## Core principles

- **IPv6 only.** The network is IPv6-only end to end. IPv4 is added only where
  a specific device or service makes it unavoidable, and each exception must be
  documented.
- **Everything by name.** Hosts and services are referenced by DNS name
  (self-hosted DNS), never by hard-coded address, wherever possible.
- **Secure by default.** Every service must have proper authentication and a
  valid SSL/TLS certificate — no plain HTTP, no unauthenticated services.
- **Reverse proxy only.** Services must not be directly reachable; all client
  access goes through the reverse proxy (harmony, on the `core` VM), which
  enforces auth, SSL, and access policy. Backends run on the `services` VM;
  harmony reaches them through a Traefik file-provider config — one route per
  service mapping `{service}.x` to its backend `services.sol.x:{port}` (Traefik's
  label auto-discovery only sees containers on its own Docker host, and harmony
  runs on a different host from the apps). Enforcement is entirely on vanguard,
  not host firewalls: the forward chain default-drops and only
  `clients → harmony:443` is opened, so clients cannot reach backend ports.
  Stronger intra-tier isolation, if ever needed, comes from giving the app tier
  its own VLAN (gateway-mediated) — never host-level firewalls.
- **Declarative over imperative.** All configuration lives in this repo.
  Manual changes on devices are considered drift and should be folded back
  into code.

## Hardware

| Host     | Role                                   | Notes |
|----------|----------------------------------------|-------|
| vanguard | VyOS gateway / firewall                | 4× ethernet: eth0=WAN (modem), eth1=WAN backup (5G), eth2=LAN (to L2 switch), eth3=configuration (direct connection for recovery/config) |
| sol      | Proxmox VE server                      | Hosts the reverse proxy and all VM/LXC services |
| AP       | UniFi Express (temporary)              | On the L2 switch. SSIDs: `x` (trusted), `x-iot` (hidden), `x-guest`. Will be replaced by a dedicated AP later |
| switch   | Dumb L2 switch (temporary)             | Will be upgraded to a managed (likely UniFi) switch for proper VLAN handling |

## Network

ULA prefix for internal communication: `fd22:1337:6769:{vlan}::/64`

The gateway (vanguard) is always at `{prefix}::1` on every VLAN.

### VLANs

| VLAN | Name       | Prefix                    | Purpose / Wi-Fi |
|------|------------|---------------------------|-----------------|
| 10   | management | `fd22:1337:6769:10::/64`  | Infrastructure management (vanguard, sol) |
| 20   | trusted    | `fd22:1337:6769:20::/64`  | Trusted clients — Wi-Fi `x` |
| 30   | services   | `fd22:1337:6769:30::/64`  | Self-hosted services (VMs/containers on sol) |
| 40   | iot        | `fd22:1337:6769:40::/64`  | IoT devices — Wi-Fi `x-iot` (hidden) |
| 50   | guest      | `fd22:1337:6769:50::/64`  | Guests — Wi-Fi `x-guest` |

More VLANs will be added for untrusted services as needed.

### Addressing

- **Clients:** SLAAC only — no DHCPv6 or DHCPv4 on the LAN.
- **Infrastructure:** static, predictable addresses (gateway at `{prefix}::1`,
  low interface IDs for servers).
- **WAN:** DHCPv6 (with prefix delegation from the ISP).
- **Dual prefixes:** hosts get a ULA address (internal communication, DNS,
  static config) plus a GUA via SLAAC from the ISP-delegated prefix (outbound
  internet). Never hard-code GUAs — the delegated prefix can change.
- **DNS:** polaris (AdGuard, `dns.sol.x`) is the resolver and does DNS64
  locally, synthesizing IPv4-only names into `64:ff9b::/96`; Cloudflare/Google
  are plain upstreams. Clients are pointed at polaris via RA RDNSS,
  **polaris-only** on trusted/management/services — no DNS64 fallback in the RA,
  because RDNSS has no primary/backup (clients treat advertised servers as
  peers), so a fallback would let them bypass polaris and miss `.x`/filtering.
  iot/guest stay on public DNS64.
- **Host resolv.conf** lists polaris first with DNS64 as fallback — safe here
  because the glibc resolver honors order (falls through only on no response),
  which also avoids a DNS bootstrap loop for sol / the dns VM when polaris is
  down. vanguard keeps its own upstreams and never depends on a service behind
  it.
- **IPv4 reachability:** NAT64 on vanguard translates `64:ff9b::/96`; polaris's
  DNS64 supplies the synthesized records. The WAN's DHCPv4 address is the
  network's only IPv4 presence.
- **Temporary exception — guest VLAN is dual-stack:** Windows has no stable
  CLAT yet, so IPv4-only needs (games, an IPv4-only work VPN) require native
  IPv4. The guest VLAN (50) carries it — hop onto `x-guest` when you need IPv4 —
  so trusted stays pure IPv6 (a real IPv6-only testbed). VLAN 50 gets DHCPv4
  (`10.0.50.0/24`) + NAT44, internet-only, in
  `roles/gateway/templates/ipv4-guest.j2` and the `guest_ipv4` var.
  Remove when Windows CLAT reaches stable (PREF64 is already advertised, so
  clients switch over automatically).
- **Untagged LAN traffic is intentionally dead:** bare eth2 has no prefix and
  the firewall logs and drops anything arriving on it. Do not "fix" this —
  every device must be on a tagged VLAN.

### Wi-Fi

| SSID      | VLAN         | Security |
|-----------|--------------|----------|
| `x`       | trusted (20) | WPA3 only |
| `x-iot`   | iot (40)     | Hidden; settings optimized for IoT compatibility (e.g. WPA2, 2.4 GHz) |
| `x-guest` | guest (50)   | Client isolation |

## Naming convention

Everything is space themed and referenced by name via self-hosted DNS
(polaris). Names resolve in three forms:

- **Services** — `{service}.x` (e.g. `gaia.x`, `andromeda.x`).
  Location-independent: they resolve to harmony, which routes by hostname, so a
  service can move hosts without its name changing.
- **VMs** — `{vm}.{node}.x` (e.g. `core.sol.x`, `services.sol.x`), tied to the
  Proxmox node they run on.
- **Physical hosts** — bare `{host}.x` (`vanguard.x`, `sol.x`).

`polaris.x` is the DNS *service*, distinct from the `dns` VM (`dns.sol.x`).

TLS for `.x` names is issued by an internal CA (atlas, step-ca). Its root
certificate is distributed to managed hosts by Ansible and trusted manually
(once) on personal devices.

The full service and device catalog — software choices, VLAN placement, and
name rationale — lives in `services.md`. New services are added there first.

## Tooling

- **Terraform** — provisions resources on Proxmox (VMs, LXC containers).
- **Ansible** — configures vanguard (VyOS) and all guests over SSH. Every
  managed host has the same login user as the local workstation, pre-seeded
  with the operator's SSH key; the SSH client authenticates through the
  1Password agent socket, so the private key never leaves 1Password.
- **Secrets — 1Password.** No secret values live in the repo. `.env.op` holds
  `op://` reference URLs (not values); everything is run as
  `op run --env-file=.env.op -- make <target>`, which resolves those
  references and injects them as environment variables for that process only.
  Terraform consumes them via `TF_VAR_*` and the provider's env vars; Ansible
  reads them the same way (`lookup('env', ...)`). The real values exist only
  in 1Password.
- **Services — Docker Compose on the VMs.** Each service is an Ansible role,
  deployed as a Compose project in its own dir under `/opt` (`services_root`).
  The role ships a hand-written, static `files/compose.yaml` (templated only
  when it needs injected/secret values) and brings it up inline with
  `community.docker.docker_compose_v2` — no shared deploy role. Config is
  declarative: rendered every run, container recreated on change. Per-host
  playbooks (`dns.yml`, `core.yml`, `services.yml`) list `common`, `docker`,
  then the host's service roles, each tagged with its name for
  `make apply LIMIT=<host> TAGS=<service>`.
- **bootstrap.md** — the manual steps required on a fresh device (network +
  SSH access) before Terraform/Ansible can manage it. Keep it minimal and up
  to date: it is the disaster-recovery entry point.

The repo layout follows Terraform/Ansible best practices and may be
restructured as the project grows.

## Conventions for changes

- Use IPv6 addresses from the ULA plan above; never invent addresses outside it.
- New hosts/services get a space-themed name, a DNS record, and an inventory
  entry.
- Any IPv4 usage must be justified in a comment or doc next to where it is
  introduced.
- Follow the addressing rules above: static addresses for infrastructure,
  SLAAC only for clients.
- **Removing config:** Ansible only merges `set` lines — it never deletes.
  When config is removed from the gateway templates, give the user the manual
  `delete` commands to run on the device; never bake one-off cleanup tasks
  into the playbook. Exception: VyOS factory defaults (e.g. the default NTP
  servers) are removed in code, because they come back on every fresh install
  and recovery must not depend on remembering manual steps.
- **Consider the security impact of every change.** Before applying a change,
  reason through: which trust boundaries it touches (WAN, guest/iot,
  untrusted, management), what new attack surface it adds (listening
  services, allowed flows, new protocols), and whether enforcement actually
  applies. Surface any weakening of isolation to the user explicitly — never
  bury it in a diff.
- **Keep this file current.** When a new decision is made, or you discover
  something that would help the next agent (a gotcha, a convention, a better
  approach), ask the user whether CLAUDE.md should be updated to reflect it.

## Debugging firewall issues

The firewall logs every dropped packet (`default-log` on the `forward` and
`input` chains). Workflow, on vanguard, when something can't connect:

1. **Watch drops live:** `monitor log` (or `show log firewall`) while
   reproducing the connection. A drop line shows chain, interfaces, and
   source/dest — it usually identifies the misconfigured rule immediately.
2. **Check rule hit counters:** `show firewall ipv6 forward filter` shows
   per-rule packet counts. Reproduce, re-run, and see which counter moves.
   If the expected rule isn't matching, the traffic is arriving on a
   different interface or address family than assumed.
3. **Confirm packets arrive:** `monitor traffic interface eth2.30 filter
   'tcp port 443'` (tcpdump wrapper) on the destination VLAN. Packets in but
   no replies → problem is on the destination host (its own firewall, or the
   service not listening on IPv6). No packets → routing/firewall upstream.
4. **Layer 3 sanity:** `show ipv6 route`, `show ipv6 neighbors`; from the
   client, ping the gateway ULA first, then the destination.

IPv6-specific gotchas:

- Clients use SLAAC **privacy addresses** (random GUAs) as source — rules
  matching on a specific source address may never see them. Prefer matching
  on inbound interface for client traffic.
- If DNS resolves a service name to its GUA but the service only listens on
  its ULA (or vice versa), the connection fails with **no firewall drops at
  all** — check which address the client actually dialed.
