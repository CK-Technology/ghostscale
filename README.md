# ghostscale

<div align="center">
  <img src="assets/ghostscale_logo.png" alt="ghostscale logo" width="128" height="128">

**Secure, Programmable Overlay Networking Tool built on Tailscale**

![zig](https://img.shields.io/badge/Zig-v0.15-yellow?logo=zig)
![tailscale](https://img.shields.io/badge/Built%20for-Tailscale-333?logo=tailscale)
![WireGuard](https://img.shields.io/badge/WireGuard-enabled-88171A?logo=wireguard)
![NGINX](https://img.shields.io/badge/Reverse%20Proxy-NGINX-green?logo=nginx)
![VPN](https://img.shields.io/badge/Type-VPN-grey?logo=protonvpn)

</div>

---

## Overview

**ghostscale** is a CLI-centric, Zig-powered toolkit for advanced Tailscale deployments.
It simplifies and automates routing, DNS, reverse proxying, and public exposure of services
using secure overlay networking. Ghostscale sits on top of the Tailscale stack, acting like a programmable Cloudflare Tunnel alternative — but native to your mesh.

It’s built for power users, MSPs, and self-hosters who want:

* 🔐 Tight access control
* 🛡️ Route metric automation
* 📡 Secure, auditable public exposure
* 🧠 DNS + proxy sync with zero manual touch

---

## Features

### 🛣 Route Management

* Automate Tailscale route advertisement
* Set preferred routes and failover paths
* Detect and fix common route conflicts

### 🌐 Reverse Proxy Control

* Define and expose Tailscale services via `ghostscale expose`
* Reverse proxy integration with NGINX
* Automatic cert management via DNS-01 (ACME)
* Service templates (e.g., Hudu, Portainer, UptimeKuma)

### 🧙 MagicDNS Enhancer

* Advanced DNS override layer
* Export Tailscale hostnames to PowerDNS, Technitium, etc.
* `ghostscale dns sync` maps tailnet into your real domains

### 🌩 Secure Tunneling

* Public exposure via Tailscale’s `funnel` or NGINX forward tunnels
* Local QUIC/HTTP2 tunnel support in development

### 🔧 Coordination + Integration

* Optional headscale-lite or Redis-style coordination backend
* Pluggable into `ghostmesh` and `ghostctl` ecosystem
* Zero-trust friendly with ACL + auth-key management

---

## Installation

```sh
zig build -Drelease-fast
sudo install -Dm755 zig-out/bin/ghostscale /usr/local/bin/ghostscale
```

Tailscale must be installed and running on the system. Ghostscale uses the Tailscale local API.

---

## Usage

```sh
ghostscale expose --name portainer --port 9000 --tailscale-domain portainer.cktechx.io

ghostscale dns sync --output powerdns

ghostscale route fix --auto
```

---

## Roadmap

* [x] Route metric sync
* [x] DNS override layer
* [x] Basic reverse proxy exposure
* [ ] QUIC tunnel layer (ghostfunnel)
* [ ] Web UI frontend (ghostplane)
* [ ] Zig-based DNS server (ghostdns)

---

## License

MIT

---

**Made with ⚡️ by [GhostKellz](https://github.com/ghostkellz)** for CK Technology LLC

