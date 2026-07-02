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
- **Everything by name — on the data plane.** Client-facing services are
  referenced by DNS name (self-hosted DNS) so they get TLS and can move hosts.
  The *control/bootstrap plane* — Terraform, inventory, firewall rules, the
  addresses services bind to — uses static IPs: it must work before and without
  DNS (you can't use DNS to deploy DNS). Internal machine-to-machine hops (e.g.
  harmony → a backend) also use static IPs, so polaris is only ever a dependency
  for client-facing name resolution, never for running-service traffic.
- **Secure by default.** Every service must have proper authentication and a
  valid SSL/TLS certificate — no plain HTTP, no unauthenticated services.
- **Reverse proxy only.** Services must not be directly reachable; all client
  access goes through the reverse proxy (harmony, on the `core` VM), which
  enforces auth, SSL, and access policy. Backends run on the `services` VM;
  harmony reaches them through a Traefik file-provider config — one route per
  service mapping `{service}.x` to its backend's static address on the services
  VM (Traefik's label auto-discovery only sees containers on its own Docker
  host, and harmony runs on a different host from the apps). Enforcement is
  entirely on vanguard, not host firewalls: the forward chain default-drops and
  only `clients → harmony:443` is opened, so clients cannot reach backend ports.
  Stronger intra-tier isolation, if ever needed, comes from giving the app tier
  its own VLAN (gateway-mediated) — never host-level firewalls. harmony
  terminates client TLS and speaks plain HTTP to backends; that hop is fine only
  while it stays host-internal (VM-to-VM on sol's bridge never reaches the
  physical wire). A backend on a different *physical* machine would cross the
  wire in plaintext, so it must get end-to-end TLS (re-encrypt to a backend
  serving its own atlas cert).
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
| 60   | untrusted  | `fd22:1337:6769:60::/64`  | Code-execution / untrusted backends |
| 70   | edge       | `fd22:1337:6769:70::/64`  | Edge / single client entry point (harmony) |
| 80   | dualstack  | `fd22:1337:6769:80::/64`  | The only IPv4 VLAN — UniFi gear + operator IPv4 needs |

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
- **IPv4 is quarantined to the dualstack VLAN (80).** UniFi gear is IPv4-first
  for adoption and some applications still require native IPv4, so a single VLAN
  carries it and every other VLAN stays pure IPv6 — hop onto dualstack when you
  need IPv4. It gets DHCPv4 (`10.0.80.0/24`) + NAT44, internet-only (intra-VLAN
  L2 is how UniFi devices reach the controller; cross-VLAN traffic to unity is
  IPv6), all in `roles/gateway/templates/dualstack.j2` and the `dualstack_ipv4`
  var. Other VLANs reach IPv4-only hosts via NAT64 instead.
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

Every managed host sets `host_description` in its host_vars, shown in the SSH
login banner. Format: `{Name} / {software or role}` (e.g.
`Unity / UniFi OS Server`).

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
  in 1Password. **Into containers**, compose files stay static (never `.j2`) and
  hold no secret literals; Ansible renders each service's secrets into a
  dedicated host file (`0600`, `no_log`, registered so a change recreates the
  container), and the container receives them by the least-exposing path its
  software supports: a mounted file (step-ca's key), an inline rendered config
  file where the app has no alternative (knot.conf's TSIG key), or a `0600`
  `.env` interpolated by compose (`${VAR}`) for env-only apps (lego, mongo).
- **Services — Docker Compose on the VMs.** Each service is an Ansible role,
  deployed as a Compose project in its own dir under `/opt` (`services_root`).
  The role ships a hand-written, static `files/compose.yaml` (templated only
  when it needs injected/secret values) and brings it up inline with
  `community.docker.docker_compose_v2` — no shared deploy role. Config is
  declarative: rendered every run, container recreated on change. Per-host
  playbooks (`core.yml`, `services.yml`, `edge.yml`) list `common`, `docker`,
  then the host's service roles, each tagged with its name for
  `make apply ANSIBLE_LIMIT=<host> ANSIBLE_TAGS=<service>`.
- **Container networking — bridge by default, host by exception.** Services run
  in bridge mode and publish only the ports they need; the Docker daemon is
  configured for IPv6 (`/etc/docker/daemon.json`: `ipv6` + `ip6tables` +
  `fixed-cidr-v6` `fd23:1337:6769::/64`) so published ports are reachable over
  IPv6. Bridge gives per-container isolation and avoids host-port clashes when
  many services share a host. Use host mode only when a service genuinely needs
  the host's real network — e.g. polaris (DNS), which must see real client
  source IPs (a bridged `:53` would SNAT every query to the docker gateway). The
  docker-bridge ULA is host-local and NAT'd — never on the LAN — so it sits
  outside the routed `fd22:1337:6769::/48`. Every container sets `container_name`
  matching its compose service, so it has a stable name for `docker logs`/`exec`
  instead of Compose's `<project>-<service>-<N>`.
- **Service definition hygiene.** Beyond `container_name` (above), every Compose
  service declares a `hostname` (the bare name, matching `container_name` — e.g.
  `gaia`, `polaris-resolver`; never the `.x` domain, which resolves to harmony,
  not the backend, and is a routing name owned by the proxy), a `TZ` env, and an
  explicit `restart: unless-stopped`. Set `PUID`/`PGID` **only** on LinuxServer.io images
  — those alone read them (to drop privileges and own bind-mounts); official
  images ignore them, so use `user:` instead when a non-root run is needed. Do
  **not** add Traefik (or other) routing labels to backends: harmony runs on a
  different Docker host than the apps and can't see their labels, so all routing
  lives in harmony's Traefik file provider (see "Reverse proxy only"), never in
  per-container labels.
- **bootstrap.md** — the manual steps required on a fresh device (network +
  SSH access) before Terraform/Ansible can manage it. Keep it minimal and up
  to date: it is the disaster-recovery entry point.

The repo layout follows Terraform/Ansible best practices and may be
restructured as the project grows.

## Conventions for changes

- **Never run commands against the live infrastructure.** The agent does not
  touch vanguard, sol, the VMs, or any managed host — no raw SSH, no ad-hoc
  Ansible, no `make check`/`make apply`/`terraform apply`, and **not even
  read-only diagnostics** (`show ipv6 neighbors`, `monitor log`, `docker ps`,
  etc.). The operator runs everything by hand. The agent's job is to produce
  the exact command(s) and say **where to run them** (e.g. "on vanguard",
  "on the services VM"); the operator executes and pastes results back. This
  keeps a human in the loop on every change and every probe of production.
- **Comments explain the non-obvious _why_, never the _what_.** Default to no
  comment. Add one only for what the code can't show: a constraint, trade-off,
  gotcha, or provenance. Never restate what a line plainly does, and don't
  narrate structure with prose — a terse section header is enough. Deferred work
  belongs in `.todo`, never in a code comment. Match the surrounding files; they
  are sparsely commented.
- Use IPv6 addresses from the ULA plan above; never invent addresses outside it.
- New hosts/services get a space-themed name, a DNS record, and an inventory
  entry.
- When pinning a version (container image tag, package, schema), look up the
  actual current latest version rather than guessing from memory — they move.
- Read facts through `ansible_facts['x']`, never the injected `ansible_x`
  variables (deprecated, removed in ansible-core 2.24).
- Any IPv4 usage must be justified in a comment or doc next to where it is
  introduced.
- Follow the addressing rules above: static addresses for infrastructure,
  SLAAC only for clients.
- **Firewall policy is data.** Inter-VLAN accept rules live in `firewall_flows`
  (`ansible/host_vars/vanguard.yml`), grouped by purpose; protocol plumbing
  (ICMPv6, NAT64, QUIC) and the input chains stay literal in `firewall.j2`.
  Fields: `source`/`destination` are VLAN names (`wan` = internet egress; omit
  `destination` for everywhere); `ports` is always a list. Rule numbers are
  stable IDs and the operator's deletion targets — never renumber or reuse
  them. Scheme: one hundreds-block per source tier (VLAN id × 10: management
  100s … dualstack 800s); x00 is the tier's broadest egress, with specific
  destinations in the tens above it; below 100 is protocol plumbing; 1000+ is
  IPv4 (config-port, dualstack).
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
`input` chains). These are commands the **operator** runs on vanguard (the
agent provides them, per the rule above) when something can't connect:

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
