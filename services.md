# Services

Every service is reachable by DNS name following the convention `{service}.x`
(e.g. `gaia.x`, `andromeda.x`). Records live in polaris (AdGuard Home);
services behind the reverse proxy resolve to harmony, which routes by
hostname and enforces auth (janus) and TLS.

TLS: an internal CA (atlas) issues certificates for `.x` names. Its root
certificate must be trusted on every managed device.

## Infrastructure

| Name     | What                          | VLAN         |
|----------|-------------------------------|--------------|
| vanguard | VyOS gateway / firewall       | all (router) |
| sol      | Proxmox VE host               | management   |
| titan    | Windows workstation           | trusted      |
| ceres    | NAS (dedicated machine)       | management   |
| quasar   | Wi-Fi access point            | management   |
| lagrange | Managed switch                | management   |
| rover    | Mac mini (macOS CI runner)    | untrusted    |

## Services

All run as VMs/LXC on sol, in the services VLAN, behind harmony — except the
untrusted VLAN entries.

| Name      | Software                     | Role                          |
|-----------|------------------------------|-------------------------------|
| harmony   | Traefik                      | Reverse proxy, TLS, routing   |
| polaris   | AdGuard Home                 | DNS, ad blocking              |
| janus     | Authelia                     | SSO / authentication          |
| atlas     | step-ca                      | Internal certificate authority |
| airlock   | Tailscale                    | VPN / remote access (on sol)  |
| unity     | UniFi Network Application    | Network controller (APs, switches) |
| hubble    | Grafana (+ Prometheus, Loki) | Monitoring & logs             |
| pulsar    | Uptime Kuma                  | Uptime monitoring             |
| houston   | Homepage (or custom web app) | Dashboard / home page         |
| beacon    | ntfy                         | Notifications                 |
| gaia      | Home Assistant               | Home automation               |
| hermes    | Mosquitto                    | MQTT broker                   |
| soyuz     | Zigbee2MQTT                  | Zigbee bridge                 |
| kepler    | n8n                          | Workflow automation           |
| andromeda | Jellyfin                     | Media server                  |
| nebula    | Immich                       | Photo management              |

### Untrusted VLAN (60, to be created)

For services running 3rd-party or arbitrary code. Internet access only: no
access to other VLANs, and no access to each other within the VLAN.
Intra-VLAN traffic never reaches vanguard, so isolation is enforced at the
bridge/switch layer: the Proxmox per-VM firewall for guests on sol, and port
isolation on lagrange for physical machines.

| Name   | Software              | Role                          |
|--------|-----------------------|-------------------------------|
| europa | Minecraft server      | Game server (3rd-party mods)  |
| probe  | GitHub Actions runner | CI (arbitrary code execution) |

## Devices

Consumer devices (Apple TV, Chromecast, game consoles, smart speakers, TVs)
live on the trusted VLAN. Unauditable hardware lives in iot: trusted can
reach it, it can only reach the internet.

| Name    | What            | VLAN    |
|---------|-----------------|---------|
| nova    | 3D printer      | iot     |
| aurora  | Ink printer     | iot     |
| pioneer | Label printer   | iot     |
| —       | Apple TV        | trusted |
| —       | Chromecast      | trusted |

## Name rationale

- **harmony** — ISS module that connects the others; the proxy everything passes through
- **polaris** — the star you navigate by; DNS is how everything finds everything
- **janus** — Saturn moon, god of gates and doorways; the auth gateway
- **atlas** — the titan holding everything up; the root of trust
- **airlock** — the only controlled way in from outside; VPN
- **unity** — ISS Node 1, the module that joins all the others into one station; the controller that unifies the UniFi fabric (and it sounds like UniFi)
- **hubble** — observes everything; monitoring
- **pulsar** — emits regular signals you can set your clock by; uptime checks
- **houston** — mission control, the page you glance at
- **beacon** — broadcasts signals; notifications
- **gaia** — the home itself
- **hermes** — asteroid named for the messenger god; MQTT shuttles messages
- **soyuz** — the docking craft bridging two worlds; Zigbee ↔ IP
- **kepler** — orbital mechanics; scheduled workflows
- **andromeda** — a galaxy of media
- **nebula** — colorful clouds captured in pictures; photos
- **europa** — an icy world to explore; minecraft
- **probe** — expendable craft sent to execute a task; CI runner
- **rover** — same, but it's hardware that does the work; macOS runner
- **ceres** — dwarf planet in the asteroid belt, a mass of accumulated stuff; storage
- **quasar** — the brightest radio source in the sky; the AP
- **lagrange** — the point where things meet and hold position; the switch
- **nova** — creates new matter; 3D printer
- **aurora** — paints color across the sky; the ink printer
- **pioneer** — the Pioneer plaque, a tag bolted on to identify; the label printer
- **titan** — the heavyweight moon; workstation
