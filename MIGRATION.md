# Network Migration

Restructuring the homelab from the current flat-ish layout to a properly tiered
one: a dedicated **edge** tier (reverse proxy + auth as the single client entry
point), a **layered DNS** stack (which unlocks ACME DNS-01 and decouples harmony
from atlas), **management** reduced to just the physical hosts, and a single
**dualstack** VLAN that quarantines all IPv4 (UniFi gear + the operator's
IPv4-only needs) so every other tier stays pure IPv6.

The method is a **clean canvas**: provision the target VMs/VLANs first, deploy
each service straight into its final home (alongside the live setup, then cut
over) — rather than morphing live VMs in place. This also exercises genesis's
core promise: rebuildable from the repo.

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
| `services` | 30 | hubble (monitoring), gaia (Home Assistant), future apps |
| `edge` | 70 | harmony + janus |
| `unity` | 80 | UniFi OS Server (appliance, not a Docker host) |

### Interactions
- **Client → service:** `client → edge:443 (harmony TLS → janus auth) → backend`
  (services app / Proxmox:8006 / unity:443). Only the edge is client-reachable;
  DNS is the one direct exception.
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
  the one sanctioned east-west exception.

---

## Naming
| Name | Is | Notes |
|------|----|-------|
| polaris | the DNS service | 3 containers: `polaris-filter` (AdGuard), `polaris-resolver` (Knot Resolver), `polaris-auth` (Knot DNS) |
| atlas | internal CA (step-ca) | `atlas-ca` = busybox serving the root cert at `ca.x` |
| harmony | reverse proxy (Traefik) | |
| janus | auth (forward-auth) | **parked** until the migration's done (Phase 7) |
| unity | UniFi controller | migrating Docker Network App → **UniFi OS Server** |
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
   Internal hop is all-IPv6: resolver `fd23:1337:6769:2::a`, auth `…::b` on a
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
   adoption, and the operator has IPv4-only needs (games, IPv4-only VPNs); both
   go here. DHCPv4 here is what makes UniFi adoption zero-touch. guest
   reverts to IPv6-only.
10. **unity → UniFi OS Server** on a dedicated VM (Ubiquiti is deprecating the
    standalone Docker Network Application).
11. **Clean-canvas approach** (provision target first, deploy into final homes)
    over in-place morphing.

---

## Current state (as of 2026-06-24)

### Live (the OLD layout still running)
- **vanguard**: all VLANs incl. `edge`(70) + `untrusted`(60) **applied**. guest
  still dual-stack (IPv4).
- **dns VM** (`30::2`): the OLD single-container AdGuard polaris.
- **core VM** (`30::3`): atlas + atlas-ca + harmony (harmony on TLS-ALPN ACME
  with genesis aliases; fronting `polaris.x`, `unity.x` route added).
- **services VM** (`30::4`): unity Docker (Network App + mongo), with the
  `MONGO_PORT`, `extra_hosts unifi`, and genesis-network fixes applied.
- **nexus + quasar**: mid-adoption, painfully, over eth3 (IPv6-only → manual
  per-device IP hacks). This is the symptom that the `dualstack` VLAN fixes.

### Built in the repo, NOT applied
- **The 3-container polaris rework** (the entire layered DNS stack) — supersedes
  the live AdGuard-only polaris. Lives in `ansible/roles/polaris/`:
  `files/compose.yaml`, `templates/{AdGuardHome.yaml.j2,config.yaml.j2,
  knot.conf.j2,zone.j2}`, `vars/main.yml` (the `dns_zones` map +
  `polaris_resolver_address`/`polaris_auth_address`), `tasks/main.yml`.
- `ansible/.env.op` references `POLARIS_TSIG_SECRET` (op://genesis/Polaris TSIG/secret).

> NOTE: the polaris role was built referencing the `dns` host, but per the
> clean-canvas decision it deploys to **`core`** — so Phase 1 renames the
> inventory `dns`→`core` (host_vars + playbook). Do NOT `make apply LIMIT=dns`
> the old way.

### Pre-reqs to remember
- **TSIG secret not generated yet.** Do: `openssl rand -base64 32` → store at
  `op://genesis/Polaris TSIG/secret`. (`tsig-keygen` isn't in the cznic/knot
  image; openssl output is a cryptographically equivalent 256-bit hmac-sha256
  key.) Needed by both polaris-auth and harmony's lego.

---

## Phased plan

### Phase 0 — VLAN groundwork ✅ done
`edge`(70) + `untrusted`(60) added to vanguard and applied.

### Phase 1 — Provision the clean canvas *(Terraform + vanguard)*
- vanguard: add `dualstack`(80, dual-stack + DHCPv4 + option 43 controller hint).
- Terraform: define + provision target Docker-host VMs **core**(30),
  **services**(30), **edge**(70). Update inventory (`dns`→`core`, add `edge`).
- Provision alongside the live VMs (cut over in Phase 6). `unity` OS-Server VM is
  an appliance → Phase 5.

### Phase 2 — Foundation: DNS + CA → `core`
- Deploy the built polaris stack **+ atlas + atlas-ca** to `core`.
- Generate/confirm TSIG; verify layered `dig`s + the CA. Keystone — DNS live.

### Phase 3 — Edge: harmony (native DNS-01) → `edge`
- Deploy harmony to `edge` with lego `rfc2136 → core:5354` from the start — no
  genesis aliases ever created.
- Repoint `{service}.x` → edge; firewall: `clients→edge`, `edge→services`, etc.

### Phase 4 — Apps → `services`
- Deploy app backends (hubble, future) to `services`, behind the edge.

### Phase 5 — UniFi: `dualstack` + OS Server
- Provision the `unity` VM (UniFi OS Server) on `dualstack`.
- Move nexus + quasar to `dualstack` → DHCPv4 + L2 discovery → zero-touch adopt.
- Migrate controller config from the old Docker unity (backup/restore or fresh).

### Phase 6 — Cutover & decommission
- Point clients (RDNSS) at the new `core` DNS; verify end-to-end.
- Tear down old VMs (`dns`, old `core`, Docker-unity on `services`).
- Consolidate IPv4 onto `dualstack`; revert guest → IPv6-only (remove `guest_ipv4`
  + the manual vanguard `delete`s per `.todo`).

### Phase 7 — Buildout
- janus un-parked → `edge` (forward-auth in front of services).
- gaia/Home Assistant on `services` + east-west rules (`services→iot`, MQTT,
  mDNS reflector); populate `untrusted` (internet-only); monitoring.

**Critical path:** `1 → 2 → 3` (spine). Phase 5 (UniFi) runs in parallel once
`dualstack` exists from Phase 1 — and since the eth3 adoption is the current
pain, pulling Phase 5's `dualstack` forward fixes it soonest. Phase 6 is the one
cross-track join (guest can't go IPv6-only until IPv4 lives on `dualstack`).

**Immediate next move: Phase 1** — the Terraform VM/VLAN definitions.

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
  the bare `x` label, so `https://x` won't get a cert (`http://x` via the apex is
  fine). Revisit the constraint if a landing page at `x` is wanted.
- **Knot images** pinned `cznic/knot-resolver:v6.4.0`, `cznic/knot:v3.5.5` — look
  up the actual latest when applying (versions move).
- **UniFi is IPv4-first for adoption** — the entire eth3 saga. Don't fight it on
  IPv6; the `dualstack` VLAN + DHCPv4 is the real fix.
- **nexus shipped with an all-ports bridge** that stitched eth3 into production
  VLANs (isolation breach) — keep the gear cabled only where intended.
- **Knot Resolver forwards to IPs, not hostnames** — that's why auth has a static
  bridge address.
