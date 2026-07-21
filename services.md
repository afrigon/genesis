# Services

Every service is reachable by DNS name following the convention `{service}.x`
(e.g. `gaia.x`, `andromeda.x`). Records live in the `dns_zones` map (polaris
role), served by polaris; services behind the reverse proxy resolve to
harmony, which routes by hostname and enforces auth (janus) and TLS.

TLS: an internal CA (atlas) issues certificates for `.x` names. Its root
certificate must be trusted on every managed device.

## Infrastructure

| Name     | What                          | VLAN         |
|----------|-------------------------------|--------------|
| vanguard | VyOS gateway / firewall       | all (router) |
| sol      | Proxmox VE host — UI at `proxmox.sol.x` | management   |
| titan    | Arch Linux workstation        | trusted      |
| ceres    | NAS (dedicated machine)       | management   |
| quasar   | Wi-Fi access point            | dualstack    |
| nexus    | Managed switch                | dualstack    |
| relay    | Managed switch (living room)  | dualstack    |
| rover    | Mac mini (macOS CI runner)    | untrusted    |

## Services

All run in containers on sol's VMs: DNS + CA on `core` and apps on `services`
(both services VLAN), the proxy pair on `edge`, and unity on its own VM
(dualstack) — except the untrusted VLAN entries.

| Name      | Software                     | Role                          |
|-----------|------------------------------|-------------------------------|
| harmony   | Traefik                      | Reverse proxy, TLS, routing   |
| polaris   | AdGuard + Knot Resolver + Knot DNS | DNS: filtering, DNS64, authoritative `x` |
| janus     | Authelia                     | Authentication (forward-auth + login portals) |
| tycho     | lldap                        | Identity directory (users, groups) |
| atlas     | step-ca                      | Internal certificate authority |
| airlock   | Tailscale                    | VPN / remote access (on sol)  |
| unity     | UniFi OS Server              | Network controller (APs, switches) |
| hubble    | Grafana (+ Prometheus, Loki) | Monitoring & logs             |
| pulsar    | Uptime Kuma                  | Uptime monitoring             |
| houston   | Homepage (or custom web app) | Dashboard / home page         |
| beacon    | ntfy                         | Notifications                 |
| gaia      | Home Assistant               | Home automation               |
| echo      | Mosquitto                    | MQTT broker                   |
| rosetta   | Zigbee2MQTT                  | Zigbee bridge                 |
| capcom    | Whisper + Piper (Wyoming)    | Voice: speech-to-text / text-to-speech for gaia |
| lyra      | Music Assistant              | Music library / multi-room streaming |
| kepler    | n8n                          | Workflow automation           |
| andromeda | Jellyfin + servarr            | Media server                  |
| nebula    | Immich                       | Photo management              |

### Untrusted VLAN (60)

For services running 3rd-party or arbitrary code. Internet access only: no
access to other VLANs, and no access to each other within the VLAN.
Intra-VLAN traffic never reaches vanguard, so isolation is enforced at the
bridge/switch layer: the Proxmox per-VM firewall for guests on sol, and port
isolation on nexus for physical machines.

| Name   | Software              | Role                          |
|--------|-----------------------|-------------------------------|
| europa | Minecraft server      | Game server (3rd-party mods)  |
| probe  | GitHub Actions runner | CI (arbitrary code execution) |

## Devices

Consumer devices (Apple TV, Chromecast, game consoles, smart speakers, TVs)
live on the trusted VLAN. Unauditable hardware lives in iot: trusted can
reach it, it can only reach the internet.

| Name    | What            | VLAN      |
|---------|-----------------|-----------|
| nova    | 3D printer      | iot       |
| aurora  | Ink printer     | iot       |
| pioneer | Label printer   | iot       |
| triton  | IR/RF blaster (Broadlink RM4 Pro, AC control) | iot |
| sputnik | Zigbee coordinator | dualstack |
| photon  | Smart PDU       | dualstack |
| eclipse | UPS (future)    | dualstack |
| telstar | Apple TV        | trusted |
| —       | Chromecast      | trusted |

## Name rationale

- **harmony** — ISS module that connects the others; the proxy everything passes through
- **polaris** — the star you navigate by; DNS is how everything finds everything
- **janus** — Saturn moon, god of gates and doorways; the auth gateway
- **tycho** — Tycho Brahe's star catalogue, positions for a thousand stars; the directory every identity is looked up in
- **atlas** — the titan holding everything up; the root of trust
- **airlock** — the only controlled way in from outside; VPN
- **unity** — ISS Node 1, the module that joins all the others into one station; the controller that unifies the UniFi fabric (and it sounds like UniFi)
- **hubble** — observes everything; monitoring
- **pulsar** — emits regular signals you can set your clock by; uptime checks
- **houston** — mission control, the page you glance at
- **beacon** — broadcasts signals; notifications
- **gaia** — the home itself
- **echo** — the balloon satellite that relayed any signal bounced off it; the MQTT broker
- **rosetta** — the mission named for the stone that unlocked translation; Zigbee ↔ MQTT
- **capcom** — the voice of mission control, the one role that both listens and speaks to the crew; speech ↔ text
- **lyra** — Orpheus's lyre drawn in the sky, the instrument among the constellations; music
- **kepler** — orbital mechanics; scheduled workflows
- **andromeda** — a galaxy of media
- **nebula** — colorful clouds captured in pictures; photos
- **europa** — an icy world to explore; minecraft
- **probe** — expendable craft sent to execute a task; CI runner
- **rover** — same, but it's hardware that does the work; macOS runner
- **ceres** — dwarf planet in the asteroid belt, a mass of accumulated stuff; storage
- **quasar** — the brightest radio source in the sky; the AP
- **nexus** — the central junction where every connection converges; the switch
- **relay** — a relay satellite exists to pass every signal onward; the switch that extends the fabric to the living room
- **nova** — creates new matter; 3D printer
- **aurora** — paints color across the sky; the ink printer
- **pioneer** — the Pioneer plaque, a tag bolted on to identify; the label printer
- **triton** — the coldest surface in the solar system, venting invisible geyser plumes; the blaster that runs the AC
- **sputnik** — the first radio transmitter in orbit; the Zigbee coordinator only speaks radio
- **telstar** — the satellite that relayed the first live transatlantic television broadcast; the box that relays television to our screen
- **titan** — the heavyweight moon; workstation
- **photon** — the particle that delivers the sun's energy to everything; the PDU
- **eclipse** — satellites run on batteries while crossing the shadow; the UPS
