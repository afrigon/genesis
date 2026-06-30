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
> clean-canvas decision it deploys to **`core`** — so Phase 1 moved the polaris
> role onto the `core` playbook and dropped the `dns` Ansible target (host_vars
> + playbook + inventory). Done. The legacy `dns` VM stays in Terraform until
> the Phase 6 teardown; do NOT `make apply LIMIT=dns` the old way.

### Pre-reqs to remember
- **TSIG secret not generated yet.** Do: `openssl rand -base64 32` → store at
  `op://genesis/Polaris TSIG/secret`. (`tsig-keygen` isn't in the cznic/knot
  image; openssl output is a cryptographically equivalent 256-bit hmac-sha256
  key.) Needed by both polaris-auth and harmony's lego.

---

## Phased plan

### Phase 0 — VLAN groundwork ✅ done
`edge`(70) + `untrusted`(60) added to vanguard and applied.

### Phase 1 — Provision the clean canvas *(Terraform + vanguard)* — repo done, apply pending
- vanguard: ✅ `dualstack`(80) added — dual-stack + DHCPv4 (`10.0.80.0/24`) +
  NAT44, internet-only, in `roles/gateway/templates/dualstack.j2` + the
  `dualstack_ipv4` var. (Adoption is L2 on the shared subnet, so no option 43 is
  needed while unity is co-located; add it in Phase 5 only if the controller ever
  moves off-subnet.) guest reverted to IPv6-only at the same time — the IPv4 role
  moved to dualstack (this pulls the guest half of Phase 6 forward).
- Terraform: ✅ **edge**(70) VM defined (`70::2`); **core**(30)/**services**(30)
  already present. Inventory ✅ `dns`→`core` polaris move + `edge` added; the
  `edge` playbook is `common`+`docker` only for now (harmony arrives Phase 3).
- Provision alongside the live VMs (cut over in Phase 6). `unity` OS-Server VM is
  an appliance → Phase 5.
- **Remaining (apply):** `terraform apply` to provision `edge`; `make apply
  LIMIT=vanguard` for the VLAN/firewall changes; `make apply LIMIT=edge` once the
  gateway permits management→`edge` SSH. Ansible only merges `set` lines, so run
  these manual deletes on vanguard to retire the old guest IPv4:
  ```
  delete interfaces ethernet eth2 vif 50 address 10.0.50.1/24
  delete service dhcp-server shared-network-name guest
  delete nat source rule 1000
  delete firewall ipv4 input filter rule 1000
  delete firewall ipv4 input filter rule 1001
  delete firewall ipv4 forward filter rule 1000
  ```

### Phase 2 — Foundation: DNS + CA → `core`
- Deploy the built polaris stack **+ atlas + atlas-ca** to `core`.
- Generate/confirm TSIG; verify layered `dig`s + the CA. Keystone — DNS live.

### Phase 3 — Edge: harmony (native DNS-01) → `edge` — repo done, apply pending
- harmony role reworked for DNS-01: traefik `dnsChallenge` (rfc2136 →
  `core:5354`, TSIG `acme.x.`), `caServer` → `https://core.sol.x:9000` (atlas's
  `ca.json` dnsNames updated to match; reached via `extra_hosts` static IP), the
  genesis network + aliases dropped. TSIG secret via a `0600` `.env` (op).
- harmony moved `core.yml` → `edge.yml`; atlas now publishes `:9000`/`:9001` so
  edge can reach it; the `ca` route targets `core:9001`.
- Zone repoint done: `polaris`/`ca`/`unity` `.x` → `70::2`, `edge.sol` added,
  retired `atlas.x`.
- Firewall: rule 210 repointed `trusted → edge:80,443`; added `edge → internet`
  (700) and `edge → services` (710). No manual `delete` needed (210 is a `set`).
- **Remaining:** operator applies vanguard + `core` + `edge`. Verify on apply:
  traefik `propagation.disableANSChecks` field name (v3.7.5), lego TSIG
  handshake against knot, and that `polaris-auth` reads `knot.conf` at `0600`.

### Phase 4 — Apps → `services`
- Deploy app backends (hubble, future) to `services`, behind the edge.

### Phase 5 — UniFi: `dualstack` + OS Server
- Provision the `unity` VM (UniFi OS Server) on `dualstack`.
- Move nexus + quasar to `dualstack` → DHCPv4 + L2 discovery → zero-touch adopt.
- Migrate controller config from the old Docker unity (backup/restore or fresh).

### Phase 6 — Cutover & decommission
- Point clients (RDNSS) at the new `core` DNS; verify end-to-end.
- Tear down old VMs (`dns`, old `core`, Docker-unity on `services`).
- IPv4 already consolidated onto `dualstack` and guest reverted to IPv6-only in
  Phase 1; just confirm nothing else still depends on native IPv4.

### Phase 7 — Buildout
- janus un-parked → `edge` (forward-auth in front of services).
- gaia/Home Assistant on `services` + cross-VLAN rules (`services→iot`, MQTT,
  mDNS reflector); populate `untrusted` (internet-only); monitoring.

**Critical path:** `1 → 2 → 3` (spine). Phase 5 (UniFi) runs in parallel once
`dualstack` exists from Phase 1 — and since the eth3 adoption is the current
pain, pulling Phase 5's `dualstack` forward fixes it soonest. (guest's revert to
IPv6-only already rode along with `dualstack` in Phase 1.)

**Immediate next move: apply.** Phases 1–3 repo work is done; the spine is now
apply-gated (operator, when home): provision via Terraform, then `make apply`
vanguard → `core` (Phase 2: polaris + atlas) → `edge` (Phase 3: harmony).

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
- **nexus shipped with an all-ports bridge** that stitched eth3 into production
  VLANs (isolation breach) — keep the gear cabled only where intended.
- **Knot Resolver forwards to IPs, not hostnames** — that's why auth has a static
  bridge address.
