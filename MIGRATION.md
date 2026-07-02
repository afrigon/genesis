# Network Migration

Restructuring the homelab from the current flat-ish layout to a properly tiered
one: a dedicated **edge** tier (reverse proxy + auth as the single client entry
point), a **layered DNS** stack (which unlocks ACME DNS-01 and decouples harmony
from atlas), **management** reduced to just the physical hosts, and a single
**dualstack** VLAN that quarantines all IPv4 (UniFi gear + the operator's
IPv4-only needs) so every other tier stays pure IPv6.

The method is a **full teardown & rebuild**: finish the repo work first, then
destroy every VM and rebuild the whole environment from the repo — no in-place
morphing, no cutover period, no leftover state carried over. Downtime is free
(no one uses the services yet), and the rebuild exercises genesis's core
promise end to end: rebuildable from the repo.

---

## Target architecture

### VLANs — only `dualstack` carries IPv4; everything else is pure IPv6
| VLAN | Tier | IPv4 | Holds |
|------|------|------|-------|
| 10 | management | — | vanguard, sol (hosts only — no service VMs) |
| 20 | trusted | — | client devices (Wi-Fi `x`) |
| 30 | services | — | `core` VM (DNS+CA), `services` VM (apps) |
| 40 | iot | — | IoT devices |
| 50 | guest | — | guests (reverted to IPv6-only) |
| 60 | untrusted | — | code-execution / untrusted backends |
| 70 | edge | — | `edge` VM |
| 80 | dualstack | ✅ only | `unity` VM, nexus, quasar, operator IPv4 clients |

### VMs (on sol) — 4
| VM | VLAN | Runs |
|----|------|------|
| `core` | 30 | polaris (filter/resolver/auth) **+ atlas + atlas-ca** |
| `services` | 30 | app backends — empty until after the migration (Phase 6) |
| `edge` | 70 | harmony + janus |
| `unity` | 80 | UniFi OS Server |

### Interactions
- **Client → service:** `client → edge:443 (harmony TLS → janus auth) → backend`
  (services app / Proxmox:8006 / unity:443). Only the edge is client-reachable;
  DNS is the one direct exception.
- **Homepage:** `https://x` (the bare apex) is the homepage — a landing page on
  the edge linking to the services. This requires a cert for the bare `x` label,
  which the current atlas name constraint doesn't cover (see Gotchas).
- **DNS:** `client → core:53 (polaris-filter) → resolver → ┬ .x/unifi → polaris-auth
  └ public → Cloudflare/Google (+DNS64)`.
- **Certs (DNS-01):** harmony/lego writes `_acme-challenge` TXT to `core:5354`
  (Knot DDNS, TSIG); harmony asks `core:9000` (atlas ACME); atlas resolves the
  TXT via polaris on localhost, validates, issues the `.x` cert. Both harmony→core
  hops are ordinary `edge → services` egress; validation is a local call inside
  `core`. No atlas→harmony connection = no hairpin = no genesis aliases.
- **UniFi (zero-touch):** `dualstack` runs DHCPv4, so nexus/quasar get a v4
  lease, L2-discover unity on the same VLAN, and adopt with no manual config.
  `client → unity.x → edge → unity:443` for the UI; `gaia(30) → unity:443` API is
  the one sanctioned cross-VLAN exception.

---

## Naming
| Name | Is | Notes |
|------|----|-------|
| polaris | the DNS service | 3 containers: `polaris-filter` (AdGuard), `polaris-resolver` (Knot Resolver), `polaris-auth` (Knot DNS) |
| atlas | internal CA (step-ca) | `atlas-ca` = busybox serving the root cert at `ca.x` |
| harmony | reverse proxy (Traefik) | |
| janus | auth (forward-auth) | **parked** until the migration's done (Phase 6) |
| unity | UniFi controller | UniFi OS Server on its own VM |
| nexus | UniFi switch | (was called `lagrange`) |
| quasar | UniFi AP | the U7-Pro-IW |
| gaia | Home Assistant | future |
| hubble | monitoring (Grafana/Loki/Alloy) | future |

---

## Key decisions (and why — settled, don't re-litigate)
1. **DNS engine = Knot** (Knot Resolver + Knot DNS). Researched against Technitium
   / PowerDNS / BIND. Knot: modern, declarative config, native DNS64, RFC2136
   DDNS for ACME, and it's CZ.NIC (runs `.cz` — carrier-grade, not "a random
   thing"). Technitium rejected: imperative/API-driven config fights the
   render-from-repo IaC model.
2. **Full layered DNS** (not minimal): polaris-filter does filtering only;
   polaris-resolver does recursion + DNS64; polaris-auth is authoritative for the
   `x` and `unifi` zones + DDNS. polaris stops doing DNS64/rewrites.
3. **DNS-01 for harmony** (lego `rfc2136`). This is the whole point of the DNS
   rework — it lets harmony prove control of `*.x` by writing a TXT record
   instead of atlas connecting back, which kills the genesis-alias hairpin and
   lets harmony and atlas live on different VMs.
4. **`dns_zones` data model**: zones → relative records, `@` = apex. The `x` zone
   plus a `unifi` zone (bare `unifi` for UniFi device discovery; it can't live in
   `x` because it's not under `.x`).
5. **resolver + auth are bridged** (least-privilege, per the "host-net only when
   genuinely needed" rule), filter is host-net (needs real client source IPs).
   Internal hop is all-IPv6: resolver `fd23:1337:6769:2::2`, auth `…::3` on a
   `polaris` docker bridge.
6. **atlas lives with polaris on `core`** — foundational infra together; the CA
   key is encrypted + name-constrained, which carries the co-location risk. NOT
   on edge (that's the frontline — a proxy compromise must not reach the signing
   API). NOT its own VM (waste) or VLAN (complexity for no gain). `atlas-ca`
   stays with atlas (it just serves atlas's root cert).
7. **edge tier** = harmony + janus, the single client entry point; keeps the
   proxy's cross-tier egress one-directional instead of punching services→mgmt.
8. **management = hosts only** (vanguard, sol). No service VMs.
9. **`dualstack` (80) is the ONLY IPv4 VLAN.** UniFi gear is IPv4-first for
   adoption, and some applications still require native IPv4; both go here.
   DHCPv4 here is what makes UniFi adoption zero-touch. guest reverts to
   IPv6-only.
10. **unity → UniFi OS Server** on a dedicated VM (Ubiquiti is deprecating the
    standalone Docker Network Application). Despite the name, OS Server is a
    regular Linux application (an installer running rootless Podman containers
    on Debian 12/13+), so unity stays a normal Terraform-provisioned Debian VM
    with an Ansible role — just not a Docker Compose one. The Docker unity role
    is retired from the repo (git history keeps it).
11. **Full teardown & rebuild** (supersedes the earlier "provision alongside,
    then cut over" clean-canvas plan): once the repo work is complete, destroy
    all VMs and rebuild from scratch so no leftover state survives. Enabled by
    zero users (downtime is free) and services built to be restorable.
12. **Migration completes before anything new is added.** App backends (hubble,
    gaia, …) come after — the old "Phase 4: apps" is folded into the buildout.
13. **UniFi controller config is manual at first.** terraform/unifi against the
    old Docker unity corrupted state and silently failed to apply (cause
    unknown); the WLANs get codified later (see `.todo`), after OS Server is up.

---

## Current state (as of 2026-07-02)

### Live (the OLD layout)
- **vanguard**: carries a stale intermediate config with no repo trace (the
  applied-state changes were reset). Full live-vs-repo diff done (2026-07-02):
  RDNSS points at the old dns VM (`30::2`) on six interfaces, dualstack is
  half-applied under old rule numbers (ipv6 600/610/620, ipv4 1010/1020/1021)
  **and on `192.168.1.0/24` — the subnet the repo now assigns to the config
  port**, eth3 is on `192.168.2.0/24`, plus a stale rule 620 (dualstack →
  unity-on-services) and a bare `dhcpv6-server`. Guest IPv4 is already gone.
  Decision: **targeted deletes before the apply** (Phase 4 step 1) — the
  subnet swap makes delete-first mandatory, not optional.
- **dns VM** (`30::2`): the OLD single-container AdGuard polaris (removed from
  Terraform in the repo; dies at teardown).
- **core VM** (`30::3`): old layout — atlas + atlas-ca + harmony (TLS-ALPN ACME
  with genesis aliases).
- **services VM** (`30::4`): unity Docker (Network App + mongo).
- **nexus + quasar**: mid-adoption over eth3 (the pain the `dualstack` VLAN
  fixes); they get re-adopted fresh in Phase 5.

### Repo (done)
- Phases 1–3 built: layered polaris, atlas on `core` (dnsNames `core.sol.x`,
  `:9000`/`:9001` published), harmony on DNS-01 in `edge.yml`, zone repoints to
  `70::2`, dualstack VLAN + DHCPv4 + NAT44, inventory `core`/`services`/`edge`.
- Retirements: legacy `dns` VM dropped from Terraform; Docker unity role deleted
  (`services.yml` is `common`+`docker` only until the buildout).
- Pre-req ✅ TSIG secret generated and stored at `op://genesis/Polaris TSIG/secret`.

---

## Phased plan

### Phase 0 — VLAN groundwork ✅ applied
`edge`(70) + `untrusted`(60) added to vanguard and applied.

### Phase 1 — Gateway + Terraform target ✅ repo done
dualstack VLAN (DHCPv4 `10.0.80.0/24` + NAT44, internet-only) + guest reverted
to IPv6-only in the gateway role; `edge` VM in Terraform; inventory/playbooks
restructured (`dns` target dropped, polaris moved to `core`).

### Phase 2 — Foundation: DNS + CA on `core` ✅ repo done
The 3-container polaris stack + atlas + atlas-ca on the `core` playbook.

### Phase 3 — Edge: harmony on DNS-01 ✅ repo done
traefik `dnsChallenge` (rfc2136 → `core:5354`, TSIG `acme.x.`), `caServer` →
`https://core.sol.x:9000` via `extra_hosts` static IP, genesis network/aliases
gone, TSIG via `0600` `.env`. Firewall 210 → edge, 700 (edge→wan), 710
(edge→services).

### Phase 4 — The rebuild *(operator runbook — everything applies here)*
Order matters: gateway first (the new VLANs/rules/RDNSS must exist before the
VMs), then destroy/provision, then Ansible core → edge → services → unity.

> After step 1 the workstation has no resolver (RDNSS points at `core` before
> the new polaris exists) — set a temporary manual resolver (e.g.
> `2606:4700:4700::1111`) if internet DNS is needed; the rebuild itself never
> needs DNS (all control-plane addressing is static IP).

0. **sol:** trunk the new VLANs on the bridge — in `/etc/network/interfaces`,
   `bridge-vids 10 30 60` → `bridge-vids 10 30 60 70 80`, then `ifreload -a`
   (matches the updated bootstrap.md). Without this the edge/unity VMs are
   dead on the wire.
1. **vanguard — stale-config deletes, then apply.** The deletes come FIRST:
   the live dualstack owns `192.168.1.0/24`, which the apply wants to give the
   config port (duplicate subnet/subnet-id → failed commit). One commit, on
   vanguard (`configure` … `commit` … `save`):
   ```
   delete interfaces ethernet eth2 vif 80 address 192.168.1.1/24
   delete interfaces ethernet eth3 address 192.168.2.1/24
   delete service dhcp-server
   delete service dns forwarding
   delete service dhcpv6-server
   delete nat source rule 1010
   delete firewall ipv4 forward filter rule 1010
   delete firewall ipv4 input filter rule 1020
   delete firewall ipv4 input filter rule 1021
   delete firewall ipv6 forward filter rule 600
   delete firewall ipv6 forward filter rule 610
   delete firewall ipv6 forward filter rule 620
   delete service router-advert interface eth2.10 name-server fd22:1337:6769:30::2
   delete service router-advert interface eth2.20 name-server fd22:1337:6769:30::2
   delete service router-advert interface eth2.30 name-server fd22:1337:6769:30::2
   delete service router-advert interface eth2.70 name-server fd22:1337:6769:30::2
   delete service router-advert interface eth2.80 name-server fd22:1337:6769:30::2
   delete service router-advert interface eth3 name-server fd22:1337:6769:30::2
   ```
   (`delete service dhcp-server` / `dns forwarding` go wholesale — removing
   just the stale subnets would leave invalid empty nodes, and the apply
   re-renders both in full. Rule 210 needs no delete: same number, the apply
   overwrites its fields.) Then, from the workstation:
   `op run --env-file=ansible/.env.op -- make apply ANSIBLE_LIMIT=vanguard`.
   Verify: re-run `show configuration commands | no-more` and re-diff against
   the repo render — zero genesis-owned live-only lines expected.
2. **Teardown + provision** (destroys dns/core/services, creates fresh
   core/services/edge/unity) — on the workstation:
   ```
   op run --env-file=terraform/proxmox/.env.op -- terraform -chdir=terraform/proxmox destroy
   op run --env-file=terraform/proxmox/.env.op -- make provision TERRAFORM_DIRECTORY=proxmox
   ```
   Fresh VMs have new SSH host keys — clear the old ones
   (`ssh-keygen -R` each address) before the Ansible runs.
3. **core:** `… make apply ANSIBLE_LIMIT=core` → polaris + atlas. Verify the
   layers: `dig @fd22:1337:6769:30::3 unity.x AAAA` (filter→resolver→auth),
   a public name (recursion + filtering), an IPv4-only name (DNS64), and the
   ACME dir over TLS (`curl --cacert root_ca.crt https://core.sol.x:9000/acme/acme/directory`
   with `core.sol.x` pinned to `30::3`).
4. **edge:** `… make apply ANSIBLE_LIMIT=edge` → harmony. Verify DNS-01
   issuance in the traefik logs: the `propagation.disableANSChecks` field name
   (v3.7.5), the lego↔knot TSIG handshake, and that `polaris-auth` reads
   `knot.conf` at `0600`. Then `https://polaris.x` + `https://ca.x` from a
   trusted client.
5. **services:** `… make apply ANSIBLE_LIMIT=services` → base only
   (`common`+`docker`); app roles come in the buildout.
6. **End-to-end:** a trusted client resolves via polaris (RDNSS), reaches
   services only through the edge, and NAT64 works for IPv4-only destinations.

### Phase 5 — UniFi: `unity` VM + adoption *(repo work not started)*
- Terraform: `unity` VM on `dualstack`(80) — needs ULA `80::2` **and** an IPv4
  story (the vm module currently only does `ipv6_address`; static
  `10.0.80.2` per the reserved .2–.99 block).
- Ansible: new unity role — `podman` + `slirp4netns` + the UniFi OS Server
  installer on Debian 13.
- Repoints (were left targeting `30::4`): `unifi` zone apex → unity's address
  (or drop the zone if L2 adoption makes it moot), harmony's `unity` route →
  the OS Server UI; firewall: allow `edge → dualstack:443` for that route.
- Move nexus + quasar onto `dualstack` → DHCPv4 + L2 discovery → zero-touch
  adopt; configure the controller manually (SSIDs — codify in terraform/unifi
  later, see `.todo`); then run terraform/unifi for the VLAN networks + mgmt
  settings.

### Phase 6 — Buildout *(after the migration — nothing new before 4–5 are done)*
- janus un-parked → `edge` (forward-auth in front of services).
- App backends → `services`: hubble (monitoring), gaia/Home Assistant +
  cross-VLAN rules (`services→iot`, MQTT, mDNS reflector, the `gaia → unity`
  API exception); populate `untrusted` (internet-only).
- terraform/unifi WLAN codification.

**Critical path:** `4 → 5` — Phase 4 is one sitting (DNS is down mid-way), and
Phase 5 needs `dualstack` live from Phase 4's vanguard apply plus its own repo
work first.

**Immediate next move:** Phase 5 repo work (unity VM + role + repoints), so the
rebuild and the UniFi migration can happen in one pass — or run Phase 4 as soon
as the operator has a free window; the two are independent.

---

## Gotchas / remember
- **lego DNS-01 propagation pre-check** fails against internal-only nameservers —
  set Traefik `--dns.propagation-disable-ans` (or `delayBeforeCheck`).
- **Cert renewal cadence:** verify Traefik actually renews the short (24h) certs
  in time before relying on it; bump leaf duration if it's too lazy.
- **knot.conf** uses `zonefile-load: difference-no-serial` + `journal-content: all`
  + `zonefile-sync: -1` for the static-zonefile-plus-DDNS interaction (ACME TXTs
  are ephemeral; never flush the journal back over the rendered file).
- **atlas name constraint is `.x`** (leading dot) — covers `*.x` but likely not
  the bare `x` label, so `https://x` won't get a cert as-is. Since `https://x` is
  the homepage, the constraint **must** be widened to also permit the bare `x`
  label (add `x` alongside `.x`) so the apex landing page gets a valid cert.
- **Knot images** pinned `cznic/knot-resolver:v6.4.0`, `cznic/knot:v3.5.5` — look
  up the actual latest when applying (versions move).
- **UniFi is IPv4-first for adoption** — the entire eth3 saga. Don't fight it on
  IPv6; the `dualstack` VLAN + DHCPv4 is the real fix.
- **UniFi OS Server** needs Podman ≥4.3.1 + slirp4netns ≥1.2, ~4 GB RAM, 20 GB+
  disk; verify the UI port and the inform flow when building the role.
- **nexus shipped with an all-ports bridge** that stitched eth3 into production
  VLANs (isolation breach) — keep the gear cabled only where intended.
- **Knot Resolver forwards to IPs, not hostnames** — that's why auth has a static
  bridge address.
