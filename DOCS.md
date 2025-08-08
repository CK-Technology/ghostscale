# Ghostscale Documentation

## Table of Contents
- [Overview](#overview)
- [Installation](#installation)
- [Configuration](#configuration)
- [Commands](#commands)
  - [expose](#expose-command)
  - [dns](#dns-command)
  - [route](#route-command)
- [Examples](#examples)
- [Architecture](#architecture)
- [API Reference](#api-reference)

## Overview

Ghostscale is a CLI-centric, Zig-powered toolkit for advanced Tailscale deployments. It simplifies and automates routing, DNS, reverse proxying, and public exposure of services using secure overlay networking.

### Key Features

- 🔐 **Secure by Default** - All traffic flows through WireGuard-encrypted Tailscale tunnels
- 🛣 **Smart Routing** - Automatic route conflict detection and resolution
- 🌐 **Multi-Provider DNS** - Sync with PowerDNS, Technitium, BIND9, and more
- 📡 **Public Exposure** - Safely expose internal services via Tailscale Funnel
- 🔧 **Zero-Touch Automation** - Set it and forget it with auto-cert and auto-config

## Installation

### Prerequisites

- Zig 0.15+ (for building from source)
- Tailscale installed and authenticated
- NGINX (for reverse proxy features)
- Root/sudo access (for network configuration)

### Build from Source

```bash
# Clone the repository
git clone https://github.com/ghostkellz/ghostscale.git
cd ghostscale

# Fetch dependencies
zig fetch --save https://github.com/ghostkellz/flash/archive/main.tar.gz

# Build release version
zig build -Doptimize=ReleaseFast

# Install system-wide
sudo install -Dm755 zig-out/bin/ghostscale /usr/local/bin/ghostscale
```

### Verify Installation

```bash
ghostscale --version
# Output: ⚡ ghostscale 0.1.0 - ⚡ Flash

ghostscale --help
```

## Configuration

### Environment Variables

```bash
# Tailscale API configuration
export TAILSCALE_API_KEY="tskey-api-..."
export TAILSCALE_TAILNET="example.com"

# DNS provider credentials
export POWERDNS_API_KEY="your-api-key"
export POWERDNS_SERVER="https://dns.example.com"

# Certificate management
export ACME_EMAIL="admin@example.com"
export CERT_DIR="/etc/ssl/ghostscale"
```

### Configuration File

Create `~/.config/ghostscale/config.toml`:

```toml
[tailscale]
api_url = "http://localhost:41641"
tailnet = "example.com"

[nginx]
config_dir = "/etc/nginx/sites-available"
reload_command = "systemctl reload nginx"

[dns]
default_provider = "powerdns"
zone = "internal.example.com"

[acme]
provider = "letsencrypt"
email = "admin@example.com"
```

## Commands

### Expose Command

Expose internal services through Tailscale with automatic HTTPS and reverse proxy configuration.

```bash
ghostscale expose [OPTIONS]
```

#### Options

| Option | Description | Default |
|--------|-------------|---------|
| `--name <name>` | Service identifier (required) | - |
| `--port <port>` | Service port number | 80 |
| `--domain <domain>` | Public domain name (required) | - |
| `--ssl` | Enable HTTPS | false |
| `--funnel` | Use Tailscale Funnel for public access | false |
| `--auto-cert` | Automatically obtain SSL certificate | false |
| `--cert-provider <provider>` | Certificate provider (tailscale/letsencrypt/zerossl) | tailscale |
| `--template <template>` | Service template (portainer/uptime-kuma/hudu) | custom |

#### Examples

```bash
# Expose a local service with automatic HTTPS
ghostscale expose --name myapp --port 3000 --domain app.example.com --ssl --auto-cert

# Expose Portainer with Tailscale Funnel
ghostscale expose --name portainer --port 9000 --domain portainer.example.com --funnel

# Use a service template for Uptime Kuma
ghostscale expose --template uptime-kuma --domain status.example.com --ssl
```

### DNS Command

Manage DNS records and synchronize Tailscale hostnames with external DNS providers.

```bash
ghostscale dns <SUBCOMMAND> [OPTIONS]
```

#### Subcommands

##### `dns sync`

Synchronize Tailscale device names to external DNS.

```bash
ghostscale dns sync --output <provider> [OPTIONS]
```

Options:
- `--output <provider>` - DNS provider (powerdns/technitium/bind9)
- `--zone <zone>` - DNS zone to update
- `--api-key <key>` - API key for DNS provider
- `--server <url>` - DNS server URL

##### `dns export`

Export DNS records in various formats.

```bash
ghostscale dns export --format <format> [OPTIONS]
```

Options:
- `--format <format>` - Export format (json/bind/csv)
- `--output <file>` - Output file path

##### `dns status`

Show current DNS configuration and device mappings.

```bash
ghostscale dns status
```

#### Examples

```bash
# Sync to PowerDNS
ghostscale dns sync --output powerdns --zone internal.example.com \
  --api-key "secret" --server "https://dns.example.com"

# Export as BIND zone file
ghostscale dns export --format bind --output /tmp/tailscale.zone

# Export as JSON for automation
ghostscale dns export --format json --output devices.json

# Check current DNS status
ghostscale dns status
```

### Route Command

Manage Tailscale subnet routes and resolve conflicts.

```bash
ghostscale route <SUBCOMMAND> [OPTIONS]
```

#### Subcommands

##### `route fix`

Automatically detect and fix route conflicts.

```bash
ghostscale route fix [--auto]
```

Options:
- `--auto` - Automatically apply fixes without confirmation

##### `route advertise`

Advertise subnet routes to the Tailscale network.

```bash
ghostscale route advertise --routes <routes>
```

Options:
- `--routes <routes>` - Comma-separated list of CIDR routes

##### `route status`

Display current route configuration and peer status.

```bash
ghostscale route status
```

#### Examples

```bash
# Fix route conflicts automatically
ghostscale route fix --auto

# Advertise multiple subnets
ghostscale route advertise --routes "10.0.0.0/24,192.168.1.0/24"

# Check route status
ghostscale route status
```

## Examples

### Complete Workflow Examples

#### 1. Expose Internal Dashboard

```bash
# Step 1: Advertise the subnet where your service lives
ghostscale route advertise --routes "10.0.0.0/24"

# Step 2: Sync DNS records for easy access
ghostscale dns sync --output powerdns --zone internal.company.com

# Step 3: Expose the dashboard with auto-cert
ghostscale expose --name dashboard --port 3000 \
  --domain dashboard.company.com --ssl --auto-cert
```

#### 2. Public Service with Tailscale Funnel

```bash
# Expose a status page publicly via Tailscale Funnel
ghostscale expose --name status --port 3001 \
  --domain status.public.company.com --funnel

# The service is now accessible from the internet securely
```

#### 3. Multi-Site Route Management

```bash
# Site A: Advertise local subnets
ghostscale route advertise --routes "10.1.0.0/16"

# Site B: Advertise local subnets
ghostscale route advertise --routes "10.2.0.0/16"

# Central: Fix any conflicts
ghostscale route fix --auto

# Verify connectivity
ghostscale route status
```

#### 4. Automated DNS Integration

```bash
# Export all Tailscale devices to BIND format
ghostscale dns export --format bind --output /etc/bind/zones/tailscale.zone

# Or sync directly to PowerDNS API
ghostscale dns sync --output powerdns \
  --zone ts.company.com \
  --api-key "$POWERDNS_KEY" \
  --server "https://dns.company.com"

# Verify DNS records
ghostscale dns status
```

## Architecture

### Component Overview

```
┌─────────────────────────────────────────────────┐
│                   Ghostscale CLI                 │
├─────────────────────────────────────────────────┤
│                   Flash Framework                │
├──────────────┬──────────────┬───────────────────┤
│   Expose     │     DNS      │      Route        │
│   Module     │    Module    │     Module        │
├──────────────┴──────────────┴───────────────────┤
│              Tailscale API Client               │
├──────────────────────────────────────────────────┤
│         System Integration Layer                 │
│    (NGINX, DNS Providers, ACME, Networking)     │
└──────────────────────────────────────────────────┘
```

### Module Descriptions

#### Tailscale Module (`src/tailscale.zig`)
- Handles all Tailscale API interactions
- Manages device status and peer information
- Controls Funnel and Serve configurations
- Routes advertisement and management

#### NGINX Module (`src/nginx.zig`)
- Generates NGINX configuration files
- Manages SSL/TLS termination
- Handles upstream proxy configuration
- Provides config testing and reload functionality

#### ACME Module (`src/acme.zig`)
- Automates certificate acquisition
- Supports multiple ACME providers
- Integrates with Tailscale's native cert system
- Handles renewal and expiry checking

#### DNS Module (`src/commands/dns.zig`)
- Multi-provider DNS synchronization
- Export in multiple formats
- Batch updates for efficiency
- MagicDNS integration

#### Route Module (`src/commands/route.zig`)
- Subnet route advertisement
- Conflict detection and resolution
- Automatic failover configuration
- Route priority management

## API Reference

### Tailscale Client API

```zig
const TailscaleClient = struct {
    // Initialize client
    pub fn init(allocator: std.mem.Allocator) TailscaleClient

    // Get network status
    pub fn getStatus() !TailscaleStatus

    // Advertise routes
    pub fn advertiseRoutes(routes: []const []const u8) !void

    // Enable Funnel
    pub fn enableFunnel(port: u16) !void
}
```

### NGINX Manager API

```zig
const NginxManager = struct {
    // Create configuration
    pub fn createConfig(config: NginxConfig) !void

    // Test configuration
    pub fn testConfig() !bool

    // Reload NGINX
    pub fn reload() !void

    // Remove configuration
    pub fn removeConfig(server_name: []const u8) !void
}
```

### Certificate Manager API

```zig
const CertificateManager = struct {
    // Obtain certificate
    pub fn obtainCertificate(domain: []const u8, provider: []const u8) !CertPaths

    // Renew certificate
    pub fn renewCertificate(domain: []const u8) !void

    // Check expiry
    pub fn checkExpiry(cert_path: []const u8) !u64
}
```

## Troubleshooting

### Common Issues

#### Tailscale Connection Issues

```bash
# Check Tailscale status
tailscale status

# Verify API access
curl http://localhost:41641/localapi/v0/status

# Check ghostscale can connect
ghostscale route status
```

#### NGINX Configuration Errors

```bash
# Test NGINX config manually
nginx -t

# Check generated configs
ls -la /etc/nginx/sites-available/

# View NGINX error logs
tail -f /var/log/nginx/error.log
```

#### Certificate Issues

```bash
# Use Tailscale's built-in cert for testing
ghostscale expose --name test --port 8080 \
  --domain test.ts.net --ssl --cert-provider tailscale

# Check certificate status
openssl x509 -in /etc/ssl/ghostscale/domain.crt -text -noout
```

#### DNS Sync Problems

```bash
# Test DNS provider connectivity
curl -H "X-API-Key: $POWERDNS_KEY" https://dns.example.com/api/v1/servers

# Export locally first to verify
ghostscale dns export --format json --output test.json

# Check DNS resolution
dig @your-dns-server hostname.internal.example.com
```

## Advanced Usage

### Custom Service Templates

Create custom templates in `~/.config/ghostscale/templates/`:

```toml
# ~/.config/ghostscale/templates/gitlab.toml
[service]
name = "gitlab"
default_port = 8080
requires_websocket = true

[nginx]
client_max_body_size = "500M"
proxy_read_timeout = 300

[headers]
X-Frame-Options = "SAMEORIGIN"
```

### Scripting and Automation

```bash
#!/bin/bash
# Auto-expose all Docker containers

for container in $(docker ps --format "{{.Names}}"); do
    port=$(docker port $container | head -1 | cut -d: -f2)
    ghostscale expose --name "$container" --port "$port" \
      --domain "$container.internal.example.com" --ssl --auto-cert
done
```

### Integration with CI/CD

```yaml
# .github/workflows/deploy.yml
name: Deploy with Ghostscale

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      
      - name: Install Ghostscale
        run: |
          wget https://github.com/ghostkellz/ghostscale/releases/latest/ghostscale
          chmod +x ghostscale
          sudo mv ghostscale /usr/local/bin/
      
      - name: Expose Service
        run: |
          ghostscale expose --name myapp --port 3000 \
            --domain app.example.com --ssl --auto-cert
```

## Security Considerations

### Best Practices

1. **API Key Management**
   - Never commit API keys to version control
   - Use environment variables or secret management tools
   - Rotate keys regularly

2. **Network Segmentation**
   - Use Tailscale ACLs to restrict access
   - Implement subnet routing carefully
   - Monitor route advertisements

3. **Certificate Security**
   - Use auto-cert for automatic renewal
   - Store certificates securely with proper permissions
   - Monitor expiry dates

4. **NGINX Hardening**
   - Regularly update NGINX
   - Use security headers
   - Implement rate limiting
   - Enable ModSecurity WAF

### Audit Logging

Enable audit logging for compliance:

```bash
# Set environment variable
export GHOSTSCALE_AUDIT_LOG="/var/log/ghostscale/audit.log"

# All commands will be logged with timestamps and parameters
tail -f /var/log/ghostscale/audit.log
```

## Contributing

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for details.

### Development Setup

```bash
# Clone with submodules
git clone --recursive https://github.com/ghostkellz/ghostscale.git

# Run tests
zig build test

# Run with debug output
GHOSTSCALE_DEBUG=1 zig build run -- expose --help
```

## License

MIT License - See [LICENSE](LICENSE) file for details.

## Support

- GitHub Issues: [github.com/ghostkellz/ghostscale/issues](https://github.com/ghostkellz/ghostscale/issues)
- Discord: [discord.gg/ghostscale](https://discord.gg/ghostscale)
- Email: support@ghostscale.dev

---

**Made with ⚡️ by GhostKellz** for CK Technology LLC